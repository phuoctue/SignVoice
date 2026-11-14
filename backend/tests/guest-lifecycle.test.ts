import {beforeAll, afterAll, afterEach, it, expect, vi} from 'vitest';
import request from 'supertest';
import {randomBytes} from 'node:crypto';
import mongoose, {Types} from 'mongoose';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {User, AuthSession, UserSettings, Conversation} from '../src/models';
import {GuestTrial} from '../src/models/GuestTrial.model';
import {authClock} from '../src/services/auth-clock';
import * as authService from '../src/services/auth.service';
import {discardGuest, pinGuestAuthority} from '../src/services/guest-data.service';
import {GuestLifecycleOutbox, GuestLifecycleCounter} from '../src/models/GuestLifecycle.model';
import {hashToken} from '../src/utils/jwt.util';
import {AuditLog} from '../src/models/AuditLog.model';
import * as avatarMedia from '../src/services/avatar-media.service';
import {access, rm} from 'node:fs/promises';
import path from 'node:path';

let app: Awaited<ReturnType<typeof createApp>>;
const day = 86400000;
const body = () => ({deviceKey: randomBytes(32).toString('hex'), requestKey: randomBytes(32).toString('hex'), expectedLastGrantAt: null as string | null});
const auth = (a: any) => ({Authorization: 'Bearer ' + a.tokens.accessToken});
const credentials = () => ({email: randomBytes(12).toString('hex') + '@example.test', password: 'Lifecycle2026!', displayName: 'Lifecycle'});
const events = () => mongoose.connection.collection('guest_lifecycle_outbox');
async function guest() {
  const input = body();
  const response = await request(app).post('/api/v1/auth/guest').send(input).expect(201);
  const a = response.body.data;
  const status = await request(app).get('/api/v1/guest-trial/status').set(auth(a)).expect(200);
  return {...a, input, version: status.body.data.dataVersion, grant: status.body.data.startedAt};
}
const discard = (a: any, input = {confirmDiscard: true, expectedDataVersion: a.version}) => request(app).post('/api/v1/guest-data/discard').set(auth(a)).send(input);
beforeAll(async () => {
  await connectDatabase();
  await Promise.all([User, AuthSession, UserSettings, Conversation, GuestTrial].map(model => model.init()));
  app = await createApp();
});
const mediaFolders = new Set<string>();
afterEach(async () => {
  vi.restoreAllMocks();
  for (const folder of mediaFolders) {
    if (path.dirname(folder) !== path.resolve(__dirname, '../../.runtime/avatar-media')) throw new Error('Unsafe media fixture cleanup');
    await rm(folder, {recursive: true, force: true});
  }
  mediaFolders.clear();
});
afterAll(async () => {await mongoose.connection.dropDatabase(); await disconnectDatabase();});

it.each(['retained', 'expired', 'legacy_unknown'])('discards %s data only with current credentials and keeps cooldown/marker', async state => {
  const a = await guest(), id = new Types.ObjectId(a.user.id);
  if (state === 'legacy_unknown') await User.collection.updateOne({_id: id}, {$unset: {guestGrantedAt: '', guestTrialId: ''}});
  else await User.collection.updateOne({_id: id}, {$set: {guestGrantedAt: new Date(Date.now() - (state === 'expired' ? 8 * day : day))}});
  await Conversation.create({userId: id, content: 'private', direction: 'TEXT'});
  const trials = await GuestTrial.find().select('+lastGrantRequestHash').lean();
  await request(app).post('/api/v1/guest-data/discard').send({deviceKey: a.input.deviceKey, confirmDiscard: true, expectedDataVersion: 0}).expect(401);
  await discard(a, {confirmDiscard: true, expectedDataVersion: a.version + 1}).expect(409);
  expect(await User.exists({_id: id})).not.toBeNull();
  await discard(a).expect(200);
  expect(await User.exists({_id: id})).toBeNull();
  expect(await Conversation.countDocuments({userId: id})).toBe(0);
  expect(await UserSettings.countDocuments({userId: id})).toBe(0);
  expect(await AuthSession.countDocuments({userId: id, status: 'ACTIVE'})).toBe(0);
  expect(await GuestTrial.find().select('+lastGrantRequestHash').lean()).toEqual(trials);
  expect(await events().countDocuments({kind: 'DISCARDED', 'payload.guestUserId': a.user.id})).toBe(1);
  await discard(a).expect(401);
  await request(app).post('/api/v1/auth/guest').send({...a.input, requestKey: randomBytes(32).toString('hex'), expectedLastGrantAt: a.grant}).expect(409);
});

