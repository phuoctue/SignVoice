import {beforeAll, afterAll, describe, it, expect} from 'vitest';
import request from 'supertest';
import {randomBytes} from 'node:crypto';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {User, AuthSession, UserSettings, DictionaryEntry, Category, Conversation} from '../src/models';
import {GuestTrial} from '../src/models/GuestTrial.model';
import {authorizeAiTicket} from '../src/services/guest-trial.service';

let app: Awaited<ReturnType<typeof createApp>>;
beforeAll(async () => {
  await connectDatabase();
  await Promise.all([User, AuthSession, UserSettings, DictionaryEntry, Category, GuestTrial, Conversation].map(model => model.init()));
  app = await createApp();
});
afterAll(disconnectDatabase);
async function guest(deviceKey = randomBytes(32).toString('hex'), cookie?: string) {
  let req = request(app).post('/api/v1/auth/guest').send({deviceKey});
  if (cookie) req = req.set('Cookie', cookie);
  const response = await req.expect(201);
  const data = response.body.data;
  return {...data, deviceKey, cookie: (response.headers['set-cookie'] as unknown as string[])
    .find(value => value.startsWith('signvoice_guest_device='))!.split(';')[0]};
}
const auth = (a: any) => ({Authorization: 'Bearer ' + a.tokens.accessToken});
const status = (a: any) => request(app).get('/api/v1/guest-trial/status').set(auth(a));
const start = (a: any) => request(app).post('/api/v1/guest-trial/start').set(auth(a)).send({});
async function expire(a: any) {
  const user = await User.findById(a.user.id).select('+guestTrialId');
  await GuestTrial.updateOne({_id: user!.guestTrialId}, {$set: {expiresAt: new Date(Date.now() - 1000)}});
}
describe('Guest ten-minute allowance', () => {
  it('keeps the public catalog readable and requires authentication for trial/inference', async () => {
    await request(app).get('/api/v1/dictionary?limit=1').expect(200);
    await request(app).get('/api/v1/categories').expect(200);
    await request(app).get('/api/v1/guest-trial/status').expect(401);
    await request(app).post('/api/v1/guest-trial/start').expect(401);
    await request(app).post('/api/v1/sign-sequence').send({text: 'xin chào'}).expect(401);
  });
  it('starts once on the server and never extends on repeated/concurrent starts or refresh', async () => {
    const a = await guest();
    await User.updateOne({_id: a.user.id}, {$set: {createdAt: new Date('2020-01-01')}});
    const initial = (await status(a).expect(200)).body.data;
    expect(initial.state).toBe('active');
    expect(initial.remainingSeconds).toBeGreaterThan(590);
    expect(initial.remainingSeconds).toBeLessThanOrEqual(600);
    const responses = await Promise.all([start(a).expect(200), start(a).expect(200), start(a).expect(200)]);
    const value = responses[0].body.data;
    expect(new Set(responses.map(r => r.body.data.expiresAt)).size).toBe(1);
    expect(Date.parse(value.expiresAt) - Date.parse(value.startedAt)).toBe(600000);
    await request(app).post('/api/v1/guest-trial/start').set(auth(a))
      .send({expiresAt: '2100-01-01', durationSeconds: 999999}).expect(400);
    const refreshed = await request(app).post('/api/v1/auth/refresh').send({refreshToken: a.tokens.refreshToken}).expect(200);
    a.tokens = refreshed.body.data;
    expect((await start(a).expect(200)).body.data.expiresAt).toBe(value.expiresAt);
    await request(app).post('/api/v1/sign-sequence').set(auth(a)).send({text: 'bạn'}).expect(200);
  });
  it('permits learning during the allowance and retains only public topic previews after expiry', async () => {
    const a = await guest();
    const category = await Category.create({name: 'Guest learning', slug: 'guest-' + randomBytes(8).toString('hex')});
    const item = await DictionaryEntry.create({word: 'Học thử', definition: 'Từ công khai', videoUrl: 'https://example.org/sign.mp4', categoryId: category._id, createdBy: a.user.id, status: 'PUBLISHED'});
    await request(app).post('/api/v1/learning/topics/' + category.id + '/start').set(auth(a)).send({}).expect(200);
    await request(app).get('/api/v1/learning/progress').set(auth(a)).expect(200);
    await request(app).get('/api/v1/sign-collections').set(auth(a)).expect(403);
    await expire(a);
    await request(app).get('/api/v1/learning/topics/' + category.id).set(auth(a)).expect(200);
    await request(app).get('/api/v1/learning/topics/' + category.id + '?stage=LEARNING').set(auth(a)).expect(403);
    await request(app).post('/api/v1/learning/topics/' + category.id + '/start').set(auth(a)).send({}).expect(403);
    await request(app).get('/api/v1/learning/history').set(auth(a)).expect(403);
    await request(app).get('/api/v1/dictionary/' + item.id).expect(200);
    await request(app).delete('/api/v1/conversations').set(auth(a)).expect(403);
  });
  it('expires inference while leaving the guest session and public browsing available', async () => {
    const a = await guest(); await start(a); await expire(a);
    expect((await status(a)).body.data.state).toBe('expired');
    expect((await start(a)).body.data.state).toBe('expired');
    const response = await request(app).post('/api/v1/sign-sequence').set(auth(a)).send({text: 'bạn'}).expect(403);
    expect(response.body.error.code).toBe('GUEST_TRIAL_EXPIRED');
    await request(app).post('/api/v1/guest-trial/ai-ticket').set(auth(a)).expect(403);
    await request(app).get('/api/v1/auth/me').set(auth(a)).expect(200);
    await request(app).get('/api/v1/learning/progress').set(auth(a)).expect(403);
    await request(app).get('/api/v1/learning/topics').set(auth(a)).expect(200);
    await request(app).get('/api/v1/sign-collections').set(auth(a)).expect(403);
    await request(app).get('/api/v1/learning/my-words').set(auth(a)).expect(403);
    await request(app).get('/api/v1/dictionary?limit=1').expect(200);
  });
  it('grants a fresh allowance for an explicit new guest while preserving the old expiry', async () => {
    const old = await guest(); await expire(old);
    const fresh = await request(app).post('/api/v1/auth/guest')
      .set('Cookie', old.cookie).send({deviceKey: old.deviceKey, newGuest: true}).expect(201);
    const next = fresh.body.data;
    expect(next.user.id).not.toBe(old.user.id);
    expect((await status(next)).body.data.remainingSeconds).toBeGreaterThan(590);
    expect((await status(old)).body.data.state).toBe('expired');
  });
  it('deletes the guest and owned data on logout and permits a fresh allowance', async () => {
    const a = await guest(); await start(a); await expire(a);
    await Conversation.create({userId: a.user.id, content: 'Temporary guest data', direction: 'TEXT'});
    await request(app).post('/api/v1/auth/logout').set(auth(a)).expect(200);
    expect(await User.findById(a.user.id)).toBeNull();
    expect(await UserSettings.countDocuments({userId: a.user.id})).toBe(0);
    expect(await AuthSession.countDocuments({userId: a.user.id})).toBe(0);
    expect(await Conversation.countDocuments({userId: a.user.id})).toBe(0);
    await request(app).get('/api/v1/auth/me').set(auth(a)).expect(401);
    const native = await guest(a.deviceKey);
    expect((await status(native)).body.data.state).toBe('active');
    const browser = await guest(randomBytes(32).toString('hex'), a.cookie);
    expect((await status(browser)).body.data.state).toBe('active');
  });
  it('binds pre-existing guest accounts to the persistent device allowance', async () => {
    const spent = await guest(); await start(spent); await expire(spent);
    const old = await guest();
    await User.updateOne({_id: old.user.id}, {$unset: {guestTrialId: ''}});
    const response = await request(app).get('/api/v1/guest-trial/status').query({deviceKey: spent.deviceKey}).set(auth(old)).expect(200);
    expect(response.body.data.state).toBe('expired');
  });
  it('requires a personal account for saving, then unlocks after conversion without losing old data', async () => {
    const a = await guest(); await start(a); await expire(a);
    await request(app).post('/api/v1/conversations').set(auth(a)).send({content: 'Cannot save as guest'}).expect(403);
    await request(app).post('/api/v1/favorites').set(auth(a)).send({entryId: 'a'.repeat(24)}).expect(403);
    await Conversation.create({userId: a.user.id, content: 'Previously saved guest content', direction: 'TEXT'});
    const converted = await request(app).post('/api/v1/auth/convert-guest').set(auth(a)).send({
      email: randomBytes(8).toString('hex') + '@example.test', password: 'GuestTrial2026!', displayName: 'Converted Guest',
    }).expect(200);
    const permanent = converted.body.data;
    expect(permanent.user.id).toBe(a.user.id);
    expect((await status(permanent)).body.data.state).toBe('unlimited');
    await request(app).post('/api/v1/sign-sequence').set(auth(permanent)).send({text: 'bạn'}).expect(200);
    await request(app).post('/api/v1/conversations').set(auth(permanent)).send({content: 'Now saved'}).expect(201);
    const history = await request(app).get('/api/v1/conversations').set(auth(permanent)).expect(200);
    expect(history.body.data.items.some((row: any) => row.content === 'Previously saved guest content')).toBe(true);
  });
  it('issues scoped stream tickets and rejects expired trials, ordinary access tokens and revoked sessions', async () => {
    const a = await guest(); await start(a);
    const issued = await request(app).post('/api/v1/guest-trial/ai-ticket').set(auth(a)).expect(200);
    const lease = await authorizeAiTicket(issued.body.data.ticket);
    expect(lease.expiresAt).toBeInstanceOf(Date);
    await expect(authorizeAiTicket(a.tokens.accessToken)).rejects.toThrow();
    await expire(a);
    await expect(authorizeAiTicket(issued.body.data.ticket)).rejects.toMatchObject({code: 'GUEST_TRIAL_EXPIRED'});
    await request(app).post('/api/v1/auth/logout').set(auth(a)).expect(200);
    await expect(authorizeAiTicket(issued.body.data.ticket)).rejects.toMatchObject({code: 'AUTH_SESSION_INVALID'});
  });
});
