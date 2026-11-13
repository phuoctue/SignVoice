import {randomUUID} from 'node:crypto';
import mongoose from 'mongoose';
import request from 'supertest';
import {afterAll, afterEach, beforeAll, expect, it, vi} from 'vitest';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {env} from '../src/config/env';
import {AuthSession} from '../src/models/AuthSession.model';
import {SessionChain} from '../src/models/SessionChain.model';
import {sessionChainTransitionModel, IChainTransition} from '../src/models/SessionChainTransition.model';
import {User} from '../src/models/User.model';
import * as auth from '../src/services/auth.service';
import {authClock} from '../src/services/auth-clock';
import {assertSessionChain, loadChainTransition, transitionDigest, tombstoneChain} from '../src/services/session-chain.service';
import {hashToken, verifyAccessToken} from '../src/utils/jwt.util';
import * as jwtUtils from '../src/utils/jwt.util';
import * as userFence from '../src/services/session-fence.service';
import {createAiTicket, authorizeAiTicket} from '../src/services/guest-trial.service';

let app: Awaited<ReturnType<typeof createApp>>;
const now = new Date(Math.floor(Date.now() / 1000) * 1000);
const manifest: IChainTransition = {_id: 'session-chain-transition', transitionId: 'fixture', policyVersion: '1',
  windowMs: 3600000, clockBudgetMs: 300000, cutoverAt: new Date(+now - 3300000), sunsetAt: new Date(+now + 300000)};
