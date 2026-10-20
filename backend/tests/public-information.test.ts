import express from 'express';
import request from 'supertest';
import { afterEach, describe, it, expect, vi } from 'vitest';
import { servePublicInformation } from '../src/public-information';

afterEach(() => vi.unstubAllEnvs());
describe('Public privacy information', () => {
  it('marks missing operator/contact configuration as a draft', async () => {
    vi.stubEnv('PRIVACY_OPERATOR_NAME', ''); vi.stubEnv('SUPPORT_EMAIL', '');
    const app = express(); servePublicInformation(app);
    const response = await request(app).get('/privacy').expect(503);
    expect(response.text).toContain('BẢN NHÁP');
  });
  it('serves public readable HTML without login and escapes operator information', async () => {
    vi.stubEnv('PRIVACY_OPERATOR_NAME', '<script>alert(1)</script>');
    vi.stubEnv('SUPPORT_EMAIL', 'support@example.com');
    const app = express(); servePublicInformation(app);
    for (const path of ['/privacy', '/data-deletion']) {
      const response = await request(app).get(path).expect(200);
      expect(response.headers['content-type']).toContain('text/html');
      expect(response.text).not.toContain('<script>');
      expect(response.text).toContain('&lt;script&gt;');
      expect(response.text).toContain('support@example.com');
    }
  });
});