it('HTTP conversion keeps the same data, pins login and emits one sanitized conversion epoch', async () => {
  const a = await guest(), data = credentials();
  const own = await Conversation.create({userId: a.user.id, content: 'keep me', direction: 'TEXT'});
  await request(app).post('/api/v1/auth/convert-guest').set(auth(a)).send({...data, requireLogin: false}).expect(400);
  const result = await request(app).post('/api/v1/auth/convert-guest').set(auth(a)).send(data).expect(200);
  expect(result.body.data).toMatchObject({loginRequired: true, user: {id: a.user.id, isGuest: false}});
  expect(result.body.data.tokens).toBeUndefined();
  expect(await Conversation.exists({_id: own._id})).not.toBeNull();
  const event = await events().findOne({kind: 'CONVERTED', 'payload.sameUserId': a.user.id});
  expect(event?.payload.newEpoch).toBe(1);
  expect(JSON.stringify(event)).not.toContain(data.email);
  expect(JSON.stringify(event)).not.toContain(a.tokens.accessToken);
  await discard(a).expect(401);
  const login = await request(app).post('/api/v1/auth/login').send(data).expect(200);
  await discard({...a, tokens: login.body.data.tokens}).expect(409);
  expect(await User.exists({_id: a.user.id, isGuest: false})).not.toBeNull();
});

it('atomically replaces a confirmed old allowance and rejects lost-response replay', async () => {
  const a = await guest(), now = new Date();
  vi.spyOn(authClock, 'now').mockReturnValue(now);
  const previous = new Date(+now - day);
  await User.collection.updateOne({_id: new Types.ObjectId(a.user.id)}, {$set: {guestGrantedAt: previous}});
  await GuestTrial.updateOne({deviceHash: (await GuestTrial.findOne().sort({createdAt: -1}))!.deviceHash}, {$set: {startedAt: previous}});
  const input = {...a.input, requestKey: randomBytes(32).toString('hex'), expectedLastGrantAt: previous.toISOString(), confirmDiscard: true, expectedDataVersion: a.version};
  const before = await events().countDocuments();
  const result = await request(app).post('/api/v1/auth/guest').set(auth(a)).send(input).expect(201);
  expect(result.body.data.user.id).not.toBe(a.user.id);
  expect(await User.exists({_id: a.user.id})).toBeNull();
  const committed = await events().find().sort({sequence: 1}).skip(before).toArray();
  expect(committed.map(e => e.kind)).toEqual(['DISCARDED', 'GRANTED']);
  expect(committed[1].sequence).toBe(committed[0].sequence + 1);
  await request(app).post('/api/v1/auth/guest').set(auth(a)).send(input).expect(401);
  const replay = await request(app).post('/api/v1/auth/guest').send(input).expect(401);
  expect(replay.body.data?.tokens).toBeUndefined();
  expect(await events().countDocuments()).toBe(before + 2);
});

async function prepareReplacement(a: any) {
  const previous = new Date(Date.now() - day - 1000);
  const user = (await User.findById(a.user.id).select('+guestTrialId'))!;
  await User.collection.updateOne({_id: user._id}, {$set: {guestGrantedAt: previous}});
  await GuestTrial.updateOne({_id: user.guestTrialId}, {$set: {startedAt: previous}});
  return {...a.input, expectedLastGrantAt: previous.toISOString(), requestKey: randomBytes(32).toString('hex')};
}
async function sessionId(a: any) {
  return (await AuthSession.findOne({tokenHash: hashToken(a.tokens.accessToken)}))!._id;
}
function latch() {
  let release!: () => void;
  const promise = new Promise<void>(resolve => {release = resolve;});
  return {promise, release};
}
// Pause exactly one transaction after its original snapshot read and before any write.
function holdSnapshot() {
  const reached = latch(), resume = latch();
  let held = false;
  const read = User.findById;
  const spy = vi.spyOn(User, 'findById').mockImplementation((function(this: typeof User, ...args: any[]) {
    const query = Reflect.apply(read, this, args), exec = query.exec;
    query.exec = async function(...params: any[]) {
      const row = await Reflect.apply(exec, this, params);
      if (!held && query.getOptions().session?.inTransaction()) {
        held = true; reached.release(); await resume.promise;
      }
      return row;
    };
    return query;
  }) as typeof read);
  return {reached, resume, restore: () => spy.mockRestore()};
}

