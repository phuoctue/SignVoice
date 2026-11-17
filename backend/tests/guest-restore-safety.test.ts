import {afterAll, afterEach, beforeAll, expect, it, vi} from 'vitest';
import mongoose, {Types} from 'mongoose';
import request from 'supertest';
import {randomBytes} from 'node:crypto';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {createApp} from '../src/app';
import {env} from '../src/config/env';
import {User} from '../src/models/User.model';
import {AuthSession} from '../src/models/AuthSession.model';
import {SessionChain} from '../src/models/SessionChain.model';
import {GuestTrial} from '../src/models/GuestTrial.model';
import {GuestLifecycleOutbox} from '../src/models/GuestLifecycle.model';
import {createGuestAccount, grantGuestAccount, refreshTokens} from '../src/services/auth.service';
import {pinGuestAuthority} from '../src/services/guest-data.service';
import {invalidateRestoredSessions} from '../scripts/guest-restore-invalidate-sessions';

let app: Awaited<ReturnType<typeof createApp>>;
const originalGrantPause = env.GUEST_GRANTS_PAUSED;
const input = () => ({deviceKey: randomBytes(32).toString('hex'), requestKey: randomBytes(32).toString('hex'), expectedLastGrantAt: null});
beforeAll(async () => {await connectDatabase(); app = await createApp();});
afterEach(() => {env.GUEST_GRANTS_PAUSED = originalGrantPause; vi.restoreAllMocks();});
afterAll(async () => {await mongoose.connection.dropDatabase(); await disconnectDatabase();});

it('revokes every restored access/refresh session, preserves fences and data, and permits fresh permanent login', async () => {
  const guest = await createGuestAccount({});
  const credentials = {email: 'restored@example.test', password: 'Restore2026!', displayName: 'Restored'};
  const permanent = (await request(app).post('/api/v1/auth/register').send(credentials).expect(201)).body.data;
  const chains = await SessionChain.find().sort({_id: 1}).lean();
  await expect(invalidateRestoredSessions(mongoose.connection.db!, false)).rejects.toThrow();
  expect(await AuthSession.countDocuments({status: 'ACTIVE'})).toBe(4);
  const before = (await mongoose.connection.db!.command({hello: 1})).localTime;
  const result = await invalidateRestoredSessions(mongoose.connection.db!, true);
  expect(result.revoked).toBe(4);
  expect(await AuthSession.countDocuments({status: 'ACTIVE'})).toBe(0);
  expect(await AuthSession.countDocuments({revokedAt: {$gte: before}})).toBe(4);
  expect(await SessionChain.find().sort({_id: 1}).lean()).toEqual(chains);
  for (const account of [guest, permanent]) {
    await request(app).get('/api/v1/auth/me').auth(account.tokens.accessToken, {type: 'bearer'}).expect(401);
    await expect(refreshTokens(account.tokens.refreshToken)).rejects.toMatchObject({statusCode: 401});
    expect(await User.exists({_id: account.user.id})).not.toBeNull();
  }
  expect((await invalidateRestoredSessions(mongoose.connection.db!, true)).revoked).toBe(0);
  const login = await request(app).post('/api/v1/auth/login').send(credentials).expect(200);
  await request(app).get('/api/v1/auth/me').auth(login.body.data.tokens.accessToken, {type: 'bearer'}).expect(200);
});

it('the restore grant gate blocks fresh identities and atomically rolls back confirmed replacement until explicitly cleared', async () => {
  const oldInput = input(), old = await grantGuestAccount({}, oldInput);
  const id = new Types.ObjectId(old.user.id), previous = new Date(Date.now() - 86401000);
  await User.collection.updateOne({_id: id}, {$set: {guestGrantedAt: previous}});
  await GuestTrial.updateOne({_id: (await User.findById(id).select('+guestTrialId'))!.guestTrialId}, {$set: {startedAt: previous}});
  const caller = (await AuthSession.findOne({userId: id, sessionType: 'ACCESS'}))!;
  const authority = await pinGuestAuthority(id, caller._id);
  const users = await User.countDocuments(), events = await GuestLifecycleOutbox.countDocuments();
  env.GUEST_GRANTS_PAUSED = true;
  await expect(grantGuestAccount({}, input())).rejects.toMatchObject({statusCode: 503, code: 'GUEST_GRANTS_PAUSED'});
  await expect(grantGuestAccount({}, {...input(), deviceKey: oldInput.deviceKey, expectedLastGrantAt: previous.toISOString()},
    {authority, expectedDataVersion: 0})).rejects.toMatchObject({statusCode: 503, code: 'GUEST_GRANTS_PAUSED'});
  expect(await User.countDocuments()).toBe(users);
  expect(await User.exists({_id: id})).not.toBeNull();
  expect(await GuestLifecycleOutbox.countDocuments()).toBe(events);
  expect(await AuthSession.countDocuments({userId: id, status: 'ACTIVE'})).toBe(2);
  env.GUEST_GRANTS_PAUSED = false;
  expect((await grantGuestAccount({}, input())).user.isGuest).toBe(true);
});
