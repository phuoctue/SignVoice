import {randomUUID} from 'node:crypto';
import mongoose from 'mongoose';
import request from 'supertest';
import {afterAll, afterEach, beforeAll, expect, it, vi} from 'vitest';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {AuthSession} from '../src/models/AuthSession.model';
import {SessionChain} from '../src/models/SessionChain.model';
import {AuditAction, AuditLog} from '../src/models/AuditLog.model';
import * as auth from '../src/services/auth.service';
import * as fence from '../src/services/session-fence.service';
import * as jwt from '../src/utils/jwt.util';
import {deleteOwnedSession, tombstoneChain} from '../src/services/session-chain.service';

let app: Awaited<ReturnType<typeof createApp>>;
beforeAll(async () => {await connectDatabase(); app = await createApp();});
afterAll(async () => {await mongoose.connection.dropDatabase(); await disconnectDatabase();});
afterEach(() => vi.restoreAllMocks());
function barrier() {let resolve!: () => void; const promise = new Promise<void>(done => {resolve = done;}); return {promise, resolve};}
async function bounded<T>(promise: Promise<T>): Promise<T> {
  let timer!: ReturnType<typeof setTimeout>;
  try {return await Promise.race([promise, new Promise<never>((_, reject) => {timer = setTimeout(() => reject(new Error('Barrier timeout')), 5000);})]);}
  finally {clearTimeout(timer);}
}
async function fixture() {
  const user = await auth.registerUser({email: `schedule-${randomUUID()}@example.com`, password: 'ChainTest123!', displayName: 'Schedule'});
  const row = (await AuthSession.findOne({tokenHash: jwt.hashToken(user.tokens.accessToken)}))!;
  return {user, row};
}
const use = (token: string) => request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
const rotate = (token: string) => request(app).post('/api/v1/auth/refresh').send({refreshToken: token});

it.each(['P0', 'P1', 'P2', 'P3', 'P4', 'P5', 'P6'] as const)('%s: a committed chain tombstone fences every late descendant', async point => {
  const {user, row} = await fixture();
  const independent = await auth.loginUser({email: user.user.email!, password: 'ChainTest123!'});
  const reached = barrier(), release = barrier();
  let intercepted = false, userReads = 0;
  const stop = async () => {if (!intercepted) {intercepted = true; reached.resolve(); await bounded(release.promise);}};
  const lookup = AuthSession.findOne;
  if (point === 'P0') vi.spyOn(AuthSession, 'findOne').mockImplementation((function(this: typeof AuthSession, ...args: any[]) {
    const query = Reflect.apply(lookup, this, args);
    if (args[0]?.sessionType === 'REFRESH') {
      const exec = query.exec; query.exec = async function(...params: any[]) {await stop(); return Reflect.apply(exec, this, params);};
    }
    return query;
  }) as any);
  const load = fence.loadSessionUser;
  if (point === 'P1' || point === 'P5') vi.spyOn(fence, 'loadSessionUser').mockImplementation((async function(...args: any[]) {
    userReads++; if (userReads === (point === 'P1' ? 1 : 2)) await stop();
    return Reflect.apply(load, fence, args);
  }) as any);
  const claim = AuthSession.findOneAndUpdate;
  if (point === 'P2') vi.spyOn(AuthSession, 'findOneAndUpdate').mockImplementation((function(this: typeof AuthSession, ...args: any[]) {
    const query = Reflect.apply(claim, this, args), exec = query.exec;
    query.exec = async function(...params: any[]) {await stop(); return Reflect.apply(exec, this, params);};
    return query;
  }) as any);
  const create = AuthSession.create;
  if (point === 'P3' || point === 'P4') vi.spyOn(AuthSession, 'create').mockImplementation((async function(this: typeof AuthSession, ...args: any[]) {
    if (args[0].sessionType === (point === 'P3' ? 'ACCESS' : 'REFRESH')) await stop();
    return Reflect.apply(create, this, args);
  }) as any);
  const audit = AuditLog.log;
  if (point === 'P6') vi.spyOn(AuditLog, 'log').mockImplementation(async (...args: Parameters<typeof audit>) => {
    if (args[0].action === AuditAction.TOKEN_REFRESH) await stop();
    return Reflect.apply(audit, AuditLog, args);
  });
  const generated = vi.spyOn(jwt, 'generateTokenPair');
  const rotating = auth.refreshTokens(user.tokens.refreshToken).then(value => ({value}), error => ({error}));
  try {
    await bounded(Promise.race([reached.promise, rotating.then(() => {throw new Error('Did not reach pause');})]));
    await auth.logoutUser(row.userId, row._id);
    release.resolve();
    const outcome = await bounded(rotating);
    if (point === 'P6') expect(outcome).toHaveProperty('value');
    else expect(outcome).toMatchObject({error: {statusCode: 401}});
    const late = generated.mock.results[0]?.value as jwt.ITokenPair | undefined;
    vi.restoreAllMocks();
    // Both original and generated-but-not-returned credentials must be rejected.
    for (const tokens of [user.tokens, ...(late ? [late] : [])]) {
      await use(tokens.accessToken).expect(401); await rotate(tokens.refreshToken).expect(401);
    }
    await use(independent.tokens.accessToken).expect(200);
    expect((await SessionChain.findOne({userId: row.userId, chainId: row.chainId}))!.status).toBe('REVOKED');
  } finally {release.resolve(); await bounded(rotating);}
}, 20000);

