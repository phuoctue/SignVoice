import { beforeAll, afterAll, afterEach, describe, it, expect, vi } from 'vitest';
import request from 'supertest';
import mongoose, { Types } from 'mongoose';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { Category, DictionaryEntry, User, AuthSession, UserSettings } from '../src/models';
import { TopicEnrollment, WordProgress } from '../src/models/Learning.model';
import { ReviewQuiz } from '../src/models/ReviewQuiz.model';
import { LearningEvent } from '../src/models/LearningEvent.model';

let app: Awaited<ReturnType<typeof createApp>>;
let a: string, b: string, userA: Types.ObjectId, userB: Types.ObjectId, topicId: Types.ObjectId;
const entries: Types.ObjectId[] = [];
const legacyDate = new Date('2026-10-20T08:30:00Z');
beforeAll(async () => {
  await connectDatabase(); app = await createApp(); await LearningEvent.init();
  const one = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  const two = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  a = `Bearer ${one.body.data.tokens.accessToken}`; b = `Bearer ${two.body.data.tokens.accessToken}`;
  userA = new Types.ObjectId(one.body.data.user.id); userB = new Types.ObjectId(two.body.data.user.id);
  const topic = await Category.create({ name: 'History greetings', slug: `history-${Date.now()}`, status: 'ACTIVE' });
  topicId = topic._id;
  const words = await DictionaryEntry.create(Array.from({ length: 12 }, (_, i) => ({
    word: `History word ${i}`, definition: 'Test history word.', categoryId: topicId, createdBy: userA,
    status: 'PUBLISHED', videoUrl: 'https://example.com/history.mp4',
  })));
  entries.push(...words.map(word => word._id));
  await TopicEnrollment.create({ userId: userB, topicId });
  await WordProgress.create({ userId: userB, topicId, entryId: entries[0], stage: 'REVIEW', reviewedAt: legacyDate });
});
afterEach(() => vi.restoreAllMocks());
afterAll(async () => {
  try {
    if (mongoose.connection.readyState === 1) {
      if (topicId) {
        await DictionaryEntry.deleteMany({ categoryId: topicId });
        await Category.deleteOne({ _id: topicId });
      }
      for (const model of [LearningEvent, WordProgress, TopicEnrollment, ReviewQuiz, AuthSession, UserSettings]) {
        await model.collection.deleteMany({ userId: { $in: [userA, userB].filter(Boolean) } });
      }
      await User.deleteMany({ _id: { $in: [userA, userB].filter(Boolean) } });
    }
  } finally { await disconnectDatabase(); }
});

