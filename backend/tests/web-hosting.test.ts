import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import path from 'path';
import request from 'supertest';
import { Application } from 'express';
import { createApp } from '../src/app';
import { env } from '../src/config/env';

const binaryParser = (res: NodeJS.ReadableStream, done: (error: Error | null, body?: Buffer) => void) => {
  const chunks: Buffer[] = [];
  res.on('data', chunk => chunks.push(Buffer.from(chunk)));
  res.on('end', () => done(null, Buffer.concat(chunks)));
  res.on('error', done);
};

let app: Application;
const webRoot = mkdtempSync(path.join(tmpdir(), 'signvoice-web-test-'));
const previous = { serveWeb: env.SERVE_WEB, webRoot: env.WEB_BUILD_DIR };

beforeAll(async () => {
  writeFileSync(path.join(webRoot, 'index.html'), '<html><body>SignVoice web</body></html>');
  mkdirSync(path.join(webRoot, 'canvaskit'));
  mkdirSync(path.join(webRoot, 'mediapipe/wasm'), { recursive: true });
  writeFileSync(path.join(webRoot, 'mediapipe/wasm/vision_wasm_internal.wasm'), Buffer.alloc(8192, 7));
  writeFileSync(path.join(webRoot, 'canvaskit/canvaskit.wasm'), Buffer.from([0, 97, 115, 109]));
  env.SERVE_WEB = true;
  env.WEB_BUILD_DIR = webRoot;
  app = await createApp();
});

afterAll(() => {
  env.SERVE_WEB = previous.serveWeb;
  env.WEB_BUILD_DIR = previous.webRoot;
  rmSync(webRoot, { recursive: true, force: true });
});

describe('Same-origin Flutter web hosting', () => {
  it('compresses and caches detector assets while preserving decoded bytes and conditional requests', async () => {
    const url = '/mediapipe/wasm/vision_wasm_internal.wasm?v=8.2';
    const response = await request(app).get(url).set('Accept-Encoding', 'gzip').buffer(true).parse(binaryParser).expect(200);
    expect(response.headers['content-encoding']).toBe('gzip');
    expect(response.headers['content-type']).toBe('application/wasm');
    expect(response.headers['cache-control']).toContain('max-age=86400');
    expect(Number(response.headers['content-length'])).toBeLessThan(100);
    expect(response.body).toEqual(Buffer.alloc(8192, 7));
    await request(app).get(url).set('Accept-Encoding', 'gzip').set('If-None-Match', response.headers.etag).expect(304);
    const plain = await request(app).get(url).set('Accept-Encoding', 'identity').buffer(true).parse(binaryParser).expect(200);
    expect(plain.headers['content-encoding']).toBeUndefined();
    expect(plain.body).toEqual(Buffer.alloc(8192, 7));
    await request(app).get('/mediapipe/secret.txt').expect(404);
  });
  it('serves Flutter HTML and routes with revalidation headers', async () => {
    const response = await request(app).get('/').expect(200);
    expect(response.text).toContain('SignVoice web');
    expect(response.headers['cache-control']).toBe('no-cache');
    expect(response.headers['content-security-policy']).toContain("'wasm-unsafe-eval'");
    await request(app).get('/staff').expect(200);
  });

  it('serves WebAssembly with the correct content type', async () => {
    const response = await request(app).get('/canvaskit/canvaskit.wasm').expect(200);
    expect(response.headers['content-type']).toBe('application/wasm');
  });

  it('keeps API authorization and unknown API 404 responses', async () => {
    await request(app).get('/api/v1/auth/me').expect(401);
    const response = await request(app).get('/api/v1/unknown').expect(404);
    expect(response.body.success).toBe(false);
    await request(app).get('/missing.js').expect(404);
  });

  it('rejects unavailable web builds at startup', async () => {
    env.WEB_BUILD_DIR = path.join(webRoot, 'missing-build');
    try {
      await expect(createApp()).rejects.toThrow('Flutter web build is missing');
    } finally {
      env.WEB_BUILD_DIR = webRoot;
    }
  });
});
