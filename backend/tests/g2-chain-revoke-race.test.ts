import { randomUUID } from 'node:crypto';
import mongoose from 'mongoose';
import request from 'supertest';
import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { env } from '../src/config/env';
import { AuthSession, SessionType } from '../src/models/AuthSession.model';
import { User, UserRole } from '../src/models/User.model';
import * as auth from '../src/services/auth.service';
import * as jwt from '../src/utils/jwt.util';

beforeAll(async () => {
  const uri = new URL(env.MONGODB_URI);
  expect(uri.hostname).toBe('127.0.0.1');
  expect(uri.pathname).toMatch(/^\/signvoice_test_/);
  await connectDatabase();
});
afterAll(async () => { await mongoose.connection.dropDatabase(); await disconnectDatabase(); });
afterEach(() => vi.restoreAllMocks());

function barrier() {
  let resolve!: () => void;
  const promise = new Promise<void>(done => { resolve = done; });
  return { promise, resolve };
}
async function bounded<T>(promise: Promise<T>): Promise<T> {
  let timer!: ReturnType<typeof setTimeout>;
  try { return await Promise.race([promise, new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error('Barrier timeout')), 5000);
  })]); } finally { clearTimeout(timer); }
}

it.each(['L', 'D', 'AD'] as const)('G1 %s: tombstone defeats a refresh paused before child insertion', async path => {
  const app = await createApp();
  const result = await auth.registerUser({ email: `chain-${randomUUID()}@example.com`, password: 'ChainTest123!', displayName: 'Chain fixture' });
  const id = new mongoose.Types.ObjectId(result.user.id);
  const target = (await AuthSession.findOne({ tokenHash: jwt.hashToken(result.tokens.accessToken) }))!;
  const other = await auth.loginUser({email: result.user.email!, password: 'ChainTest123!'});
  let adminToken: string | undefined;
  if (path === 'AD') {
    const admin = await auth.registerUser({email: `admin-${randomUUID()}@example.com`, password: 'ChainTest123!', displayName: 'Admin'});
    await User.updateOne({_id: admin.user.id}, {$set: {role: UserRole.ADMIN}});
    adminToken = (await auth.loginUser({email: admin.user.email!, password: 'ChainTest123!'})).tokens.accessToken;
  }
  const reached = barrier(), release = barrier();
  const realCreate = AuthSession.create;
  let paused = false;
  vi.spyOn(AuthSession, 'create').mockImplementation((async function(this: typeof AuthSession, ...args: unknown[]) {
    const row = args[0] as {userId: unknown; sessionType: string};
    if (!paused && String(row.userId) === String(id) && row.sessionType === SessionType.ACCESS) {
      paused = true; reached.resolve(); await bounded(release.promise);
    }
    return Reflect.apply(realCreate, this, args);
  }) as typeof AuthSession.create);
  const generated = vi.spyOn(jwt, 'generateTokenPair');
  const rotating = auth.refreshTokens(result.tokens.refreshToken).then(value => ({value}), error => ({error}));
  try {
    await bounded(reached.promise);
    const late = generated.mock.results[0].value;
    if (path === 'L') await auth.logoutUser(id, target._id);
    else if (path === 'D') await request(app).delete(`/api/v1/users/sessions/${target._id}`)
      .set('Authorization', `Bearer ${other.tokens.accessToken}`).expect(200);
    else await request(app).delete(`/api/v1/admin/sessions/${target._id}`)
      .set('Authorization', `Bearer ${adminToken}`).expect(200);
    release.resolve();
    await bounded(rotating);
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${late.accessToken}`).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({refreshToken: late.refreshToken}).expect(401);
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${other.tokens.accessToken}`).expect(200);
  } finally { release.resolve(); await bounded(rotating); }
}, 25000);
