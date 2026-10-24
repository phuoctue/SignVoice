import { beforeAll, afterAll, describe, it, expect, vi } from 'vitest';
import request from 'supertest';
import { Types } from 'mongoose';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { Category, DictionaryEntry, User, AuthSession, UserSettings } from '../src/models';
import { TopicEnrollment, WordProgress, PersonalWord } from '../src/models/Learning.model';
import { deleteOwnAccount } from '../src/services/account-deletion.service';

let app: Awaited<ReturnType<typeof createApp>>;
let a: string, b: string, userA: Types.ObjectId, userB: Types.ObjectId;
const topics: Types.ObjectId[] = [], entries: Types.ObjectId[] = [];
const stamp = `learn-${Date.now()}`;
beforeAll(async () => {
  await connectDatabase(); app = await createApp();
  await Promise.all([TopicEnrollment.init(), WordProgress.init(), PersonalWord.init()]);
  const first = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  const second = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  a = `Bearer ${first.body.data.tokens.accessToken}`; b = `Bearer ${second.body.data.tokens.accessToken}`;
  userA = new Types.ObjectId(first.body.data.user.id); userB = new Types.ObjectId(second.body.data.user.id);
  for (let i = 0; i < 12; i++) {
    const topic = await Category.create({ name: `Chủ đề ${stamp} ${i}`, slug: `${stamp}-${i}`, status: 'ACTIVE', sortOrder: i });
    topics.push(topic._id);
    const words = await DictionaryEntry.create(Array.from({ length: i === 0 ? 14 : 1 }, (_, j) => ({
      word: `Từ ${String(j).padStart(2, '0')}`, definition: 'Ý nghĩa để kiểm thử học từ.', categoryId: topic._id,
      createdBy: userA, status: i === 0 && j === 13 ? 'DRAFT' : 'PUBLISHED',
      videoUrl: 'https://example.com/sign.mp4', thumbnailUrl: 'https://example.com/sign.jpg',
      imageUrls: ['https://example.com/frame.jpg'], usageExample: 'Đây là một câu ví dụ.',
    })));
    if (i === 0) entries.push(...words.map(w => w._id));
  }
});
afterAll(async () => {
  vi.restoreAllMocks();
  await DictionaryEntry.deleteMany({ categoryId: { $in: topics } });
  await Category.deleteMany({ _id: { $in: topics } });
  for (const userId of [userA, userB]) {
    if (!userId) continue;
    for (const model of [TopicEnrollment, WordProgress, PersonalWord]) await model.collection.deleteMany({ userId });
    await AuthSession.deleteMany({ userId }); await UserSettings.deleteMany({ userId }); await User.deleteOne({ _id: userId });
  }
  await disconnectDatabase();
});