it.each([
  ['convert', 'discard', 401, 'AUTH_SESSION_INVALID'], ['discard', 'convert', 401, 'AUTH_SESSION_INVALID'],
  ['convert', 'replacement', 401, 'AUTH_SESSION_INVALID'], ['replacement', 'convert', 401, 'AUTH_SESSION_INVALID'],
  ['discard', 'discard', 401, 'AUTH_SESSION_INVALID'], ['replacement', 'grant', 409, 'GUEST_GRANT_ALREADY_COMMITTED'],
  ['grant', 'replacement', 409, 'GUEST_GRANT_ALREADY_COMMITTED'],
])('serializes a paused %s against winning %s without lost conversion, double grant or orphans', async (loser, winner, statusCode, code) => {
  const a = await guest(), input = await prepareReplacement(a), id = new Types.ObjectId(a.user.id), sid = await sessionId(a);
  const authority = await pinGuestAuthority(id, sid), data = credentials();
  await Conversation.create({userId: id, content: 'race data', direction: 'TEXT'});
  const before = await events().countDocuments();
  const action = (kind: string) => kind === 'convert' ? authService.convertGuestToPermanent(id, data, {}, false, sid)
    : kind === 'discard' ? discardGuest(id, sid, a.version)
    : authService.grantGuestAccount({}, input, kind === 'replacement' ? {authority, expectedDataVersion: a.version} : undefined);
  const hold = holdSnapshot();
  // A grant has no old User read; pause it at the cooldown read instead.
  let trialSpy: ReturnType<typeof vi.spyOn> | undefined;
  if (loser === 'grant') {
    hold.restore();
    const read = GuestTrial.findOne;
    let held = false;
    trialSpy = vi.spyOn(GuestTrial, 'findOne').mockImplementation((function(this: typeof GuestTrial, ...args: any[]) {
      const query = Reflect.apply(read, this, args), exec = query.exec;
      query.exec = async function(...params: any[]) {
        const row = await Reflect.apply(exec, this, params);
        if (!held && query.getOptions().session?.inTransaction()) {held = true; hold.reached.release(); await hold.resume.promise;}
        return row;
      };
      return query;
    }) as typeof read);
  }
  const pending = action(loser).then(value => ({value, error: undefined}), error => ({value: undefined, error}));
  try {
    await hold.reached.promise;
    await action(winner);
    hold.resume.release();
    const result = await pending;
    expect(result.error).toMatchObject({statusCode, code});
    expect(await events().countDocuments()).toBe(before + (winner === 'replacement' ? 2 : 1));
    if (winner === 'convert') {
      expect(await User.exists({_id: id, isGuest: false})).not.toBeNull();
      expect(await Conversation.countDocuments({userId: id})).toBe(1);
    } else if (winner !== 'grant') {
      expect(await User.exists({_id: id})).toBeNull();
      expect(await Conversation.countDocuments({userId: id})).toBe(0);
      expect(await UserSettings.countDocuments({userId: id})).toBe(0);
    } else {
      expect(await User.exists({_id: id, isGuest: true})).not.toBeNull();
      expect(await Conversation.countDocuments({userId: id})).toBe(1);
    }
  } finally {hold.resume.release(); await pending; hold.restore(); trialSpy?.mockRestore();}
});

