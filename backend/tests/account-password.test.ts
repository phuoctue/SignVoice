import { beforeAll, afterAll, afterEach, describe, it, expect, vi } from 'vitest';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { User, UserRole, AccountType, AccountStatus } from '../src/models/User.model';
import { Role } from '../src/models/Role.model';
import { AuthSession } from '../src/models/AuthSession.model';
import { AuditLog } from '../src/models/AuditLog.model';
import { UserSettings } from '../src/models/UserSettings.model';
import { hashPassword, verifyPassword } from '../src/utils/password.util';
import * as passwordUtils from '../src/utils/password.util';

let app: Awaited<ReturnType<typeof createApp>>;
const prefix = randomUUID().slice(0, 8), oldPassword = 'CurrentPassword123', newPassword = 'ChangedPassword456';
const users: Record<string, any> = {}, tokens: Record<string, any> = {};
let customRole: any;
const auth = (key = 'admin') => ({ Authorization: `Bearer ${tokens[key].accessToken}` });
const endpoint = (key = 'target') => `/api/v1/admin/users/${users[key]._id}/password`;
beforeAll(async () => {
  await connectDatabase(); app = await createApp();
  customRole = await Role.create({ name: 'Limited password operator', key: `PW_${prefix.toUpperCase()}`, permissions: ['admin:access', 'users:read', 'users:write'] });
  const passwordHash = await hashPassword(oldPassword);
  for (const [key, role] of Object.entries({ admin: UserRole.ADMIN, revoked: UserRole.ADMIN, demoted: UserRole.ADMIN, limited: UserRole.ADMIN, staff: UserRole.STAFF, target: UserRole.USER, rollback: UserRole.USER, self: UserRole.USER, locked: UserRole.USER, social: UserRole.USER, guest: UserRole.USER, deleted: UserRole.USER })) {
    users[key] = await User.create({ email: `password-${prefix}-${key}@example.com`, displayName: `Password ${key}`, passwordHash,
      role, accountType: key === 'social' ? AccountType.GOOGLE : key === 'guest' ? AccountType.GUEST : AccountType.LOCAL,
      isGuest: key === 'guest', status: key === 'deleted' ? AccountStatus.DELETED : AccountStatus.ACTIVE,
      ...(key === 'limited' ? { customRoleId: customRole._id } : {}),
      ...(key === 'social' ? { googleProvider: { providerId: `password-google-${prefix}`, email: `password-${prefix}-social@example.com` } } : {}),
      ...(key === 'target' ? { passwordResetTokenHash: 'pending-reset-hash', passwordResetExpiresAt: new Date(Date.now() + 60000) } : {}) });
    if (!['social', 'guest', 'deleted'].includes(key)) tokens[key] = (await request(app).post('/api/v1/auth/login').send({ email: users[key].email, password: oldPassword }).expect(200)).body.data.tokens;
  }
  await User.updateOne({ _id: users.locked._id }, { $set: { status: AccountStatus.SUSPENDED } });
});
afterEach(() => vi.restoreAllMocks());
afterAll(async () => {
  const ids = Object.values(users).map(user => user._id);
  await Promise.all([User.deleteMany({ _id: { $in: ids } }), UserSettings.deleteMany({ userId: { $in: ids } }), AuthSession.deleteMany({ userId: { $in: ids } }), AuditLog.deleteMany({ userId: { $in: ids } }), Role.deleteOne({ _id: customRole?._id })]);
  await disconnectDatabase();
});

