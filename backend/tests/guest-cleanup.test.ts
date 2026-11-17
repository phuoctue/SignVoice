import {beforeAll, beforeEach, afterAll, afterEach, it, expect, vi} from 'vitest';
import mongoose, {Types} from 'mongoose';
import {createHash} from 'node:crypto';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {User} from '../src/models/User.model';
import {createGuestAccount, grantGuestAccount} from '../src/services/auth.service';
import {guestTrialStatus} from '../src/services/guest-trial.service';
import {authClock} from '../src/services/auth-clock';
import {GuestCleanupControl} from '../src/models/GuestCleanupControl.model';
import {GuestLifecycleOutbox} from '../src/models/GuestLifecycle.model';
import {GuestTrial} from '../src/models/GuestTrial.model';
import {AuthSession} from '../src/models/AuthSession.model';
import {Conversation} from '../src/models/Conversation.model';
import {UserSettings} from '../src/models/UserSettings.model';
import {AuditLog} from '../src/models/AuditLog.model';
import {SessionChain} from '../src/models/SessionChain.model';
import {GuestMediaCleanup} from '../src/models/GuestMediaCleanup.model';
import {runGuestCleanup, startGuestCleanup} from '../src/services/guest-cleanup.service';
import {syntheticCanaryRegistry} from '../src/services/synthetic-canary.service';
import * as chainService from '../src/services/session-chain.service';
import * as avatarMedia from '../src/services/avatar-media.service';
import {discardGuest, pinGuestAuthority} from '../src/services/guest-data.service';
import {convertGuestToPermanent} from '../src/services/auth.service';
import {hashToken} from '../src/utils/jwt.util';
import {changeCleanupControl, waitForCleanupDrain} from '../scripts/guest-cleanup-control';
import {guestCleanupDryRun} from '../src/services/guest-cleanup-report.service';

const day = 86400000;
beforeAll(async () => {await connectDatabase(); await User.init();});
beforeEach(async () => {
  for (const model of [User, GuestTrial, AuthSession, Conversation, UserSettings, AuditLog, SessionChain,
    GuestCleanupControl, GuestMediaCleanup, GuestLifecycleOutbox]) await model.deleteMany({});
  await mongoose.connection.collection('guest_retention_activation').deleteMany({});
  await GuestCleanupControl.create({_id: 'guest-cleanup', paused: false, reason: 'test resume', changedAt: new Date(), changedBy: 'test', version: 1});
});
afterEach(() => {vi.restoreAllMocks();});
afterAll(async () => {await mongoose.connection.dropDatabase(); await disconnectDatabase();});

it('shows a durable activation plus seven days without granting legacy trial access', async () => {
  const a = await createGuestAccount({}), id = new Types.ObjectId(a.user.id);
  expect((await guestTrialStatus(id)).dataRetainedUntil).toBeNull();
  const activatedAt = new Date('2026-11-17T00:00:00Z');
  await mongoose.connection.collection('guest_retention_activation').insertOne({_id: 'legacy-retention' as any, activatedAt});
  vi.spyOn(authClock, 'now').mockReturnValue(new Date('2026-11-23T00:00:00Z'));
  const retained = await guestTrialStatus(id);
  expect(retained.dataRetainedUntil?.toISOString()).toBe('2026-11-24T00:00:00.000Z');
  expect(retained).toMatchObject({state: 'expired', dataState: 'legacy_unknown', remainingSeconds: 0});
  expect(retained.allowedActions).toContain('convert');
  vi.mocked(authClock.now).mockReturnValue(new Date('2026-11-24T00:00:00Z'));
  const expired = await guestTrialStatus(id);
  expect(expired.dataState).toBe('expired');
  expect(expired.allowedActions).not.toContain('convert');
  expect(expired.allowedActions).toContain('discard');
  await mongoose.connection.collection('guest_retention_activation').deleteMany({});
});

