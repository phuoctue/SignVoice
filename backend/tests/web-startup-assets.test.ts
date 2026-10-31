import express from 'express';
import request from 'supertest';
import {afterAll, beforeAll, describe, expect, it} from 'vitest';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import {serveWebStartupAssets} from '../src/web-startup-assets';

const runtime = path.resolve(__dirname, '../../.runtime');
const root = mkdtempSync(path.join(runtime, 'startup-assets-'));
const javascript = 'window.startup = "SignVoice";\n'.repeat(10000);
let app: express.Application;
beforeAll(() => {
  writeFileSync(path.join(root, 'main.dart.js'), javascript);
  mkdirSync(path.join(root, 'canvaskit/chromium'), {recursive: true});
  writeFileSync(path.join(root, 'canvaskit/chromium/canvaskit.wasm'), Buffer.alloc(10000, 7));
  app = express(); serveWebStartupAssets(app, root);
});
afterAll(() => {
  if (!root.startsWith(runtime + path.sep)) throw new Error('Unsafe fixture cleanup');
  rmSync(root, {recursive: true, force: true});
});
describe('Startup assets', () => {
  it('compresses JavaScript for supporting clients and revalidates changed versions', async () => {
    const response = await request(app).get('/main.dart.js').set('Accept-Encoding', 'gzip').expect(200);
    expect(response.headers['content-encoding']).toBe('gzip');
    expect(Number(response.headers['content-length'])).toBeLessThan(javascript.length / 2);
    expect(response.text).toBe(javascript);
    expect(response.headers.vary).toContain('Accept-Encoding');
    expect(response.headers['cache-control']).toContain('no-cache');
    await request(app).get('/main.dart.js').set('Accept-Encoding', 'gzip;q=0, identity;q=0').expect(406);
    await request(app).get('/main.dart.js').set('Accept-Encoding', 'gzip').set('If-None-Match', response.headers.etag).expect(304);
  });
  it('preserves identity responses and leaves API and unknown paths alone', async () => {
    const response = await request(app).get('/main.dart.js').set('Accept-Encoding', 'gzip;q=0, identity').expect(200);
    expect(response.headers['content-encoding']).toBeUndefined();
    expect(response.text).toBe(javascript);
    await request(app).get('/api/v1/users/profile').expect(404);
    await request(app).get('/canvaskit/missing.wasm').expect(404);
    await request(app).head('/canvaskit/chromium/canvaskit.wasm').set('Accept-Encoding', 'gzip').expect(200).expect('Content-Encoding', 'gzip');
  });
  it('does not preload the camera model before entering the camera flow', () => {
    const html = readFileSync(path.resolve(__dirname, '../../web/index.html'), 'utf8');
    expect(html).not.toMatch(/<link[^>]*rel="preload"[^>]*hand_landmarker/);
    expect(html).toMatch(/<link[^>]*rel="preload"[^>]*href="main\.dart\.js"[^>]*as="script"/);
  });
});
