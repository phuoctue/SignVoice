import {randomUUID} from 'node:crypto';
import mongoose from 'mongoose';
import request from 'supertest';
import {afterAll, afterEach, beforeAll, beforeEach, expect, it, vi} from 'vitest';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {AuthSession} from '../src/models/AuthSession.model';
import {SessionChain} from '../src/models/SessionChain.model';
import {User, UserRole} from '../src/models/User.model';
import {AuditAction, AuditLog} from '../src/models/AuditLog.model';
import {NotificationDevice, UserNotification} from '../src/models/Notification.model';
import {deliverNotificationBatch} from '../src/services/notification.service';
import {deleteOwnedSession, effectiveSessions, tombstoneChain} from '../src/services/session-chain.service';
import {sessionChainTransitionModel} from '../src/models/SessionChainTransition.model';
import * as auth from '../src/services/auth.service';
import * as jwt from '../src/utils/jwt.util';

let app: Awaited<ReturnType<typeof createApp>>;
beforeAll(async () => {await connectDatabase(); app = await createApp();});
beforeEach(async () => {await AuthSession.deleteMany({}); await SessionChain.deleteMany({}); await User.deleteMany({});});
afterEach(() => {vi.restoreAllMocks(); vi.unstubAllEnvs();});
afterAll(async () => {await mongoose.connection.dropDatabase(); await disconnectDatabase();});
async function fixture(admin = false) {
  const result = await auth.registerUser({email: `consumer-${randomUUID()}@example.com`, password: 'ChainTest123!', displayName: 'Consumer'});
  const row = (await AuthSession.findOne({tokenHash: jwt.hashToken(result.tokens.accessToken)}))!;
  if (admin) await User.updateOne({_id: row.userId}, {$set: {role: UserRole.ADMIN}});
  return {result, row};
}
function barrier() {let resolve!: () => void; const promise = new Promise<void>(done => {resolve = done;}); return {promise, resolve};}
async function bounded<T>(promise: Promise<T>): Promise<T> {
  let timer!: ReturnType<typeof setTimeout>;
  try {return await Promise.race([promise, new Promise<never>((_, reject) => {timer = setTimeout(() => reject(new Error('Barrier timeout')), 5000);})]);}
  finally {clearTimeout(timer);}
}
const access = (token: string) => request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
it('effective lists and token-row counts filter epoch and root before pagination and hide metadata', async () => {
  const admin = await fixture(true), valid = await fixture(), stale = await fixture(), revoked = await fixture();
  await User.collection.updateOne({_id: stale.row.userId}, {$set: {sessionRevocationEpoch: 1}});
  await tombstoneChain(revoked.row.userId, revoked.row.chainId!);
  await AuthSession.updateMany({userId: {$in: [stale.row.userId, revoked.row.userId]}}, {$set: {lastUsedAt: new Date(Date.now() + 100000)}});
  const response = await request(app).get('/api/v1/admin/sessions?page=1&limit=3')
    .set('Authorization', `Bearer ${admin.result.tokens.accessToken}`).expect(200);
  expect(response.body.data.pagination.total).toBe(4);
  expect(response.body.data.sessions).toHaveLength(3);
  for (const row of response.body.data.sessions) {
    expect([admin.result.user.id, valid.result.user.id]).toContain(row.userId._id);
    for (const secret of ['chainId', 'legacyDerived', 'userEpoch', 'tokenHash']) expect(row[secret]).toBeUndefined();
  }
  const dashboard = await request(app).get('/api/v1/admin/stats').set('Authorization', `Bearer ${admin.result.tokens.accessToken}`).expect(200);
  expect(dashboard.body.data.sessions.active).toBe(4);
  const list = await request(app).get('/api/v1/users/sessions').set('Authorization', `Bearer ${valid.result.tokens.accessToken}`).expect(200);
  expect(list.body.data).toHaveLength(1); expect(list.body.data[0].chainId).toBeUndefined();
});
it.each(['refresh-last', 'delete-last'] as const)('D current-chain cookie identity survives a rotated sid (%s response)', async order => {
  const {row, result} = await fixture();
  let child: jwt.ITokenPair;
  if (order === 'refresh-last') {
    const reached = barrier(), release = barrier(), audit = AuditLog.log;
    vi.spyOn(AuditLog, 'log').mockImplementation(async (...args: Parameters<typeof audit>) => {
      if (args[0].action === AuditAction.TOKEN_REFRESH) {reached.resolve(); await bounded(release.promise);}
      return Reflect.apply(audit, AuditLog, args);
    });
    const generated = vi.spyOn(jwt, 'generateTokenPair');
    const rotating = request(app).post('/api/v1/auth/refresh').send({refreshToken: result.tokens.refreshToken}).then(response => response);
    try {
      await bounded(reached.promise); child = generated.mock.results[0].value;
      const deleted = await request(app).delete(`/api/v1/users/sessions/${row._id}`).set('Authorization', `Bearer ${child.accessToken}`).expect(200);
      expect(deleted.body.data.revokedCurrent).toBe(true);
      expect(deleted.headers['set-cookie'].join()).toContain('signvoice_refresh=;');
      release.resolve();
      const response = await bounded(rotating);
      expect(response.status).toBe(200); expect(response.headers['set-cookie'].join()).toContain('signvoice_refresh=');
    } finally {release.resolve(); await bounded(rotating);}
  } else {
    child = (await request(app).post('/api/v1/auth/refresh').send({refreshToken: result.tokens.refreshToken}).expect(200)).body.data;
    const deleted = await request(app).delete(`/api/v1/users/sessions/${row._id}`).set('Authorization', `Bearer ${child.accessToken}`).expect(200);
    expect(deleted.body.data.revokedCurrent).toBe(true);
    expect(deleted.headers['set-cookie'].join()).toContain('signvoice_refresh=;');
  }
  await access(child!.accessToken).expect(401);
  await request(app).post('/api/v1/auth/refresh').send({refreshToken: child!.refreshToken}).expect(401);
});
it('push handoff denies a terminal root while retaining its registration', async () => {
  const {row} = await fixture();
  await NotificationDevice.create({userId: row.userId, token: randomUUID(), platform: 'android', sessionFamily: row.sessionFamily,
    deliveredAt: new Date(0), expiresAt: new Date(Date.now() + 60000)});
  await UserNotification.create({userId: row.userId, key: randomUUID(), kind: 'TEST', title: 'Fixture', body: 'Fixture', route: '/', expiresAt: new Date(Date.now() + 60000)});
  await tombstoneChain(row.userId, row.chainId!);
  vi.stubEnv('GOOGLE_APPLICATION_CREDENTIALS', 'unused-fixture'); vi.stubEnv('FIREBASE_PROJECT_ID', 'unused-fixture');
  const send = vi.fn(), warn = vi.spyOn(console, 'warn');
  await deliverNotificationBatch(send, row.userId);
  expect(send).not.toHaveBeenCalled(); expect(warn).not.toHaveBeenCalled();
  expect(await NotificationDevice.exists({userId: row.userId})).toBeTruthy();
});
it('admin actor guard conflicts with chain-only revocation and retries fail closed', async () => {
  const actor = await fixture(true), target = await fixture();
  const reached = barrier(), release = barrier(), update = SessionChain.collection.updateOne;
  let paused = false;
  vi.spyOn(SessionChain.collection, 'updateOne').mockImplementation((async function(this: typeof SessionChain.collection, ...args: any[]) {
    if (!paused && String(args[0].userId) === String(actor.row.userId) && args[2]?.session && args[1].$inc?.guardRevision) {
      paused = true; reached.resolve(); await bounded(release.promise);
    }
    return Reflect.apply(update, this, args);
  }) as any);
  const reset = request(app).post(`/api/v1/admin/users/${target.row.userId}/password`)
    .set('Authorization', `Bearer ${actor.result.tokens.accessToken}`).send({newPassword: 'ChangedPassword456'}).then(response => response);
  try {
    await bounded(reached.promise);
    await tombstoneChain(actor.row.userId, actor.row.chainId!);
    release.resolve(); expect((await bounded(reset)).status).toBe(401);
    expect((await User.findById(target.row.userId))!.passwordVersion).toBe(0);
  } finally {release.resolve(); await bounded(reset);}
});
it('D retains the active-account transaction guard before writing a tombstone', async () => {
  const {row} = await fixture();
  await User.collection.updateOne({_id: row.userId}, {$set: {status: 'SUSPENDED'}});
  await expect(deleteOwnedSession(row.userId, String(row._id), row._id)).rejects.toMatchObject({statusCode: 404});
  expect((await SessionChain.findOne({userId: row.userId, chainId: row.chainId}))!.status).toBe('ACTIVE');
});
it('R1 N1: records the effective-list read cost without weakening per-row fences', async () => {
  await fixture(); await fixture(); const stale = await fixture(), revoked = await fixture();
  await User.collection.updateOne({_id: stale.row.userId}, {$set: {sessionRevocationEpoch: 1}});
  await tombstoneChain(revoked.row.userId, revoked.row.chainId!);
  const users = vi.spyOn(User.collection, 'findOne'), chains = vi.spyOn(SessionChain.collection, 'findOne');
  const transitions = vi.spyOn(sessionChainTransitionModel().collection, 'findOne');
  const started = Date.now();
  expect(await effectiveSessions()).toHaveLength(4);
  expect(users).toHaveBeenCalledTimes(8);
  expect(chains).toHaveBeenCalledTimes(6);
  expect(transitions).toHaveBeenCalledTimes(7);
  console.log(`R1 effective-list fixture: 8 token rows, 4 effective; 21 fence reads; ${Date.now() - started}ms`);
});