async function expiredGuest() {
  const a = await createGuestAccount({}), id = new Types.ObjectId(a.user.id);
  await User.collection.updateOne({_id: id}, {$set: {guestGrantedAt: new Date(Date.now() - 8 * day)}});
  const session = (await AuthSession.findOne({tokenHash: hashToken(a.tokens.accessToken)}))!;
  return {...a, id, sessionId: session._id};
}
const run = () => runGuestCleanup({enabled: true});

it('deletes expired owned data, audit rows and User atomically with one sanitized receipt, retaining cooldown and revocation fences', async () => {
  const a = await expiredGuest();
  const trial = await GuestTrial.create({deviceHash: 'a'.repeat(64), lastGrantRequestHash: 'b'.repeat(64), legacyFallbackDisabledAt: new Date()});
  await User.updateOne({_id: a.id}, {$set: {guestTrialId: trial._id}});
  await Conversation.create({userId: a.id, content: 'private content', direction: 'TEXT'});
  await AuditLog.collection.insertOne({userId: a.id});
  const result = await run();
  expect(result.deleted).toBe(1);
  expect(await User.exists({_id: a.id})).toBeNull();
  expect(await Conversation.countDocuments({userId: a.id})).toBe(0);
  expect(await UserSettings.countDocuments({userId: a.id})).toBe(0);
  expect(await AuditLog.countDocuments({userId: a.id})).toBe(0);
  expect(await AuthSession.countDocuments({userId: a.id, status: 'REVOKED'})).toBe(2);
  expect(await SessionChain.countDocuments({userId: a.id, status: 'REVOKED'})).toBe(1);
  expect(await GuestTrial.findById(trial._id).select('+lastGrantRequestHash').lean()).toMatchObject({lastGrantRequestHash: 'b'.repeat(64), legacyFallbackDisabledAt: trial.legacyFallbackDisabledAt});
  const receipt = (await GuestLifecycleOutbox.findOne({kind: 'EXPIRED_CLEANED'}).lean())!;
  expect(receipt.payload).toMatchObject({guestUserId: String(a.id), reason: 'ordinary_expired', dataVersion: 0});
  expect(Object.keys(receipt.payload).sort()).toEqual(['dataVersion', 'deadline', 'deletedAt', 'guestUserId', 'reason']);
  expect(JSON.stringify(receipt)).not.toContain(a.tokens.accessToken);
  expect(JSON.stringify(receipt)).not.toContain('private content');
  expect((await run()).deleted).toBe(0);
  expect(await GuestLifecycleOutbox.countDocuments({kind: 'EXPIRED_CLEANED'})).toBe(1);
});

it('rolls owned data and fences back if the receipt cannot commit', async () => {
  const a = await expiredGuest();
  await Conversation.create({userId: a.id, content: 'keep', direction: 'TEXT'});
  vi.spyOn(GuestLifecycleOutbox, 'create').mockRejectedValueOnce(new Error('outbox unavailable'));
  expect((await run()).failed).toBe(1);
  expect(await User.exists({_id: a.id})).not.toBeNull();
  expect(await Conversation.countDocuments({userId: a.id})).toBe(1);
  expect(await AuthSession.countDocuments({userId: a.id, status: 'ACTIVE'})).toBe(2);
  expect(await GuestMediaCleanup.countDocuments()).toBe(0);
});

it('is OFF by default and fails closed on absent or malformed control', async () => {
  const a = await expiredGuest();
  expect((await runGuestCleanup()).state).toBe('disabled');
  const scheduler = startGuestCleanup();
  await scheduler.stop();
  await GuestCleanupControl.deleteMany({});
  expect((await run()).state).toBe('paused');
  await GuestCleanupControl.collection.insertOne({_id: 'guest-cleanup', paused: false} as any);
  expect((await run()).state).toBe('paused');
  expect(await User.exists({_id: a.id})).not.toBeNull();
});

