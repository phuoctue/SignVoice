import { beforeAll, afterAll, describe, expect, it } from 'vitest';
import request from 'supertest';
import { Application } from 'express';
import { randomUUID } from 'crypto';
import jwt from 'jsonwebtoken';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { env } from '../src/config/env';
import { User, UserRole, AccountStatus } from '../src/models/User.model';
import { AuthSession, SessionType } from '../src/models/AuthSession.model';
import { UserSettings } from '../src/models/UserSettings.model';
import { AuditLog } from '../src/models/AuditLog.model';
import { generateTokenPair, hashToken, verifyAccessToken, verifyRefreshToken } from '../src/utils/jwt.util';

let app: Application;
const accounts: Record<string, { id: string; email: string; tokens: { accessToken: string; refreshToken: string } }> = {};
const password = 'SecurityTest123';

beforeAll(async () => {
  await connectDatabase();
  app = await createApp();
  for (const role of Object.values(UserRole)) {
    const email = `security-${randomUUID()}@example.com`;
    const registered = await request(app).post('/api/v1/auth/register')
      .send({ email, password, displayName: `Test ${role}`, role: 'ADMIN' }).expect(201);
    expect(registered.body.data.user.role).toBe(UserRole.USER);
    const id = registered.body.data.user.id;
    accounts[role] = { id, email, tokens: registered.body.data.tokens };
    await User.findByIdAndUpdate(id, { role });
    const login = await request(app).post('/api/v1/auth/login').send({ email, password }).expect(200);
    accounts[role].tokens = login.body.data.tokens;
  }
});

afterAll(async () => {
  const ids = Object.values(accounts).map(account => account.id);
  await Promise.all([
    AuthSession.deleteMany({ userId: { $in: ids } }),
    UserSettings.deleteMany({ userId: { $in: ids } }),
    AuditLog.deleteMany({ userId: { $in: ids } }),
    User.deleteMany({ _id: { $in: ids } }),
  ]);
  await disconnectDatabase();
});

async function login(role = UserRole.USER) {
  const res = await request(app).post('/api/v1/auth/login')
    .send({ email: accounts[role].email, password }).expect(200);
  return res.body.data.tokens as { accessToken: string; refreshToken: string };
}

