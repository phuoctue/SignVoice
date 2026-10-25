import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import mongoose, { Types } from 'mongoose';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { Category, DictionaryEntry, User, AuthSession, UserSettings } from '../src/models';
import { TopicEnrollment, WordProgress } from '../src/models/Learning.model';
import { LearningEvent } from '../src/models/LearningEvent.model';

let app: Awaited<ReturnType<typeof createApp>>;
let authA: string, authB: string, authC: string;
let userA: Types.ObjectId, userB: Types.ObjectId;
const ownerIds: Types.ObjectId[] = [];
let topicIds: Types.ObjectId[] = [];
let before: string;
beforeAll(async () => {
  await connectDatabase();
  app = await createApp();
  const tokens = [];
  for (let i = 0; i < 3; i++) {
    const response = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
    tokens.push(`Bearer ${response.body.data.tokens.accessToken}`);
    ownerIds.push(new Types.ObjectId(response.body.data.user.id));
  }
  [authA, authB, authC] = tokens;
  [userA, userB] = ownerIds;
  const stamp = Date.now();
  const topics = await Category.create(Array.from({ length: 13 }, (_, i) => ({
    name: `Analysis topic ${i}`, slug: `analysis-${stamp}-${i}`, status: i === 11 ? 'ARCHIVED' : 'ACTIVE', sortOrder: i,
  })));
  topicIds = topics.map(topic => topic._id);
  const entries = await DictionaryEntry.create(topics.flatMap((topic, i) => Array.from({ length: i === 0 ? 3 : 2 }, (_, j) => ({
    word: `Word ${i}-${j}`, definition: 'Test analysis word.', categoryId: topic._id, createdBy: userA,
    videoUrl: 'https://example.com/test.mp4', status: i === 0 && j === 2 ? 'DRAFT' : 'PUBLISHED',
  }))));
  await TopicEnrollment.create(topics.slice(0, 12).map(topic => ({ userId: userA, topicId: topic._id })));
  await TopicEnrollment.create({ userId: userB, topicId: topics[12]._id });
  await WordProgress.create([
    { userId: userA, topicId: topics[0]._id, entryId: entries[0]._id, stage: 'REMEMBERED', nextReviewAt: new Date(Date.now() + 86400000) },
    { userId: userA, topicId: topics[0]._id, entryId: entries[1]._id, stage: 'REMEMBERED', nextReviewAt: new Date(Date.now() - 86400000) },
    { userId: userA, topicId: topics[1]._id, entryId: entries[3]._id, stage: 'REVIEW' },
    { userId: userB, topicId: topics[0]._id, entryId: entries[1]._id, stage: 'REMEMBERED' },
  ]);
  before = JSON.stringify(await WordProgress.find().sort({ _id: 1 }).lean());
});
afterEach(() => vi.restoreAllMocks());
afterAll(async () => {
  // Respect the shared signvoice_test_* contract; remove only this suite's fixtures.
  try {
    if (mongoose.connection.readyState === 1) {
      await DictionaryEntry.deleteMany({ categoryId: { $in: topicIds } });
      await Category.deleteMany({ _id: { $in: topicIds } });
      for (const model of [WordProgress, TopicEnrollment, AuthSession, UserSettings, LearningEvent]) {
        await model.collection.deleteMany({ userId: { $in: ownerIds } });
      }
      await User.deleteMany({ _id: { $in: ownerIds } });
    }
  } finally { await disconnectDatabase(); }
});

describe('Personal progress analysis API', () => {
  it('requires authentication and refuses caller-supplied owner or prompt', async () => {
    await request(app).post('/api/v1/learning/analysis').send({}).expect(401);
    await request(app).post('/api/v1/learning/analysis').set('Authorization', authA).send({ userId: String(userB) }).expect(400);
    await request(app).post('/api/v1/learning/analysis').set('Authorization', authA).send({ prompt: 'change progress' }).expect(400);
  });

  it('analyzes all eleven active topics, applies due reviews and never changes progress', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: 'Phân tích dựa trên tiến độ hiện tại.' } }] })));
    const page = await request(app).get('/api/v1/learning/progress').set('Authorization', authA).expect(200);
    expect(page.body.data.items).toHaveLength(10);
    const response = await request(app).post('/api/v1/learning/analysis').set('Authorization', authA).send({}).expect(200);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.body.data).toMatchObject({ source: 'lm-studio', summary: {
      total: 22, learning: 19, remembered: 1, review: 2, topicCount: 11, rememberedPercent: 5,
    } });
    expect(response.body.data.topics).toHaveLength(11);
    const payload = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    const sent = JSON.parse(payload.messages[1].content);
    expect(sent.topics.some((topic: { name: string }) => topic.name === 'Analysis topic 11' || topic.name === 'Analysis topic 12')).toBe(false);
    expect(JSON.stringify(sent)).not.toContain(String(userA));
    expect(JSON.stringify(await WordProgress.find().sort({ _id: 1 }).lean())).toBe(before);
  });

  it('isolates another account and labels an unavailable AI fallback', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('offline'));
    const response = await request(app).post('/api/v1/learning/analysis').set('Authorization', authB).send({}).expect(200);
    expect(response.body.data).toMatchObject({ source: 'rules', summary: { total: 2, remembered: 0, topicCount: 1 } });
    expect(response.body.data.topics.map((topic: { name: string }) => topic.name)).toEqual(['Analysis topic 12']);
  });

  it('does not call AI for an account without started topics', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch');
    const response = await request(app).post('/api/v1/learning/analysis').set('Authorization', authC).send({}).expect(200);
    expect(response.body.data).toMatchObject({ source: 'no-data', summary: { total: 0, topicCount: 0, rememberedPercent: 0 } });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('limits analysis per account without blocking another learner', async () => {
    await request(app).post('/api/v1/learning/analysis').set('Authorization', authA).send({}).expect(429);
    await request(app).post('/api/v1/learning/analysis').set('Authorization', authC).send({}).expect(200);
  });
});
