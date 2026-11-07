import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import request from 'supertest';
import { mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFile } from 'node:fs/promises';
import { videoConverterPath } from '../src/services/video-conversion';
import { createVideoUploadRouter } from '../src/routes/video-upload.routes';
import { createSignMediaRouter } from '../src/routes/sign-media.routes';
import { DictionaryEntry } from '../src/models/DictionaryEntry.model';
import { errorHandler } from '../src/common/middlewares/errorHandler';
import { createPersonalVideoRouter } from '../src/routes/personal-video.routes';
import { ownedPersonalVideo, signPersonalVideo, validPersonalVideoSignature } from '../src/services/personal-video';

vi.mock('../src/common/middlewares/auth.middleware', async importOriginal => {
  const actual = await importOriginal<typeof import('../src/common/middlewares/auth.middleware')>();
  return { ...actual, requireAuth: (req: express.Request, res: express.Response, next: express.NextFunction) => {
    const role = req.get('x-test-role');
    if (!role) { res.sendStatus(401); return; }
    req.user = { id: 'a'.repeat(24), permissions: role === 'editor' ? ['dictionary:write'] : [] } as express.Request['user'];
    next();
  } };
});

let folder: string;
const bytes = Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypmp42'), Buffer.alloc(20)]);
const filename = `${createHash('sha256').update(bytes).digest('hex')}.mp4`;
beforeEach(() => { folder = mkdtempSync(path.join(tmpdir(), 'signvoice-upload-')); });
afterEach(() => { vi.restoreAllMocks(); rmSync(folder, { recursive: true, force: true }); });
function app(maxBytes?: number) {
  return express().use('/upload', createVideoUploadRouter(folder, async (input, output) => {
    await copyFile(input, output);
  }, maxBytes))
    .use('/sign-media', createSignMediaRouter(folder)).use(errorHandler);
}

describe('dictionary video upload', () => {
  it('lets a regular user upload private video, with signed ranged playback', async () => {
    const server = express().use('/upload', createVideoUploadRouter(folder, copyFile, 1024, 'personal'))
      .use('/personal-videos', createPersonalVideoRouter(folder)).use(errorHandler);
    const result = await request(server).post('/upload').set('x-test-role', 'user')
      .set('Content-Type', 'application/octet-stream').send(bytes).expect(201);
    const link = result.body.data.videoUrl;
    expect(link).toContain(`/personal-videos/${'a'.repeat(24)}/${filename}?`);
    const video = await request(server).get(link).set('Range', 'bytes=0-15').expect(206);
    expect(video.body).toEqual(bytes.subarray(0, 16));
    expect(video.headers['cache-control']).toBe('private, no-store');
    await request(server).get(link.split('?')[0]).expect(403);
    await request(server).get(link.replace('a'.repeat(24), 'b'.repeat(24))).expect(403);
    const url = new URL(link, 'http://localhost');
    url.searchParams.set('expires', '1');
    await request(server).get(url.pathname + url.search).expect(403);
  });

  it('prevents attaching another account private video and rejects forged links', () => {
    const resource = `/personal-videos/${'a'.repeat(24)}/${filename}`;
    expect(ownedPersonalVideo(signPersonalVideo(resource), 'a'.repeat(24))).toBe(resource);
    expect(() => ownedPersonalVideo(resource, 'b'.repeat(24))).toThrow('Video không thuộc tài khoản');
    expect(validPersonalVideoSignature(resource, '9999999999', '0'.repeat(64))).toBe(false);
  });
  it('requires authentication and dictionary editing permission before saving', async () => {
    const server = app();
    await request(server).post('/upload').set('Content-Type', 'video/mp4').send(bytes).expect(401);
    await request(server).post('/upload').set('x-test-role', 'user').set('Content-Type', 'video/mp4').send(bytes).expect(403);
    expect(readdirSync(folder)).toEqual([]);
  });

  it('stores exact bytes, deduplicates and streams only published video references', async () => {
    const server = app();
    for (let i = 0; i < 2; i++) {
      const uploaded = await request(server).post('/upload').set('x-test-role', 'editor')
        .set('Content-Type', 'video/mp4').send(bytes).expect(201);
      expect(uploaded.body.data.videoUrl).toMatch(new RegExp(`/sign-media/${filename}$`));
    }
    expect(readdirSync(folder)).toEqual([filename]);
    expect(readFileSync(path.join(folder, filename))).toEqual(bytes);
    let published = false;
    vi.spyOn(DictionaryEntry, 'findOne').mockImplementation(() => ({
      select: () => ({ lean: async () => published ? { _id: 'entry' } : null }),
    }) as never);
    await request(server).get(`/sign-media/${filename}`).expect(404);
    published = true;
    const streamed = await request(server).get(`/sign-media/${filename}`).set('Range', 'bytes=0-15').expect(206);
    expect(streamed.body).toEqual(bytes.subarray(0, 16));
  });

  it('rejects non-binary upload content types and empty files', async () => {
    const server = app();
    await request(server).post('/upload').set('x-test-role', 'editor')
      .set('Content-Type', 'text/html').send('<html>').expect(415);
    await request(server).post('/upload').set('x-test-role', 'editor')
      .set('Content-Type', 'application/octet-stream').send(Buffer.alloc(0)).expect(400);
    expect(readdirSync(folder)).toEqual([]);
  });

  it('rejects oversized input before writing a file', async () => {
    await request(app(1024)).post('/upload').set('x-test-role', 'editor')
      .set('Content-Type', 'application/octet-stream').send(Buffer.alloc(1025)).expect(413);
    expect(readdirSync(folder)).toEqual([]);
  });

  it.each(['mp4', 'mov', 'avi', 'mkv', 'webm'])('converts real %s video to a playable H.264 MP4', async extension => {
    const input = path.join(folder, `fixture.${extension}`);
    execFileSync(videoConverterPath(), ['-hide_banner', '-loglevel', 'error', '-y',
      '-f', 'lavfi', '-i', 'color=c=blue:s=64x64:r=10', '-t', '0.2',
      '-c:v', extension === 'webm' ? 'libvpx-vp9' : extension === 'avi' ? 'mpeg4' : 'libx264',
      '-threads', '1', input], { windowsHide: true });
    const server = express().use('/upload', createVideoUploadRouter(folder)).use(errorHandler);
    const uploaded = await request(server).post('/upload').set('x-test-role', 'editor')
      .set('Content-Type', 'application/octet-stream').send(readFileSync(input)).expect(201);
    const result = path.join(folder, uploaded.body.data.videoUrl.split('/').pop());
    expect(readFileSync(result).toString('ascii', 4, 8)).toBe('ftyp');
    const info = spawnSync(videoConverterPath(), ['-hide_banner', '-i', result, '-f', 'null', '-'], {
      windowsHide: true, encoding: 'utf8', stdio: 'pipe',
    });
    expect(info.status).toBe(0);
    expect(info.stderr).toContain('h264');
    expect(info.stderr).toContain('yuv420p');
  });

  it('rejects corrupt video and cleans temporary data after conversion fails', async () => {
    const server = express().use('/upload', createVideoUploadRouter(folder)).use(errorHandler);
    await request(server).post('/upload').set('x-test-role', 'editor')
      .set('Content-Type', 'application/octet-stream').send(Buffer.from('not a video')).expect(422);
    expect(readdirSync(folder)).toEqual([]);
  });
});
