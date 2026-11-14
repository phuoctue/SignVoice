import {guestGrantBody} from './guest-fixture';
import { afterAll, beforeAll, beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { randomUUID } from 'crypto';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { env } from '../src/config/env';
import { oauthConfig } from '../src/config/oauth';
import { OAuthState } from '../src/models/OAuthState.model';
import { User, AccountStatus } from '../src/models/User.model';
import { UserSettings } from '../src/models/UserSettings.model';
import { AuthSession } from '../src/models/AuthSession.model';
import { AuditLog } from '../src/models/AuditLog.model';
import { exchangeIdentity, googleVerifier } from '../src/services/oauth-provider.service';
import { digest } from '../src/services/oauth.service';

let app: Awaited<ReturnType<typeof createApp>>;
const original = { ...env };
const prefix = `oauth-${randomUUID()}`;
const ids: string[] = [];
const states: string[] = [];
beforeAll(async () => { await connectDatabase(); await User.init(); await OAuthState.init(); app = await createApp(); });
beforeEach(() => {
  env.GOOGLE_CLIENT_ID = 'google-test'; env.GOOGLE_CLIENT_SECRET = 'google-secret';
  env.FACEBOOK_APP_ID = 'facebook-test'; env.FACEBOOK_APP_SECRET = 'facebook-secret';
  env.FACEBOOK_GRAPH_API_VERSION = 'v25.0'; env.OAUTH_BACKEND_ORIGIN = 'http://localhost:3000';
  env.OAUTH_FRONTEND_ORIGIN = 'http://localhost:8080'; env.NODE_ENV = 'test';
  env.OAUTH_STATE_TTL_SECONDS = 600; env.GOOGLE_CALLBACK_URL = ''; env.FACEBOOK_CALLBACK_URL = '';
  env.CORS_ALLOWED_ORIGINS = ['http://localhost:8080'];
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); Object.assign(env, original); });
afterAll(async () => {
  const users = await User.find({ $or: [{ displayName: new RegExp(`^${prefix}`) }, { _id: { $in: ids } }] });
  const userIds = users.map(u => u._id);
  await Promise.all([AuthSession.deleteMany({ userId: { $in: userIds } }), UserSettings.deleteMany({ userId: { $in: userIds } }),
    AuditLog.deleteMany({ userId: { $in: userIds } }), User.deleteMany({ _id: { $in: userIds } }),
    OAuthState.deleteMany({ stateHash: { $in: states.map(digest) } })]);
  await disconnectDatabase();
});
async function start(provider = 'google') {
  const response = await request(app).get(`/api/v1/auth/oauth/${provider}/start`).expect(302);
  const url = new URL(response.headers.location);
  const state = url.searchParams.get('state')!;
  states.push(state);
  const cookie = (response.headers['set-cookie'] as unknown as string[])[0];
  expect(cookie).toContain('HttpOnly'); expect(cookie).toContain('SameSite=Lax');
  return { state, cookie: cookie.split(';')[0], nonce: url.searchParams.get('nonce'), url };
}
function google(nonce: string | null, overrides = {}) {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({ id_token: 'fake-provider-id-token' }))));
  vi.spyOn(googleVerifier, 'verifyIdToken').mockResolvedValue({ getPayload: () => ({
    sub: `${prefix}-${randomUUID()}`, aud: env.GOOGLE_CLIENT_ID, iss: 'https://accounts.google.com',
    exp: Math.floor(Date.now() / 1000) + 300, nonce, email: `${prefix}-${randomUUID()}@example.com`,
    email_verified: true, name: prefix, ...overrides,
  }) } as any);
}
const callback = (s: { state: string; cookie: string }, provider = 'google') =>
  request(app).get(`/api/v1/auth/oauth/${provider}/callback`).set('Cookie', s.cookie);

