import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import express from 'express';
import request from 'supertest';
import { createSignMediaRouter } from '../src/routes/sign-media.routes';
import { DictionaryEntry } from '../src/models/DictionaryEntry.model';

let folder: string;
beforeEach(() => { folder = mkdtempSync(path.join(tmpdir(), 'signvoice-media-test-')); });
afterEach(() => { vi.restoreAllMocks(); rmSync(folder, { recursive: true, force: true }); });
const file = `${'a'.repeat(64)}.mp4`;
const query = (value: unknown) => ({ select: vi.fn().mockReturnThis(), lean: vi.fn().mockResolvedValue(value) });
describe('published reference media', () => {
  it('streams byte ranges required for mobile seeking', async () => {
    writeFileSync(path.join(folder, file), Buffer.from('0123456789'));
    const spy = vi.spyOn(DictionaryEntry, 'findOne').mockReturnValue(query({ _id: 'published' }) as never);
    const app = express().use('/sign-media', createSignMediaRouter(folder));
    const response = await request(app).get(`/sign-media/${file}`).set('Range', 'bytes=2-5');
    expect(response.status).toBe(206);
    expect(response.headers['content-range']).toBe('bytes 2-5/10');
    expect(response.headers['content-type']).toContain('video/mp4');
    expect(Buffer.from(response.body).toString()).toBe('2345');
    expect(spy.mock.calls[0][0]).toMatchObject({ status: 'PUBLISHED' });
  });
  it('does not expose files without a published dictionary reference', async () => {
    writeFileSync(path.join(folder, file), 'private');
    vi.spyOn(DictionaryEntry, 'findOne').mockReturnValue(query(null) as never);
    const response = await request(express().use(createSignMediaRouter(folder))).get(`/${file}`);
    expect(response.status).toBe(404);
  });
  it('rejects arbitrary paths before database lookup', async () => {
    const spy = vi.spyOn(DictionaryEntry, 'findOne');
    const app = express().use(createSignMediaRouter(folder));
    expect((await request(app).get('/review.html')).status).toBe(404);
    expect((await request(app).get('/secret.json')).status).toBe(404);
    expect(spy).not.toHaveBeenCalled();
  });
  it('returns 404 for missing referenced assets', async () => {
    vi.spyOn(DictionaryEntry, 'findOne').mockReturnValue(query({ _id: 'missing-file' }) as never);
    const response = await request(express().use(createSignMediaRouter(folder))).get(`/${file}`);
    expect(response.status).toBe(404);
  });
});