const image = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7X8AAAAASUVORK5CYII=';
async function avatar(a: any) {
  const saved = await request(app).patch('/api/v1/users/profile').set(auth(a)).send({avatarImage: image}).expect(200);
  const folder = path.resolve(__dirname, '../../.runtime/avatar-media', a.user.id);
  mediaFolders.add(folder);
  a.version = (await request(app).get('/api/v1/guest-trial/status').set(auth(a)).expect(200)).body.data.dataVersion;
  return {folder, url: saved.body.data.avatarUrl};
}
it.each(['discard', 'replacement'])('removes owned avatar files and audit rows only after committed %s, retaining revocation fences', async action => {
  const a = await guest(), other = await guest(), owned = await avatar(a), untouched = await avatar(other);
  const input = action === 'replacement' ? await prepareReplacement(a) : undefined;
  expect(await AuditLog.countDocuments({userId: a.user.id})).toBeGreaterThan(0);
  if (input) await request(app).post('/api/v1/auth/guest').set(auth(a)).send({...input, confirmDiscard: true, expectedDataVersion: a.version}).expect(201);
  else await discard(a).expect(200);
  await expect(access(owned.folder)).rejects.toMatchObject({code: 'ENOENT'});
  await access(untouched.folder);
  await request(app).get(untouched.url).expect(200);
  expect(await AuditLog.countDocuments({$or: [{userId: a.user.id}, {resourceType: 'User', resourceId: a.user.id}]})).toBe(0);
  expect(await AuthSession.countDocuments({userId: a.user.id, status: 'REVOKED'})).toBe(2);
});
it('keeps failed post-commit media deletion durable and retryable without undoing discard', async () => {
  const a = await guest(), owned = await avatar(a);
  const remove = vi.spyOn(avatarMedia, 'removeOwnedAvatars').mockRejectedValue(new Error('disk unavailable'));
  const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
  await discard(a).expect(200);
  expect(await User.exists({_id: a.user.id})).toBeNull();
  expect(remove).toHaveBeenCalledTimes(3);
  expect(warning).toHaveBeenCalled();
  const jobs = mongoose.connection.collection('guest_media_cleanup');
  expect(await jobs.findOne({_id: a.user.id as any})).toMatchObject({paths: [owned.folder], attempts: 3});
  await access(owned.folder);
  remove.mockRestore();
  const {retryGuestMediaCleanup} = await import('../src/services/guest-media-cleanup.service');
  await retryGuestMediaCleanup();
  await expect(access(owned.folder)).rejects.toMatchObject({code: 'ENOENT'});
  expect(await jobs.countDocuments({_id: a.user.id as any})).toBe(0);
});
it('does not delete media or audit rows, enqueue cleanup or disable fallback when the transaction aborts', async () => {
  const a = await guest(), owned = await avatar(a), before = await AuditLog.countDocuments({userId: a.user.id});
  vi.spyOn(GuestLifecycleOutbox, 'create').mockRejectedValueOnce(new Error('outbox unavailable'));
  await discard(a).expect(500);
  await access(owned.folder);
  expect(await AuditLog.countDocuments({userId: a.user.id})).toBe(before);
  expect(await mongoose.connection.collection('guest_media_cleanup').countDocuments({_id: a.user.id as any})).toBe(0);
});
it('never re-anchors the remaining bound legacy guest after discard, even after later logout', async () => {
  const startedAt = new Date(Date.now() - day);
  const trial = await GuestTrial.create({deviceHash: randomBytes(32).toString('hex'), startedAt, expiresAt: new Date(+startedAt + 600000)});
  const a = await authService.createGuestAccount({}, trial._id), b = await authService.createGuestAccount({}, trial._id);
  await User.collection.updateMany({_id: {$in: [a, b].map(g => new Types.ObjectId(g.user.id))}}, {$set: {createdAt: new Date(+startedAt - 1)}});
  const status = () => request(app).get('/api/v1/guest-trial/status').set(auth(b)).expect(200);
  expect((await status()).body.data.dataState).toBe('legacy_unknown');
  await discard({...a, version: 0}).expect(200);
  expect((await status()).body.data).toMatchObject({dataState: 'legacy_unknown', dataRetainedUntil: null});
  const marked = await GuestTrial.findById(trial._id).lean();
  expect(marked?.legacyFallbackDisabledAt).toBeInstanceOf(Date);
  await request(app).post('/api/v1/auth/logout').set(auth(b)).expect(200);
  expect((await GuestTrial.findById(trial._id).lean())?.legacyFallbackDisabledAt).toEqual(marked?.legacyFallbackDisabledAt);
});
it('does not combine a stale unmarked trial read with a post-discard single-user count', async () => {
  const startedAt = new Date(Date.now() - day);
  const trial = await GuestTrial.create({deviceHash: randomBytes(32).toString('hex'), startedAt, expiresAt: new Date(+startedAt + 600000)});
  const a = await authService.createGuestAccount({}, trial._id), b = await authService.createGuestAccount({}, trial._id);
  await User.collection.updateMany({_id: {$in: [a, b].map(g => new Types.ObjectId(g.user.id))}}, {$set: {createdAt: new Date(+startedAt - 1)}});
  const reached = latch(), resume = latch(), read = GuestTrial.findById;
  let held = false;
  const spy = vi.spyOn(GuestTrial, 'findById').mockImplementation((function(this: typeof GuestTrial, ...args: any[]) {
    const query = Reflect.apply(read, this, args), exec = query.exec;
    query.exec = async function(...params: any[]) {
      const row = await Reflect.apply(exec, this, params);
      if (!held && String(query.getFilter()._id) === String(trial._id)) {held = true; reached.release(); await resume.promise;}
      return row;
    };
    return query;
  }) as typeof read);
  const pending = request(app).get('/api/v1/guest-trial/status').set(auth(b)).then(response => response);
  try {
    await reached.promise;
    await discard({...a, version: 0}).expect(200);
    resume.release();
    const result = await pending;
    expect(result.status).toBe(200);
    expect(result.body.data).toMatchObject({dataState: 'legacy_unknown', dataRetainedUntil: null});
  } finally {resume.release(); await pending; spy.mockRestore();}
});
it('rolls back the durable fallback flag if a legacy discard aborts', async () => {
  const startedAt = new Date(Date.now() - day);
  const trial = await GuestTrial.create({deviceHash: randomBytes(32).toString('hex'), startedAt, expiresAt: new Date(+startedAt + 600000)});
  const a = await authService.createGuestAccount({}, trial._id);
  await User.collection.updateOne({_id: new Types.ObjectId(a.user.id)}, {$set: {createdAt: new Date(+startedAt - 1)}});
  const audit = await AuditLog.countDocuments({userId: a.user.id});
  vi.spyOn(GuestLifecycleOutbox, 'create').mockRejectedValueOnce(new Error('outbox unavailable'));
  await discard({...a, version: 0}).expect(500);
  expect((await GuestTrial.findById(trial._id).lean())?.legacyFallbackDisabledAt).toBeUndefined();
  expect(await User.exists({_id: a.user.id})).not.toBeNull();
  expect(await AuditLog.countDocuments({userId: a.user.id})).toBe(audit);
});
it.each(['cooldown', 'stale'])('aborts an authenticated replacement on %s without deleting old data or writing events', async reason => {
  const a = await guest(), owned = await avatar(a);
  await Conversation.create({userId: a.user.id, content: 'keep', direction: 'TEXT'});
  const counts = await Promise.all([User.countDocuments(), UserSettings.countDocuments(), AuthSession.countDocuments(), events().countDocuments()]);
  const before = await User.findById(a.user.id).lean(), trials = await GuestTrial.find().select('+lastGrantRequestHash').lean();
  const counter = await GuestLifecycleCounter.findById('lifecycle').lean(), audit = await AuditLog.countDocuments({userId: a.user.id});
  const result = await request(app).post('/api/v1/auth/guest').set(auth(a)).send({...a.input, requestKey: randomBytes(32).toString('hex'),
    expectedLastGrantAt: reason === 'cooldown' ? a.grant : null, confirmDiscard: true, expectedDataVersion: a.version}).expect(409);
  expect(result.body.error.code).toBe(reason === 'cooldown' ? 'GUEST_TRIAL_COOLDOWN' : 'GUEST_GRANT_STALE');
  expect(await Promise.all([User.countDocuments(), UserSettings.countDocuments(), AuthSession.countDocuments(), events().countDocuments()])).toEqual(counts);
  expect(await User.findById(a.user.id).lean()).toEqual(before);
  expect(await GuestTrial.find().select('+lastGrantRequestHash').lean()).toEqual(trials);
  expect(await GuestLifecycleCounter.findById('lifecycle').lean()).toEqual(counter);
  expect(await AuditLog.countDocuments({userId: a.user.id})).toBe(audit);
  expect(await mongoose.connection.collection('guest_media_cleanup').countDocuments({_id: a.user.id as any})).toBe(0);
  expect(await Conversation.countDocuments({userId: a.user.id})).toBe(1);
  await access(owned.folder);
});