it('treats a raw null lease as malformed control and remains paused', async () => {
  const a = await expiredGuest();
  await GuestCleanupControl.collection.updateOne({_id: 'guest-cleanup'}, {$set: {lease: null}} as any);
  expect((await run()).state).toBe('paused');
  expect(await User.exists({_id: a.id})).not.toBeNull();
});

it('pauses during the certified freeze and resumes ordinary D2 cleanup during W', async () => {
  const a = await expiredGuest();
  await GuestCleanupControl.updateOne({_id: 'guest-cleanup'}, {$set: {paused: true}});
  expect((await run()).state).toBe('paused');
  expect(await User.exists({_id: a.id})).not.toBeNull();
  await GuestCleanupControl.updateOne({_id: 'guest-cleanup'}, {$set: {paused: false}});
  expect((await run()).deleted).toBe(1);
});

it.each(['registered', 'unknown', 'unreadable', 'no-transition', 'boundary'])('exempts a synthetic candidate only until durable T_s+30m: %s', async kind => {
  const a = await expiredGuest(), now = new Date();
  vi.spyOn(authClock, 'now').mockReturnValue(now);
  if (kind === 'unreadable') vi.spyOn(syntheticCanaryRegistry, 'contains').mockRejectedValue(new Error('registry unavailable'));
  else vi.spyOn(syntheticCanaryRegistry, 'contains').mockResolvedValue(kind === 'registered' || kind === 'no-transition' || kind === 'boundary');
  vi.spyOn(chainService, 'loadChainTransition').mockResolvedValue(kind === 'no-transition' ? null : {
    _id: 'session-chain-transition', sunsetAt: new Date(+now - (kind === 'boundary' ? 1800000 : 1)),
  } as any);
  expect((await guestTrialStatus(a.id)).allowedActions).not.toContain('convert');
  expect((await guestTrialStatus(a.id)).state).toBe('expired');
  const result = await run();
  expect(result.deleted).toBe(kind === 'registered' ? 0 : 1);
  expect(result.syntheticExempt).toBe(kind === 'registered' ? 1 : 0);
});

it('leaves unknown legacy guests until activation, then cleans at exactly activation+7d', async () => {
  const a = await createGuestAccount({});
  expect((await run()).deleted).toBe(0);
  await mongoose.connection.collection('guest_retention_activation').insertOne({_id: 'legacy-retention' as any, activatedAt: new Date(Date.now() - 7 * day)});
  expect((await run()).deleted).toBe(1);
  expect(await GuestLifecycleOutbox.findOne({kind: 'EXPIRED_CLEANED'}).lean()).toMatchObject({payload: {guestUserId: a.user.id, reason: 'legacy_unknown'}});
});

it('bounds a run to 25 indexed candidates and reports overdue pending count and age', async () => {
  await User.insertMany(Array.from({length: 27}, () => ({displayName: 'expired', isGuest: true, accountType: 'GUEST', guestGrantedAt: new Date(Date.now() - 9 * day)})));
  const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
  const result = await run();
  expect(result.considered).toBe(25);
  expect(result.deleted).toBe(25);
  expect(result.pendingCount).toBe(2);
  expect(result.oldestPendingAgeMs).toBeGreaterThanOrEqual(2 * day);
  expect(warning.mock.calls.flat().join(' ')).toContain('24h');
});

it('never starts another candidate after the 30s monotonic budget', async () => {
  await expiredGuest(); await expiredGuest();
  let calls = 0;
  const result = await runGuestCleanup({enabled: true, monotonicNow: () => calls++ < 4 ? 0 : 30000});
  expect(result.deleted).toBeLessThan(2);
  expect(await User.countDocuments()).toBeGreaterThan(0);
});

