import { randomUUID } from 'node:crypto';
import mongoose from 'mongoose';
import request from 'supertest';
import { afterAll, afterEach, beforeAll, expect, it, vi } from 'vitest';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { env } from '../src/config/env';
import { AuthSession, SessionStatus, SessionType } from '../src/models/AuthSession.model';
import { hashToken, verifyAccessToken } from '../src/utils/jwt.util';
import * as jwtUtils from '../src/utils/jwt.util';
import * as authService from '../src/services/auth.service';
import { User, UserRole } from '../src/models/User.model';
import { AuditLog } from '../src/models/AuditLog.model';
import { NotificationDevice, UserNotification } from '../src/models/Notification.model';
import { createAiTicket, authorizeAiTicket } from '../src/services/guest-trial.service';
import { deliverNotificationBatch } from '../src/services/notification.service';
import { sessionEpoch } from '../src/services/session-fence.service';
import {authClock} from '../src/services/auth-clock';

function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>(done => { resolve = done; });
  return { promise, resolve };
}

async function bounded<T>(promise: Promise<T>, label: string): Promise<T> {
  let timer!: ReturnType<typeof setTimeout>;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out: ${label}`)), 5000);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

beforeAll(async () => {
  const uri = new URL(env.MONGODB_URI);
  console.log(`G1 target: ${uri.toString()}`);
  expect(uri.protocol).toBe('mongodb:');
  expect(uri.hostname).toBe('127.0.0.1');
  expect(uri.pathname.slice(1)).toMatch(/^signvoice_test_[a-z0-9_]+$/i);
  await connectDatabase();
});

afterAll(async () => {
  vi.restoreAllMocks();
  if (mongoose.connection.readyState === 1) await mongoose.connection.dropDatabase();
  await disconnectDatabase();
});

afterEach(() => vi.restoreAllMocks());

it('G1 P3: logout-all rejects a late refresh successor after returning 200', async () => {
  const app = await createApp();
  const email = `g1-${randomUUID()}@example.com`;
  const password = 'G1RaceTest123';
  const registered = await request(app).post('/api/v1/auth/register')
    .send({ email, password, displayName: 'G1 race fixture' }).expect(201);
  const userId = registered.body.data.user.id as string;
  const original = registered.body.data.tokens as { accessToken: string; refreshToken: string };
  const originalSid = verifyAccessToken(original.accessToken).sid;
  // Logout-all uses a second login, still valid after refresh revokes the first family.
  const otherLogin = await request(app).post('/api/v1/auth/login')
    .send({ email, password }).expect(200);
  const reached = deferred();
  const release = deferred();
  const released = deferred();
  let intercepted = false;
  const realCreate = AuthSession.create;
  const spy = vi.spyOn(AuthSession, 'create').mockImplementation((async function (
    this: typeof AuthSession, ...args: unknown[]
  ) {
    const row = args[0] as { userId?: unknown; sessionType?: SessionType; sessionFamily?: string };
    if (!intercepted && String(row.userId) === userId &&
        row.sessionType === SessionType.ACCESS && row.sessionFamily !== originalSid) {
      intercepted = true;
      reached.resolve();
      await bounded(release.promise, 'P3 release');
      released.resolve();
    }
    // Preserve the receiver, arguments, Mongoose implementation and real insert.
    return Reflect.apply(realCreate, this, args);
  }) as typeof AuthSession.create);
  const refresh = request(app).post('/api/v1/auth/refresh')
    .send({ refreshToken: original.refreshToken }).timeout({ deadline: 15000 }).then(response => response);

  try {
    await bounded(Promise.race([
      reached.promise,
      refresh.then(() => { throw new Error('Refresh completed before reaching P3'); }),
    ]), 'P3 reached');
    const oldRows = await AuthSession.find({ userId, sessionFamily: originalSid });
    expect(oldRows).toHaveLength(2);
    expect(oldRows.every(row => row.status === SessionStatus.REVOKED)).toBe(true);
    expect(await AuthSession.countDocuments({ userId })).toBe(4);

    const logoutAll = await request(app).post('/api/v1/auth/logout-all')
      .set('Authorization', `Bearer ${otherLogin.body.data.tokens.accessToken}`).expect(200);
    expect(logoutAll.body.data.sessionsRevoked).toBe(2);
    expect(await AuthSession.countDocuments({ userId, status: SessionStatus.ACTIVE })).toBe(0);
    release.resolve();
    await bounded(released.promise, 'P3 released acknowledgement');
    const late = await bounded(refresh, 'late refresh response');
    spy.mockRestore();

    if (late.status === 401) return;
    expect(late.status).toBe(200);
    const successor = late.body.data as { accessToken: string; refreshToken: string };
    expect(verifyAccessToken(successor.accessToken).sid).not.toBe(originalSid);
    const accessRow = await AuthSession.findOne({ userId, tokenHash: hashToken(successor.accessToken) });
    const refreshRow = await AuthSession.findOne({ userId, tokenHash: hashToken(successor.refreshToken) });
    const accessUse = await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${successor.accessToken}`);
    const refreshUse = await request(app).post('/api/v1/auth/refresh')
      .send({ refreshToken: successor.refreshToken });
    const observed = {
      logoutAll: logoutAll.status, lateRefresh: late.status,
      accessRow: accessRow?.status ?? 'ABSENT', refreshRow: refreshRow?.status ?? 'ABSENT',
      accessUse: accessUse.status, refreshUse: refreshUse.status,
    };
    console.log('G1 P3 after LA200:', JSON.stringify(observed));
    expect({
      accessBlocked: accessRow?.status !== SessionStatus.ACTIVE || accessUse.status === 401,
      refreshBlocked: refreshRow?.status !== SessionStatus.ACTIVE || refreshUse.status === 401,
    }, `LA200 must leave late successors rejected or non-ACTIVE: ${JSON.stringify(observed)}`)
      .toEqual({ accessBlocked: true, refreshBlocked: true });
  } finally {
    release.resolve();
    await bounded(Promise.allSettled([refresh]), 'refresh cleanup');
    spy.mockRestore();
  }
}, 25000);