it('rolls deletion and replacement back with their outbox, preserving sequence and old auth', async () => {
  const a = await guest(), input = await prepareReplacement(a), id = new Types.ObjectId(a.user.id);
  const before = await events().countDocuments(), counter = await GuestLifecycleCounter.findById('lifecycle').lean();
  await Conversation.create({userId: id, content: 'rollback', direction: 'TEXT'});
  const spy = vi.spyOn(GuestLifecycleOutbox, 'create').mockRejectedValue(new Error('Outbox unavailable'));
  await discard(a).expect(500);
  await request(app).post('/api/v1/auth/guest').set(auth(a)).send({...input, confirmDiscard: true, expectedDataVersion: a.version}).expect(500);
  expect(await User.exists({_id: id, isGuest: true})).not.toBeNull();
  expect(await Conversation.countDocuments({userId: id})).toBe(1);
  expect(await events().countDocuments()).toBe(before);
  expect(await GuestLifecycleCounter.findById('lifecycle').lean()).toEqual(counter);
  spy.mockRestore();
  await request(app).get('/api/v1/auth/me').set(auth(a)).expect(200);
});

it('denies legacy replacement and permits separate discard followed by cooldown-checked fresh grant', async () => {
  const a = await guest(), input = await prepareReplacement(a), id = new Types.ObjectId(a.user.id);
  await User.collection.updateOne({_id: id}, {$unset: {guestGrantedAt: '', guestTrialId: ''}});
  const before = await events().countDocuments();
  const result = await request(app).post('/api/v1/auth/guest').set(auth(a)).send({...input, confirmDiscard: true, expectedDataVersion: a.version}).expect(409);
  expect(result.body.error.code).toBe('GUEST_LEGACY_REPLACEMENT_DENIED');
  expect(await events().countDocuments()).toBe(before);
  await discard(a).expect(200);
  await request(app).post('/api/v1/auth/guest').send(input).expect(201);
});