describe('OAuth configuration and browser-bound state', () => {
  it('reports only availability flags and leaves password/guest login working without credentials', async () => {
    env.GOOGLE_CLIENT_ID = ''; env.FACEBOOK_APP_ID = '';
    const response = await request(app).get('/api/v1/auth/oauth/providers').expect(200);
    expect(response.body.data).toEqual({ google: false, facebook: false });
    expect((await request(app).get('/api/v1/auth/oauth/google/start').expect(503)).body.error.code).toBe('OAUTH_DISABLED');
    const email = `${prefix}@example.com`, password = 'OAuthTest123';
    const registered = await request(app).post('/api/v1/auth/register').send({ email, password, displayName: prefix }).expect(201);
    ids.push(registered.body.data.user.id);
    await request(app).post('/api/v1/auth/login').send({ email, password }).expect(200);
    const guest = await request(app).post('/api/v1/auth/guest').send(guestGrantBody()).expect(201); ids.push(guest.body.data.user.id);
  });
  it.each(['http://evil.example', 'https://u:p@example.com', 'https://example.com/path', 'javascript:alert(1)'])('rejects unsafe origin %s', origin => {
    env.OAUTH_BACKEND_ORIGIN = origin;
    expect(() => oauthConfig('google')).toThrowError(/Cấu hình OAuth/);
  });
  it('requires HTTPS in production and rejects callback override or cross-site frontend', () => {
    env.NODE_ENV = 'production'; expect(() => oauthConfig('google')).toThrow();
    env.NODE_ENV = 'test'; env.GOOGLE_CALLBACK_URL = 'https://evil.example/api/v1/auth/oauth/google/callback';
    expect(() => oauthConfig('google')).toThrow();
    env.GOOGLE_CALLBACK_URL = ''; env.OAUTH_FRONTEND_ORIGIN = 'https://evil.example';
    expect(() => oauthConfig('google')).toThrow();
  });
  it('ignores attacker Host and redirect parameters and uses PKCE', async () => {
    const response = await request(app).get('/api/v1/auth/oauth/google/start?redirect=https://evil.example')
      .set('Host', 'evil.example').set('X-Forwarded-Host', 'evil.example').expect(302);
    const url = new URL(response.headers.location); states.push(url.searchParams.get('state')!);
    expect(url.searchParams.get('redirect_uri')).toBe('http://localhost:3000/api/v1/auth/oauth/google/callback');
    expect(url.searchParams.get('code_challenge_method')).toBe('S256');
    expect(url.searchParams.get('code_challenge')).toMatch(/^[\w-]{43}$/);
  });
  it('rejects missing state, mismatched browser, provider mismatch, expired and replayed state', async () => {
    const s = await start();
    for (const req of [callback(s), request(app).get('/api/v1/auth/oauth/google/callback').query({ state: s.state, code: 'code' }),
      callback(s, 'facebook').query({ state: s.state, code: 'code' })]) {
      const response = await req.expect(303); expect(response.headers.location).toContain('OAUTH_STATE_INVALID');
    }
    await OAuthState.updateOne({ stateHash: digest(s.state) }, { expiresAt: new Date(0) });
    expect((await callback(s).query({ state: s.state, code: 'code' }).expect(303)).headers.location).toContain('OAUTH_STATE_INVALID');
    const cancelled = await start();
    expect((await callback(cancelled).query({ state: cancelled.state, error: 'access_denied', error_description: 'secret' }).expect(303)).headers.location).toContain('OAUTH_CANCELLED');
    expect((await callback(cancelled).query({ state: cancelled.state, code: 'code' }).expect(303)).headers.location).toContain('OAUTH_STATE_INVALID');
  });
  it('accepts a state at most once under concurrent callbacks', async () => {
    const s = await start(); google(s.nonce);
    const responses = await Promise.all([callback(s).query({ state: s.state, code: 'code' }), callback(s).query({ state: s.state, code: 'code' })]);
    expect(responses.filter(r => r.headers.location.includes('OAUTH_STATE_INVALID'))).toHaveLength(1);
    expect(responses.filter(r => r.headers.location === 'http://localhost:8080/#/oauth-complete')).toHaveLength(1);
  });
});