it('retries failed durable media jobs, alerts on persistent failure and keeps the job', async () => {
  const a = await expiredGuest();
  vi.spyOn(avatarMedia, 'removeOwnedAvatars').mockRejectedValue(new Error('disk unavailable'));
  const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
  await discardGuest(a.id, a.sessionId, 0);
  expect((await GuestMediaCleanup.findById(String(a.id)).lean())?.attempts).toBe(3);
  await run();
  expect((await GuestMediaCleanup.findById(String(a.id)).lean())?.attempts).toBe(6);
  expect(warning.mock.calls.flat().join(' ')).toContain('media');
  vi.mocked(avatarMedia.removeOwnedAvatars).mockResolvedValue();
  await run();
  expect(await GuestMediaCleanup.countDocuments()).toBe(0);
});

it('retries old media jobs before a candidate batch exhausts the run budget', async () => {
  const id = String(new Types.ObjectId());
  await GuestMediaCleanup.create({_id: id, paths: [avatarMedia.ownedAvatarPath(id)], attempts: 3, createdAt: new Date()});
  await expiredGuest();
  let time = 0;
  const hold = holdUserRead(false), pending = runGuestCleanup({enabled: true, monotonicNow: () => time});
  try {
    await hold.reached.promise;
    time = 30000;
    hold.resume.release();
    await pending;
    expect(await GuestMediaCleanup.exists({_id: id})).toBeNull();
  } finally {hold.resume.release(); await pending; hold.restore();}
});

it('skips converted/permanent users and candidates whose version changed after selection', async () => {
  const a = await expiredGuest();
  const hold = holdUserRead(false), pending = run();
  try {
    await hold.reached.promise;
    await User.updateOne({_id: a.id}, {$inc: {dataVersion: 1}});
    hold.resume.release();
    expect((await pending).skipped).toBe(1);
  } finally {hold.resume.release(); await pending; hold.restore();}
  await User.updateOne({_id: a.id}, {$set: {isGuest: false, guestConvertedAt: new Date()}});
  expect((await run()).deleted).toBe(0);
  expect(await User.exists({_id: a.id})).not.toBeNull();
});

function latch() {
  let release!: () => void;
  const promise = new Promise<void>(resolve => {release = resolve;});
  return {promise, release};
}
function holdUserRead(transaction: boolean) {
  const reached = latch(), resume = latch();
  const method = transaction ? 'findById' : 'find', read = User[method];
  let held = false;
  const spy = vi.spyOn(User, method).mockImplementation((function(this: typeof User, ...args: any[]) {
    const query = Reflect.apply(read, this, args), exec = query.exec;
    query.exec = async function(...params: any[]) {
      const rows = await Reflect.apply(exec, this, params);
      if (!held && (transaction ? query.getOptions().session?.inTransaction() : query.getOptions().limit === 25)) {
        held = true; reached.release(); await resume.promise;
      }
      return rows;
    };
    return query;
  }) as any);
  return {reached, resume, restore: () => spy.mockRestore()};
}
const enrollment = {email: 'conversion@example.test', password: 'Cleanup2026!', displayName: 'Converted'};

it('a just-in-time conversion wins a paused cleanup snapshot and is never deleted on retry', async () => {
  const a = await expiredGuest(), now = new Date(), deadline = new Date(+now + 1);
  await User.collection.updateOne({_id: a.id}, {$unset: {guestGrantedAt: ''}});
  await mongoose.connection.collection('guest_retention_activation').insertOne({_id: 'legacy-retention' as any, activatedAt: new Date(+deadline - 7 * day)});
  vi.spyOn(authClock, 'now').mockReturnValue(now);
  const hold = holdUserRead(true), pending = run();
  try {
    await hold.reached.promise;
    await convertGuestToPermanent(a.id, enrollment, {}, false, a.sessionId);
    vi.mocked(authClock.now).mockReturnValue(deadline);
    hold.resume.release();
    expect((await pending).deleted).toBe(0);
    expect(await User.exists({_id: a.id, isGuest: false})).not.toBeNull();
    expect(await GuestLifecycleOutbox.countDocuments({kind: 'EXPIRED_CLEANED'})).toBe(0);
  } finally {hold.resume.release(); await pending; hold.restore();}
});

