import {randomUUID} from 'node:crypto';
import mongoose from 'mongoose';
import request from 'supertest';
import {afterAll, afterEach, beforeAll, expect, it, vi} from 'vitest';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {AuthSession} from '../src/models/AuthSession.model';
import {User} from '../src/models/User.model';
import {SessionChain} from '../src/models/SessionChain.model';
import {AuditLog} from '../src/models/AuditLog.model';
import * as auth from '../src/services/auth.service';
import * as jwt from '../src/utils/jwt.util';
import {authClock} from '../src/services/auth-clock';
import {transitionDigest} from '../src/services/session-chain.service';
import {sessionChainTransitionModel, IChainTransition} from '../src/models/SessionChainTransition.model';

let app: Awaited<ReturnType<typeof createApp>>;
beforeAll(async () => {await connectDatabase(); app = await createApp();});
afterAll(async () => {await sessionChainTransitionModel().db.dropDatabase(); await mongoose.connection.dropDatabase(); await disconnectDatabase();});
afterEach(() => {vi.restoreAllMocks(); vi.unstubAllEnvs();});
const access = (token: string) => request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
const refresh = (token: string) => request(app).post('/api/v1/auth/refresh').send({refreshToken: token});
const credentials = () => ({email: `convert-${randomUUID()}@example.com`, password: 'ChainTest123!', displayName: 'Converted'});
const collections = ['favorites', 'conversations', 'search_history', 'learning_enrollments', 'learning_word_progress',
  'learning_personal_words', 'learning_review_quizzes', 'learning_events', 'learning_sign_collections', 'learning_sign_notes',
  'collection_reports', 'notification_devices', 'user_notifications', 'guest_trials'];
