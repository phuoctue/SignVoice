import {beforeAll, afterAll, afterEach, describe, it, expect, vi} from 'vitest';
import request from 'supertest';
import {createHash, randomBytes} from 'node:crypto';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {User, AuthSession, UserSettings, Conversation, SearchHistory, Category, DictionaryEntry} from '../src/models';
import {GuestTrial} from '../src/models/GuestTrial.model';
import {guestTrialStatus} from '../src/services/guest-trial.service';
import mongoose, {Types} from 'mongoose';
import express from 'express';
import {requireAuth} from '../src/common/middlewares/auth.middleware';
import {clearOwnedData, userTransaction} from '../src/services/user-data.service';
import {authClock} from '../src/services/auth-clock';
import {createGuestAccount} from '../src/services/auth.service';
import {isSyntheticCanary, syntheticCanaryRegistry} from '../src/services/synthetic-canary.service';

let app: Awaited<ReturnType<typeof createApp>>;
const hour = 3600000, day = 24 * hour;
const maintenance = ['status', 'auth_me', 'refresh', 'logout'];
const grantBody = () => ({deviceKey: randomBytes(32).toString('hex'), requestKey: randomBytes(32).toString('hex'), expectedLastGrantAt: null as string | null});
const bearer = (a: any) => ({Authorization: 'Bearer ' + a.tokens.accessToken});
const status = (a: any) => request(app).get('/api/v1/guest-trial/status').set(bearer(a));
async function guest() {
  const body = grantBody();
  const response = await request(app).post('/api/v1/auth/guest').send(body).expect(201);
  return {...response.body.data, body, cookies: response.headers['set-cookie'] as unknown as string[]};
}
async function setAge(a: any, age: number, now: Date) {
  await User.collection.updateOne({_id: new Types.ObjectId(a.user.id)}, {$set: {guestGrantedAt: new Date(+now - age)}});
}
function latch() {
  let release!: () => void;
  const promise = new Promise<void>(resolve => {release = resolve;});
  return {promise, release};
}
async function bounded<T>(promise: Promise<T>): Promise<T> {
  let timer!: ReturnType<typeof setTimeout>;
  try {
    return await Promise.race([promise, new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => reject(new Error('Grant barrier timed out')), 10000);
    })]);
  } finally {clearTimeout(timer);}
}
function holdGrantReads(deviceKey: string) {
  const deviceHash = createHash('sha256').update(deviceKey).digest('hex');
  const reached = [latch(), latch()], resume = [latch(), latch()];
  const observed: (string | null)[] = [];
  const read = GuestTrial.findOne;
  const spy = vi.spyOn(GuestTrial, 'findOne').mockImplementation((function(this: typeof GuestTrial, ...args: any[]) {
    const query = Reflect.apply(read, this, args), exec = query.exec;
    query.exec = async function(...params: any[]) {
      const row = await Reflect.apply(exec, this, params);
      if (query.getFilter().deviceHash === deviceHash && query.getOptions().session?.inTransaction() && observed.length < 2) {
        const index = observed.length;
        observed.push(row?.startedAt?.toISOString() ?? null);
        reached[index].release();
        await resume[index].promise;
      }
      return row;
    };
    return query;
  }) as typeof read);
  return {deviceHash, reached, resume, observed, restore: () => spy.mockRestore()};
}
const grantCounts = () => Promise.all([User.countDocuments(), UserSettings.countDocuments(), AuthSession.countDocuments()]);
beforeAll(async () => {
  await connectDatabase();
  await Promise.all([User, AuthSession, UserSettings, Conversation, SearchHistory, GuestTrial, Category, DictionaryEntry].map(model => model.init()));
  app = await createApp();
});
afterEach(() => vi.restoreAllMocks());
afterAll(disconnectDatabase);

