import { beforeAll, afterAll, describe, it, expect } from 'vitest';
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
const ids: Types.ObjectId[] = [];
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
});
afterAll(async () => {
  await DictionaryEntry.deleteMany({ categoryId: topicId }); await Category.deleteOne({ _id: topicId });
  for (const userId of [userA, userB]) {
    for (const model of [ReviewQuiz, TopicEnrollment, WordProgress]) await model.collection.deleteMany({ userId });
    await AuthSession.deleteMany({ userId }); await UserSettings.deleteMany({ userId }); await User.deleteOne({ _id: userId });
  }
  await disconnectDatabase();
});

describe('Camera review quiz access and account cleanup', () => {
  it('requires auth and enrollment; snapshots only ten review words without reference answers', async () => {
    await request(app).post(`/api/v1/learning/topics/${topicId}/quiz`).send({}).expect(401);
    await request(app).post(`/api/v1/learning/topics/${topicId}/quiz`).set('Authorization', b).send({}).expect(409);
    const created = await request(app).post(`/api/v1/learning/topics/${topicId}/quiz`).set('Authorization', a).send({}).expect(200);
    const attemptId = created.body.data._id;
    const questions = created.body.data.questions as { entryId: string; word: string }[];
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
  it('removes drafts and results when the owner deletes their account', async () => {
    expect(await ReviewQuiz.countDocuments({ userId: userA })).toBeGreaterThan(0);
    await deleteOwnAccount(userA);
    expect(await ReviewQuiz.countDocuments({ userId: userA })).toBe(0);
    expect(await User.exists({ _id: userB })).not.toBeNull();
  });
});