it('cleanup wins when a paused conversion crosses the deadline; no conversion or orphan can commit', async () => {
  const a = await expiredGuest(), now = new Date(), deadline = new Date(+now + 1);
  await User.collection.updateOne({_id: a.id}, {$set: {guestGrantedAt: new Date(+deadline - 7 * day)}});
  await Conversation.create({userId: a.id, content: 'race data', direction: 'TEXT'});
  vi.spyOn(authClock, 'now').mockReturnValue(now);
  const hold = holdUserRead(true);
  const pending = convertGuestToPermanent(a.id, enrollment, {}, false, a.sessionId).catch(error => error);
  try {
    await hold.reached.promise;
    vi.mocked(authClock.now).mockReturnValue(deadline);
    expect((await run()).deleted).toBe(1);
    hold.resume.release();
    expect(await pending).toMatchObject({statusCode: 401});
    expect(await User.exists({_id: a.id})).toBeNull();
    expect(await Conversation.countDocuments({userId: a.id})).toBe(0);
    expect(await GuestLifecycleOutbox.countDocuments({kind: 'CONVERTED'})).toBe(0);
  } finally {hold.resume.release(); await pending; hold.restore();}
});

it.each(['cleanup', 'discard'])('serializes a paused %s against the other deletion with exactly one event', async loser => {
  const a = await expiredGuest(), hold = holdUserRead(true);
  const action = (name: string) => name === 'cleanup' ? run() : discardGuest(a.id, a.sessionId, 0);
  const pending = action(loser).catch(error => error);
  try {
    await hold.reached.promise;
    await action(loser === 'cleanup' ? 'discard' : 'cleanup');
    hold.resume.release(); await pending;
    expect(await User.exists({_id: a.id})).toBeNull();
    expect(await GuestLifecycleOutbox.countDocuments({kind: {$in: ['DISCARDED', 'EXPIRED_CLEANED']}})).toBe(1);
  } finally {hold.resume.release(); await pending; hold.restore();}
});

it('a pause between selection and deletion drains the lease without touching the candidate', async () => {
  const a = await expiredGuest(), hold = holdUserRead(false), pending = run(), db = mongoose.connection.db!;
  try {
    await hold.reached.promise;
    const paused = await changeCleanupControl(db, {paused: true, expectedVersion: 1, reason: 'K+S B2', operator: 'qa'});
    await expect(waitForCleanupDrain(db, paused.version, {maxWaitMs: 0})).rejects.toThrow();
    hold.resume.release();
    expect((await pending).deleted).toBe(0);
    await waitForCleanupDrain(db, paused.version, {maxWaitMs: 0});
    expect(await User.exists({_id: a.id})).not.toBeNull();
  } finally {hold.resume.release(); await pending; hold.restore();}
});

it('bounds repeated transaction conflicts without deleting the user or emitting an event', async () => {
  const a = await expiredGuest(), update = User.updateOne;
  let conflicts = 0;
  vi.spyOn(User, 'updateOne').mockImplementation((function(this: typeof User, ...args: any[]) {
    if (args[0].isGuest === true) {
      conflicts++;
      const error = new mongoose.mongo.MongoServerError({message: 'WriteConflict', code: 112});
      error.addErrorLabel('TransientTransactionError');
      return Promise.reject(error);
    }
    return Reflect.apply(update, this, args);
  }) as any);
  const result = await run();
  expect(conflicts).toBe(3);
  expect(result.deleted).toBe(0);
  expect(await User.exists({_id: a.id})).not.toBeNull();
  expect(await GuestLifecycleOutbox.countDocuments()).toBe(0);
});

