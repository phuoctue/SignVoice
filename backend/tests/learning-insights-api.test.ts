import { beforeAll, afterAll, describe, expect, it } from 'vitest';
import request from 'supertest';
import mongoose, { Types } from 'mongoose';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { Category, DictionaryEntry, User, UserSettings, AuthSession } from '../src/models';
import { TopicEnrollment, WordProgress } from '../src/models/Learning.model';
import { LearningEvent } from '../src/models/LearningEvent.model';
import { ReviewQuiz } from '../src/models/ReviewQuiz.model';

let app: Awaited<ReturnType<typeof createApp>>, a: string, b: string;
const users: Types.ObjectId[] = [], topics: Types.ObjectId[] = [], words: Types.ObjectId[] = [];
const now = new Date();
const ago = (days: number) => new Date(now.getTime() - days * 86400000);
beforeAll(async () => {
  await connectDatabase(); app = await createApp();
  for (let i = 0; i < 2; i++) {
    const result = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
    users.push(new Types.ObjectId(result.body.data.user.id));
    if (i === 0) a = `Bearer ${result.body.data.tokens.accessToken}`; else b = `Bearer ${result.body.data.tokens.accessToken}`;
  }
  for (let i = 0; i < 3; i++) topics.push((await Category.create({ name: `Insights ${i}`, slug: `insights-${Date.now()}-${i}`, status: i === 1 ? 'ARCHIVED' : 'ACTIVE' }))._id);
  for (let i = 0; i < 7; i++) words.push((await DictionaryEntry.create({ word: `Insights word ${i}`, definition: 'Test insights.', createdBy: users[0],
    categoryId: i === 4 ? topics[1] : i === 6 ? topics[2] : topics[0], status: i === 5 ? 'DRAFT' : 'PUBLISHED', videoUrl: 'https://example.com/sign.mp4' }))._id);
  await TopicEnrollment.create(users.map(userId => ({ userId, topicId: topics[0] })));
  await LearningEvent.create([
    { userId: users[0], entryId: words[0], firstLearning: true, createdAt: now },
    { userId: users[0], entryId: words[0], firstLearning: false, createdAt: now },
    { userId: users[0], entryId: words[1], createdAt: now },
    { userId: users[0], entryId: words[2], firstLearning: true, createdAt: ago(1) },
    { userId: users[0], entryId: words[3], firstLearning: true, createdAt: ago(-1) },
    { userId: users[1], entryId: words[0], firstLearning: true, createdAt: now },
  ].map(event => ({ ...event, kind: 'SELF_RATED', topicId: topics[0], topicName: 'Insights 0', word: 'word', stage: 'REMEMBERED' })));
  const quiz = (user: number, completedAt: Date, scores: [number, number][], source = 'sign-ai-camera') => ({
    userId: users[user], topicId: topics[0], kind: 'CAMERA', status: 'COMPLETED', completedAt,
    questions: scores.map(([word]) => ({ entryId: String(words[word]), word: `Insights word ${word}` })),
    result: { source, items: scores.map(([word, score]) => ({ entryId: String(words[word]), word: `Insights word ${word}`, score, applied: true })) },
  });
  // Older completed camera quizzes have no LearningEvent rows, and must still count.
  await ReviewQuiz.create([
    quiz(0, now, [[0, 0], [1, 10], [4, 0], [5, 0], [6, 0]]), quiz(0, now, [[0, 0]]),
    quiz(0, ago(1), [[0, 10]]), quiz(0, ago(10), [[2, 0]]), quiz(0, now, [[3, 0]], 'lm-studio'),
    quiz(1, now, [[0, 0]]), quiz(0, ago(-1), [[3, 0]]),
  ]);
});
afterAll(async () => {
  try {
    if (mongoose.connection.readyState === 1) {
      for (const model of [LearningEvent, WordProgress, TopicEnrollment, ReviewQuiz, UserSettings, AuthSession]) await model.collection.deleteMany({ userId: { $in: users } });
      await DictionaryEntry.deleteMany({ _id: { $in: words } }); await Category.deleteMany({ _id: { $in: topics } }); await User.deleteMany({ _id: { $in: users } });
    }
  } finally { await disconnectDatabase(); }
});