const policy = () => {
  vi.stubEnv('SESSION_CHAIN_MODE', 'enforcement');
  vi.stubEnv('SESSION_CHAIN_TRANSITION_ID', 'fixture');
  vi.stubEnv('SESSION_CHAIN_POLICY_VERSION', '1');
  vi.stubEnv('SESSION_CHAIN_WINDOW_MS', '3600000');
  vi.stubEnv('SESSION_CHAIN_CLOCK_BUDGET_MS', '300000');
  vi.stubEnv('SESSION_CHAIN_DIGEST', transitionDigest(manifest));
};
beforeAll(async () => { await connectDatabase(); app = await createApp(); await SessionChain.init(); });
afterAll(async () => { await sessionChainTransitionModel().db.dropDatabase(); await mongoose.connection.dropDatabase(); await disconnectDatabase(); });
afterEach(async () => { vi.restoreAllMocks(); vi.unstubAllEnvs(); await sessionChainTransitionModel().collection.deleteMany({}); });
const access = (token: string) => request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
const refresh = (token: string) => request(app).post('/api/v1/auth/refresh').send({refreshToken: token});
async function fixture(guest = false) {
  vi.spyOn(authClock, 'now').mockReturnValue(new Date(+manifest.sunsetAt - 300001));
  const result = guest ? await auth.createGuestAccount() : await auth.registerUser({email: `chain-${randomUUID()}@example.com`, password: 'ChainTest123!', displayName: 'Fixture'});
  const row = (await AuthSession.findOne({tokenHash: hashToken(result.tokens.accessToken)}))!;
  return {result, row};
}
async function activate() {
  await sessionChainTransitionModel().collection.insertOne(manifest);
  policy();
}
it('SF-A1: record-first failure emits no cookie or persisted usable row', async () => {
  vi.spyOn(SessionChain.collection, 'insertOne').mockRejectedValueOnce(new Error('Unknown record acknowledgment'));
  const response = await request(app).post('/api/v1/auth/register').send({email: `fail-${randomUUID()}@example.com`, password: 'ChainTest123!', displayName: 'Failure'}).expect(500);
  expect(response.headers['set-cookie']).toBeUndefined();
  expect(response.body.data?.tokens).toBeUndefined();
  const user = await User.findOne({displayName: 'Failure'});
  expect(await AuthSession.countDocuments({userId: user!._id})).toBe(0);
});
it('compat mixed old writers inherit absence; new writers retain a false root', async () => {
  const old = await fixture(), fresh = await fixture(true);
  await AuthSession.collection.updateMany({userId: old.row.userId}, {$unset: {chainId: ''}});
  const child = await auth.refreshTokens(old.result.tokens.refreshToken);
  expect((await AuthSession.collection.findOne({tokenHash: hashToken(child.accessToken)}))!.chainId).toBeUndefined();
  expect((await AuthSession.findOne({tokenHash: hashToken(fresh.result.tokens.accessToken)}))!.chainId).toBe(fresh.row.chainId);
  expect((await SessionChain.findOne({userId: fresh.row.userId, chainId: fresh.row.chainId}))!.legacyDerived).toBe(false);
});
it.each(['root-loss', 'root-added'] as const)('refresh rejects %s between admission and the exact raw claim', async change => {
  const {row, result} = await fixture();
  const parent = (await AuthSession.findOne({tokenHash: hashToken(result.tokens.refreshToken)}))!;
  if (change === 'root-added') await AuthSession.collection.updateOne({_id: parent._id}, {$unset: {chainId: ''}});
  const claim = AuthSession.findOneAndUpdate;
  vi.spyOn(AuthSession, 'findOneAndUpdate').mockImplementation((function(this: typeof AuthSession, ...args: any[]) {
    const query = Reflect.apply(claim, this, args), exec = query.exec;
    query.exec = async function(...params: any[]) {
      await AuthSession.collection.updateOne({_id: parent._id}, change === 'root-loss'
        ? {$unset: {chainId: ''}} : {$set: {chainId: row.chainId}});
      return Reflect.apply(exec, this, params);
    };
    return query;
  }) as any);
  await refresh(result.tokens.refreshToken).expect(401);
  expect(await AuthSession.countDocuments({userId: row.userId})).toBe(2);
  expect((await AuthSession.findById(parent._id))!.status).toBe('ACTIVE');
});
it('explicit INACTIVE rejects a present singleton and a missing/invalid mode', async () => {
  vi.stubEnv('SESSION_CHAIN_MODE', '');
  await expect(loadChainTransition()).rejects.toThrow('mode');
  vi.stubEnv('SESSION_CHAIN_MODE', 'compat');
  await sessionChainTransitionModel().collection.insertOne(manifest);
  await expect(loadChainTransition()).rejects.toThrow('inactive');
});
it('enforcement rejects a missing singleton without inventing dates', async () => {
  policy();
  await expect(loadChainTransition()).rejects.toThrow('transition');
});
it('enforcement rejects malformed/arithmetic/changed-but-valid singleton and policy/digest drift', async () => {
  policy();
  const collection = sessionChainTransitionModel().collection;
  for (const override of [{sunsetAt: 'bad'}, {windowMs: Number.MAX_SAFE_INTEGER},
    {sunsetAt: new Date(+manifest.sunsetAt + 1)}, {transitionId: 'other'},
    {cutoverAt: new Date(+manifest.cutoverAt + 1000), sunsetAt: new Date(+manifest.sunsetAt + 1000)}]) {
    await collection.deleteMany({}); await collection.insertOne({...manifest, ...override} as any);
    await expect(loadChainTransition()).rejects.toThrow();
  }
  await collection.deleteMany({}); await collection.insertOne(manifest as any);
  vi.stubEnv('SESSION_CHAIN_WINDOW_MS', '');
  await expect(loadChainTransition()).rejects.toThrow('policy');
});
// Once armed, this process stays enforcing. Each later test recreates the same immutable authority.
it('SF-A2: record-first permanent login and new guest survive T_s', async () => {
  const permanent = await fixture(), guest = await fixture(true);
  await activate();
  vi.spyOn(authClock, 'now').mockReturnValue(new Date(+manifest.sunsetAt + 1));
  await access(permanent.result.tokens.accessToken).expect(200);
  await access(guest.result.tokens.accessToken).expect(200);
  await refresh(guest.result.tokens.refreshToken).expect(200);
});
it('SF-A3: true legacy descendants deny at T_s minus skew with equality denied', async () => {
  policy(); await sessionChainTransitionModel().collection.insertOne(manifest);
  const {row, result} = await fixture(true);
  await SessionChain.collection.updateOne({userId: row.userId, chainId: row.chainId}, {$set: {legacyDerived: true}});
  await access(result.tokens.accessToken).expect(200);
  const child = await auth.refreshTokens(result.tokens.refreshToken);
  const stored = (await AuthSession.findOne({tokenHash: hashToken(child.accessToken)}))!;
  expect(stored.chainId).toBe(row.chainId);
  expect((await SessionChain.findOne({userId: row.userId, chainId: row.chainId}))!.legacyDerived).toBe(true);
  for (const delta of [0, 1, 299999, 300000, 300001, 600000]) {
    vi.spyOn(authClock, 'now').mockReturnValue(new Date(+manifest.sunsetAt - 300000 + delta));
    await access(child.accessToken).expect(401);
    await refresh(child.refreshToken).expect(401);
  }
});
it('SF-A4: old writer linkage loss after final mapping fails closed before T_s', async () => {
  policy(); await sessionChainTransitionModel().collection.insertOne(manifest);
  const {row, result} = await fixture();
  await AuthSession.collection.updateMany({userId: row.userId}, {$unset: {chainId: ''}});
  await access(result.tokens.accessToken).expect(401);
  await refresh(result.tokens.refreshToken).expect(401);
});
it('singleton DB timeout is 5xx; credentials recover after the infrastructure fault', async () => {
  policy(); await sessionChainTransitionModel().collection.insertOne(manifest);
  const {result} = await fixture();
  const spy = vi.spyOn(sessionChainTransitionModel().collection, 'findOne').mockRejectedValue(new Error('Read timeout'));
  await access(result.tokens.accessToken).expect(500);
  await refresh(result.tokens.refreshToken).expect(500);
  spy.mockRestore();
  await access(result.tokens.accessToken).expect(200);
});
it('fence reads are fresh primary/linearizable/bounded and AI tickets obey tombstones', async () => {
  policy(); await sessionChainTransitionModel().collection.insertOne(manifest);
  const {row} = await fixture();
  const read = vi.spyOn(SessionChain.collection, 'findOne');
  const ticket = await createAiTicket(row.userId, row._id);
  expect(read.mock.calls.some(call => (call[1] as any)?.readConcern?.level === 'linearizable' &&
    (call[1] as any)?.readPreference === 'primary' && (call[1] as any)?.maxTimeMS === 5000)).toBe(true);
  await tombstoneChain(row.userId, row.chainId!);
  await expect(createAiTicket(row.userId, row._id)).rejects.toMatchObject({statusCode: 401});
  await expect(authorizeAiTicket(ticket)).rejects.toMatchObject({statusCode: 401});
  await expect(assertSessionChain(row)).rejects.toMatchObject({statusCode: 401});
});
it('SF-E: only a true guest receives the conservative cutoff carrier; metadata stays private', async () => {
  policy(); await sessionChainTransitionModel().collection.insertOne(manifest);
  const {row, result} = await fixture(true);
  expect((await access(result.tokens.accessToken).expect(200)).body.data.legacyGuestSessionCutoffAt).toBeUndefined();
  await SessionChain.collection.updateOne({userId: row.userId, chainId: row.chainId}, {$set: {legacyDerived: true}});
  vi.spyOn(authClock, 'now').mockReturnValue(new Date(+manifest.cutoverAt - 1));
  expect((await access(result.tokens.accessToken).expect(200)).body.data.legacyGuestSessionCutoffAt).toBeUndefined();
  vi.spyOn(authClock, 'now').mockReturnValue(new Date(+manifest.sunsetAt - 300001));
  const carrierReads = vi.spyOn(sessionChainTransitionModel().collection, 'findOne');
  const response = await access(result.tokens.accessToken).expect(200);
  expect(carrierReads).toHaveBeenCalledTimes(1);
  expect(response.body.data.legacyGuestSessionCutoffAt).toBe(new Date(+manifest.sunsetAt - 600000).toISOString());
  expect(response.body.data.chainId).toBeUndefined(); expect(response.body.data.legacyDerived).toBeUndefined();
});
it('owned historical IDs return 409; foreign/missing IDs stay 404; no implicit epoch bump', async () => {
  policy(); await sessionChainTransitionModel().collection.insertOne(manifest);
  const {row, result} = await fixture(), other = await fixture();
  const historical = await AuthSession.create({userId: row.userId, sessionFamily: randomUUID(), tokenHash: randomUUID(),
    passwordVersion: 0, sessionType: 'REFRESH', status: 'REVOKED', expiresAt: new Date(+now + 999999)});
  const response = await request(app).delete(`/api/v1/users/sessions/${historical._id}`).set('Authorization', `Bearer ${result.tokens.accessToken}`).expect(409);
  expect(response.body.error.code).toBe('SESSION_CHAIN_UNRESOLVABLE');
  for (const id of [other.row._id, new mongoose.Types.ObjectId()]) {
    await request(app).delete(`/api/v1/users/sessions/${id}`).set('Authorization', `Bearer ${result.tokens.accessToken}`).expect(404);
  }
  expect((await User.findById(row.userId).select('+sessionRevocationEpoch'))!.sessionRevocationEpoch).toBe(0);
  expect(verifyAccessToken(result.tokens.accessToken).sid).toBe(row.sessionFamily);
});
it.each(['claim', 'ACCESS', 'REFRESH', 'final'] as const)('a refresh paused at %s across T_s fails its final time fence and emits no replacement cookie', async point => {
  policy(); await sessionChainTransitionModel().collection.insertOne(manifest);
  const {row, result} = await fixture(true);
  await SessionChain.collection.updateOne({userId: row.userId, chainId: row.chainId}, {$set: {legacyDerived: true}});
  let reached!: () => void, release!: () => void;
  const paused = new Promise<void>(done => {reached = done;}), resume = new Promise<void>(done => {release = done;});
  const create = AuthSession.create;
  let stopped = false;
  const pause = async () => {if (!stopped) {stopped = true; reached(); await resume;}};
  vi.spyOn(AuthSession, 'create').mockImplementation((async function(this: typeof AuthSession, ...args: any[]) {
    if (args[0].sessionType === point) await pause();
    return Reflect.apply(create, this, args);
  }) as any);
  if (point === 'claim') {
    const claim = AuthSession.findOneAndUpdate;
    vi.spyOn(AuthSession, 'findOneAndUpdate').mockImplementation((function(this: typeof AuthSession, ...args: any[]) {
      const query = Reflect.apply(claim, this, args), exec = query.exec;
      query.exec = async function(...params: any[]) {await pause(); return Reflect.apply(exec, this, params);};
      return query;
    }) as any);
  }
  if (point === 'final') {
    const load = userFence.loadSessionUser;
    let reads = 0;
    vi.spyOn(userFence, 'loadSessionUser').mockImplementation((async function(...args: any[]) {
      if (++reads === 2) await pause();
      return Reflect.apply(load, userFence, args);
    }) as any);
  }
  const generated = vi.spyOn(jwtUtils, 'generateTokenPair');
  const rotating = refresh(result.tokens.refreshToken).timeout({deadline: 10000}).then(response => response);
  try {
    await Promise.race([paused, rotating.then(() => {throw new Error('Refresh did not pause');})]);
    vi.spyOn(authClock, 'now').mockReturnValue(new Date(+manifest.sunsetAt + 1));
    release();
    const response = await rotating;
    expect(response.status).toBe(401); expect(response.headers['set-cookie']).toBeUndefined();
    const late = generated.mock.results[0].value;
    const rows = await AuthSession.find({sessionFamily: verifyAccessToken(late.accessToken).sid});
    expect(rows).toHaveLength(2); expect(rows.every(child => child.chainId === row.chainId)).toBe(true);
    await access(late.accessToken).expect(401); await refresh(late.refreshToken).expect(401);
  } finally {release(); await rotating;}
});
it('schema contracts keep roots immutable, uniquely keyed and non-expiring; app transition updates reject', async () => {
  expect(AuthSession.schema.path('chainId').options.immutable).toBe(true);
  expect(AuthSession.schema.path('chainId').options.default).toBeUndefined();
  expect(AuthSession.schema.indexes().some(([key]) => JSON.stringify(key) === JSON.stringify({userId: 1, chainId: 1, status: 1}))).toBe(true);
  expect(SessionChain.schema.indexes().some(([key, options]) => key.userId === 1 && key.chainId === 1 && options.unique)).toBe(true);
  expect(SessionChain.schema.indexes().some(([, options]) => options.expireAfterSeconds !== undefined)).toBe(false);
  await expect(sessionChainTransitionModel().updateOne({_id: manifest._id}, {$set: {sunsetAt: new Date()}})).rejects.toThrow('insert-only');
});
it.each(['lost-ack', 'revoke-after-insert'] as const)('SF-A1: %s before row issuance leaves no usable token', async fault => {
  policy(); await sessionChainTransitionModel().collection.insertOne(manifest);
  const insert = SessionChain.collection.insertOne;
  let root: any;
  const write = vi.spyOn(SessionChain.collection, 'insertOne').mockImplementation((async function(this: typeof SessionChain.collection, ...args: any[]) {
    root = args[0];
    const result = await Reflect.apply(insert, this, args);
    if (fault === 'lost-ack') throw new Error('Lost record acknowledgment');
    await tombstoneChain(root.userId, root.chainId);
    return result;
  }) as any);
  const result = auth.registerUser({email: `record-${randomUUID()}@example.com`, password: 'ChainTest123!', displayName: 'Record failure'});
  if (fault === 'lost-ack') await expect(result).rejects.toThrow('acknowledgment');
  else await expect(result).rejects.toMatchObject({statusCode: 401});
  expect(write.mock.calls[0][1]).toMatchObject({writeConcern: {w: 'majority', j: true}});
  expect(await AuthSession.countDocuments({userId: root.userId})).toBe(0);
  expect((await SessionChain.findOne({userId: root.userId, chainId: root.chainId}))!.status).toBe(fault === 'lost-ack' ? 'ACTIVE' : 'REVOKED');
});
it.each(['ACTIVE', 'REVOKED'] as const)('SF-A1: a duplicate %s root is reread without issuing rows or reusing authority', async status => {
  policy(); await sessionChainTransitionModel().collection.insertOne(manifest);
  const insert = SessionChain.collection.insertOne;
  let root: any;
  vi.spyOn(SessionChain.collection, 'insertOne').mockImplementation((async function(this: typeof SessionChain.collection, ...args: any[]) {
    root = args[0];
    await Reflect.apply(insert, this, [{...root, status, ...(status === 'REVOKED' ? {revokedAt: now} : {})}, args[1]]);
    throw Object.assign(new Error('Duplicate root'), {code: 11000});
  }) as any);
  const result = auth.registerUser({email: `duplicate-${randomUUID()}@example.com`, password: 'ChainTest123!', displayName: 'Duplicate root'});
  if (status === 'REVOKED') await expect(result).rejects.toMatchObject({statusCode: 401});
  else await expect(result).rejects.toThrow('Duplicate');
  expect(await AuthSession.countDocuments({userId: root.userId})).toBe(0);
  expect((await SessionChain.findOne({userId: root.userId, chainId: root.chainId}))!.status).toBe(status);
});