describe('guest policy v1 grant and status', () => {
  it('requires explicit grant parameters and rejects unsupported replacement without writes', async () => {
    const before = await User.countDocuments();
    for (const body of [{}, {newGuest: true}, {...grantBody(), expectedLastGrantAt: undefined}, {...grantBody(), requestKey: ''}]) {
      await request(app).post('/api/v1/auth/guest').send(body).expect(400);
    }
    const trialCount = await GuestTrial.countDocuments();
    for (const authorization of ['Bearer invalid', 'invalid']) {
      const result = await request(app).post('/api/v1/auth/guest').set('Authorization', authorization).send(grantBody()).expect(409);
      expect(result.body.error.code).toBe('GUEST_REPLACEMENT_UNAVAILABLE');
      expect(result.headers['set-cookie']).toBeUndefined();
    }
    const replacement = await request(app).post('/api/v1/auth/guest').send({...grantBody(), confirmDiscard: true, expectedDataVersion: 0}).expect(409);
    expect(replacement.body.error.code).toBe('GUEST_REPLACEMENT_UNAVAILABLE');
    expect(await User.countDocuments()).toBe(before);
    expect(await GuestTrial.countDocuments()).toBe(trialCount);
  });

  it('rejects sequential replay and cooldown with metadata only', async () => {
    const body = grantBody(), before = await User.countDocuments();
    const winner = (await request(app).post('/api/v1/auth/guest').send(body).expect(201)).body.data;
    expect(await User.countDocuments()).toBe(before + 1);
    expect(await UserSettings.countDocuments({userId: winner.user.id})).toBe(1);
    expect(await AuthSession.countDocuments({userId: winner.user.id})).toBe(2);
    const snapshot = (await status(winner).expect(200)).body.data;
    for (let retry = 0; retry < 3; retry++) {
      const result = await request(app).post('/api/v1/auth/guest').send(body).expect(409);
      expect(result.body.error.code).toBe('GUEST_GRANT_ALREADY_COMMITTED');
      expect(Object.keys(result.body.data).sort()).toEqual(['nextTrialAvailableAt', 'serverNow']);
      expect(result.body.data.nextTrialAvailableAt).toBe(snapshot.nextTrialAvailableAt);
      expect(result.headers['set-cookie']).toBeUndefined();
    }
    const cooldown = await request(app).post('/api/v1/auth/guest').send({...body, requestKey: randomBytes(32).toString('hex'), expectedLastGrantAt: snapshot.startedAt}).expect(409);
    expect(cooldown.body.error.code).toBe('GUEST_TRIAL_COOLDOWN');
    const row = await GuestTrial.findOne({lastGrantRequestHash: {$exists: true}}).sort({createdAt: -1}).select('+lastGrantRequestHash');
    expect(row!.toObject().lastGrantRequestHash).not.toBe(body.requestKey);
  });

  it.each(['first insert', 'existing-row CAS'] as const)('serializes distinct multi-tab keys at the %s after both transaction reads', async stage => {
    let body = grantBody();
    const now = new Date();
    let observed: string | null = null;
    if (stage === 'existing-row CAS') {
      const prior = await guest();
      const data = (await status(prior).expect(200)).body.data;
      observed = data.startedAt;
      now.setTime(Date.parse(data.startedAt) + day);
      body = {...prior.body, requestKey: randomBytes(32).toString('hex'), expectedLastGrantAt: observed};
    }
    vi.spyOn(authClock, 'now').mockReturnValue(now);
    const other = {...body, requestKey: randomBytes(32).toString('hex')};
    expect(other.requestKey).not.toBe(body.requestKey);
    const before = await grantCounts(), gate = holdGrantReads(body.deviceKey);
    const pending: Promise<any>[] = [];
    try {
      const first = request(app).post('/api/v1/auth/guest').send(body).then(response => response);
      pending.push(first);
      await bounded(gate.reached[0].promise);
      const second = request(app).post('/api/v1/auth/guest').send(other).then(response => response);
      pending.push(second);
      await bounded(gate.reached[1].promise);
      expect(gate.observed).toEqual([observed, observed]);
      expect(await grantCounts()).toEqual(before);
      // Both snapshots are real and neither transaction has reached its write yet.
      gate.resume[0].release();
      const winner = await bounded(first);
      expect(winner.status).toBe(201);
      gate.resume[1].release();
      const loser = await bounded(second);
      expect(loser.status).toBe(409);
      expect(loser.body.error.code).toBe('GUEST_GRANT_STALE');
      expect(Object.keys(loser.body.data).sort()).toEqual(['nextTrialAvailableAt', 'serverNow']);
      expect(loser.body.data).toEqual({serverNow: now.toISOString(), nextTrialAvailableAt: new Date(+now + day).toISOString()});
      expect(loser.headers['set-cookie']).toBeUndefined();
      expect((await grantCounts()).map((count, index) => count - before[index])).toEqual([1, 1, 2]);
      const row = (await GuestTrial.findOne({deviceHash: gate.deviceHash}).select('+lastGrantRequestHash'))!;
      expect(await GuestTrial.countDocuments({deviceHash: gate.deviceHash})).toBe(1);
      expect(row.lastGrantRequestHash).toBe(createHash('sha256').update(body.requestKey).digest('hex'));
      expect(await User.countDocuments({_id: winner.body.data.user.id, guestTrialId: row._id})).toBe(1);
    } finally {
      gate.resume.forEach(item => item.release());
      await bounded(Promise.allSettled(pending));
      gate.restore();
    }
  });

  it('rejects a latched stale expectation after an intervening grant even when its next cooldown has elapsed', async () => {
    const prior = await guest(), initial = (await status(prior).expect(200)).body.data;
    const stale = {...prior.body, requestKey: randomBytes(32).toString('hex'), expectedLastGrantAt: initial.startedAt};
    const intervening = {...stale, requestKey: randomBytes(32).toString('hex')};
    const clock = vi.spyOn(authClock, 'now').mockReturnValue(new Date(Date.parse(initial.startedAt) + day));
    const before = await grantCounts(), gate = holdGrantReads(stale.deviceKey);
    const pending: Promise<any>[] = [];
    try {
      const older = request(app).post('/api/v1/auth/guest').send(stale).then(response => response);
      pending.push(older);
      await bounded(gate.reached[0].promise);
      const newer = request(app).post('/api/v1/auth/guest').send(intervening).then(response => response);
      pending.push(newer);
      await bounded(gate.reached[1].promise);
      expect(gate.observed).toEqual([initial.startedAt, initial.startedAt]);
      gate.resume[1].release();
      expect((await bounded(newer)).status).toBe(201);
      clock.mockReturnValue(new Date(Date.parse(initial.startedAt) + 2 * day));
      gate.resume[0].release();
      const rejected = await bounded(older);
      expect(rejected.status).toBe(409);
      expect(rejected.body.error.code).toBe('GUEST_GRANT_STALE');
      expect(Object.keys(rejected.body.data).sort()).toEqual(['nextTrialAvailableAt', 'serverNow']);
      expect(rejected.body.data.nextTrialAvailableAt).toBe(new Date(Date.parse(initial.startedAt) + 2 * day).toISOString());
      expect(rejected.headers['set-cookie']).toBeUndefined();
      expect((await grantCounts()).map((count, index) => count - before[index])).toEqual([1, 1, 2]);
      const row = (await GuestTrial.findOne({deviceHash: gate.deviceHash}).select('+lastGrantRequestHash'))!;
      expect(row.lastGrantRequestHash).toBe(createHash('sha256').update(intervening.requestKey).digest('hex'));
      expect((await guestTrialStatus(new Types.ObjectId(prior.user.id))).allowedActions).toContain('new_trial');
    } finally {
      gate.resume.forEach(item => item.release());
      await bounded(Promise.allSettled(pending));
      gate.restore();
    }
  });

  it('rolls back the cooldown and new User when grant creation fails, then permits the same request', async () => {
    const body = grantBody(), before = await User.countDocuments();
    vi.spyOn(UserSettings, 'create').mockRejectedValueOnce(new Error('fixture storage failure'));
    const failed = await request(app).post('/api/v1/auth/guest').send(body).expect(500);
    expect(failed.headers['set-cookie']).toBeUndefined();
    expect(await User.countDocuments()).toBe(before);
    expect(await GuestTrial.countDocuments({deviceHash: createHash('sha256').update(body.deviceKey).digest('hex')})).toBe(0);
    await request(app).post('/api/v1/auth/guest').send(body).expect(201);
  });

  it('grants at exactly 24h and denies stale requests after intervening grants', async () => {
    const a = await guest(), initial = (await status(a).expect(200)).body.data;
    const next = {...a.body, requestKey: randomBytes(32).toString('hex'), expectedLastGrantAt: initial.startedAt};
    const clock = vi.spyOn(authClock, 'now');
    clock.mockReturnValue(new Date(Date.parse(initial.startedAt) + day - 1));
    expect((await guestTrialStatus(new Types.ObjectId(a.user.id))).allowedActions).not.toContain('new_trial');
    await request(app).post('/api/v1/auth/guest').send(next).expect(409);
    clock.mockReturnValue(new Date(Date.parse(initial.startedAt) + day));
    expect((await guestTrialStatus(new Types.ObjectId(a.user.id))).allowedActions).toContain('new_trial');
    const b = await request(app).post('/api/v1/auth/guest').send(next).expect(201);
    expect(b.body.data.user.id).not.toBe(a.user.id);
    clock.mockReturnValue(new Date(Date.parse(initial.startedAt) + 2 * day));
    await request(app).post('/api/v1/auth/guest').send(a.body).expect(409);
    await request(app).post('/api/v1/auth/guest').send(next).expect(409);
    expect(await User.countDocuments({_id: {$in: [a.user.id, b.body.data.user.id]}})).toBe(2);
    clock.mockReturnValue(new Date(Date.parse(initial.startedAt) + day));
    expect((await guestTrialStatus(new Types.ObjectId(a.user.id))).state).toBe('expired');
  });

  it('uses the persistent device cookie for cooldown and recovers only through validated refresh', async () => {
    const a = await guest();
    const device = a.cookies.find((v: string) => v.startsWith('signvoice_guest_device='))!.split(';')[0];
    const refresh = a.cookies.find((v: string) => v.startsWith('signvoice_refresh='))!.split(';')[0];
    await request(app).post('/api/v1/auth/guest').set('Cookie', device).send(grantBody()).expect(409);
    await request(app).post('/api/v1/auth/refresh').set('Cookie', refresh).send({}).expect(403);
    const recovered = await request(app).post('/api/v1/auth/refresh').set('Origin', 'http://localhost:8080').set('Cookie', refresh).send({}).expect(200);
    expect((await status({...a, tokens: recovered.body.data}).expect(200)).body.data.dataState).toBe('trial_active');
    await request(app).post('/api/v1/auth/guest').set('Cookie', device).send(a.body).expect(409);
  });

  it('keeps the installed APK status/start parsing contract without mutation, including legacy unknown', async () => {
    const a = await guest(), now = new Date();
    vi.spyOn(authClock, 'now').mockReturnValue(now);
    for (const legacy of [false, true]) {
      if (legacy) await User.collection.updateOne({_id: new Types.ObjectId(a.user.id)}, {$unset: {guestGrantedAt: '', guestTrialId: ''}});
      const userBefore = await User.findById(a.user.id).lean(), trialsBefore = await GuestTrial.find().lean();
      const get = await status(a).expect(200);
      const post = await request(app).post('/api/v1/guest-trial/start').set(bearer(a)).send({deviceKey: randomBytes(32).toString('hex'), newGuest: true}).expect(200);
      expect(post.body.data).toEqual(get.body.data);
      const data = get.body.data;
      expect(['active', 'expired']).toContain(data.state);
      expect(typeof data.serverNow).toBe('string');
      expect(Number.isFinite(Date.parse(data.serverNow))).toBe(true);
      expect(typeof data.durationSeconds).toBe('number');
      expect(typeof data.remainingSeconds).toBe('number');
      expect(typeof data.dataVersion).toBe('number');
      if (data.expiresAt != null) expect(Number.isFinite(Date.parse(data.expiresAt))).toBe(true);
      if (!legacy) {
        expect(typeof data.expiresAt).toBe('string');
        expect(Date.parse(data.expiresAt) - Date.parse(data.startedAt)).toBe(600000);
        expect(Date.parse(data.dataRetainedUntil) - Date.parse(data.startedAt)).toBe(604800000);
        expect(Date.parse(data.nextTrialAvailableAt) - Date.parse(data.startedAt)).toBe(86400000);
      } else {
        expect(data.dataState).toBe('legacy_unknown');
        expect(data.dataRetainedUntil).toBeNull();
        expect(data.allowedActions).toEqual([...maintenance, 'convert', 'discard']);
      }
      expect(await User.findById(a.user.id).lean()).toEqual(userBefore);
      expect(await GuestTrial.find().lean()).toEqual(trialsBefore);
    }
  });

  it('uses only its own proven legacy binding and never device input to infer a grant', async () => {
    const a = await guest();
    const before = (await status(a).expect(200)).body.data;
    const owner = (await User.findById(a.user.id).select('+guestTrialId'))!;
    await GuestTrial.updateOne({_id: owner.guestTrialId}, {$unset: {lastGrantRequestHash: ''}});
    await User.collection.updateOne({_id: new Types.ObjectId(a.user.id)}, {$unset: {guestGrantedAt: ''}, $set: {createdAt: new Date(Date.parse(before.startedAt) - 1)}});
    const fallback = await request(app).get('/api/v1/guest-trial/status').query({deviceKey: randomBytes(32).toString('hex')}).set(bearer(a)).expect(200);
    expect(fallback.body.data.startedAt).toBe(before.startedAt);
    expect(fallback.body.data.dataRetainedUntil).toBe(before.dataRetainedUntil);
    expect((await User.findById(a.user.id).select('+guestGrantedAt').lean())!.guestGrantedAt).toBeUndefined();
    await User.collection.updateOne({_id: new Types.ObjectId(a.user.id)}, {$set: {createdAt: new Date(Date.parse(before.startedAt) + 1)}});
    const inherited = (await status(a).expect(200)).body.data;
    expect(inherited.dataState).toBe('legacy_unknown');
    expect(inherited.startedAt).toBeUndefined();
    expect(inherited.dataRetainedUntil).toBeNull();
  });

  it('never revives a bound legacy guest when a v1 grant commits during its status read', async () => {
    const body = grantBody(), previous = new Date(Date.now() - day);
    const trial = await GuestTrial.create({deviceHash: createHash('sha256').update(body.deviceKey).digest('hex'),
      startedAt: previous, expiresAt: new Date(+previous + 600000)});
    const legacy = await createGuestAccount({}, trial._id);
    await User.collection.updateOne({_id: new Types.ObjectId(legacy.user.id)}, {$set: {createdAt: new Date(+previous - 1)}});
    const before = (await status(legacy).expect(200)).body.data;
    expect(before.state).toBe('expired');
    expect(before.dataState).toBe('retained');
    let entered!: () => void, release!: () => void;
    const reached = new Promise<void>(resolve => {entered = resolve;});
    const gate = new Promise<void>(resolve => {release = resolve;});
    const read = GuestTrial.findById;
    const spy = vi.spyOn(GuestTrial, 'findById').mockImplementation((function(this: typeof GuestTrial, ...args: any[]) {
      const query = Reflect.apply(read, this, args), exec = query.exec;
      query.exec = async function(...params: any[]) {entered(); await gate; return Reflect.apply(exec, this, params);};
      return query;
    }) as typeof read);
    const pending = status(legacy).then(response => response);
    try {
      await reached;
      const next = await request(app).post('/api/v1/auth/guest').send({...body, expectedLastGrantAt: previous.toISOString()}).expect(201);
      release();
      const raced = await pending;
      expect(raced.status).toBe(200);
      expect(raced.body.data.state).toBe('expired');
      expect(raced.body.data.dataState).toBe('legacy_unknown');
      expect(raced.body.data.dataRetainedUntil).toBeNull();
      spy.mockRestore();
      expect((await status(next.body.data).expect(200)).body.data.state).toBe('active');
      await request(app).post('/api/v1/sign-sequence').set(bearer(legacy)).send({text: 'bạn'}).expect(403);
      expect((await User.findById(legacy.user.id).select('+guestGrantedAt'))!.guestGrantedAt).toBeUndefined();
    } finally {release(); await pending;}
  });

  it('treats shared legacy bindings as unknown in the common server-side rule', async () => {
    const startedAt = new Date(Date.now() - day);
    const trial = await GuestTrial.create({deviceHash: randomBytes(32).toString('hex'), startedAt, expiresAt: new Date(+startedAt + 600000)});
    const first = await createGuestAccount({}, trial._id), second = await createGuestAccount({}, trial._id);
    await User.collection.updateMany({_id: {$in: [first, second].map(a => new Types.ObjectId(a.user.id))}}, {$set: {createdAt: new Date(+startedAt - 1)}});
    for (const a of [first, second]) {
      const data = (await status(a).expect(200)).body.data;
      expect(data.dataState).toBe('legacy_unknown');
      expect(data.dataRetainedUntil).toBeNull();
      expect(data.allowedActions).toEqual([...maintenance, 'convert', 'discard']);
      await request(app).post('/api/v1/sign-sequence').set(bearer(a)).send({text: 'bạn'}).expect(403);
      await request(app).get('/api/v1/users/profile').set(bearer(a)).expect(403);
    }
  });

  it('preserves the v1 marker through logout and owned-data/User removal primitives', async () => {
    const a = await guest(), user = (await User.findById(a.user.id).select('+guestTrialId'))!;
    const legacy = await createGuestAccount({}, user.guestTrialId);
    const before = (await GuestTrial.findById(user.guestTrialId).select('+lastGrantRequestHash').lean())!;
    await request(app).post('/api/v1/auth/logout').set(bearer(a)).expect(200);
    expect((await GuestTrial.findById(user.guestTrialId).select('+lastGrantRequestHash').lean())!.lastGrantRequestHash).toBe(before.lastGrantRequestHash);
    // Task-3 discard and task-5 cleanup handlers do not exist yet; verify their shared deletion primitives.
    await mongoose.connection.transaction(async session => {
      const id = new Types.ObjectId(a.user.id);
      await clearOwnedData(id, session);
      await AuthSession.deleteMany({userId: id}, {session});
      await User.deleteOne({_id: id}, {session});
    });
    expect(await GuestTrial.findById(user.guestTrialId).select('+lastGrantRequestHash').lean()).toEqual(before);
    expect((await status(legacy).expect(200)).body.data.dataState).toBe('legacy_unknown');
  });

  it('samples server time after asynchronous eligibility reads at the exact trial boundary', async () => {
    const a = await guest(), now = new Date();
    let checkpoint = now;
    vi.spyOn(authClock, 'now').mockImplementation(() => checkpoint);
    await setAge(a, 599999, now);
    const read = GuestTrial.findById;
    vi.spyOn(GuestTrial, 'findById').mockImplementation((function(this: typeof GuestTrial, ...args: any[]) {
      const query = Reflect.apply(read, this, args), exec = query.exec;
      query.exec = async function(...params: any[]) {
        const value = await Reflect.apply(exec, this, params);
        checkpoint = new Date(+now + 1);
        return value;
      };
      return query;
    }) as typeof read);
    const data = (await status(a).expect(200)).body.data;
    expect(data.state).toBe('expired');
    expect(data.serverNow).toBe(new Date(+now + 1).toISOString());
  });

  it('locks at exactly 600s and 7d while auth maintenance remains valid and status never extends dates', async () => {
    const a = await guest(), now = new Date();
    vi.spyOn(authClock, 'now').mockReturnValue(now);
    for (const [age, state, dataState, actions] of [
      [599999, 'active', 'trial_active', [...maintenance, 'convert', 'discard']],
      [600000, 'expired', 'retained', [...maintenance, 'convert', 'discard']],
      [7 * day - 1, 'expired', 'retained', [...maintenance, 'convert', 'discard']],
      [7 * day, 'expired', 'expired', [...maintenance, 'discard']],
    ] as const) {
      await setAge(a, age, now);
      const data = (await status(a).expect(200)).body.data;
      expect(data.state).toBe(state);
      expect(data.dataState).toBe(dataState);
      expect(data.allowedActions).toEqual(actions);
      await request(app).get('/api/v1/auth/me').set(bearer(a)).expect(200);
      const inference = await request(app).post('/api/v1/sign-sequence').set(bearer(a)).send({text: 'bạn'});
      expect(inference.status).toBe(age < 600000 ? 200 : 403);
      if (age === 7 * day) {
        const conversion = await request(app).post('/api/v1/auth/convert-guest').set(bearer(a)).send({email: 'expired@example.test', password: 'Trial2026!', displayName: 'Expired'}).expect(403);
        expect(conversion.body.error.code).toBe('GUEST_DATA_EXPIRED');
      }
    }
    const before = (await status(a).expect(200)).body.data;
    a.tokens = (await request(app).post('/api/v1/auth/refresh').send({refreshToken: a.tokens.refreshToken}).expect(200)).body.data;
    expect((await status(a).expect(200)).body.data).toEqual(before);
    const own = await Conversation.create({userId: a.user.id, content: 'retained', direction: 'TEXT'});
    await request(app).post('/api/v1/auth/logout').set(bearer(a)).expect(200);
    expect(await User.exists({_id: a.user.id})).not.toBeNull();
    expect(await Conversation.exists({_id: own._id})).not.toBeNull();
    await request(app).post('/api/v1/auth/guest').send({...a.body, requestKey: randomBytes(32).toString('hex')}).expect(409);
  });

  it('returns 401 for a deleted User on me, status, start, refresh and private endpoints', async () => {
    const a = await guest();
    await User.deleteOne({_id: a.user.id});
    for (const path of ['/auth/me', '/guest-trial/status', '/users/profile']) await request(app).get('/api/v1' + path).set(bearer(a)).expect(401);
    await request(app).post('/api/v1/guest-trial/start').set(bearer(a)).send({}).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({refreshToken: a.tokens.refreshToken}).expect(401);
  });
});