async function fixture(legacy = true) {
  const result = await auth.createGuestAccount();
  const row = (await AuthSession.findOne({tokenHash: jwt.hashToken(result.tokens.accessToken)}))!;
  if (legacy) await SessionChain.collection.updateOne({userId: row.userId, chainId: row.chainId}, {$set: {legacyDerived: true}});
  for (const name of collections) await mongoose.connection.db!.collection(name).insertOne({userId: row.userId,
    fixture: randomUUID(), token: randomUUID(), entryId: new mongoose.Types.ObjectId(), topicId: new mongoose.Types.ObjectId(),
    key: randomUUID(), deviceHash: randomUUID(), startedAt: new Date(1000), expiresAt: new Date(Date.now() + 86400000), nested: {preserved: true}});
  return {result, row};
}
async function snapshot(id: mongoose.Types.ObjectId) {
  return Promise.all([...collections, 'user_settings'].map(name => mongoose.connection.db!.collection(name).find({userId: id}).sort({_id: 1}).toArray()));
}
it.each([true, false])('SF-A5: transactional conversion preserves all owned data and issues one/no fresh root (%s)', async issueSession => {
  const {row, result} = await fixture(), data = credentials();
  const hidden = await auth.loginOAuthUser((await User.findById(row.userId).select('+sessionRevocationEpoch'))!);
  await SessionChain.collection.updateMany({userId: row.userId}, {$set: {legacyDerived: true}});
  const before = await snapshot(row.userId);
  const converted = await auth.convertGuestToPermanent(row.userId, data, {}, issueSession, row._id);
  expect(converted.user.id).toBe(result.user.id);
  expect(await snapshot(row.userId)).toEqual(before);
  expect((await User.findById(row.userId).select('+sessionRevocationEpoch'))!.sessionRevocationEpoch).toBe(1);
  expect(await SessionChain.countDocuments({userId: row.userId, legacyDerived: true, status: 'ACTIVE'})).toBe(0);
  expect(await SessionChain.countDocuments({userId: row.userId, legacyDerived: false})).toBe(issueSession ? 1 : 0);
  for (const tokens of [result.tokens, hidden.tokens]) {
    await access(tokens.accessToken).expect(401); await refresh(tokens.refreshToken).expect(401);
  }
  if (issueSession) {
    await access(converted.tokens.accessToken).expect(200);
    expect((await AuthSession.findOne({tokenHash: jwt.hashToken(converted.tokens.accessToken)}))!.userEpoch).toBe(1);
  } else expect(await AuthSession.countDocuments({userId: row.userId, status: 'ACTIVE'})).toBe(0);
  const count = await SessionChain.countDocuments({userId: row.userId});
  await expect(auth.convertGuestToPermanent(row.userId, data, {}, issueSession, row._id)).rejects.toMatchObject({statusCode: 400});
  expect(await SessionChain.countDocuments({userId: row.userId})).toBe(count);
  expect(await snapshot(row.userId)).toEqual(before);
  await auth.loginUser({email: data.email, password: data.password});
});
it('compat conversion accepts an unlinked caller, bumps the epoch, and never upgrades old hidden rows', async () => {
  const {row, result} = await fixture(false);
  await AuthSession.collection.updateMany({userId: row.userId}, {$unset: {chainId: ''}});
  const converted = await auth.convertGuestToPermanent(row.userId, credentials(), {}, true, row._id);
  const replacement = (await AuthSession.findOne({tokenHash: jwt.hashToken(converted.tokens.accessToken)}))!;
  expect(replacement.userEpoch).toBe(1);
  expect((await SessionChain.findOne({userId: row.userId, chainId: replacement.chainId}))!.legacyDerived).toBe(false);
  await access(result.tokens.accessToken).expect(401); await refresh(result.tokens.refreshToken).expect(401);
});
it('unknown record write aborts conversion, preserving guest enrollment and business data', async () => {
  const {row} = await fixture(), before = await snapshot(row.userId);
  vi.spyOn(SessionChain.collection, 'insertOne').mockRejectedValueOnce(new Error('Unknown acknowledgment'));
  await expect(auth.convertGuestToPermanent(row.userId, credentials(), {}, true, row._id)).rejects.toThrow('Unknown');
  expect((await User.findById(row.userId).select('+sessionRevocationEpoch'))!.sessionRevocationEpoch).toBe(0);
  expect((await User.findById(row.userId))!.isGuest).toBe(true);
  expect(await snapshot(row.userId)).toEqual(before);
  expect((await SessionChain.findOne({userId: row.userId, chainId: row.chainId}))!.status).toBe('ACTIVE');
});
it('audit/lost response after committed enrollment preserves a recoverable permanent login', async () => {
  const {row} = await fixture(), before = await snapshot(row.userId), data = credentials();
  vi.spyOn(AuditLog, 'log').mockRejectedValueOnce(new Error('Audit unavailable'));
  await expect(auth.convertGuestToPermanent(row.userId, data, {}, true, row._id)).rejects.toThrow('Audit');
  expect((await User.findById(row.userId).select('+sessionRevocationEpoch'))!.sessionRevocationEpoch).toBe(1);
  expect(await snapshot(row.userId)).toEqual(before);
  await auth.loginUser({email: data.email, password: data.password});
});
it.each(['ACCESS', 'REFRESH'] as const)('conversion fences a hidden refresh paused at %s creation without changing its inherited epoch', async type => {
  const {row, result} = await fixture();
  const callerLogin = await auth.loginOAuthUser((await User.findById(row.userId).select('+sessionRevocationEpoch'))!);
  const caller = (await AuthSession.findOne({tokenHash: jwt.hashToken(callerLogin.tokens.accessToken)}))!;
  await SessionChain.collection.updateMany({userId: row.userId}, {$set: {legacyDerived: true}});
  const before = await snapshot(row.userId);
  let reached!: () => void, release!: () => void;
  const paused = new Promise<void>(done => {reached = done;}), resume = new Promise<void>(done => {release = done;});
  const create = AuthSession.create;
  let stopped = false;
  vi.spyOn(AuthSession, 'create').mockImplementation((async function(this: typeof AuthSession, ...args: any[]) {
    if (!stopped && !Array.isArray(args[0]) && args[0].sessionType === type) {stopped = true; reached(); await resume;}
    return Reflect.apply(create, this, args);
  }) as any);
  const generated = vi.spyOn(jwt, 'generateTokenPair');
  const rotating = auth.refreshTokens(result.tokens.refreshToken).then(value => ({value}), error => ({error}));
  try {
    await Promise.race([paused, rotating.then(() => {throw new Error('Refresh did not pause');})]);
    const late = generated.mock.results[0].value;
    const converted = await auth.convertGuestToPermanent(row.userId, credentials(), {}, true, caller._id);
    release(); expect(await rotating).toMatchObject({error: {statusCode: 401}});
    const lateRows = await AuthSession.find({userId: row.userId, sessionFamily: jwt.verifyAccessToken(late.accessToken).sid});
    expect(lateRows).toHaveLength(2); expect(lateRows.every(child => child.userEpoch === 0 && child.chainId === row.chainId)).toBe(true);
    await access(late.accessToken).expect(401); await refresh(late.refreshToken).expect(401);
    await access(converted.tokens.accessToken).expect(200);
    expect(await snapshot(row.userId)).toEqual(before);
    expect((await User.findById(row.userId).select('+sessionRevocationEpoch'))!.sessionRevocationEpoch).toBe(1);
  } finally {release(); await rotating;}
});
it('SF-A5: a legacy conversion replacement survives T_s; missing-chain conversion after enforcement denies', async () => {
  const clock = new Date(Math.floor(Date.now() / 1000) * 1000);
  vi.spyOn(authClock, 'now').mockReturnValue(clock);
  const {row} = await fixture(), unlinked = await fixture(false);
  await AuthSession.collection.updateMany({userId: unlinked.row.userId}, {$unset: {chainId: ''}});
  const manifest: IChainTransition = {_id: 'session-chain-transition', transitionId: 'conversion', policyVersion: '1',
    windowMs: 3600000, clockBudgetMs: 300000, cutoverAt: new Date(+clock - 2999999), sunsetAt: new Date(+clock + 600001)};
  await sessionChainTransitionModel().collection.insertOne(manifest);
  for (const [key, value] of Object.entries({SESSION_CHAIN_MODE: 'enforcement', SESSION_CHAIN_TRANSITION_ID: 'conversion',
    SESSION_CHAIN_POLICY_VERSION: '1', SESSION_CHAIN_WINDOW_MS: '3600000', SESSION_CHAIN_CLOCK_BUDGET_MS: '300000',
    SESSION_CHAIN_DIGEST: transitionDigest(manifest)})) vi.stubEnv(key, value);
  const before = await snapshot(row.userId);
  const converted = await auth.convertGuestToPermanent(row.userId, credentials(), {}, true, row._id);
  await expect(auth.convertGuestToPermanent(unlinked.row.userId, credentials(), {}, true, unlinked.row._id)).rejects.toMatchObject({statusCode: 401});
  vi.spyOn(authClock, 'now').mockReturnValue(new Date(+manifest.sunsetAt + 1));
  await access(converted.tokens.accessToken).expect(200);
  expect(await snapshot(row.userId)).toEqual(before);
});
