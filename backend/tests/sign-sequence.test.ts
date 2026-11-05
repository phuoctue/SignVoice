import { describe, expect, it, vi, afterEach } from 'vitest';
import express from 'express';
import request from 'supertest';
import { composeSignSequence, SignMediaEntry } from '../src/services/sign-sequence';
import router from '../src/routes/sign-sequence.routes';
import { DictionaryEntry } from '../src/models/DictionaryEntry.model';
// These tests isolate composition/query behavior; real trial/auth protection is
// exercised against MongoDB in guest-trial.test.ts.
vi.mock('../src/common/middlewares/auth.middleware', () => ({requireAuth: (_req: unknown, _res: unknown, next: () => void) => next()}));
vi.mock('../src/common/middlewares/guest-trial.middleware', () => ({requireActiveTrial: (_req: unknown, _res: unknown, next: () => void) => next()}));

const entry = (word: string, extra = {}): SignMediaEntry => ({ _id: word, word, videoUrl: 'https://example.org/sign.mp4', ...extra });
afterEach(() => vi.restoreAllMocks());

describe('dictionary sequence', () => {
  it('spells missing Vietnamese words with real letter media and preserves their accents', () => {
    const result = composeSignSequence('tôi là bạn', [entry('tôi'), entry('bạn'), entry('l'), entry('a')]);
    expect(result.segments.map(s => s.type)).toEqual(['sign', 'fingerspelling', 'sign']);
    expect(result.segments[1]).toMatchObject({text: 'là', letters: [
      {type: 'sign', text: 'l', word: 'l'}, {type: 'sign', text: 'à', word: 'a'},
    ], hasTone: true});
    expect(composeSignSequence('tớ', [entry('t'), entry('ơ')]).segments[0]).toMatchObject({
      type: 'fingerspelling', letters: [{word: 't'}, {word: 'ơ'}],
    });
  });
  it('does not invent or partially drop letters when spelling media is missing', () => {
    expect(composeSignSequence('là', [entry('l')]).segments[0].type).toBe('missing');
    expect(composeSignSequence('là', [entry('l'), entry('a', {videoUrl: undefined})]).segments[0].type).toBe('missing');
  });
  it('uses explicit aliases while preferring an exact dictionary word', () => {
    const rows = [entry('0 (số không)', {aliases: ['0', 'số không']}), entry('bạn', {aliases: ['các bạn']}), entry('các bạn')];
    expect(composeSignSequence('0 các bạn', rows).segments).toMatchObject([
      {type: 'sign', word: '0 (số không)'}, {type: 'sign', word: 'các bạn'},
    ]);
  });
  it('keeps multi-syllable words and chooses longest phrase', () => {
    const result = composeSignSequence('Bàn tay bạn', [entry('bàn'), entry('bàn tay'), entry('bạn')]);
    expect(result.segments.map(s => [s.type, s.text])).toEqual([['sign', 'Bàn tay'], ['sign', 'bạn']]);
  });
  it('preserves punctuation, repetition and missing words without alias guesses', () => {
    const result = composeSignSequence('xin chào, tôi là An! chào chào', [entry('chào'), entry('tôi')]);
    expect(result.segments.map(s => [s.type, s.text])).toEqual([
      ['missing', 'xin'], ['sign', 'chào'], ['punctuation', ','], ['sign', 'tôi'],
      ['missing', 'là'], ['missing', 'An'], ['punctuation', '!'], ['sign', 'chào'], ['sign', 'chào'],
    ]);
  });
  it('matches decomposed Vietnamese but keeps original text and accents', () => {
    const text = 'CHÀO'.normalize('NFD');
    const result = composeSignSequence(text, [entry('chào')]);
    expect(result.segments[0]).toMatchObject({ type: 'sign', text, start: 0, end: text.length });
    expect(composeSignSequence('chao', [entry('chào')]).segments[0]).toMatchObject({type: 'sign', word: 'chào'});
  });
  it('matches the longest unaccented phrase before fingerspelling and preserves input', () => {
    expect(composeSignSequence('xin chao, rat vui duoc gap ban', [
      entry('xin'), entry('chào'), entry('xin chào'), entry('rất vui'), entry('được'), entry('gặp'), entry('bạn'),
    ]).segments).toMatchObject([
      {type: 'sign', text: 'xin chao', word: 'xin chào'},
      {type: 'punctuation', text: ','}, {type: 'sign', word: 'rất vui'},
      {type: 'sign', word: 'được'}, {type: 'sign', word: 'gặp'}, {type: 'sign', word: 'bạn'},
    ]);
  });
  it('keeps exact accents authoritative and reports ambiguous unaccented words', () => {
    const rows = [entry('bàn'), entry('bạn')];
    expect(composeSignSequence('ban', rows).segments[0].type).toBe('ambiguous');
    expect(composeSignSequence('bạn', rows).segments[0]).toMatchObject({type: 'sign', word: 'bạn'});
    expect(composeSignSequence('bán', rows).segments[0].type).toBe('missing');
  });
  it('does not match a phrase across punctuation', () => {
    expect(composeSignSequence('bàn, tay', [entry('bàn tay')]).segments.map(s => s.type))
      .toEqual(['missing', 'punctuation', 'missing']);
  });
  it('marks duplicate words ambiguous instead of selecting a random variant', () => {
    expect(composeSignSequence('chào', [entry('chào'), entry('CHÀO')]).segments[0].type).toBe('ambiguous');
  });
  it('removes executable media URLs and distinguishes missing media', () => {
    const result = composeSignSequence('tôi', [entry('tôi', { videoUrl: 'javascript:alert(1)', imageUrls: ['data:text/html,x'] })]);
    expect(result.segments[0]).toMatchObject({ type: 'missing_media', imageUrls: [] });
    expect(result.segments[0].videoUrl).toBeUndefined();
  });
  it('returns missing tokens for an empty published catalog', () => {
    expect(composeSignSequence('rau', []).segments[0]).toMatchObject({ type: 'missing', text: 'rau' });
  });
});

describe('sequence endpoint', () => {
  const app = express().use(express.json()).use('/sequence', router);
  it('validates input before touching the database', async () => {
    const spy = vi.spyOn(DictionaryEntry, 'find');
    for (const text of ['', ' ', null, {}, 'a'.repeat(2001)]) {
      expect((await request(app).post('/sequence').send({ text })).status).toBe(400);
    }
    expect(spy).not.toHaveBeenCalled();
  });
  it('fetches only published entries and does not depend on dictionary page size', async () => {
    const rows = Array.from({ length: 125 }, (_, i) => entry(`mục ${i}`));
    const query = { select: vi.fn().mockReturnThis(), sort: vi.fn().mockReturnThis(), limit: vi.fn().mockReturnThis(), lean: vi.fn().mockResolvedValue(rows) };
    const spy = vi.spyOn(DictionaryEntry, 'find').mockReturnValue(query as never);
    const response = await request(app).post('/sequence').send({ text: 'mục 124' });
    expect(spy).toHaveBeenCalledWith({ status: 'PUBLISHED' });
    expect(response.status).toBe(200);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.body.data.segments[0]).toMatchObject({ type: 'sign', text: 'mục 124' });
    expect(response.body.data.catalogEntries).toBe(125);
  });
});