describe('Account password management', () => {
  it('enforces authentication, admin permission and target hierarchy', async () => {
    await request(app).post(endpoint()).send({ newPassword }).expect(401);
    for (const key of ['target', 'staff']) await request(app).post(endpoint()).set(auth(key)).send({ newPassword }).expect(403);
    await request(app).post(endpoint('admin')).set(auth('limited')).send({ newPassword }).expect(403);
  });
  it('validates inputs and rejects self, guest, social and deleted targets', async () => {
    await request(app).post('/api/v1/admin/users/bad/password').set(auth()).send({ newPassword }).expect(400);
    for (const body of [{}, { newPassword: 'weak' }, { newPassword, role: 'ADMIN' }]) await request(app).post(endpoint()).set(auth()).send(body).expect(400);
    for (const key of ['admin', 'guest', 'social']) await request(app).post(endpoint(key)).set(auth()).send({ newPassword }).expect(400);
    await request(app).post(`/api/v1/admin/users/${String(users.admin._id).toUpperCase()}/password`).set(auth()).send({ newPassword }).expect(400);
    await request(app).post(endpoint('deleted')).set(auth()).send({ newPassword }).expect(404);
  });
  it('changes password, revokes old sessions and reset links, preserves actor session and writes a safe audit', async () => {
    const response = await request(app).post(endpoint()).set(auth()).send({ newPassword }).expect(200);
    expect(JSON.stringify(response.body)).not.toContain('passwordHash');
    expect(JSON.stringify(response.body)).not.toContain(newPassword);
    const target = await User.findById(users.target._id).select('+passwordHash +passwordResetTokenHash +passwordResetExpiresAt');
    expect(await verifyPassword(target!.passwordHash!, newPassword)).toBe(true);
    expect(target!.passwordVersion).toBe(1);
    expect(target!.passwordResetTokenHash).toBeUndefined();
    await request(app).get('/api/v1/auth/me').set(auth('target')).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: tokens.target.refreshToken }).expect(401);
    await request(app).post('/api/v1/auth/login').send({ email: users.target.email, password: oldPassword }).expect(401);
    await request(app).post('/api/v1/auth/login').send({ email: users.target.email, password: newPassword }).expect(200);
    await request(app).get('/api/v1/auth/me').set(auth()).expect(200);
    const audit = await AuditLog.findOne({ userId: users.admin._id, resourceId: users.target._id, action: 'PASSWORD_RESET' }).lean();
    expect(audit).toBeTruthy(); expect(JSON.stringify(audit)).not.toContain(newPassword);
  });
  it('rolls back the password and session changes if the audit write fails', async () => {
    vi.spyOn(AuditLog, 'create').mockRejectedValueOnce(new Error('audit unavailable') as never);
    await request(app).post(endpoint('rollback')).set(auth()).send({ newPassword }).expect(500);
    const target = await User.findById(users.rollback._id).select('+passwordHash');
    expect(target!.passwordVersion).toBe(0);
    expect(await verifyPassword(target!.passwordHash!, oldPassword)).toBe(true);
    await request(app).get('/api/v1/auth/me').set(auth('rollback')).expect(200);
  });
  it('allows a limited admin to reset a lower-privilege suspended account without reactivating it', async () => {
    await request(app).post(endpoint('locked')).set(auth('limited')).send({ newPassword }).expect(200);
    expect((await User.findById(users.locked._id))!.status).toBe(AccountStatus.SUSPENDED);
  });
  it('rejects actor session revocation or permission removal during hashing', async () => {
    for (const key of ['revoked', 'demoted']) {
      const actualHash = passwordUtils.hashPassword;
      vi.spyOn(passwordUtils, 'hashPassword').mockImplementationOnce(async value => {
        if (key === 'revoked') await AuthSession.updateMany({ userId: users[key]._id }, { $set: { status: 'REVOKED' } });
        else await User.updateOne({ _id: users[key]._id }, { $set: { role: UserRole.USER } });
        return actualHash(value);
      });
      await request(app).post(endpoint('rollback')).set(auth(key)).send({ newPassword }).expect(key === 'revoked' ? 401 : 403);
      vi.restoreAllMocks();
      expect((await User.findById(users.rollback._id))!.passwordVersion).toBe(0);
    }
  });
  it('requires the old personal password and invalidates the old login only on success', async () => {
    const change = (currentPassword: string, password = newPassword) => request(app).post('/api/v1/auth/change-password').set(auth('self')).send({ currentPassword, newPassword: password });
    await change('wrong').expect(400);
    await request(app).get('/api/v1/auth/me').set(auth('self')).expect(200);
    await change(oldPassword, oldPassword).expect(422);
    await change(oldPassword).expect(200);
    await request(app).get('/api/v1/auth/me').set(auth('self')).expect(401);
    await request(app).post('/api/v1/auth/login').send({ email: users.self.email, password: newPassword }).expect(200);
  });
});