it('PZ: cleanup/audit failure leaves the acknowledged terminal fence durable and idempotent', async () => {
  const {user, row} = await fixture();
  vi.spyOn(AuthSession, 'updateMany').mockRejectedValueOnce(new Error('Cleanup failed'));
  await expect(auth.logoutUser(row.userId, row._id)).rejects.toThrow('Cleanup');
  expect(await AuthSession.countDocuments({userId: row.userId, status: 'ACTIVE'})).toBe(2);
  const root = (await SessionChain.findOne({userId: row.userId, chainId: row.chainId}))!;
  await use(user.tokens.accessToken).expect(401); await rotate(user.tokens.refreshToken).expect(401);
  vi.spyOn(AuditLog, 'log').mockRejectedValueOnce(new Error('Audit failed'));
  await expect(auth.logoutUser(row.userId, row._id)).rejects.toThrow('Audit');
  await auth.logoutUser(row.userId, row._id);
  const retried = (await SessionChain.findOne({userId: row.userId, chainId: row.chainId}))!;
  expect(retried.revokedAt).toEqual(root.revokedAt); expect(retried.guardRevision).toBe(root.guardRevision);
});
it('PR/R1: consumed-token replay cannot revoke the winner, but a retained grandparent selects its root', async () => {
  const {user, row} = await fixture();
  const child = await auth.refreshTokens(user.tokens.refreshToken);
  const grandchild = await auth.refreshTokens(child.refreshToken);
  await rotate(user.tokens.refreshToken).expect(401);
  await use(grandchild.accessToken).expect(200);
  await auth.logoutUser(row.userId, row._id);
  await use(grandchild.accessToken).expect(401); await rotate(grandchild.refreshToken).expect(401);
});
it('PS: stale row business writes cannot overwrite immutable chain metadata or resurrect a tombstone', async () => {
  const {user, row} = await fixture();
  const stale = (await AuthSession.findById(row._id))!;
  await tombstoneChain(row.userId, row.chainId!);
  stale.chainId = randomUUID(); stale.lastUsedAt = new Date(); await stale.save();
  expect((await AuthSession.collection.findOne({_id: row._id}))!.chainId).toBe(row.chainId);
  await use(user.tokens.accessToken).expect(401); await rotate(user.tokens.refreshToken).expect(401);
});
it('D abort returns no false success; a lost response after a majority commit retains the tombstone', async () => {
  const {row, user} = await fixture();
  vi.spyOn(AuthSession, 'updateMany').mockRejectedValueOnce(new Error('Transaction abort'));
  await expect(deleteOwnedSession(row.userId, String(row._id), row._id)).rejects.toThrow('abort');
  expect((await SessionChain.findOne({userId: row.userId, chainId: row.chainId}))!.status).toBe('ACTIVE');
  await use(user.tokens.accessToken).expect(200);
  const actual = mongoose.connection.transaction;
  const transaction = vi.spyOn(mongoose.connection, 'transaction').mockImplementation((async function(this: typeof mongoose.connection, ...args: any[]) {
    await Reflect.apply(actual, this, args); throw new Error('Lost commit response');
  }) as typeof actual);
  await expect(deleteOwnedSession(row.userId, String(row._id), row._id)).rejects.toThrow('Lost');
  expect(transaction.mock.calls[0][1]).toMatchObject({writeConcern: {w: 'majority', j: true}});
  await use(user.tokens.accessToken).expect(401);
});