it('rejects conversion when dataVersion changes after the original request read', async () => {
  const a = await guest(), id = new Types.ObjectId(a.user.id), sid = await sessionId(a);
  const hold = holdSnapshot();
  const pending = authService.convertGuestToPermanent(id, credentials(), {}, false, sid).catch(error => error);
  try {
    await hold.reached.promise;
    await User.updateOne({_id: id}, {$inc: {dataVersion: 1}});
    hold.resume.release();
    expect(await pending).toMatchObject({statusCode: 409, code: 'GUEST_DATA_CHANGED'});
    expect(await User.exists({_id: id, isGuest: true})).not.toBeNull();
    expect(await events().countDocuments({kind: 'CONVERTED', 'payload.sameUserId': a.user.id})).toBe(0);
  } finally {hold.resume.release(); await pending; hold.restore();}
});

it.each(['convert', 'discard'])('accepts the existing version-zero default for a legacy row without stored dataVersion on %s', async action => {
  const a = await guest();
  await User.collection.updateOne({_id: new Types.ObjectId(a.user.id)}, {$unset: {guestGrantedAt: '', guestTrialId: '', dataVersion: ''}});
  const status = await request(app).get('/api/v1/guest-trial/status').set(auth(a)).expect(200);
  expect(status.body.data).toMatchObject({dataState: 'legacy_unknown', dataVersion: 0});
  if (action === 'discard') await discard({...a, version: 0}).expect(200);
  else await request(app).post('/api/v1/auth/convert-guest').set(auth(a)).send(credentials()).expect(200);
});