describe('OAuth identity verification and real session handoff', () => {
  it.each([{ aud: 'wrong' }, { iss: 'evil' }, { nonce: 'wrong' }, { exp: 1 }, { email_verified: false }, { sub: '' }])('rejects invalid Google claims %j', async overrides => {
    google('nonce', overrides);
    await expect(exchangeIdentity('google', oauthConfig('google'), 'code', 'nonce', 'verifier')).rejects.toMatchObject({ code: 'OAUTH_IDENTITY_INVALID' });
  });
  it('does not trust an unverified Google signature', async () => {
    google('nonce'); vi.mocked(googleVerifier.verifyIdToken).mockRejectedValue(new Error('bad signature token secret'));
    await expect(exchangeIdentity('google', oauthConfig('google'), 'code', 'nonce', 'verifier')).rejects.toMatchObject({ message: 'Không xác minh được danh tính OAuth. Vui lòng đăng nhập lại.' });
  });
  it('creates persisted sessions, metadata and rotates cookie completion without URL tokens', async () => {
    const s = await start(); google(s.nonce);
    const response = await callback(s).query({ state: s.state, code: 'code' }).expect(303);
    expect(response.headers.location).toBe('http://localhost:8080/#/oauth-complete');
    const cookie = (response.headers['set-cookie'] as unknown as string[]).find(c => c.startsWith('signvoice_refresh='))!;
    expect(cookie).toContain('HttpOnly');
    const completed = await request(app).post('/api/v1/auth/oauth/complete').set('Origin', env.OAUTH_FRONTEND_ORIGIN)
      .set('Cookie', cookie.split(';')[0]).send({}).expect(200);
    ids.push(completed.body.data.user.id);
    expect(await UserSettings.exists({ userId: completed.body.data.user.id })).toBeTruthy();
    expect(await AuthSession.countDocuments({ userId: completed.body.data.user.id })).toBe(4);
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${completed.body.data.tokens.accessToken}`).expect(200);
    await request(app).post('/api/v1/auth/oauth/complete').set('Origin', env.OAUTH_FRONTEND_ORIGIN)
      .set('Cookie', cookie.split(';')[0]).send({}).expect(401);
    await request(app).post('/api/v1/auth/oauth/complete').set('Cookie', cookie.split(';')[0]).send({}).expect(403);
  });
  it('never merges a matching local email; suspended identities cannot sign in', async () => {
    const email = `${prefix}-collision@example.com`;
    const register = await request(app).post('/api/v1/auth/register').send({ email, password: 'OAuthTest123', displayName: prefix }).expect(201);
    ids.push(register.body.data.user.id);
    let s = await start(); google(s.nonce, { email });
    expect((await callback(s).query({ state: s.state, code: 'code' })).headers.location).toContain('OAUTH_ACCOUNT_COLLISION');
    expect((await User.findById(register.body.data.user.id))!.googleProvider?.providerId).toBeUndefined();
    vi.restoreAllMocks(); s = await start(); const subject = `${prefix}-suspended`;
    const user = await User.create({ displayName: prefix, accountType: 'GOOGLE', googleProvider: { providerId: subject }, status: AccountStatus.SUSPENDED });
    ids.push(user.id); google(s.nonce, { sub: subject });
    expect((await callback(s).query({ state: s.state, code: 'code' })).headers.location).toContain('USER_DISABLED');
  });
  it.each([{ app_id: 'wrong' }, { is_valid: false }, { user_id: 'wrong' }, { expires_at: 1 }, { data_access_expires_at: 1 }])('rejects invalid Facebook token metadata %j', async overrides => {
    const now = Math.floor(Date.now() / 1000) + 600;
    const fetch = vi.fn().mockResolvedValueOnce(new Response(JSON.stringify({ access_token: 'fb-token', token_type: 'bearer' })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ data: { app_id: env.FACEBOOK_APP_ID, is_valid: true, type: 'USER',
        user_id: 'subject', expires_at: now, data_access_expires_at: now, ...overrides } })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: 'subject', name: prefix })));
    vi.stubGlobal('fetch', fetch);
    await expect(exchangeIdentity('facebook', oauthConfig('facebook'), 'code', 'nonce', 'verifier')).rejects.toMatchObject({ code: 'OAUTH_IDENTITY_INVALID' });
  });
  it('verifies Facebook identity and uses appsecret_proof without persisting provider tokens', async () => {
    const s = await start('facebook'), subject = `${prefix}-facebook`, now = Math.floor(Date.now() / 1000) + 600;
    const fetch = vi.fn().mockResolvedValueOnce(new Response(JSON.stringify({ access_token: 'private-fb-token', token_type: 'bearer' })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ data: { app_id: env.FACEBOOK_APP_ID, is_valid: true, type: 'USER',
        user_id: subject, expires_at: now, data_access_expires_at: now } })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: subject, name: prefix })));
    vi.stubGlobal('fetch', fetch);
    const response = await callback(s, 'facebook').query({ state: s.state, code: 'code' }).expect(303);
    expect(response.headers.location).not.toContain('error');
    expect(fetch.mock.calls[2][0]).toContain('appsecret_proof=');
    const user = await User.findOne({ 'facebookProvider.providerId': subject });
    expect(user).toBeTruthy(); expect(JSON.stringify(user)).not.toContain('private-fb-token');
  });
  it('changes local passwords only after proof and revokes existing access/refresh sessions', async () => {
    const email = `${prefix}-password@example.com`, password = 'PasswordTest123';
    const registered = await request(app).post('/api/v1/auth/register').send({ email, password, displayName: prefix }).expect(201);
    const { user, tokens } = registered.body.data; ids.push(user.id);
    const change = () => request(app).post('/api/v1/auth/change-password').set('Authorization', `Bearer ${tokens.accessToken}`);
    const rejected = await change().send({ currentPassword: 'wrong', newPassword: 'NewPassword123' }).expect(400);
    expect(rejected.body.error.code).toBe('VALIDATION_ERROR');
    expect(rejected.headers['set-cookie']).toBeUndefined();
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${tokens.accessToken}`).expect(200);
    await change().send({ currentPassword: password, newPassword: 'weak' }).expect(400);
    await change().send({ currentPassword: password, newPassword: password }).expect(422);
    const response = await change().send({ currentPassword: password, newPassword: 'NewPassword123' }).expect(200);
    expect(response.headers['set-cookie'][0]).toContain('signvoice_refresh=;');
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${tokens.accessToken}`).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: tokens.refreshToken }).expect(401);
    await request(app).post('/api/v1/auth/login').send({ email, password }).expect(401);
    await request(app).post('/api/v1/auth/login').send({ email, password: 'NewPassword123' }).expect(200);
    const guest = await request(app).post('/api/v1/auth/guest').send(guestGrantBody()).expect(201); ids.push(guest.body.data.user.id);
    await request(app).post('/api/v1/auth/change-password').set('Authorization', `Bearer ${guest.body.data.tokens.accessToken}`)
      .send({ currentPassword: password, newPassword: 'NewPassword123' }).expect(400);
  });
});
