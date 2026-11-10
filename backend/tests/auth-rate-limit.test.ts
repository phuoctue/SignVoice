import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import type { Application } from 'express';
import express from 'express';

// Enforce the real production thresholds in this file only.
let app: Application;
let appConfig: typeof import('../src/config/env').env;

beforeAll(async () => {
  process.env.AUTH_RATE_LIMIT_ENFORCE_IN_TEST = 'true';
  delete process.env.TRUST_PROXY;
  vi.resetModules();
  appConfig = (await import('../src/config/env')).env;
  const { createApp } = await import('../src/app');
  app = await createApp();
});

afterAll(() => {
  delete process.env.AUTH_RATE_LIMIT_ENFORCE_IN_TEST;
  vi.resetModules();
});

// Invalid payloads are rejected by validation (400) after the limiter has counted them,
// so these tests do not need user records.
async function exhaust(path: string, body: object, allowed: number, headers: Record<string, string> = {}) {
  for (let i = 0; i < allowed; i += 1) {
    const res = await request(app).post(path).set(headers).send(body);
    expect(res.status).not.toBe(429);
  }
  return request(app).post(path).set(headers).send(body);
}

describe('auth endpoint rate limits', () => {
  it('limits failed logins per IP + email, and spoofed X-Forwarded-For does not bypass it', async () => {
    const body = { email: 'victim@example.com' };
    const blocked = await exhaust('/api/v1/auth/login', body, 10);
    expect(blocked.status).toBe(429);
    expect(blocked.body.error.code).toBe('TOO_MANY_REQUESTS');

    const spoofed = await request(app).post('/api/v1/auth/login')
      .set('X-Forwarded-For', '203.0.113.77').send(body);
    expect(spoofed.status).toBe(429);

    // Another account from the same address is not locked out by the per-email budget.
    const other = await request(app).post('/api/v1/auth/login').send({ email: 'other@example.com' });
    expect(other.status).not.toBe(429);
  });

  it('limits registration per IP', async () => {
    const blocked = await exhaust('/api/v1/auth/register', {}, 20);
    expect(blocked.status).toBe(429);
  });

  it('limits guest creation per IP', async () => {
    const blocked = await exhaust('/api/v1/auth/guest', { invalid: true }, 30);
    expect(blocked.status).toBe(429);
  });

  it('limits refresh per IP', async () => {
    const blocked = await exhaust('/api/v1/auth/refresh', { invalid: true }, 120);
    expect(blocked.status).toBe(429);
  });
});

describe('TRUST_PROXY parsing', () => {
  afterAll(() => {
    delete process.env.TRUST_PROXY;
    vi.resetModules();
  });

  async function load(value: string | undefined) {
    vi.resetModules();
    if (value === undefined) delete process.env.TRUST_PROXY;
    else process.env.TRUST_PROXY = value;
    return (await import('../src/config/env')).env.TRUST_PROXY;
  }

  it('defaults to not trusting forwarded headers', async () => {
    expect(await load(undefined)).toBe(false);
  });

  it('accepts a hop count or explicit proxy list', async () => {
    expect(await load('1')).toBe(1);
    expect(await load('loopback')).toBe('loopback');
  });

  it('rejects TRUST_PROXY=true', async () => {
    await expect(load('true')).rejects.toThrow(/unsafe/);
  });

  it.each(['TRUE', 'yes', '0.0.0.0/0', '::/0', '99', 'not-a-proxy'])('rejects unsafe proxy configuration %s', async value => {
    await expect(load(value)).rejects.toThrow(/TRUST_PROXY/);
  });
});