describe('JWT sessions and RBAC', () => {
  it('creates unique token pairs within the same second with explicit session types', async () => {
    const user = await User.findById(accounts.USER.id);
    const first = generateTokenPair(user!._id, user!.role);
    const second = generateTokenPair(user!._id, user!.role);
    expect(first.accessToken).not.toBe(second.accessToken);
    expect(first.refreshToken).not.toBe(second.refreshToken);
    expect(verifyAccessToken(first.accessToken).sid).toBe(verifyRefreshToken(first.refreshToken).sid);
    const session = await AuthSession.findOne({ tokenHash: hashToken(accounts.USER.tokens.accessToken) });
    expect(session!.sessionType).toBe(SessionType.ACCESS);
    expect(first.accessTokenExpiresAt.getTime()).toBe(verifyAccessToken(first.accessToken).exp! * 1000);
  });

  it.each(['/api/v1/admin/stats', '/api/v1/staff/stats'])('requires a valid Bearer token for %s', async path => {
    await request(app).get(path).expect(401);
    await request(app).get(path).set('Authorization', 'Bearer invalid').expect(401);
    await request(app).get(path).set('Authorization', 'Basic invalid').expect(401);
  });

  it('enforces USER / STAFF / ADMIN permissions', async () => {
    for (const [role, staffStatus, adminStatus] of [
      [UserRole.USER, 403, 403], [UserRole.STAFF, 200, 200], [UserRole.ADMIN, 200, 200],
    ] as const) {
      const token = accounts[role].tokens.accessToken;
      await request(app).get('/api/v1/staff/stats').set('Authorization', `Bearer ${token}`).expect(staffStatus);
      await request(app).get('/api/v1/admin/stats').set('Authorization', `Bearer ${token}`).expect(adminStatus);
    }
  });

  it('protects dictionary and category write routes before controllers', async () => {
    for (const path of ['/api/v1/dictionary', '/api/v1/categories']) {
      await request(app).post(path).send({}).expect(401);
      await request(app).post(path).set('Authorization', `Bearer ${accounts.USER.tokens.accessToken}`).send({}).expect(403);
    }
  });

  it('rejects expired access tokens and unexpected signing algorithms', async () => {
    const claims = verifyAccessToken(accounts.USER.tokens.accessToken);
    const expired = jwt.sign({ ...claims, exp: Math.floor(Date.now() / 1000) - 1 }, env.JWT_ACCESS_SECRET);
    const response = await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${expired}`).expect(401);
    expect(response.body.error.code).toBe('AUTH_TOKEN_EXPIRED');
    const wrongAlgorithm = jwt.sign(claims, env.JWT_ACCESS_SECRET, { algorithm: 'HS384' });
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${wrongAlgorithm}`).expect(401);
  });

  it('derives token expiration from environment configuration', async () => {
    const previous = env.JWT_ACCESS_EXPIRES_IN;
    try {
      env.JWT_ACCESS_EXPIRES_IN = '30s';
      const user = await User.findById(accounts.USER.id);
      const tokens = generateTokenPair(user!._id, user!.role);
      const claims = verifyAccessToken(tokens.accessToken);
      expect(claims.exp! - claims.iat!).toBe(30);
      expect(tokens.accessTokenExpiresAt.getTime()).toBe(claims.exp! * 1000);
    } finally {
      env.JWT_ACCESS_EXPIRES_IN = previous;
    }
  });

  it('rejects refresh tokens as access tokens and malformed signed claims', async () => {
    await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${accounts.USER.tokens.refreshToken}`).expect(401);
    const token = jwt.sign({ userId: 'bad-id', role: 'ADMIN', sessionType: 'ACCESS' }, env.JWT_ACCESS_SECRET,
      { issuer: 'signvoice-api', audience: 'signvoice-app', expiresIn: '15m' });
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`).expect(401);
  });

  it('uses the current database role, including downgrades', async () => {
    await User.findByIdAndUpdate(accounts.STAFF.id, { role: UserRole.USER });
    await request(app).get('/api/v1/staff/stats')
      .set('Authorization', `Bearer ${accounts.STAFF.tokens.accessToken}`).expect(403);
    await User.findByIdAndUpdate(accounts.STAFF.id, { role: UserRole.STAFF });
  });

  it('rejects suspended users even with valid tokens', async () => {
    await User.findByIdAndUpdate(accounts.USER.id, { status: AccountStatus.SUSPENDED });
    await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${accounts.USER.tokens.accessToken}`).expect(401);
    await User.findByIdAndUpdate(accounts.USER.id, { status: AccountStatus.ACTIVE });
  });

  it('rotates once under concurrent refresh and rejects reuse', async () => {
    const tokens = await login();
    const responses = await Promise.all([1, 2].map(() => request(app)
      .post('/api/v1/auth/refresh').send({ refreshToken: tokens.refreshToken })));
    expect(responses.map(res => res.status).sort()).toEqual([200, 401]);
    const rotated = responses.find(res => res.status === 200)!.body.data;
    expect(rotated.refreshToken).not.toBe(tokens.refreshToken);
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: tokens.refreshToken }).expect(401);
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${tokens.accessToken}`).expect(401);
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${rotated.accessToken}`).expect(200);
  });

  it('logout revokes both tokens for that device and preserves another login', async () => {
    const first = await login();
    const second = await login();
    const res = await request(app).post('/api/v1/auth/logout')
      .set('Authorization', `Bearer ${first.accessToken}`).expect(200);
    expect(res.headers['set-cookie'][0]).toContain('Expires=Thu, 01 Jan 1970');
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${first.accessToken}`).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: first.refreshToken }).expect(401);
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${second.accessToken}`).expect(200);
  });

  it('restores a browser session with an HttpOnly cookie and an allowed origin', async () => {
    const res = await request(app).post('/api/v1/auth/login')
      .send({ email: accounts.USER.email, password }).expect(200);
    const cookie = res.headers['set-cookie'][0];
    expect(cookie).toContain('HttpOnly');
    expect(cookie).toContain('SameSite=Strict');
    await request(app).post('/api/v1/auth/refresh').set('Cookie', cookie).send({}).expect(403);
    const refreshed = await request(app).post('/api/v1/auth/refresh')
      .set('Cookie', cookie).set('Origin', env.CORS_ALLOWED_ORIGINS[0]).send({}).expect(200);
    expect(refreshed.headers['set-cookie'][0]).toContain('HttpOnly');
  });

  it('admin termination revokes both tokens in the selected device session', async () => {
    const tokens = await login();
    const session = await AuthSession.findOne({ tokenHash: hashToken(tokens.accessToken) });
    await request(app).delete(`/api/v1/admin/sessions/${session!._id}`)
      .set('Authorization', `Bearer ${accounts.ADMIN.tokens.accessToken}`).expect(200);
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${tokens.accessToken}`).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: tokens.refreshToken }).expect(401);
  });

  it('logout-all revokes all access and refresh sessions', async () => {
    const tokens = await login();
    await request(app).post('/api/v1/auth/logout-all')
      .set('Authorization', `Bearer ${tokens.accessToken}`).expect(200);
    await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${accounts.USER.tokens.accessToken}`).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: tokens.refreshToken }).expect(401);
  });
});