type App = Awaited<ReturnType<typeof createApp>>;
type Tokens = { accessToken: string; refreshToken: string };
const password = 'G1RaceTest123';

async function fixture(app: App) {
  const email = `g1-${randomUUID()}@example.com`;
  const result = await request(app).post('/api/v1/auth/register')
    .send({ email, password, displayName: 'Epoch fixture' }).expect(201);
  return { email, id: new mongoose.Types.ObjectId(result.body.data.user.id), tokens: result.body.data.tokens as Tokens };
}

async function login(app: App, email: string) {
  return (await request(app).post('/api/v1/auth/login').send({ email, password }).expect(200)).body.data.tokens as Tokens;
}

const useAccess = (app: App, token: string) => request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`);
const logoutAll = (app: App, token: string) => request(app).post('/api/v1/auth/logout-all').set('Authorization', `Bearer ${token}`);
const refreshWith = (app: App, token: string) => request(app).post('/api/v1/auth/refresh').send({ refreshToken: token });

function pauseCreate(userId: mongoose.Types.ObjectId, type: SessionType) {
  const reached = deferred(), release = deferred();
  const actual = AuthSession.create;
  let intercepted = false;
  vi.spyOn(AuthSession, 'create').mockImplementation((async function (this: typeof AuthSession, ...args: unknown[]) {
    const row = args[0] as {userId: unknown; sessionType: SessionType};
    if (!intercepted && String(row.userId) === String(userId) && row.sessionType === type) {
      intercepted = true;
      reached.resolve();
      await bounded(release.promise, 'create release');
    }
    return Reflect.apply(actual, this, args);
  }) as typeof AuthSession.create);
  return {reached, release};
}

it.each([['P3', SessionType.ACCESS], ['P4', SessionType.REFRESH]] as const)(
  '%s: late rows inherit the old epoch and both consumers reject after LA200', async (point, type) => {
    const app = await createApp(), user = await fixture(app), other = await login(app, user.email);
    const gate = pauseCreate(user.id, type);
    const generate = vi.spyOn(jwtUtils, 'generateTokenPair');
    const rotating = refreshWith(app, user.tokens.refreshToken).then(response => response);
    try {
      await bounded(gate.reached.promise, `${point} reached`);
      const successor = generate.mock.results[0].value as Tokens;
      await logoutAll(app, other.accessToken).expect(200);
      gate.release.resolve();
      expect((await bounded(rotating, 'late refresh')).status).toBe(401);
      const rows = await AuthSession.find({userId: user.id, sessionFamily: verifyAccessToken(successor.accessToken).sid});
      expect(rows).toHaveLength(2);
      expect(rows.map(row => row.userEpoch)).toEqual([0, 0]);
      expect(rows.find(row => row.sessionType === SessionType.REFRESH)!.status).toBe(SessionStatus.ACTIVE);
      await useAccess(app, successor.accessToken).expect(401);
      await refreshWith(app, successor.refreshToken).expect(401);
      console.log(`${point}: lateRefresh=401 accessUse=401 refreshUse=401 inheritedEpoch=0`);
    } finally {
      gate.release.resolve();
      await bounded(Promise.allSettled([rotating]), 'rotation cleanup');
    }
  });

it('legacy missing epochs mean zero without backfill; another user remains valid', async () => {
  const app = await createApp(), old = await fixture(app), unrelated = await fixture(app);
  await User.collection.updateOne({_id: old.id}, {$unset: {sessionRevocationEpoch: ''}});
  await AuthSession.collection.updateMany({userId: old.id}, {$unset: {userEpoch: ''}});
  await useAccess(app, old.tokens.accessToken).expect(200);
  const rotated = await refreshWith(app, old.tokens.refreshToken).expect(200);
  await AuthSession.collection.updateMany({userId: old.id}, {$unset: {userEpoch: ''}});
  expect((await User.collection.findOne({_id: old.id}))!.sessionRevocationEpoch).toBeUndefined();
  expect((await AuthSession.collection.findOne({userId: old.id}))!.userEpoch).toBeUndefined();
  // Leave rows ACTIVE to isolate the authoritative epoch fence from row cleanup.
  vi.spyOn(AuthSession, 'revokeAllForUser').mockResolvedValueOnce(0);
  await logoutAll(app, rotated.body.data.accessToken).expect(200);
  expect((await User.collection.findOne({_id: old.id}))!.sessionRevocationEpoch).toBe(1);
  await useAccess(app, rotated.body.data.accessToken).expect(401);
  await refreshWith(app, rotated.body.data.refreshToken).expect(401);
  await useAccess(app, unrelated.tokens.accessToken).expect(200);
  await refreshWith(app, unrelated.tokens.refreshToken).expect(200);
  expect((await User.collection.findOne({_id: unrelated.id}))!.sessionRevocationEpoch).toBe(0);
});

it('retry before commit increments once; retry after commit cannot increment or revoke an intervening login', async () => {
  const app = await createApp(), user = await fixture(app);
  const rawUpdate = User.collection.updateOne;
  const failure = vi.spyOn(User.collection, 'updateOne').mockImplementationOnce((async function (...args: unknown[]) {
    expect(args[1]).toMatchObject({$inc: {sessionRevocationEpoch: 1}});
    throw new Error('injected fence write unavailable');
  }) as typeof rawUpdate);
  await logoutAll(app, user.tokens.accessToken).expect(500);
  failure.mockRestore();
  expect((await User.collection.findOne({_id: user.id}))!.sessionRevocationEpoch).toBe(0);
  const write = vi.spyOn(User.collection, 'updateOne');
  await logoutAll(app, user.tokens.accessToken).expect(200);
  const fenceWrite = write.mock.calls.find(call => (call[1] as any).$inc?.sessionRevocationEpoch);
  expect(fenceWrite?.[2]).toMatchObject({writeConcern: {w: 'majority', j: true}});
  const fresh = await login(app, user.email);
  await logoutAll(app, user.tokens.accessToken).expect(401);
  const oldRow = await AuthSession.findOne({tokenHash: hashToken(user.tokens.accessToken)});
  await expect(authService.logoutAllDevices(user.id, oldRow!._id)).rejects.toMatchObject({statusCode: 401, code: 'AUTH_SESSION_INVALID'});
  expect((await User.collection.findOne({_id: user.id}))!.sessionRevocationEpoch).toBe(1);
  await useAccess(app, fresh.accessToken).expect(200);
  await logoutAll(app, fresh.accessToken).expect(200);
  expect((await User.collection.findOne({_id: user.id}))!.sessionRevocationEpoch).toBe(2);
});

it('an audit failure after commit returns 500 but keeps the fence and makes retry harmless', async () => {
  const app = await createApp(), user = await fixture(app);
  vi.spyOn(AuditLog, 'log').mockRejectedValueOnce(new Error('injected audit unavailable'));
  await logoutAll(app, user.tokens.accessToken).expect(500);
  expect((await User.collection.findOne({_id: user.id}))!.sessionRevocationEpoch).toBe(1);
  const fresh = await login(app, user.email);
  await logoutAll(app, user.tokens.accessToken).expect(401);
  await useAccess(app, fresh.accessToken).expect(200);
});

it.each(['access', 'refresh'] as const)('a %s fence read error is 500 and preserves usable credentials on recovery', async consumer => {
  const app = await createApp(), user = await fixture(app);
  const find = vi.spyOn(User.collection, 'findOne').mockRejectedValueOnce(new Error('injected primary confirmation unavailable'));
  const response = consumer === 'access'
    ? await useAccess(app, user.tokens.accessToken) : await refreshWith(app, user.tokens.refreshToken);
  expect(response.status).toBe(500);
  expect(find.mock.calls[0][1]).toMatchObject({readConcern: {level: 'linearizable'}, maxTimeMS: 5000});
  expect(String((find.mock.calls[0][1] as any).readPreference.mode)).toBe('primary');
  find.mockRestore();
  await useAccess(app, user.tokens.accessToken).expect(200);
  await refreshWith(app, user.tokens.refreshToken).expect(200);
});

it('R1 concurrent refresh has one winner; replay does not revoke the winner', async () => {
  const app = await createApp(), user = await fixture(app);
  const responses = await Promise.all([refreshWith(app, user.tokens.refreshToken), refreshWith(app, user.tokens.refreshToken)]);
  expect(responses.map(response => response.status).sort()).toEqual([200, 401]);
  const winner = responses.find(response => response.status === 200)!.body.data as Tokens;
  await refreshWith(app, user.tokens.refreshToken).expect(401);
  await useAccess(app, winner.accessToken).expect(200);
  await refreshWith(app, winner.refreshToken).expect(200);
});

it.each(['missing', 'explicit'] as const)('PS %s: a stale middleware touch cannot rewrite session provenance or status', async initial => {
  const app = await createApp(), user = await fixture(app), other = await login(app, user.email);
  const row = await AuthSession.findOne({tokenHash: hashToken(user.tokens.accessToken)});
  if (initial === 'missing') await AuthSession.collection.updateOne({_id: row!._id}, {$unset: {userEpoch: ''}});
  const reached = deferred(), release = deferred(), actual = AuthSession.collection.updateOne;
  let emitted: unknown;
  vi.spyOn(AuthSession.collection, 'updateOne').mockImplementation((async function (this: typeof AuthSession.collection, ...args: unknown[]) {
    if (String((args[0] as any)._id) === String(row!._id) && (args[1] as any).$set?.lastUsedAt) {
      emitted = args[1]; reached.resolve(); await bounded(release.promise, 'session touch release');
    }
    return Reflect.apply(actual, this, args);
  }) as typeof actual);
  const access = useAccess(app, user.tokens.accessToken).then(response => response);
  try {
    await bounded(reached.promise, 'session touch reached');
    await logoutAll(app, other.accessToken).expect(200);
    // Canary raw metadata change while the already-admitted document is stale; no production backfill.
    await Reflect.apply(actual, AuthSession.collection, [{_id: row!._id}, {$set: {userEpoch: 7}}]);
    release.resolve();
    expect((await bounded(access, 'admitted access')).status).toBe(200);
    const stored = await AuthSession.collection.findOne({_id: row!._id});
    expect(stored!.userEpoch).toBe(7);
    expect(stored!.status).toBe(SessionStatus.REVOKED);
    expect(Object.keys((emitted as any).$set).sort()).toEqual(['lastUsedAt', 'updatedAt']);
    console.log(`PS session ${initial}: emitted=${JSON.stringify(emitted)} rawEpoch=7 rawStatus=REVOKED`);
  } finally { release.resolve(); await bounded(Promise.allSettled([access]), 'touch cleanup'); }
});

it.each(['login', 'conversion', 'shared'] as const)('PS %s: stale User writes preserve the fence and old issuance snapshot', async path => {
  for (const initial of ['missing', 'explicit'] as const) {
    // Lead decision r1 supersedes only conversion: r2 must reject stale enrollment authority.
    if (path === 'conversion') {
      const app = await createApp(), guest = await activeGuestFixture();
      const id = new mongoose.Types.ObjectId(guest.user.id);
      const other = (await authService.loginOAuthUser((await User.findById(id).select('+sessionRevocationEpoch'))!)).tokens;
      const caller = (await AuthSession.findOne({tokenHash: hashToken(other.accessToken)}))!;
      if (initial === 'missing') await User.collection.updateOne({_id: id}, {$unset: {sessionRevocationEpoch: ''}});
      const gate = pauseCreate(id, SessionType.ACCESS);
      const generated = vi.spyOn(jwtUtils, 'generateTokenPair');
      const rotating = refreshWith(app, guest.tokens.refreshToken).then(response => response);
      const reached = deferred(), release = deferred(), transaction = mongoose.connection.transaction;
      vi.spyOn(mongoose.connection, 'transaction').mockImplementation((async function(this: typeof mongoose.connection, ...args: unknown[]) {
        reached.resolve(); await bounded(release.promise, 'conversion transaction release');
        return Reflect.apply(transaction, this, args);
      }) as typeof transaction);
      let conversion: Promise<unknown> | undefined;
      try {
        await bounded(gate.reached.promise, 'conversion late refresh');
        const late = generated.mock.results[0].value as Tokens;
        conversion = authService.convertGuestToPermanent(id,
          {email: `converted-${randomUUID()}@example.com`, password, displayName: 'Converted fixture'}, {}, true, caller._id)
          .then(value => ({value}), error => ({error}));
        await bounded(reached.promise, 'conversion captured old authority');
        await logoutAll(app, other.accessToken).expect(200);
        release.resolve();
        expect(await bounded(conversion, 'stale conversion abort')).toMatchObject({error: {statusCode: 401}});
        expect((await User.collection.findOne({_id: id}))!.sessionRevocationEpoch).toBe(1);
        expect((await User.collection.findOne({_id: id}))!.isGuest).toBe(true);
        gate.release.resolve();
        expect((await bounded(rotating, 'conversion late rotation')).status).toBe(401);
        for (const tokens of [guest.tokens, other, late]) {
          await useAccess(app, tokens.accessToken).expect(401);
          await refreshWith(app, tokens.refreshToken).expect(401);
        }
        expect((await User.collection.findOne({_id: id}))!.sessionRevocationEpoch).toBe(1);
      } finally {
        release.resolve(); gate.release.resolve();
        await bounded(Promise.allSettled([rotating, ...(conversion ? [conversion] : [])]), 'conversion cleanup');
        vi.restoreAllMocks();
      }
      continue;
    }
    const app = await createApp();
    const normal = path === 'conversion' ? null : await fixture(app);
    const guest = path === 'conversion' ? await activeGuestFixture() : null;
    const id = normal?.id ?? new mongoose.Types.ObjectId(guest!.user.id);
    const oldTokens = normal?.tokens ?? guest!.tokens;
    const other = normal ? await login(app, normal.email)
      : (await authService.loginOAuthUser((await User.findById(id).select('+sessionRevocationEpoch'))!)).tokens;
    if (initial === 'missing') await User.collection.updateOne({_id: id}, {$unset: {sessionRevocationEpoch: ''}});
    const gate = pauseCreate(id, SessionType.ACCESS);
    const rotating = refreshWith(app, oldTokens.refreshToken).then(response => response);
    const reached = deferred(), release = deferred(), actual = User.collection.updateOne;
    let emitted: unknown;
    const write = vi.spyOn(User.collection, 'updateOne').mockImplementation((async function (this: typeof User.collection, ...args: unknown[]) {
      const update = args[1] as any;
      if (String((args[0] as any)._id) === String(id) && (path === 'conversion' ? update.$set?.guestConvertedAt : update.$set?.lastLoginAt)) {
        emitted = update; reached.resolve(); await bounded(release.promise, 'stale user write release');
      }
      return Reflect.apply(actual, this, args);
    }) as typeof actual);
    let stale: Promise<Tokens> | undefined;
    try {
      await bounded(gate.reached.promise, 'PS refresh P3');
      stale = path === 'login' ? login(app, normal!.email)
        : path === 'conversion' ? authService.convertGuestToPermanent(id,
          {email: `converted-${randomUUID()}@example.com`, password, displayName: 'Converted fixture'}).then(result => result.tokens)
        : authService.loginOAuthUser((await User.findById(id).select('+sessionRevocationEpoch'))!).then(result => result.tokens);
      await bounded(reached.promise, 'stale user write reached');
      await logoutAll(app, other.accessToken).expect(200);
      release.resolve();
      const staleTokens = await bounded(stale, 'stale issuance');
      write.mockRestore();
      expect((await User.collection.findOne({_id: id}))!.sessionRevocationEpoch).toBe(1);
      expect(Object.keys((emitted as any).$set)).not.toContain('sessionRevocationEpoch');
      expect(Object.keys((emitted as any).$set)).not.toContain('passwordVersion');
      const staleRows = await AuthSession.find({userId: id, sessionFamily: verifyAccessToken(staleTokens.accessToken).sid});
      expect(staleRows).toHaveLength(2);
      expect(staleRows.every(row => row.userEpoch === 0)).toBe(true);
      await useAccess(app, staleTokens.accessToken).expect(401);
      await refreshWith(app, staleTokens.refreshToken).expect(401);
      gate.release.resolve();
      expect((await bounded(rotating, 'PS late rotation')).status).toBe(401);
      console.log(`PS ${path} ${initial}: emittedFields=${Object.keys((emitted as any).$set).join(',')} rawUserEpoch=1 staleRowEpoch=0`);
    } finally {
      release.resolve(); gate.release.resolve();
      await bounded(Promise.allSettled([rotating, ...(stale ? [stale] : [])]), 'PS cleanup');
      vi.restoreAllMocks();
    }
  }
});

it('epoch-only revocation fences AI ticket issuance/authorization and push eligibility', async () => {
  const app = await createApp(), user = await fixture(app);
  const access = await AuthSession.findOne({tokenHash: hashToken(user.tokens.accessToken)});
  const ticket = await createAiTicket(user.id, access!._id);
  await authorizeAiTicket(ticket);
  vi.spyOn(AuthSession, 'revokeAllForUser').mockResolvedValueOnce(0);
  await logoutAll(app, user.tokens.accessToken).expect(200);
  await expect(createAiTicket(user.id, access!._id)).rejects.toMatchObject({statusCode: 401});
  await expect(authorizeAiTicket(ticket)).rejects.toMatchObject({statusCode: 401});
  await NotificationDevice.create({userId: user.id, token: randomUUID(), platform: 'android',
    sessionFamily: access!.sessionFamily, deliveredAt: new Date(0), expiresAt: new Date(Date.now() + 60000)});
  await UserNotification.create({userId: user.id, key: randomUUID(), kind: 'TEST', title: 'Fixture', body: 'Fixture', route: '/', expiresAt: new Date(Date.now() + 60000)});
  const send = vi.fn();
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  vi.stubEnv('GOOGLE_APPLICATION_CREDENTIALS', 'unused-fixture');
  vi.stubEnv('FIREBASE_PROJECT_ID', 'unused-fixture');
  try {
    await deliverNotificationBatch(send, user.id);
    expect(send).not.toHaveBeenCalled();
    expect(warn).not.toHaveBeenCalled();
    expect(await NotificationDevice.exists({userId: user.id})).toBeTruthy();
  }
  finally { vi.unstubAllEnvs(); }
});

it('admin reset serializes its commit-time actor check against epoch-only logout-all', async () => {
  const app = await createApp(), actor = await fixture(app), target = await fixture(app);
  await User.updateOne({_id: actor.id}, {$set: {role: UserRole.ADMIN}});
  const admin = await login(app, actor.email);
  const reached = deferred(), release = deferred(), actual = User.collection.updateOne;
  let intercepted = false;
  vi.spyOn(User.collection, 'updateOne').mockImplementation((async function (this: typeof User.collection, ...args: unknown[]) {
    if (!intercepted && String((args[0] as any)._id) === String(actor.id) && (args[1] as any).$inc?.dataVersion && (args[2] as any)?.session) {
      intercepted = true; reached.resolve(); await bounded(release.promise, 'actor write release');
    }
    return Reflect.apply(actual, this, args);
  }) as typeof actual);
  const reset = request(app).post(`/api/v1/admin/users/${target.id}/password`)
    .set('Authorization', `Bearer ${admin.accessToken}`).send({newPassword: 'ChangedPassword456'}).then(response => response);
  try {
    await bounded(reached.promise, 'actor transaction reached');
    vi.spyOn(AuthSession, 'revokeAllForUser').mockResolvedValueOnce(0);
    await logoutAll(app, admin.accessToken).expect(200);
    release.resolve();
    expect((await bounded(reset, 'reset after conflict retry')).status).toBe(401);
    expect((await User.findById(target.id))!.passwordVersion).toBe(0);
  } finally { release.resolve(); await bounded(Promise.allSettled([reset]), 'reset cleanup'); }
});

it('session epochs fail closed on malformed values and session provenance is immutable', async () => {
  for (const value of [null, -1, 0.5, NaN, Infinity, '0', Number.MAX_SAFE_INTEGER + 1]) {
    expect(() => sessionEpoch(value)).toThrow('Invalid session revocation epoch');
  }
  expect(sessionEpoch(undefined)).toBe(0);
  const app = await createApp(), user = await fixture(app);
  const row = await AuthSession.findOne({userId: user.id});
  row!.userEpoch = 9; await row!.save();
  expect((await AuthSession.collection.findOne({_id: row!._id}))!.userEpoch).toBe(0);
  await User.collection.updateOne({_id: user.id}, {$set: {sessionRevocationEpoch: -1}});
  await useAccess(app, user.tokens.accessToken).expect(500);
  await refreshWith(app, user.tokens.refreshToken).expect(500);
});

it('allowlisted login tracking preserves removal of an omitted login IP', async () => {
  const app = await createApp(), user = await fixture(app);
  expect((await User.collection.findOne({_id: user.id}))!.lastLoginIp).toBeTruthy();
  await authService.loginUser({email: user.email, password});
  expect((await User.collection.findOne({_id: user.id}))!.lastLoginIp).toBeUndefined();
  const loaded = (await User.findById(user.id).select('+sessionRevocationEpoch'))!;
  loaded.lastLoginIp = '127.0.0.1'; await loaded.save();
  await authService.loginOAuthUser(loaded);
  expect((await User.collection.findOne({_id: user.id}))!.lastLoginIp).toBeUndefined();
});

it('D4: a login issued after the committed fence survives the delayed logout-all sweep', async () => {
  const app = await createApp(), user = await fixture(app);
  const reached = deferred(), release = deferred(), actual = AuthSession.revokeAllForUser;
  const sweep = vi.spyOn(AuthSession, 'revokeAllForUser').mockImplementationOnce(async function (...args) {
    reached.resolve();
    await bounded(release.promise, 'logout-all sweep release');
    return Reflect.apply(actual, AuthSession, args);
  });
  const pending = logoutAll(app, user.tokens.accessToken).then(response => response);
  try {
    await bounded(reached.promise, 'logout-all committed fence');
    expect((await User.collection.findOne({_id: user.id}))!.sessionRevocationEpoch).toBe(1);
    const fresh = await login(app, user.email);
    const freshSid = verifyAccessToken(fresh.accessToken).sid;
    const issued = await AuthSession.find({userId: user.id, sessionFamily: freshSid});
    expect(issued).toHaveLength(2);
    expect(issued.every(row => row.userEpoch === 1 && row.status === SessionStatus.ACTIVE)).toBe(true);
    release.resolve();
    const response = await bounded(pending, 'logout-all delayed sweep response');
    expect(response.status).toBe(200);
    expect(response.body.data.sessionsRevoked).toBe(2);
    sweep.mockRestore();
    const remaining = await AuthSession.find({userId: user.id, sessionFamily: freshSid});
    expect(remaining.every(row => row.status === SessionStatus.ACTIVE)).toBe(true);
    await useAccess(app, fresh.accessToken).expect(200);
    await refreshWith(app, fresh.refreshToken).expect(200);
    await useAccess(app, user.tokens.accessToken).expect(401);
    await refreshWith(app, user.tokens.refreshToken).expect(401);
    console.log('D4 delayed sweep: epoch=1 freshRows=ACTIVE freshAccess=200 freshRefresh=200 sessionsRevoked=2');
  } finally {
    release.resolve();
    await bounded(Promise.allSettled([pending]), 'sweep cleanup');
    sweep.mockRestore();
  }
});

it.each(['missing', 'explicit'] as const)('refresh claim rejects a changed %s immutable epoch stamp', async initial => {
  const app = await createApp(), user = await fixture(app);
  const row = await AuthSession.findOne({tokenHash: hashToken(user.tokens.refreshToken)});
  if (initial === 'missing') await AuthSession.collection.updateOne({_id: row!._id}, {$unset: {userEpoch: ''}});
  const reached = deferred(), release = deferred(), actual = AuthSession.collection.findOneAndUpdate;
  vi.spyOn(AuthSession.collection, 'findOneAndUpdate').mockImplementationOnce((async function (this: typeof AuthSession.collection, ...args: unknown[]) {
    reached.resolve();
    await bounded(release.promise, 'refresh claim release');
    return Reflect.apply(actual, this, args);
  }) as typeof actual);
  const pending = refreshWith(app, user.tokens.refreshToken).then(response => response);
  try {
    await bounded(reached.promise, 'refresh claim after early fence');
    // Simulate inconsistent raw metadata changing after the authenticated row was loaded.
    await AuthSession.collection.updateOne({_id: row!._id}, {$set: {userEpoch: 7}});
    release.resolve();
    expect((await bounded(pending, 'changed stamp response')).status).toBe(401);
    expect(await AuthSession.countDocuments({userId: user.id})).toBe(2);
  } finally {
    release.resolve();
    await bounded(Promise.allSettled([pending]), 'claim cleanup');
  }
});

async function activeGuestFixture() {
  const guest = await authService.createGuestAccount();
  await User.collection.updateOne({_id: new mongoose.Types.ObjectId(guest.user.id)}, {$set: {guestGrantedAt: authClock.now()}});
  return guest;
}
