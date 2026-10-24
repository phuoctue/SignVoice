import { beforeAll, afterAll, afterEach, describe, it, expect, vi } from 'vitest';
import request from 'supertest';
import { Types } from 'mongoose';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { Category, DictionaryEntry, User, AuthSession, UserSettings } from '../src/models';
import { TopicEnrollment, WordProgress } from '../src/models/Learning.model';
import { ReviewQuiz } from '../src/models/ReviewQuiz.model';
import { deleteOwnAccount } from '../src/services/account-deletion.service';

let app: Awaited<ReturnType<typeof createApp>>, a: string, b: string;
let userA: Types.ObjectId, userB: Types.ObjectId, topicId: Types.ObjectId;
let attemptId: string;
let questions: { entryId: string; word: string }[];
const ids: Types.ObjectId[] = [];
const oldModel = process.env.LM_STUDIO_MODEL;
beforeAll(async () => {
  await connectDatabase();
  app = await createApp();
  await Promise.all([ReviewQuiz.init(), TopicEnrollment.init(), WordProgress.init()]);
  const first = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  const second = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  userA = new Types.ObjectId(first.body.data.user.id); userB = new Types.ObjectId(second.body.data.user.id);
  a = `Bearer ${first.body.data.tokens.accessToken}`; b = `Bearer ${second.body.data.tokens.accessToken}`;
  const category = await Category.create({ name: 'Quiz ' + Date.now(), slug: 'quiz-' + Date.now(), status: 'ACTIVE' });
  topicId = category._id;
  await TopicEnrollment.create({ userId: userA, topicId });
  for (let i = 0; i < 14; i++) {
    const entry = await DictionaryEntry.create({ word: `Từ quiz ${String(i).padStart(2, '0')}`, definition: 'Dữ liệu tham khảo không gửi trước khi làm bài.',
      videoUrl: 'https://example.com/quiz.mp4', usageExample: 'Ví dụ tham khảo riêng.', categoryId: topicId, createdBy: userA, status: 'PUBLISHED' });
    ids.push(entry._id);
    await WordProgress.create({ userId: userA, entryId: entry._id, topicId,
      stage: i < 12 ? 'REVIEW' : i === 12 ? 'REMEMBERED' : 'LEARNING',
      nextReviewAt: i === 12 ? new Date(Date.now() + 86400000) : null,
      reviewedAt: new Date(Date.now() - 60000) });
  }
  process.env.LM_STUDIO_MODEL = 'test-quiz-model';
});
afterEach(() => vi.restoreAllMocks());
afterAll(async () => {
  if (oldModel === undefined) delete process.env.LM_STUDIO_MODEL; else process.env.LM_STUDIO_MODEL = oldModel;
  await DictionaryEntry.deleteMany({ categoryId: topicId }); await Category.deleteOne({ _id: topicId });
  for (const userId of [userA, userB]) {
    for (const model of [ReviewQuiz, TopicEnrollment, WordProgress]) await model.collection.deleteMany({ userId });
    await AuthSession.deleteMany({ userId }); await UserSettings.deleteMany({ userId }); await User.deleteOne({ _id: userId });
  }
  await disconnectDatabase();
});
const responseFor = (content: unknown) => new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify(content) } }] }), { status: 200 });
const grades = (qs: { entryId: string }[]) => ({ feedback: 'Hãy tiếp tục luyện tập các câu chưa đạt.', items: qs.map((q, i) => ({ entryId: q.entryId, score: i % 2 ? 3 : 9, feedback: i % 2 ? 'Cần dùng đúng ngữ cảnh.' : 'Dùng từ đúng nghĩa.' })) });

