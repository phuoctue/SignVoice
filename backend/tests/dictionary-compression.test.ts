import {afterAll, beforeAll, describe, expect, it} from 'vitest';
import express from 'express';
import {get} from 'node:http';
import {AddressInfo} from 'node:net';
import {gunzipSync} from 'node:zlib';
import {dictionaryCompression} from '../src/common/middlewares/dictionary-compression';

const app = express();
const body = {data: {word: 'xin chào', thumbnailDataUrl: 'data:image/jpeg;base64,' + 'abc123'.repeat(1000)}};
app.use(dictionaryCompression);
app.use((req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  return res.json(req.path === '/small' ? {ok: true} : body);
});
let server: ReturnType<typeof app.listen>, origin: string;
beforeAll(async () => {
  server = app.listen(0, '127.0.0.1');
  await new Promise<void>(resolve => server.once('listening', resolve));
  origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(async () => { await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); });
function read(path: string, encoding?: string) {
  return new Promise<{headers: import('node:http').IncomingHttpHeaders; bytes: Buffer}>((resolve, reject) => {
    get(origin + path, {headers: encoding === undefined ? {} : {'Accept-Encoding': encoding}}, response => {
      const chunks: Buffer[] = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('error', reject);
      response.on('end', () => resolve({headers: response.headers, bytes: Buffer.concat(chunks)}));
    }).on('error', reject);
  });
}
describe('dictionary JSON transport compression', () => {
  it('reduces wire bytes without changing Vietnamese JSON or private caching headers', async () => {
    const response = await read('/large', 'gzip');
    expect(response.headers['content-encoding']).toBe('gzip');
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.headers.vary).toContain('Accept-Encoding');
    expect(response.headers['content-type']).toContain('application/json');
    expect(JSON.parse(gunzipSync(response.bytes).toString('utf8'))).toEqual(body);
    expect(response.bytes.length).toBeLessThan(Buffer.byteLength(JSON.stringify(body)));
  });
  it.each([undefined, 'gzip;q=0, identity', 'br'])('keeps plain JSON when gzip is not accepted: %s', async encoding => {
    const response = await read('/large', encoding);
    expect(response.headers['content-encoding']).toBeUndefined();
    expect(JSON.parse(response.bytes.toString('utf8'))).toEqual(body);
  });
  it('does not compress small responses', async () => {
    const response = await read('/small', 'gzip');
    expect(response.headers['content-encoding']).toBeUndefined();
    expect(JSON.parse(response.bytes.toString('utf8'))).toEqual({ok: true});
  });
  it('leaves authentication responses uncompressed',async()=>{
    const response=await read('/auth/me','gzip');
    expect(response.headers['content-encoding']).toBeUndefined();
    expect(response.headers['cache-control']).toBe('no-store');
    expect(JSON.parse(response.bytes.toString('utf8'))).toEqual(body);
  });
});
