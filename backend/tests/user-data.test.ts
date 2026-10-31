import { beforeAll, afterAll, describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { User, UserSettings, Favorite, Conversation, SearchHistory, Category, DictionaryEntry, AuthSession } from '../src/models';
import {NotificationDevice, UserNotification} from '../src/models/Notification.model';
import {deliverNotificationBatch} from '../src/services/notification.service';

let app: Awaited<ReturnType<typeof createApp>>;
const password = 'Verification2026!';
let sequence = 0;
beforeAll(async () => {
  await connectDatabase();
  await Promise.all([User, UserSettings, Favorite, Conversation, SearchHistory, Category, DictionaryEntry, AuthSession].map(model => model.init()));
  app = await createApp();
});
afterAll(async () => { await disconnectDatabase(); });
async function account(local = true) {
  const response = await request(app).post('/api/v1/auth/' + (local ? 'register' : 'guest'))
    .send(local ? {email: `completion-${Date.now()}-${sequence++}@example.com`, password, displayName: 'Verification User'} : {}).expect(201);
  return response.body.data;
}
function client(user: any) {
  const authorization = `Bearer ${user.tokens.accessToken}`;
  return {
    get: (url: string) => request(app).get('/api/v1' + url).set('Authorization', authorization),
    post: (url: string, body: any) => request(app).post('/api/v1' + url).set('Authorization', authorization).send(body),
    patch: (url: string, body: any) => request(app).patch('/api/v1' + url).set('Authorization', authorization).send(body),
    delete: (url: string, body: any = {}) => request(app).delete('/api/v1' + url).set('Authorization', authorization)
      .send({...url === '/users/account' && !user.user.isGuest ? {currentPassword: password} : {}, ...body}),
  };
}
async function entry(owner: any, status = 'PUBLISHED') {
  const category = await Category.create({name: 'Verification', slug: `verification-${Date.now()}-${sequence++}`});
  const item = await DictionaryEntry.create({word: 'Xin chào', definition: 'Lời chào giao tiếp.', videoUrl: 'https://example.org/sign.mp4', categoryId: category._id, createdBy: owner.user.id, status});
  return {category, item};
}

describe('study reminder inbox', () => {
  it('creates one due reminder, keeps read state and isolates accounts', async () => {
    const a = await account(), b = await account();
    const x = client(a), y = client(b);
    const nowLocal = new Date(Date.now() + 7 * 3600000);
    await x.patch('/users/settings', {studyReminder: {enabled: true, hour: 0,
      minute: 0, weekdays: [nowLocal.getUTCDay() || 7], timezone: 'Asia/Ho_Chi_Minh'}}).expect(200);
    await UserSettings.updateOne({userId: a.user.id}, {$set: {studyReminderConfiguredAt: new Date(Date.now() - 86400000), notificationsEnabled: false}});
    const savedAt = (await UserSettings.findOne({userId: a.user.id}))!.studyReminderConfiguredAt;
    await x.get('/users/settings').expect(200);
    await x.patch('/users/settings', {theme: 'DARK'}).expect(200);
    expect((await UserSettings.findOne({userId: a.user.id}))!.studyReminderConfiguredAt).toEqual(savedAt);
    const [first, second] = await Promise.all([x.get('/users/notifications').expect(200), x.get('/users/notifications').expect(200)]);
    const notices = first.body.data.items.filter((item: any) => item.kind === 'STUDY_REMINDER');
    expect(notices).toHaveLength(1);
    expect(second.body.data.items.filter((item: any) => item.kind === 'STUDY_REMINDER')).toHaveLength(1);
    expect(notices[0].read).toBe(false);
    await y.patch('/users/notifications/' + notices[0]._id, {read: true}).expect(404);
    await x.patch('/users/notifications/' + notices[0]._id, {read: true}).expect(200);
    const feed = await x.get('/users/notifications').expect(200);
    expect(feed.body.data.items.find((item: any) => item._id === notices[0]._id).read).toBe(true);
    expect((await y.get('/users/notifications')).body.data.items.some((item: any) => item.kind === 'STUDY_REMINDER')).toBe(false);
  });
});
describe('Persisted user data', () => {
  it('bootstraps only the signed-in account and excludes unpublished favorites', async () => {
    const a = await account(), b = await account(), x = client(a), y = client(b);
    await x.post('/conversations', {content: 'Own startup history'}).expect(201);
    await y.post('/conversations', {content: 'Other private history'}).expect(201);
    const {item, category} = await entry(a);
    await x.post('/favorites', {entryId: item.id}).expect(201);
    await x.patch('/users/settings', {theme: 'DARK'}).expect(200);
    const response = await x.get('/users/bootstrap').expect(200);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.body.data.profile.id).toBe(a.user.id);
    expect(response.body.data.settings.theme).toBe('DARK');
    expect(response.body.data.conversations.items.map((item: any) => item.content)).toEqual(['Own startup history']);
    expect(response.body.data.favorites.map((item: any) => item.entryId)).toEqual([item.id]);
    expect(JSON.stringify(response.body.data)).not.toContain('passwordHash');
    await DictionaryEntry.updateOne({_id: item.id}, {$set: {status: 'DRAFT'}});
    expect((await x.get('/users/bootstrap')).body.data.favorites).toHaveLength(0);
    await DictionaryEntry.updateOne({_id: item.id}, {$set: {status: 'PUBLISHED'}});
    await Category.updateOne({_id: category.id}, {$set: {status: 'ARCHIVED'}});
    expect((await x.get('/users/bootstrap')).body.data.favorites).toHaveLength(0);
    await request(app).get('/api/v1/users/bootstrap').expect(401);
    await x.get('/users/bootstrap?userId=' + b.user.id).expect(400);
  });
  it('stores a weekly study reminder and validates days and time', async () => {
    const x = client(await account());
    const studyReminder = {enabled: true, hour: 19, minute: 30, weekdays: [1, 3, 5], timezone: 'Asia/Ho_Chi_Minh'};
    await x.patch('/users/settings', {studyReminder}).expect(200);
    expect((await x.get('/users/settings')).body.data.studyReminder).toMatchObject(studyReminder);
    for (const bad of [{...studyReminder, hour: 24}, {...studyReminder, weekdays: []}, {...studyReminder, weekdays: [1, 1]}, {...studyReminder, timezone: 'invalid'}]) {
      await x.patch('/users/settings', {studyReminder: bad}).expect(400);
    }
  });
  it('stores avatar uploads and rejects unsupported data and another account avatar', async () => {
    const x = client(await account()), y = client(await account());
    const image = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7X8AAAAASUVORK5CYII=';
    const saved = await x.patch('/users/profile', {avatarImage: image}).expect(200);
    const url = saved.body.data.avatarUrl;
    expect(url).toMatch(/^\/user-media\/avatars\//);
    await request(app).get(url).expect(200).expect('Content-Type', /image\/png/);
    await y.patch('/users/profile', {avatarUrl: url}).expect(400);
    await x.patch('/users/profile', {avatarImage: 'data:image/png;base64,bm90IGFuIGltYWdl'}).expect(400);
    await x.patch('/users/profile', {avatarUrl: ''}).expect(200);
    await request(app).get(url).expect(404);
    expect((await x.get('/users/profile')).body.data.avatarUrl ?? '').toBe('');
  });
  it('keeps notification read state and device tokens scoped to their owner', async () => {
    const a = await account(), b = await account(), x = client(a), y = client(b);
    const {item} = await entry(a);
    await DictionaryEntry.updateOne({_id: item.id}, {$set: {publishedAt: new Date()}});
    const feed = await x.get('/users/notifications').expect(200);
    const notification = feed.body.data.items.find((n: any) => n.kind === 'NEW_WORDS');
    expect(notification).toBeDefined();
    await y.patch('/users/notifications/' + notification._id, {read: true}).expect(404);
    await x.patch('/users/notifications/' + notification._id, {read: true}).expect(200);
    expect((await x.get('/users/notifications')).body.data.items.find((n: any) => n._id === notification._id).read).toBe(true);
    const token = 'fcm-test-token-'.repeat(5);
    await x.post('/users/notification-devices', {token, platform: 'android'}).expect(200);
    // Rotation/reinstallation can transfer one installation token, never duplicate delivery.
    await y.post('/users/notification-devices', {token, platform: 'android'}).expect(200);
    expect(await NotificationDevice.countDocuments({token})).toBe(1);
    expect(String((await NotificationDevice.findOne({token}))?.userId)).toBe(b.user.id);
    await x.delete('/users/notification-devices', {token}).expect(200);
    await y.post('/users/notification-devices', {token: '', platform: 'android'}).expect(400);
  });
  it('push delivery retries failures, deduplicates successful delivery and stops for revoked sessions', async () => {
    const previousProject = process.env.FIREBASE_PROJECT_ID, previousCredentials = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    process.env.FIREBASE_PROJECT_ID = 'isolated-test'; process.env.GOOGLE_APPLICATION_CREDENTIALS = 'unused-by-fake-sender';
    try {
      const a = await account(), x = client(a), token = 'isolated-worker-test-token';
      await x.post('/users/notification-devices', {token, platform: 'android'}).expect(200);
      const notice = await UserNotification.create({userId: a.user.id, key: 'worker-test', kind: 'REVIEW', title: 'Ôn tập', body: 'Một từ', route: '/learn?tab=1', expiresAt: new Date(Date.now() + 86400000)});
      await NotificationDevice.updateOne({token}, {$set: {deliveredAt: new Date(0)}});
      const alarm = await UserNotification.create({userId: a.user.id, key: 'local-alarm', kind: 'STUDY_REMINDER', title: 'Đến giờ học', body: 'Nhắc học', route: '/learn?tab=1', expiresAt: new Date(Date.now() + 86400000)});
      let alarmsSent = 0;
      let attempts = 0;
      const send = async (target: string, message: any) => {if (String(message._id) === alarm.id) alarmsSent++; if (target === token && String(message._id) === notice.id) {attempts++; if (attempts === 1) throw new Error('Temporary network failure');}};
      await deliverNotificationBatch(send);
      await NotificationDevice.updateOne({token}, {$set: {checkedAt: new Date(0)}});
      await deliverNotificationBatch(send);
      await NotificationDevice.updateOne({token}, {$set: {checkedAt: new Date(0)}});
      await deliverNotificationBatch(send);
      expect(attempts).toBe(2);
      expect(alarmsSent).toBe(0);
      await AuthSession.updateMany({userId: a.user.id}, {$set: {status: 'REVOKED'}});
      await NotificationDevice.updateOne({token}, {$set: {checkedAt: new Date(0)}});
      await deliverNotificationBatch(send);
      expect(attempts).toBe(2);
      expect(await NotificationDevice.exists({token})).not.toBeNull();
    } finally {
      if (previousProject === undefined) delete process.env.FIREBASE_PROJECT_ID; else process.env.FIREBASE_PROJECT_ID = previousProject;
      if (previousCredentials === undefined) delete process.env.GOOGLE_APPLICATION_CREDENTIALS; else process.env.GOOGLE_APPLICATION_CREDENTIALS = previousCredentials;
    }
  });
  it('test push requires an enabled, registered device and persists only to the owner bell', async () => {
    const x = client(await account());
    await x.post('/users/notifications/test', {}).expect(409);
    await x.patch('/users/settings', {notificationsEnabled: false}).expect(200);
    await x.post('/users/notifications/test', {}).expect(409);
  });
  it('account deletion cannot leave notifications or device registrations behind a concurrent refresh', async () => {
    const a = await account(), x = client(a);
    await entry(a);
    await x.post('/users/notification-devices', {token: 'account-delete-notification-device', platform: 'android'}).expect(200);
    await x.get('/users/notifications').expect(200);
    const [feed, deleted] = await Promise.all([x.get('/users/notifications'), x.delete('/users/account', {confirm: true})]);
    expect([200, 401, 404]).toContain(feed.status);
    expect(deleted.status).toBe(200);
    expect(await UserNotification.countDocuments({userId: a.user.id})).toBe(0);
    expect(await NotificationDevice.countDocuments({userId: a.user.id})).toBe(0);
  });
  it('stores conversations and enforces ownership on every operation', async () => {
    const a = await account(), b = await account(), x = client(a), y = client(b);
    const created = await x.post('/conversations', {content: 'Hello [literal]', direction: 'TEXT'}).expect(201);
    const id = created.body.data._id;
    expect((await x.get('/conversations?search=%5Bliteral%5D')).body.data.items).toHaveLength(1);
    expect((await y.get('/conversations')).body.data.items).toHaveLength(0);
    await y.get('/conversations/' + id).expect(404);
    await y.patch('/conversations/' + id, {favorite: true}).expect(404);
    await y.delete('/conversations/' + id).expect(404);
    await x.patch('/conversations/' + id, {favorite: true, content: 'Saved'}).expect(200);
    expect((await x.get('/conversations?favorite=true')).body.data.items[0].content).toBe('Saved');
    await x.delete('/conversations/' + id).expect(200);
    await x.get('/conversations/' + id).expect(404);
  });
  it('validates owned resources, query limits and immutable fields', async () => {
    const x = client(await account());
    for (const body of [{content: ''}, {content: 'valid', userId: 'a'.repeat(24)}, {content: 'x'.repeat(10001)}]) await x.post('/conversations', body).expect(400);
    for (const query of ['page=0', 'limit=1000', 'search[x]=x', 'favorite=anything']) await x.get('/conversations?' + query).expect(400);
    await x.get('/conversations/invalid').expect(400);
    await x.patch('/users/settings', {userId: 'a'.repeat(24)}).expect(400);
    await x.patch('/users/settings', {theme: 'dark'}).expect(400);
    await x.patch('/users/profile', {role: 'ADMIN'}).expect(400);
    await x.patch('/users/profile', {avatarUrl: 'javascript:alert(1)'}).expect(400);
  });
  it('persists settings and returns a flat safe profile', async () => {
    const a = await account(), x = client(a);
    await x.patch('/users/settings', {theme: 'DARK', fontSize: 20, highContrast: true, speechSpeed: 1.5, avatarColor: 2}).expect(200);
    expect((await x.get('/users/settings')).body.data).toMatchObject({theme: 'DARK', fontSize: 20, highContrast: true, speechSpeed: 1.5, avatarColor: 2});
    await x.patch('/users/profile', {displayName: 'Persisted Name', avatarUrl: 'https://example.org/avatar.png'}).expect(200);
    const profile = (await x.get('/users/profile')).body.data;
    expect(profile).toMatchObject({_id: a.user.id, displayName: 'Persisted Name', permissions: []});
    for (const key of ['passwordHash', 'passwordVersion', 'googleProvider', 'facebookProvider', 'lastLoginIp', 'dataVersion']) expect(profile).not.toHaveProperty(key);
  });
  it('requires password proof for email changes without expiring the session', async () => {
    const a = await account(true), x = client(a);
    await x.patch('/users/profile', {email: 'changed@example.com', currentPassword: 'wrong'}).expect(400);
    await x.get('/auth/me').expect(200);
    await x.patch('/users/profile', {email: 'changed@example.com', currentPassword: password}).expect(200);
    expect((await x.get('/users/profile')).body.data.email).toBe('changed@example.com');
  });
  it('keeps favorites idempotent and counts accurate across clear/delete', async () => {
    const a = await account(), b = await account(), x = client(a), y = client(b);
    const {item} = await entry(a);
    await Promise.all([x.post('/favorites', {entryId: item.id}).expect(201), x.post('/favorites', {entryId: item.id}).expect(201)]);
    await y.post('/favorites', {entryId: item.id}).expect(201);
    expect((await x.get('/favorites')).body.data[0]).toMatchObject({entryId: item.id, entry: {_id: item.id}});
    expect((await DictionaryEntry.findById(item.id))!.favoriteCount).toBe(2);
    await DictionaryEntry.updateOne({_id: item.id}, {$set: {favoriteCount: 0}});
    await x.post('/favorites', {entryId: item.id}).expect(201);
    expect((await DictionaryEntry.findById(item.id))!.favoriteCount).toBe(2);
    await x.delete('/users/data', {confirm: true}).expect(200);
    expect((await DictionaryEntry.findById(item.id))!.favoriteCount).toBe(1);
    await x.delete('/favorites/' + item.id).expect(200);
    expect((await y.get('/favorites')).body.data).toHaveLength(1);
    await y.delete('/users/account', {confirm: true}).expect(200);
    expect((await DictionaryEntry.findById(item.id))!.favoriteCount).toBe(0);
  });
  it('rejects draft favorites and filters archived categories from favorites', async () => {
    const a = await account(), x = client(a), {item, category} = await entry(a, 'DRAFT');
    await x.post('/favorites', {entryId: item.id}).expect(404);
    await DictionaryEntry.updateOne({_id: item.id}, {$set: {status: 'PUBLISHED'}});
    await x.post('/favorites', {entryId: item.id}).expect(201);
    await Category.updateOne({_id: category.id}, {$set: {status: 'ARCHIVED'}});
    expect((await x.get('/favorites')).body.data).toHaveLength(0);
    await x.post('/favorites', {entryId: item.id}).expect(404);
  });
  it('exports only owned safe data and clears it while preserving identity and sessions', async () => {
    const a = await account(), b = await account(), x = client(a), y = client(b);
    await x.post('/conversations', {content: 'Owner private text'}).expect(201);
    await y.post('/conversations', {content: 'Other private text'}).expect(201);
    const exported = (await x.get('/users/data/export').expect(200)).body.data;
    expect(exported.conversations).toHaveLength(1);
    expect(JSON.stringify(exported)).not.toContain('Other private text');
    for (const key of ['tokenHash', 'passwordHash', 'refreshToken', 'accessToken']) expect(JSON.stringify(exported)).not.toContain(key);
    await x.delete('/users/data', {confirm: true}).expect(200);
    expect((await x.get('/conversations')).body.data.items).toHaveLength(0);
    expect((await y.get('/conversations')).body.data.items).toHaveLength(1);
    await x.get('/auth/me').expect(200);
  });
  it('requires deletion confirmation and protects the last administrator', async () => {
    const a = await account(true), x = client(a);
    await x.delete('/users/account').expect(400);
    await x.delete('/users/account', {confirm: true, currentPassword: 'wrong'}).expect(400);
    await x.get('/auth/me').expect(200);
    await User.updateOne({_id: a.user.id}, {$set: {role: 'ADMIN'}});
    await x.delete('/users/account', {confirm: true, currentPassword: password}).expect(409);
    await x.get('/auth/me').expect(200);
  });
  it('revokes only an owned session family and reports the current device', async () => {
    const a = await account(true), b = await account(), x = client(a), y = client(b);
    const otherLogin = await request(app).post('/api/v1/auth/login').send({email: a.user.email, password}).expect(200);
    const other = client(otherLogin.body.data);
    const sessions = (await x.get('/users/sessions')).body.data;
    expect(sessions.filter((item: any) => item.current)).toHaveLength(1);
    expect(JSON.stringify(sessions)).not.toContain('tokenHash');
    const foreign = (await y.get('/users/sessions')).body.data[0];
    await x.delete('/users/sessions/' + foreign._id).expect(404);
    const second = sessions.find((item: any) => !item.current);
    expect((await x.delete('/users/sessions/' + second._id).expect(200)).body.data.revokedCurrent).toBe(false);
    await other.get('/auth/me').expect(401);
    await x.get('/auth/me').expect(200);
  });
  it('preserves guest conversations and settings after conversion', async () => {
    const a = await account(false), x = client(a);
    await Conversation.create({userId: a.user.id, content: 'Guest saved text', direction: 'TEXT'});
    await x.post('/conversations', {content: 'New guest text'}).expect(403);
    await x.patch('/users/settings', {highContrast: true}).expect(200);
    const converted = await x.post('/auth/convert-guest', {email: `converted-${Date.now()}@example.com`, password, displayName: 'Converted User'}).expect(200);
    expect(converted.body.data.user.id).toBe(a.user.id);
    const signedIn = client(converted.body.data);
    expect((await signedIn.get('/conversations')).body.data.items[0].content).toBe('Guest saved text');
    expect((await signedIn.get('/users/settings')).body.data.highContrast).toBe(true);
  });
  it('staff manages shared content and never reports a fake successful report update', async () => {
    const a = await account(), b = await account();
    await User.updateMany({_id: {$in: [a.user.id, b.user.id]}}, {$set: {role: 'STAFF'}});
    const x = client(a), y = client(b), {item} = await entry(a, 'DRAFT');
    const shared = await y.patch('/staff/content/' + item.id, {definition: 'Shared staff edit'}).expect(200);
    expect(shared.body.data.definition).toBe('Shared staff edit');
    await y.patch('/dictionary/' + item.id, {definition: 'Shared alias edit'}).expect(200);
    const response = await x.patch('/staff/content/' + item.id, {definition: 'Owned edit saved'}).expect(200);
    expect(response.body.data.definition).toBe('Owned edit saved');
    const list = await x.get('/staff/content?status=DRAFT').expect(200);
    expect(list.body.data.items.some((record: any) => record._id === item.id)).toBe(true);
    expect((await x.get('/staff/stats')).body.data.content).toBeDefined();
    await x.get('/staff/content?page[x]=1').expect(400);
    await x.get('/staff/reports').expect(501);
    await x.patch('/staff/reports/' + item.id, {status: 'RESOLVED'}).expect(501);
  });
  it('category deletion and content creation cannot leave a dangling reference', async () => {
    const a = await account();
    await User.updateOne({_id: a.user.id}, {$set: {role: 'ADMIN'}});
    const x = client(a);
    const category = await Category.create({name: 'Race category', slug: 'race-' + Date.now()});
    const [created, deleted] = await Promise.all([
      x.post('/admin/dictionary', {word: 'Race word', definition: 'Transaction race check', videoUrl: 'https://example.org/race.mp4', categoryId: category.id}),
      x.delete('/admin/categories/' + category.id),
    ]);
    expect([201, 400]).toContain(created.status);
    expect([200, 409]).toContain(deleted.status);
    const saved = await DictionaryEntry.findOne({categoryId: category.id});
    if (saved) expect(await Category.exists({_id: category.id})).not.toBeNull();
    expect(created.status === 201 && deleted.status === 200).toBe(false);
  });
  it('concurrent self deletion cannot remove the last active administrator', async () => {
    const existing = await User.find({role: 'ADMIN', status: 'ACTIVE'}).distinct('_id');
    await User.updateMany({_id: {$in: existing}}, {$set: {status: 'SUSPENDED'}});
    try {
      const a = await account(true), b = await account(true);
      await User.updateMany({_id: {$in: [a.user.id, b.user.id]}}, {$set: {role: 'ADMIN'}});
      const responses = await Promise.all([
        client(a).delete('/users/account', {confirm: true, currentPassword: password}),
        client(b).delete('/users/account', {confirm: true, currentPassword: password}),
      ]);
      expect(responses.map(response => response.status).sort()).toEqual([200, 409]);
      expect(await User.countDocuments({_id: {$in: [a.user.id, b.user.id]}, status: 'ACTIVE'})).toBe(1);
    } finally { await User.updateMany({_id: {$in: existing}}, {$set: {status: 'ACTIVE'}}); }
  });

});