describe('Personal learning history', () => {
  it('requires auth, validates filters and presents actual legacy review time', async () => {
    await request(app).get('/api/v1/learning/history').expect(401);
    await request(app).get('/api/v1/learning/history?page=-1').set('Authorization', a).expect(400);
    await request(app).get('/api/v1/learning/history?entryId=bad').set('Authorization', a).expect(400);
    const old = await request(app).get('/api/v1/learning/history').set('Authorization', b).expect(200);
    expect(old.body.data.items).toHaveLength(1);
    expect(old.body.data.items[0]).toMatchObject({ kind: 'RECORDED_PROGRESS', stage: 'REVIEW', createdAt: legacyDate.toISOString() });
  });

  it('records starts and changed ratings once, pages/searches and isolates accounts', async () => {
    for (let i = 0; i < 2; i++) await request(app).post(`/api/v1/learning/topics/${topicId}/start`).set('Authorization', a).send({}).expect(200);
    for (const entry of entries) await request(app).patch(`/api/v1/learning/words/${entry}/progress`).set('Authorization', a).send({ stage: 'REMEMBERED' }).expect(200);
    await request(app).patch(`/api/v1/learning/words/${entries[0]}/progress`).set('Authorization', a).send({ stage: 'REMEMBERED' }).expect(200);
    expect(await LearningEvent.countDocuments({ userId: userA })).toBe(13);
    const first = await request(app).get('/api/v1/learning/history').set('Authorization', a).expect(200);
    const second = await request(app).get('/api/v1/learning/history?page=2').set('Authorization', a).expect(200);
    expect(first.headers['cache-control']).toBe('no-store');
    expect(first.body.data.items).toHaveLength(10); expect(second.body.data.items).toHaveLength(3);
    expect(first.body.data.pagination).toMatchObject({ total: 13, pages: 2 });
    const wider = await request(app).get('/api/v1/learning/history?pageSize=20').set('Authorization', a).expect(200);
    expect(wider.body.data.items).toHaveLength(13);
    expect(wider.body.data.pagination).toMatchObject({ total: 13, pages: 1, pageSize: 20 });
    await request(app).get('/api/v1/learning/history?pageSize=1000').set('Authorization', a).expect(400);
    await request(app).get('/api/v1/learning/history?pageSize=0').set('Authorization', a).expect(400);
    expect(first.body.data.items.every((item: { userId?: string }) => item.userId === undefined)).toBe(true);
    const word = await request(app).get(`/api/v1/learning/history?entryId=${entries[0]}`).set('Authorization', a).expect(200);
    expect(word.body.data.items).toHaveLength(1);
    expect(word.body.data.items[0]).toMatchObject({ word: 'History word 0', kind: 'SELF_RATED', stage: 'REMEMBERED', firstLearning: true });
    expect((await request(app).get('/api/v1/learning/history?search=%5B%2E*').set('Authorization', a)).body.data.items).toHaveLength(0);
    expect((await request(app).get('/api/v1/learning/history').set('Authorization', b)).body.data.pagination.total).toBe(1);
  });

  it('records each camera quiz result once, including repeated submission', async () => {
    await request(app).patch(`/api/v1/learning/words/${entries[0]}/progress`).set('Authorization', a).send({ stage: 'REVIEW' }).expect(200);
    const quiz = await request(app).post(`/api/v1/learning/topics/${topicId}/quiz`).set('Authorization', a).send({}).expect(200);
    const id = quiz.body.data._id;
    await request(app).patch(`/api/v1/learning/quizzes/${id}/captures`).set('Authorization', a).send({ entryId: String(entries[0]), recognizedLabel: 'History word 0' }).expect(200);
    for (let i = 0; i < 2; i++) await request(app).post(`/api/v1/learning/quizzes/${id}/submit`).set('Authorization', a).send({}).expect(200);
    const events = await LearningEvent.find({ userId: userA, kind: 'QUIZ_REVIEWED' }).lean();
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ stage: 'REMEMBERED', score: 10, applied: true });
  });

  it('returns canonical Vietnamese quiz words and accepted aliases', async () => {
    const word = 'Ca\u0301m o\u031bn', alias = 'Ca\u0309m o\u031bn';
    const quiz = await ReviewQuiz.create({ userId: userB, topicId, kind: 'CAMERA', status: 'DRAFT',
      questions: [{ entryId: String(entries[0]), word, aliases: [alias] }] });
    const response = await request(app).get(`/api/v1/learning/quizzes/${quiz._id}`).set('Authorization', b).expect(200);
    expect(response.body.data.questions[0]).toMatchObject({ word: word.normalize('NFC'), aliases: [alias.normalize('NFC')] });
  });

  it('rolls back the rating if its history write fails', async () => {
    const previous = await WordProgress.findOne({ userId: userA, entryId: entries[1] }).lean();
    vi.spyOn(LearningEvent, 'create').mockRejectedValueOnce(new Error('history unavailable') as never);
    await request(app).patch(`/api/v1/learning/words/${entries[1]}/progress`).set('Authorization', a).send({ stage: 'REVIEW' }).expect(500);
    expect(await WordProgress.findOne({ userId: userA, entryId: entries[1] }).lean()).toEqual(previous);
  });

  it('exports owned history and removes it with reset/deletion without touching another user', async () => {
    const exported = await request(app).get('/api/v1/users/data/export').set('Authorization', a).expect(200);
    expect(exported.body.data.learningHistory.length).toBeGreaterThan(0);
    expect(exported.body.data.learningHistory.every((event: { userId?: string }) => event.userId === undefined)).toBe(true);
    await request(app).delete('/api/v1/users/data').set('Authorization', a).send({ confirm: true }).expect(200);
    expect((await request(app).get('/api/v1/learning/history').set('Authorization', a)).body.data.pagination.total).toBe(0);
    expect((await request(app).get('/api/v1/learning/history').set('Authorization', b)).body.data.pagination.total).toBe(1);
    await request(app).patch(`/api/v1/learning/words/${entries[1]}/progress`).set('Authorization', b).send({ stage: 'REMEMBERED' }).expect(200);
    expect(await LearningEvent.countDocuments({ userId: userB })).toBe(1);
    await request(app).delete('/api/v1/users/account').set('Authorization', b).send({ confirm: true }).expect(200);
    expect(await LearningEvent.countDocuments({ userId: userB })).toBe(0);
  });
});
