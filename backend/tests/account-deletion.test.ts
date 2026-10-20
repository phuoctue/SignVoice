import { beforeAll, afterAll, describe, it, expect, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { User, UserSettings, AuthSession, Conversation, Favorite, SearchHistory, AuditLog } from '../src/models';
import { deleteOwnAccount } from '../src/services/account-deletion.service';

let app: Awaited<ReturnType<typeof createApp>>;
const users: string[] = [];
beforeAll(async () => {
  await connectDatabase();
  await User.init();
  app = await createApp();
});
afterAll(async () => {
  vi.restoreAllMocks();
  await User.deleteMany({ _id: { $in: users } });
  for (const model of [UserSettings, AuthSession, Conversation, Favorite, SearchHistory, AuditLog]) {
    await model.collection.deleteMany({ userId: { $in: users.map(id => new User({ _id: id })._id) } });
  }
  await disconnectDatabase();
});
async function guest() {
  const r = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  users.push(r.body.data.user.id);
  return r.body.data;
}
describe('Account deletion', () => {
  it('requires authentication', async () => {
    await request(app).delete('/api/v1/users/account').expect(401);
  });
  it('deletes only the authenticated user and invalidates old sessions', async () => {
    const a = await guest(), b = await guest();
    const userId = new User({ _id: a.user.id })._id;
    await Conversation.create({ userId, messages: [{ role: 'USER', content: 'private text' }] });
    await request(app).delete('/api/v1/users/account')
      .set('Authorization', `Bearer ${a.tokens.accessToken}`).send({ userId: b.user.id }).expect(200);
    expect(await User.exists({ _id: a.user.id })).toBeNull();
    expect(await User.exists({ _id: b.user.id })).not.toBeNull();
    for (const model of [UserSettings, AuthSession, Conversation, Favorite, SearchHistory, AuditLog]) {
      expect(await model.collection.countDocuments({ userId })).toBe(0);
    }
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${a.tokens.accessToken}`).expect(401);
    await request(app).get('/api/v1/auth/me').set('Authorization', `Bearer ${b.tokens.accessToken}`).expect(200);
  });
  it('rolls back deletion when related data cannot be removed', async () => {
    const a = await guest();
    const id = new User({ _id: a.user.id })._id;
    const spy = vi.spyOn(AuditLog, 'deleteMany').mockImplementationOnce(() => { throw new Error('simulated storage error'); });
    try { await expect(deleteOwnAccount(id)).rejects.toThrow('simulated storage error'); }
    finally { spy.mockRestore(); }
    expect(await User.exists({ _id: id })).not.toBeNull();
    expect(await AuthSession.countDocuments({ userId: id })).toBeGreaterThan(0);
  });
});