describe('proxy client isolation', () => {
  async function proxyApp(trust: false | string | number, production = false) {
    vi.resetModules();
    process.env.AUTH_RATE_LIMIT_ENFORCE_IN_TEST = 'true';
    delete process.env.TRUST_PROXY;
    const {env} = await import('../src/config/env');
    env.isProduction = production;
    env.TRUST_PROXY = trust;
    const {loginLimiter, requireProxyClientIp} = await import('../src/common/middlewares/auth-rate-limit');
    const isolated = express();
    isolated.set('trust proxy', trust);
    isolated.use(express.json(), requireProxyClientIp, loginLimiter);
    isolated.post('/', (req, res) => res.status(400).json({ip: req.ip}));
    return isolated;
  }

  it.each([1, 'loopback'])('separates clients and ignores forged leftmost hops with trust=%s', async trust => {
    const proxy = await proxyApp(trust);
    for (let i = 0; i < 10; i++) {
      await request(proxy).post('/').set('X-Forwarded-For', `198.51.100.${i + 1}, 203.0.113.7`)
        .send({email: 'same@example.com'}).expect(400);
    }
    await request(proxy).post('/').set('X-Forwarded-For', '198.51.100.250, 203.0.113.7')
      .send({email: 'same@example.com'}).expect(429);
    const other = await request(proxy).post('/').set('X-Forwarded-For', '203.0.113.8')
      .send({email: 'same@example.com'}).expect(400);
    expect(other.body.ip).toBe('203.0.113.8');
  });

  it('does not trust forwarding headers from a peer outside the proxy allowlist', async () => {
    const direct = await proxyApp('192.0.2.10');
    const response = await request(direct).post('/').set('X-Forwarded-For', '203.0.113.9').send({});
    expect(response.body.ip).not.toBe('203.0.113.9');
  });

  it('returns 503 before sharing a loopback budget when the tunnel supplies no client IP', async () => {
    const proxy = await proxyApp('loopback', true);
    await request(proxy).post('/').send({}).expect(503);
    await request(proxy).post('/').set('X-Forwarded-For', '203.0.113.20').send({}).expect(400);
  });

  afterAll(() => {
    delete process.env.AUTH_RATE_LIMIT_ENFORCE_IN_TEST;
    delete process.env.TRUST_PROXY;
    vi.resetModules();
  });
});

describe('production loopback guard route scope', () => {
  let productionApp: Application;
  let previousProduction: boolean;
  let previousTrust: typeof appConfig.TRUST_PROXY;

  beforeAll(() => {
    // Use the real router with production guard behavior, without connecting to
    // a user database. Requests must reach auth/validation, never their handlers.
    // Reuse the app to avoid recompiling Mongoose models after resetModules.
    previousProduction = appConfig.isProduction;
    previousTrust = appConfig.TRUST_PROXY;
    appConfig.isProduction = true;
    appConfig.TRUST_PROXY = 'loopback';
    productionApp = app;
    productionApp.set('trust proxy', 'loopback');
  });

  afterAll(() => {
    appConfig.isProduction = previousProduction;
    appConfig.TRUST_PROXY = previousTrust;
    productionApp.set('trust proxy', previousTrust);
  });

  it.each(['login', 'register', 'guest', 'refresh'])('blocks %s without a forwarded client IP', async route => {
    const response = await request(productionApp).post(`/api/v1/auth/${route}`).send({});
    expect(response.status).toBe(503);
    expect(response.body.error.code).toBe('PROXY_CLIENT_IP_UNAVAILABLE');
  });

  it.each(['me', 'logout', 'logout-all'])('keeps Bearer authentication reachable for %s without XFF', async route => {
    const response = route === 'me'
      ? await request(productionApp).get('/api/v1/auth/me')
      : await request(productionApp).post(`/api/v1/auth/${route}`).send({});
    // A missing Bearer must reach requireAuth and return its normal 401.
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe('AUTH_REQUIRED');
  });

  it('keeps OAuth discovery and password-reset validation reachable without XFF', async () => {
    await request(productionApp).get('/api/v1/auth/oauth/providers').expect(200);
    const response = await request(productionApp).post('/api/v1/auth/reset-password').send({});
    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe('VALIDATION_ERROR');
  });
});