it('cleans suspended expired guests too, while authenticated status remains denied', async () => {
  const a = await expiredGuest();
  await User.updateOne({_id: a.id}, {$set: {status: 'SUSPENDED'}});
  await expect(guestTrialStatus(a.id)).rejects.toMatchObject({statusCode: 401});
  expect((await run()).deleted).toBe(1);
});

it('matches discard ownership coverage and dry-run totals, preserving other users and dictionary counters', async () => {
  const a = await expiredGuest(), other = await createGuestAccount({}), otherId = new Types.ObjectId(other.user.id), db = mongoose.connection.db!;
  await User.updateOne({_id: otherId}, {$set: {isGuest: false, guestConvertedAt: new Date()}});
  const entryId = new Types.ObjectId(), collectionId = new Types.ObjectId();
  await db.collection('dictionary_entries').insertOne({_id: entryId, favoriteCount: 2});
  const ownedCollections = ['favorites', 'conversations', 'search_history', 'learning_enrollments', 'learning_word_progress',
    'learning_personal_words', 'learning_review_quizzes', 'learning_events', 'notification_devices', 'user_notifications',
    'learning_sign_notes', 'audit_logs'];
  for (const name of ownedCollections) {
    await db.collection(name).insertMany([{userId: a.id, entryId, token: 'cleanup-owned'}, {userId: otherId, entryId, token: 'cleanup-other'}]);
  }
  await db.collection('learning_sign_collections').insertMany([{_id: collectionId, userId: a.id}, {userId: otherId}]);
  await db.collection('collection_reports').insertMany([{userId: a.id}, {userId: otherId, collectionId}, {userId: otherId}]);
  const before = await guestCleanupDryRun(new Date());
  const totals: Record<string, number> = {};
  const otherCounts: Record<string, number> = {};
  for (const name of Object.keys(before.documents)) totals[name] = await db.collection(name).countDocuments();
  for (const name of ownedCollections) otherCounts[name] = await db.collection(name).countDocuments({userId: otherId});
  expect((await run()).deleted).toBe(1);
  for (const [name, count] of Object.entries(before.documents)) {
    expect(totals[name] - await db.collection(name).countDocuments(), name).toBe(count);
  }
  expect((await db.collection('dictionary_entries').findOne({_id: entryId}))?.favoriteCount).toBe(1);
  for (const name of ownedCollections) expect(await db.collection(name).countDocuments({userId: otherId}), name).toBe(otherCounts[name]);
  expect(await User.exists({_id: otherId, isGuest: false})).not.toBeNull();
});

it('cleanup permanently disables a shared legacy fallback while preserving its cooldown', async () => {
  const a = await expiredGuest(), b = await createGuestAccount({}), startedAt = new Date(Date.now() - day);
  const trial = await GuestTrial.create({deviceHash: 'c'.repeat(64), startedAt, expiresAt: new Date(+startedAt + 600000)});
  await User.updateMany({_id: {$in: [a.id, new Types.ObjectId(b.user.id)]}}, {$set: {guestTrialId: trial._id}});
  await User.collection.updateOne({_id: new Types.ObjectId(b.user.id)}, {$set: {createdAt: new Date(+startedAt - 1)}});
  expect((await guestTrialStatus(new Types.ObjectId(b.user.id))).dataState).toBe('legacy_unknown');
  expect((await run()).deleted).toBe(1);
  expect((await guestTrialStatus(new Types.ObjectId(b.user.id))).dataState).toBe('legacy_unknown');
  expect((await GuestTrial.findById(trial._id).lean())?.legacyFallbackDisabledAt).toBeInstanceOf(Date);
  expect((await GuestTrial.findById(trial._id).lean())?.startedAt).toEqual(startedAt);
});