describe('Dictionary learning', () => {
  it('requires authentication and validates pagination and identifiers', async () => {
    await request(app).get('/api/v1/learning/topics').expect(401);
    await request(app).get('/api/v1/learning/topics?page=-1').set('Authorization', a).expect(400);
    await request(app).get('/api/v1/learning/topics/bad-id').set('Authorization', a).expect(400);
  });
  it('uses published words, actual learners, and ten items per page', async () => {
    const list = await request(app).get(`/api/v1/learning/topics?search=${stamp}`).set('Authorization', a).expect(200);
    expect(list.body.data.items).toHaveLength(10);
    expect(list.body.data.pagination).toMatchObject({ total: 12, pages: 2, pageSize: 10 });
    expect(list.body.data.items[0]).toMatchObject({ wordCount: 13, learnerCount: 0 });
    const page1 = await request(app).get(`/api/v1/learning/topics/${topics[0]}`).set('Authorization', a).expect(200);
    const page2 = await request(app).get(`/api/v1/learning/topics/${topics[0]}?page=2`).set('Authorization', a).expect(200);
    expect(page1.body.data.items).toHaveLength(10); expect(page2.body.data.items).toHaveLength(3);
    expect(page1.body.data.items[0]).toHaveProperty('thumbnailUrl');
    expect(page1.body.data.items[0]).toHaveProperty('usageExample');
    expect(page1.body.data.enrolled).toBe(false);
    expect(await TopicEnrollment.countDocuments({ userId: userA })).toBe(0);
    await request(app).patch(`/api/v1/learning/words/${entries[0]}/progress`).set('Authorization', a).send({ stage: 'REMEMBERED' }).expect(409);
    for (let i = 0; i < 2; i++) await request(app).post(`/api/v1/learning/topics/${topics[0]}/start`).set('Authorization', a).send({}).expect(200);
    expect(await TopicEnrollment.countDocuments({ userId: userA, topicId: topics[0] })).toBe(1);
    const learned = await request(app).get(`/api/v1/learning/topics/${topics[0]}`).set('Authorization', a).expect(200);
    expect(learned.body.data.topic.learnerCount).toBe(1);
  });
  it('reports missing local media without returning broken file URLs', async () => {
    const missing = `https://old.example/sign-media/${'f'.repeat(64)}`;
    await DictionaryEntry.updateOne({ _id: entries[12] }, { $set: {
      thumbnailUrl: `${missing}-3.jpg`, imageUrls: [`${missing}-1.jpg`], videoUrl: `${missing}.mp4`,
    } });
    const result = await request(app).get(`/api/v1/learning/topics/${topics[0]}?page=2`).set('Authorization', a).expect(200);
    const word = result.body.data.items.find((item: { _id: string }) => item._id === String(entries[12]));
    expect(word).toMatchObject({ mediaUnavailable: true, videoUrl: '', thumbnailUrl: '', imageUrls: [] });
  });
  it('persists self ratings, schedules review, and isolates accounts', async () => {
    await request(app).patch(`/api/v1/learning/words/${entries[0]}/progress`).set('Authorization', a).send({ stage: 'REMEMBERED' }).expect(200);
    let progress = await request(app).get('/api/v1/learning/progress').set('Authorization', a).expect(200);
    expect(progress.body.data.summary).toMatchObject({ remembered: 1, learning: 12, review: 0, total: 13 });
    const other = await request(app).get('/api/v1/learning/progress').set('Authorization', b).expect(200);
    expect(other.body.data.items).toHaveLength(0);
    await WordProgress.updateOne({ userId: userA, entryId: entries[0] }, { $set: { nextReviewAt: new Date(Date.now() - 1000) } });
    progress = await request(app).get('/api/v1/learning/progress?stage=REVIEW').set('Authorization', a).expect(200);
    expect(progress.body.data.summary).toMatchObject({ remembered: 0, review: 1 });
    const review = await request(app).get(`/api/v1/learning/topics/${topics[0]}?stage=REVIEW`).set('Authorization', a).expect(200);
    expect(review.body.data.items).toHaveLength(1);
    await request(app).patch(`/api/v1/learning/words/${entries[0]}/progress`).set('Authorization', a).send({ stage: 'REMEMBERED' }).expect(409);
    await WordProgress.updateOne({ userId: userA, entryId: entries[0] }, { $set: { stage: 'LEARNING', nextReviewAt: null } });
    await request(app).patch(`/api/v1/learning/words/${entries[13]}/progress`).set('Authorization', a).send({ stage: 'REMEMBERED' }).expect(404);
  });
  it('paginates many enrolled topics and escapes search text', async () => {
    for (const topic of topics.slice(1)) await request(app).post(`/api/v1/learning/topics/${topic}/start`).set('Authorization', a).send({}).expect(200);
    const progress = await request(app).get('/api/v1/learning/progress?page=2').set('Authorization', a).expect(200);
    expect(progress.body.data.items).toHaveLength(2);
    expect(progress.body.data.pagination.total).toBe(12);
    const search = await request(app).get('/api/v1/learning/topics?search=%5B%2E*').set('Authorization', a).expect(200);
    expect(search.body.data.items).toHaveLength(0);
  });
  it('stores private words, examples, images and ownership checks', async () => {
    let id = '';
    for (let i = 0; i < 11; i++) {
      const created = await request(app).post('/api/v1/learning/my-words').set('Authorization', a).send({ word: `Từ riêng ${i}`, definition: 'Ý nghĩa riêng', usageExample: 'Ví dụ của tôi', imageUrl: 'https://example.com/sign.jpg' }).expect(201);
      id = created.body.data._id;
    }
    const mine = await request(app).get('/api/v1/learning/my-words?page=2').set('Authorization', a).expect(200);
    expect(mine.body.data.items).toHaveLength(1);
    expect(mine.body.data.pagination.total).toBe(11);
    expect((await request(app).get('/api/v1/learning/my-words').set('Authorization', b)).body.data.items).toHaveLength(0);
    await request(app).patch(`/api/v1/learning/my-words/${id}`).set('Authorization', b).send({ definition: 'Xâm nhập' }).expect(404);
    await request(app).delete(`/api/v1/learning/my-words/${id}`).set('Authorization', b).expect(404);
    await request(app).patch(`/api/v1/learning/my-words/${id}`).set('Authorization', a).send({ definition: 'Đã sửa' }).expect(200);
    await request(app).post('/api/v1/learning/my-words').set('Authorization', a).send({ word: 'Sai', definition: 'Sai', videoUrl: 'javascript:alert(1)' }).expect(400);
    await request(app).delete(`/api/v1/learning/my-words/${id}`).set('Authorization', a).expect(200);
  });
  it('labels LM Studio advice and never lets advice change self ratings', async () => {
    const before = await WordProgress.find({ userId: userA }).lean();
    const oldModel = process.env.LM_STUDIO_MODEL;
    process.env.LM_STUDIO_MODEL = 'test-coach';
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ choices: [{ message: { content: 'Ôn tập 5 phút với từ đã chọn.' } }] }), { status: 200 }));
    const advice = await request(app).post('/api/v1/learning/coach').set('Authorization', a).send({}).expect(200);
    expect(advice.body.data.source).toBe('lm-studio');
    expect(await WordProgress.find({ userId: userA }).lean()).toEqual(before);
    fetchMock.mockRejectedValue(new Error('offline'));
    const fallback = await request(app).post('/api/v1/learning/coach').set('Authorization', a).send({}).expect(200);
    expect(fallback.body.data.source).toBe('rules');
    fetchMock.mockRestore();
    if (oldModel === undefined) delete process.env.LM_STUDIO_MODEL; else process.env.LM_STUDIO_MODEL = oldModel;
  });
  it('removes learning data with its owning account', async () => {
    await deleteOwnAccount(userA);
    expect(await TopicEnrollment.countDocuments({ userId: userA })).toBe(0);
    expect(await WordProgress.countDocuments({ userId: userA })).toBe(0);
    expect(await PersonalWord.countDocuments({ userId: userA })).toBe(0);
    expect(await User.exists({ _id: userB })).not.toBeNull();
  });
});