describe('Learning insights and goals', () => {
  it('authenticates and validates query and goal inputs', async () => {
    await request(app).get('/api/v1/learning/insights').expect(401);
    for (const query of ['days=14', 'page=0', `userId=${users[1]}`]) await request(app).get(`/api/v1/learning/insights?${query}`).set('Authorization', a).expect(400);
    for (const body of [{ newWords: 0, reviewWords: 10 }, { newWords: 5.5, reviewWords: 10 }, { newWords: 5, reviewWords: 201 }, { newWords: 5, reviewWords: 10, userId: String(users[1]) }]) {
      await request(app).patch('/api/v1/learning/goals').set('Authorization', a).send(body).expect(400);
    }
  });
  it('zero-fills seven days, deduplicates word/day and includes real older quiz completions', async () => {
    const response = await request(app).get('/api/v1/learning/insights?days=7').set('Authorization', a).expect(200);
    expect(response.headers['cache-control']).toBe('no-store');
    const data = response.body.data;
    expect(data.activity).toHaveLength(7);
    expect(data.today).toMatchObject({ learned: 2, newWords: 1, reviewed: 5 });
    expect(data.goals).toEqual({ newWords: 5, reviewWords: 10 });
    expect(data.activity.reduce((sum: number, row: { reviewed: number }) => sum + row.reviewed, 0)).toBe(6);
    expect(data.activity.some((row: { learned: number; reviewed: number }) => row.learned === 0 && row.reviewed === 0)).toBe(true);
  });
  it('shows a full 30-day period and only available/enrolled weak words, ranked by misses', async () => {
    const data = (await request(app).get('/api/v1/learning/insights?days=30').set('Authorization', a).expect(200)).body.data;
    expect(data.activity).toHaveLength(30);
    expect(data.activity.reduce((sum: number, row: { reviewed: number }) => sum + row.reviewed, 0)).toBe(7);
    expect(data.weakWords.pagination.total).toBe(2);
    expect(data.weakWords.items[0]).toMatchObject({ word: 'Insights word 0', misses: 2, attempts: 3, missRate: 67, latestMatched: false });
    expect(data.weakWords.items[1].word).toBe('Insights word 2');
    const other = (await request(app).get('/api/v1/learning/insights').set('Authorization', b).expect(200)).body.data;
    expect(other.today).toMatchObject({ learned: 1, newWords: 1, reviewed: 1 });
    expect(other.weakWords.items[0]).toMatchObject({ misses: 1, attempts: 1 });
  });
  it('filters unavailable words before paging and sorts tied misses consistently', async () => {
    const extra = await DictionaryEntry.create(Array.from({ length: 11 }, (_, i) => ({
      word: `Extra weak ${i}`, definition: 'Paging fixture.', createdBy: users[0], categoryId: topics[0],
      status: 'PUBLISHED', videoUrl: 'https://example.com/weak.mp4',
    })));
    words.push(...extra.map(entry => entry._id));
    await ReviewQuiz.create({ userId: users[0], topicId: topics[0], status: 'COMPLETED', kind: 'CAMERA', completedAt: new Date(),
      questions: extra.map(entry => ({ entryId: String(entry._id), word: entry.word })),
      result: { source: 'sign-ai-camera', items: extra.map(entry => ({ entryId: String(entry._id), word: entry.word, score: 0, applied: true })) } });
    const first = (await request(app).get('/api/v1/learning/insights?page=1').set('Authorization', a).expect(200)).body.data.weakWords;
    const second = (await request(app).get('/api/v1/learning/insights?page=2').set('Authorization', a).expect(200)).body.data.weakWords;
    expect(first.pagination).toMatchObject({ total: 13, pages: 2 });
    expect(first.items).toHaveLength(10); expect(second.items).toHaveLength(3);
    expect(first.items[0].word).toBe('Insights word 0');
    expect(first.items.slice(1).map((entry: { word: string }) => entry.word)).toEqual(Array.from({ length: 9 }, (_, i) => `Extra weak ${i}`));
    expect(new Set([...first.items, ...second.items].map(entry => entry.entryId)).size).toBe(13);
  });
  it('sets the new-word marker only on first progress creation, not retries or later ratings', async () => {
    const before = (await request(app).get('/api/v1/learning/insights').set('Authorization', a)).body.data.today;
    for (let i = 0; i < 2; i++) await request(app).patch(`/api/v1/learning/words/${words[3]}/progress`).set('Authorization', a).send({ stage: 'REMEMBERED' }).expect(200);
    await request(app).patch(`/api/v1/learning/words/${words[3]}/progress`).set('Authorization', a).send({ stage: 'REVIEW' }).expect(200);
    const logged = await LearningEvent.find({ userId: users[0], entryId: words[3], createdAt: { $lte: new Date() } }).sort({ createdAt: 1 }).lean();
    expect(logged).toHaveLength(2);
    expect(logged.map(event => event.firstLearning)).toEqual([true, false]);
    const after = (await request(app).get('/api/v1/learning/insights').set('Authorization', a)).body.data.today;
    expect(after.newWords).toBe(before.newWords + 1);
    expect(after.learned).toBe(before.learned + 1);
  });
  it('persists daily goals per account and includes them in export', async () => {
    await request(app).patch('/api/v1/learning/goals').set('Authorization', a).send({ newWords: 7, reviewWords: 12 }).expect(200);
    expect((await request(app).get('/api/v1/learning/insights').set('Authorization', a)).body.data.goals).toEqual({ newWords: 7, reviewWords: 12 });
    expect((await request(app).get('/api/v1/learning/insights').set('Authorization', b)).body.data.goals).toEqual({ newWords: 5, reviewWords: 10 });
    const exported = await request(app).get('/api/v1/users/data/export').set('Authorization', a).expect(200);
    expect(exported.body.data.settings.learningGoals).toEqual({ newWords: 7, reviewWords: 12 });
  });
  it('exposes lightweight today progress and validates day filters', async () => {
    await request(app).get('/api/v1/learning/today').expect(401);
    const all = (await request(app).get('/api/v1/learning/insights').set('Authorization', a)).body.data;
    const daily = (await request(app).get('/api/v1/learning/today').set('Authorization', a).expect(200)).body.data;
    expect(daily.today).toEqual(all.today); expect(daily.goals).toEqual(all.goals);
    expect(daily.weakWords).toBeUndefined();
    for (const query of ['date=2026-02-30', 'date=bad', 'date=2026-10-25&kind=bad', 'date=2026-10-25&page=0', `date=2026-10-25&userId=${users[1]}`]) {
      await request(app).get(`/api/v1/learning/activity?${query}`).set('Authorization', a).expect(400);
    }
  });
  it('lists actual unique words behind a chart day with privacy and pagination', async () => {
    const chart = (await request(app).get('/api/v1/learning/insights').set('Authorization', a)).body.data;
    const date = chart.today.date;
    const study = (await request(app).get(`/api/v1/learning/activity?date=${date}&kind=learned`).set('Authorization', a).expect(200)).body.data;
    expect(study.pagination.total).toBe(chart.today.learned);
    expect(study.items.filter((item: { word: string }) => item.word === 'word')).toHaveLength(2);
    expect(study.items.some((item: { entryId: string }) => item.entryId === String(words[3]))).toBe(true);
    const first = (await request(app).get(`/api/v1/learning/activity?date=${date}&kind=reviewed`).set('Authorization', a).expect(200)).body.data;
    const second = (await request(app).get(`/api/v1/learning/activity?date=${date}&kind=reviewed&page=2`).set('Authorization', a).expect(200)).body.data;
    expect(first.pagination.total).toBe(chart.today.reviewed);
    expect(first.items).toHaveLength(10);
    expect(new Set([...first.items, ...second.items].map(item => item.entryId)).size).toBe(chart.today.reviewed);
    expect(first.items.every((item: { userId?: string }) => item.userId === undefined)).toBe(true);
    const other = (await request(app).get(`/api/v1/learning/activity?date=${date}&kind=reviewed`).set('Authorization', b).expect(200)).body.data;
    expect(other.pagination.total).toBe(1);
    expect(other.items[0].entryId).toBe(String(words[0]));
  });
  it('resets owned goals/activity without affecting another account', async () => {
    await request(app).delete('/api/v1/users/data').set('Authorization', a).send({ confirm: true }).expect(200);
    const reset = (await request(app).get('/api/v1/learning/insights').set('Authorization', a).expect(200)).body.data;
    expect(reset.goals).toEqual({ newWords: 5, reviewWords: 10 });
    expect(reset.today).toMatchObject({ learned: 0, newWords: 0, reviewed: 0 });
    expect(reset.weakWords.items).toHaveLength(0);
    expect((await request(app).get('/api/v1/learning/insights').set('Authorization', b)).body.data.today.reviewed).toBe(1);
  });
});