it('activation expiry never adds trial rights to an unknown legacy binding', async () => {
  const a = await createGuestAccount({}), id = new Types.ObjectId(a.user.id), startedAt = new Date(Date.now() - 8 * day);
  const deviceKey = 'expired-legacy-device-key-'.repeat(3);
  const trial = await GuestTrial.create({deviceHash: createHash('sha256').update(deviceKey).digest('hex'), startedAt, lastGrantRequestHash: 'e'.repeat(64)});
  await User.updateOne({_id: id}, {$set: {guestTrialId: trial._id}});
  await mongoose.connection.collection('guest_retention_activation').insertOne({_id: 'legacy-retention' as any, activatedAt: startedAt});
  const status = await guestTrialStatus(id);
  expect(status.dataState).toBe('expired');
  expect(status.allowedActions).toEqual(['status', 'auth_me', 'refresh', 'logout', 'discard']);
  const caller = (await AuthSession.findOne({userId: id, sessionType: 'ACCESS'}))!;
  const authority = await pinGuestAuthority(id, caller._id);
  await expect(grantGuestAccount({}, {deviceKey, requestKey: 'f'.repeat(64), expectedLastGrantAt: startedAt.toISOString()},
    {authority, expectedDataVersion: 0})).rejects.toMatchObject({statusCode: 409, code: 'GUEST_LEGACY_REPLACEMENT_DENIED'});
  expect(await User.exists({_id: id})).not.toBeNull();
});

it('rotates past 25 unactivated legacy guests so they cannot starve ordinary expiry', async () => {
  await User.insertMany(Array.from({length: 26}, () => ({displayName: 'legacy', isGuest: true, accountType: 'GUEST'})));
  const a = await expiredGuest();
  expect((await run()).deleted).toBe(0);
  expect((await run()).deleted).toBe(1);
  expect(await User.exists({_id: a.id})).toBeNull();
});

it('cleans historical version-zero users whose stored dataVersion field is absent', async () => {
  const a = await expiredGuest();
  await User.collection.updateOne({_id: a.id}, {$unset: {dataVersion: ''}});
  expect((await run()).deleted).toBe(1);
  expect(await User.exists({_id: a.id})).toBeNull();
});

it('does not take over an expired lease until the previous process is certified stopped', async () => {
  const a = await expiredGuest();
  const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
  await GuestCleanupControl.updateOne({_id: 'guest-cleanup'}, {$set: {lease: {holder: 'stalled-run', expiresAt: new Date(0), revision: 0}}});
  expect((await run()).deleted).toBe(0);
  expect(await User.exists({_id: a.id})).not.toBeNull();
  expect(warning.mock.calls.flat().join(' ')).toContain('ALERT');
});

it.each(['paused', 'malformed', 'leased'])('re-checks %s control after selection and before deletion', async kind => {
  const a = await expiredGuest(), hold = holdUserRead(false), pending = run();
  try {
    await hold.reached.promise;
    await GuestCleanupControl.collection.updateOne({_id: 'guest-cleanup'} as any,
      {$set: kind === 'paused' ? {paused: true} : kind === 'malformed' ? {changedBy: ''} : {'lease.holder': 'another-run'}});
    hold.resume.release();
    expect((await pending).deleted).toBe(0);
    expect(await User.exists({_id: a.id})).not.toBeNull();
  } finally {hold.resume.release(); await pending; hold.restore();}
});

it('a permanently failing media batch cannot starve later durable jobs', async () => {
  const ids = Array.from({length: 26}, () => String(new Types.ObjectId())), last = ids[25];
  await GuestMediaCleanup.insertMany(ids.map(id => ({_id: id, paths: [avatarMedia.ownedAvatarPath(id)], createdAt: new Date()})));
  vi.spyOn(avatarMedia, 'removeOwnedAvatars').mockImplementation(async id => {if (id !== last) throw new Error('persistent disk failure');});
  vi.spyOn(console, 'warn').mockImplementation(() => {});
  await run();
  expect(await GuestMediaCleanup.countDocuments()).toBe(26);
  await run();
  expect(await GuestMediaCleanup.exists({_id: last})).toBeNull();
  expect(await GuestMediaCleanup.countDocuments()).toBe(25);
});