describe('Review quiz with LM Studio assessment', () => {
  it('requires auth and enrollment; snapshots only ten review words without reference answers', async () => {
    await request(app).post(`/api/v1/learning/topics/${topicId}/quiz`).send({}).expect(401);
    await request(app).post(`/api/v1/learning/topics/${topicId}/quiz`).set('Authorization', b).send({}).expect(409);
    const created = await request(app).post(`/api/v1/learning/topics/${topicId}/quiz`).set('Authorization', a).send({}).expect(200);
    attemptId = created.body.data._id; questions = created.body.data.questions;
    expect(questions).toHaveLength(10);
    expect(questions.some(q => [String(ids[12]), String(ids[13])].includes(q.entryId))).toBe(false);
    expect(JSON.stringify(created.body)).not.toContain('Ví dụ tham khảo riêng');
    expect(JSON.stringify(created.body)).not.toContain('Dữ liệu tham khảo');
    const resumed = await request(app).post(`/api/v1/learning/topics/${topicId}/quiz`).set('Authorization', a).send({}).expect(200);
    expect(resumed.body.data._id).toBe(attemptId);
    await request(app).get(`/api/v1/learning/quizzes/${attemptId}`).set('Authorization', b).expect(404);
    await request(app).post(`/api/v1/learning/quizzes/${attemptId}/submit`).set('Authorization', b).send({}).expect(404);
    await request(app).patch(`/api/v1/learning/quizzes/${attemptId}/answers`).set('Authorization', b).send({ answers: questions.map(() => 'a') }).expect(404);
  });
  it('validates answers, saves drafts and prevents client supplied grades', async () => {
    await request(app).post(`/api/v1/learning/quizzes/${attemptId}/submit`).set('Authorization', a).send({}).expect(400);
    await request(app).patch(`/api/v1/learning/quizzes/${attemptId}/answers`).set('Authorization', a).send({ answers: ['mismatch'] }).expect(400);
    await request(app).patch(`/api/v1/learning/quizzes/${attemptId}/answers`).set('Authorization', a).send({ answers: questions.map(() => 'a'), score: 10 }).expect(400);
    const answers = questions.map(q => `Câu sử dụng ${q.word}.`);
    await request(app).patch(`/api/v1/learning/quizzes/${attemptId}/answers`).set('Authorization', a).send({ answers }).expect(200);
    const reload = await request(app).get(`/api/v1/learning/quizzes/${attemptId}`).set('Authorization', a).expect(200);
    expect(reload.body.data.questions.map((q: any) => q.answer)).toEqual(answers);
    await request(app).post(`/api/v1/learning/quizzes/${attemptId}/submit`).set('Authorization', a).send({ result: grades(questions) }).expect(400);
  });
  it('does not fake AI results or change progress when LM Studio is offline', async () => {
    const before = await WordProgress.find({ userId: userA }).lean();
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('offline'));
    const failed = await request(app).post(`/api/v1/learning/quizzes/${attemptId}/submit`).set('Authorization', a).send({}).expect(503);
    expect(failed.body.error.code).toBe('QUIZ_GRADING_UNAVAILABLE');
    expect(await WordProgress.find({ userId: userA }).lean()).toEqual(before);
    const stored = await ReviewQuiz.findById(attemptId).lean();
    expect(stored!.status).toBe('DRAFT'); expect(stored!.result).toBeNull(); expect(stored!.gradingUntil).toBeNull();
    expect(stored!.answers).toHaveLength(10);
  });
  it('rejects missing or duplicate model results without applying any grades', async () => {
    const invalid = grades(questions); invalid.items[1].entryId = invalid.items[0].entryId;
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(responseFor(invalid));
    await request(app).post(`/api/v1/learning/quizzes/${attemptId}/submit`).set('Authorization', a).send({}).expect(503);
    expect(await WordProgress.countDocuments({ userId: userA, stage: 'REVIEW' })).toBe(12);
  });
  it('saves AI feedback and grades atomically; repeat submission is idempotent', async () => {
    const mocked = vi.spyOn(globalThis, 'fetch').mockResolvedValue(responseFor(grades(questions)));
    const graded = await request(app).post(`/api/v1/learning/quizzes/${attemptId}/submit`).set('Authorization', a).send({}).expect(200);
    expect(graded.body.data).toMatchObject({ status: 'COMPLETED', result: { source: 'lm-studio', model: 'test-quiz-model', passScore: 7, score: 6 } });
    expect(graded.body.data.result.items.filter((i: any) => i.applied)).toHaveLength(10);
    expect(await WordProgress.countDocuments({ userId: userA, stage: 'REMEMBERED' })).toBe(6);
    expect(await WordProgress.countDocuments({ userId: userA, stage: 'REVIEW' })).toBe(7);
    const before = await WordProgress.find({ userId: userA }).lean();
    const again = await request(app).post(`/api/v1/learning/quizzes/${attemptId}/submit`).set('Authorization', a).send({}).expect(200);
    expect(again.body.data.result).toEqual(graded.body.data.result);
    expect(mocked).toHaveBeenCalledTimes(1);
    expect(await WordProgress.find({ userId: userA }).lean()).toEqual(before);
    await request(app).patch(`/api/v1/learning/quizzes/${attemptId}/answers`).set('Authorization', a).send({ answers: questions.map(() => 'edited') }).expect(409);
  });
  it('does not overwrite a newer learning state during grading, and locks draft edits', async () => {
    const created = await request(app).post(`/api/v1/learning/topics/${topicId}/quiz`).set('Authorization', a).send({}).expect(200);
    const id = created.body.data._id, qs = created.body.data.questions;
    expect(qs).toHaveLength(7);
    await request(app).patch(`/api/v1/learning/quizzes/${id}/answers`).set('Authorization', a).send({ answers: qs.map(() => 'Câu trả lời.') }).expect(200);
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => {
      await request(app).patch(`/api/v1/learning/quizzes/${id}/answers`).set('Authorization', a).send({ answers: qs.map(() => 'late edit') }).expect(409);
      await WordProgress.updateOne({ userId: userA, entryId: qs[0].entryId }, { $set: { stage: 'LEARNING', reviewedAt: new Date(Date.now() + 1000) } });
      return responseFor(grades(qs));
    });
    const graded = await request(app).post(`/api/v1/learning/quizzes/${id}/submit`).set('Authorization', a).send({}).expect(200);
    expect(graded.body.data.result.items[0].applied).toBe(false);
    expect((await WordProgress.findOne({ userId: userA, entryId: qs[0].entryId }))!.stage).toBe('LEARNING');
  });
  it('removes drafts and results when the owner deletes their account', async () => {
    expect(await ReviewQuiz.countDocuments({ userId: userA })).toBeGreaterThan(0);
    await deleteOwnAccount(userA);
    expect(await ReviewQuiz.countDocuments({ userId: userA })).toBe(0);
    expect(await User.exists({ _id: userB })).not.toBeNull();
  });
});