describe('shared post-trial guest guard', () => {
  const id = 'a'.repeat(24);
  const privateRequests = [
    ['get', '/users/bootstrap'], ['get', '/users/profile'], ['patch', '/users/profile'],
    ['get', '/users/settings'], ['patch', '/users/settings'], ['get', '/users/data/export'],
    ['get', '/users/sessions'], ['delete', '/users/sessions/' + id],
    ['get', '/history'], ['delete', '/history'], ['get', '/favorites'], ['post', '/favorites'], ['delete', '/favorites/' + id],
    ['get', '/conversations'], ['get', '/conversations/' + id], ['post', '/conversations'],
    ['patch', '/conversations/' + id], ['delete', '/conversations/' + id], ['delete', '/conversations'],
    ['get', '/learning/topics'], ['get', '/learning/topics/' + id], ['get', '/learning/progress'],
    ['get', '/learning/history'], ['post', '/learning/topics/' + id + '/start'], ['get', '/learning/my-words'],
    ['get', '/sign-collections'], ['get', '/sign-notes'], ['get', '/users/notifications'],
    ['post', '/guest-trial/ai-ticket'], ['post', '/sign-sequence'], ['post', '/auth/logout-all'],
    ['post', '/auth/change-password'], ['post', '/auth/set-password'], ['post', '/auth/google/native/link'],
  ] as const;

  it('denies every private route at trial and data expiry before validation or handlers', async () => {
    const a = await guest(), now = new Date();
    vi.spyOn(authClock, 'now').mockReturnValue(now);
    for (const age of [600000, 7 * day]) {
      await setAge(a, age, now);
      for (const [method, path] of privateRequests) {
        const response = await request(app)[method]('/api/v1' + path).set(bearer(a)).send({});
        expect([method, path, response.status, response.body.error?.code]).toEqual([method, path, 403, 'GUEST_TRIAL_EXPIRED']);
      }
    }
  });

  it('blocks both DELETE bypasses in all guest states without changing any business data', async () => {
    const a = await guest(), now = new Date();
    vi.spyOn(authClock, 'now').mockReturnValue(now);
    const conversation = await Conversation.create({userId: a.user.id, content: 'do not delete', direction: 'TEXT'});
    for (const age of [0, 600000, 7 * day]) {
      await setAge(a, age, now);
      const before = await User.findById(a.user.id).lean(), settings = await UserSettings.findOne({userId: a.user.id}).lean();
      const sessions = await AuthSession.find({userId: a.user.id}).lean();
      for (const path of ['/users/account', '/users/data', '/USERS/ACCOUNT/']) {
        const result = await request(app).delete('/api/v1' + path).set(bearer(a)).send({confirm: true}).expect(403);
        expect(result.body.error.code).toBe('GUEST_USE_DISCARD');
      }
      expect(await User.findById(a.user.id).lean()).toEqual(before);
      expect(await UserSettings.findOne({userId: a.user.id}).lean()).toEqual(settings);
      expect(await AuthSession.find({userId: a.user.id}).lean()).toEqual(sessions);
      expect(await Conversation.exists({_id: conversation._id})).not.toBeNull();
      expect(await AuthSession.countDocuments({userId: a.user.id})).toBe(2);
    }
  });

  it('does not allow path prefixes, alternate methods or HEAD to escape the exact allowlist', async () => {
    const a = await guest();
    await setAge(a, 600000, new Date());
    for (const [method, path] of [['head', '/auth/me'], ['head', '/guest-trial/status'], ['get', '/guest-trial/status/extra']] as const) {
      await request(app)[method]('/api/v1' + path).set(bearer(a)).expect(403);
    }
    await request(app).get('/api/v1/auth/me').set(bearer(a)).expect(200);
    await status(a).expect(200);
    await request(app).post('/api/v1/guest-trial/start').set(bearer(a)).send({}).expect(200);
  });

  it('admits discard after 7d and legacy convert/discard only through valid authentication', async () => {
    const a = await guest();
    await setAge(a, 7 * day, new Date());
    // Exercise the shared auth guard without implementing the task-3 discard handler.
    const probe = express();
    probe.post('/api/v1/guest-data/discard', requireAuth, (_req, res) => {res.sendStatus(204);});
    await request(probe).post('/api/v1/guest-data/discard').set(bearer(a)).expect(204);
    await request(probe).post('/api/v1/guest-data/discard').expect(401);
    await User.collection.updateOne({_id: new Types.ObjectId(a.user.id)}, {$unset: {guestGrantedAt: '', guestTrialId: ''}});
    const data = (await status(a).expect(200)).body.data;
    expect(data.allowedActions).toEqual([...maintenance, 'convert', 'discard']);
    const converted = await request(app).post('/api/v1/auth/convert-guest').set(bearer(a)).send({
      email: randomBytes(8).toString('hex') + '@example.test', password: 'Legacy2026!', displayName: 'Legacy',
    }).expect(200);
    expect(converted.body.data.user.id).toBe(a.user.id);
    await request(probe).post('/api/v1/guest-data/discard').set(bearer(a)).expect(401);
  });

  it('rolls back an admitted private write when the trial ends before commit', async () => {
    const a = await guest(), now = new Date();
    let checkpoint = now;
    vi.spyOn(authClock, 'now').mockImplementation(() => checkpoint);
    await setAge(a, 599999, now);
    await expect(userTransaction(new Types.ObjectId(a.user.id), async session => {
      await Conversation.create([{userId: a.user.id, content: 'must roll back', direction: 'TEXT'}], {session});
      checkpoint = new Date(+now + 1);
    })).rejects.toMatchObject({code: 'GUEST_TRIAL_EXPIRED'});
    expect(await Conversation.countDocuments({userId: a.user.id})).toBe(0);
  });

  it('keeps public dictionary detail readable without expired guest history writes', async () => {
    const a = await guest(), now = new Date();
    vi.spyOn(authClock, 'now').mockReturnValue(now);
    const category = await Category.create({name: 'Public', slug: 'public-' + randomBytes(8).toString('hex')});
    const item = await DictionaryEntry.create({word: 'Public', definition: 'Public content', videoUrl: 'https://example.test/sign.mp4', categoryId: category._id, createdBy: a.user.id, status: 'PUBLISHED'});
    await setAge(a, 600000, now);
    await request(app).get('/api/v1/dictionary/' + item.id).set(bearer(a)).expect(200);
    expect(await SearchHistory.countDocuments({userId: a.user.id})).toBe(0);
    await setAge(a, 0, now);
    await request(app).get('/api/v1/dictionary/' + item.id).set(bearer(a)).expect(200);
    expect(await SearchHistory.countDocuments({userId: a.user.id})).toBe(1);
    const permanent = (await request(app).post('/api/v1/auth/register').send({email: randomBytes(8).toString('hex') + '@example.test', password: 'Permanent2026!', displayName: 'Permanent'}).expect(201)).body.data;
    await request(app).get('/api/v1/dictionary/' + item.id).set(bearer(permanent)).expect(200);
    expect(await SearchHistory.countDocuments({userId: permanent.user.id})).toBe(1);
  });

  it('fails closed on unknown or unreadable synthetic registry and never exempts request-time data expiry', async () => {
    const a = await guest(), id = new Types.ObjectId(a.user.id);
    await setAge(a, 7 * day, new Date());
    expect(await isSyntheticCanary(id)).toBe(false);
    const read = vi.spyOn(syntheticCanaryRegistry, 'contains');
    for (const result of [undefined, false, true]) {
      read.mockResolvedValue(result);
      expect(await isSyntheticCanary(id)).toBe(result === true);
      expect((await status(a).expect(200)).body.data.dataState).toBe('expired');
      await request(app).post('/api/v1/auth/convert-guest').set(bearer(a)).send({email: 'synthetic@example.test', password: 'Synthetic2026!', displayName: 'Synthetic'}).expect(403);
    }
    read.mockRejectedValue(new Error('private registry unavailable'));
    expect(await isSyntheticCanary(id)).toBe(false);
    await request(app).get('/api/v1/users/profile').set(bearer(a)).expect(403);
  });
});
