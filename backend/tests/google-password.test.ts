import {beforeAll, afterAll, describe, it, expect, vi} from 'vitest';
import request from 'supertest';
import {randomUUID} from 'node:crypto';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {User, AccountType} from '../src/models/User.model';
import {AuthSession} from '../src/models/AuthSession.model';
import {UserSettings} from '../src/models/UserSettings.model';
import {loginOAuthUser} from '../src/services/auth.service';
import {resolveOAuthUser} from '../src/services/oauth.service';
import {hashPassword} from '../src/utils/password.util';
import * as mail from '../src/services/mail.service';
import {env} from '../src/config/env';

let app: Awaited<ReturnType<typeof createApp>>;
const password = 'GoogleLocal2026!';
beforeAll(async () => {await connectDatabase(); await User.init(); app = await createApp();});
afterAll(disconnectDatabase);
async function fixture(type = AccountType.GOOGLE) {
  const subject = randomUUID();
  const user = await User.create({email: `${subject}@example.test`, displayName: 'Google password fixture',
    accountType: type, isGuest: type === AccountType.GUEST,
    ...(type === AccountType.GOOGLE ? {googleProvider: {providerId: subject}} : {}),
    ...(type === AccountType.FACEBOOK ? {facebookProvider: {providerId: subject}} : {}),
    ...(type === AccountType.LOCAL ? {passwordHash: await hashPassword(password)} : {})});
  await UserSettings.create({userId: user._id, settings: {}});
  const session = await loginOAuthUser(user);
  return {user, subject, session, authorization: 'Bearer ' + session.tokens.accessToken};
}
describe('Google account local password setup', () => {
  it('supports forgot/reset after adding a password without changing the Google identity', async () => {
    const original = {...env};
    Object.assign(env, {SMTP_HOST: 'smtp.example.test', SMTP_USER: 'fixture@example.test', SMTP_PASS: 'fixture',
      SMTP_FROM: 'fixture@example.test', SMTP_PORT: 465, SMTP_SECURE: true, PASSWORD_RESET_ORIGIN: 'http://localhost:3003'});
    let resetToken = '';
    const send = vi.spyOn(mail, 'sendPasswordResetEmail').mockImplementation(async (_email, token) => { resetToken = token; });
    try {
      const f = await fixture();
      await request(app).post('/api/v1/auth/set-password').set('Authorization', f.authorization).send({newPassword: password}).expect(200);
      const login = await request(app).post('/api/v1/auth/login').send({email: f.user.email, password}).expect(200);
      expect(login.body.data.user.id).toBe(f.user.id);
      await request(app).post('/api/v1/auth/forgot-password').send({email: f.user.email}).expect(200);
      expect(send).toHaveBeenCalledWith(f.user.email, expect.any(String));
      expect(resetToken).toMatch(/^[a-f0-9]{64}$/);
      await request(app).post('/api/v1/auth/reset-password').send({token: resetToken, newPassword: 'GoogleReset2026!'}).expect(200);
      await request(app).post('/api/v1/auth/reset-password').send({token: resetToken, newPassword: password}).expect(400);
      await request(app).post('/api/v1/auth/login').send({email: f.user.email, password}).expect(401);
      expect((await request(app).post('/api/v1/auth/login').send({email: f.user.email, password: 'GoogleReset2026!'}).expect(200)).body.data.user.id).toBe(f.user.id);
      const google = await resolveOAuthUser('google', {subject: f.subject, email: f.user.email!, displayName: 'Google reset fixture'});
      expect((await loginOAuthUser(google)).user.id).toBe(f.user.id);
      expect(await UserSettings.countDocuments({userId: f.user.id})).toBe(1);
    } finally { send.mockRestore(); Object.assign(env, original); }
  });
  it('requires authentication and validated password input', async () => {
    await request(app).post('/api/v1/auth/set-password').send({newPassword: password}).expect(401);
    const f = await fixture();
    for (const body of [{newPassword: 'weak'}, {}, {newPassword: password, userId: 'other'}]) {
      await request(app).post('/api/v1/auth/set-password').set('Authorization', f.authorization).send(body).expect(400);
    }
    expect((await User.findById(f.user.id).select('+passwordHash'))!.passwordHash).toBeUndefined();
  });
  it('preserves identity, settings and Google login while enabling email login', async () => {
    const f = await fixture();
    const response = await request(app).post('/api/v1/auth/set-password').set('Authorization', f.authorization)
      .send({newPassword: password}).expect(200);
    expect(JSON.stringify(response.body)).not.toContain(password);
    expect(JSON.stringify(response.body)).not.toContain('passwordHash');
    await request(app).get('/api/v1/auth/me').set('Authorization', f.authorization).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({refreshToken: f.session.tokens.refreshToken}).expect(401);
    const local = await request(app).post('/api/v1/auth/login').send({email: f.user.email, password}).expect(200);
    expect(local.body.data.user.id).toBe(f.user.id);
    const google = await resolveOAuthUser('google', {subject: f.subject, email: f.user.email!, displayName: 'Same Google fixture'});
    expect(google.id).toBe(f.user.id);
    expect(google.accountType).toBe(AccountType.LOCAL);
    expect((await loginOAuthUser(google)).user.id).toBe(f.user.id);
    expect(await UserSettings.countDocuments({userId: f.user.id})).toBe(1);
    await request(app).post('/api/v1/auth/set-password').set('Authorization', 'Bearer ' + local.body.data.tokens.accessToken)
      .send({newPassword: 'AnotherPassword2026'}).expect(400);
  });
  it('rejects other account types and old Google sessions', async () => {
    for (const type of [AccountType.FACEBOOK, AccountType.GUEST, AccountType.LOCAL]) {
      const f = await fixture(type);
      await request(app).post('/api/v1/auth/set-password').set('Authorization', f.authorization).send({newPassword: password}).expect(400);
    }
    const f = await fixture();
    const old = new Date(Date.now() - 11 * 60 * 1000);
    await AuthSession.collection.updateMany({userId: f.user._id}, {$set: {createdAt: old, authenticatedAt: old}});
    const response = await request(app).post('/api/v1/auth/set-password').set('Authorization', f.authorization).send({newPassword: password}).expect(403);
    expect(response.body.error.code).toBe('AUTH_REAUTHENTICATION_REQUIRED');
    await request(app).get('/api/v1/auth/me').set('Authorization', f.authorization).expect(200);
    const refreshed = await request(app).post('/api/v1/auth/refresh').send({refreshToken: f.session.tokens.refreshToken}).expect(200);
    await request(app).post('/api/v1/auth/set-password')
      .set('Authorization', 'Bearer ' + refreshed.body.data.accessToken).send({newPassword: password}).expect(403);
    const legacy = await fixture();
    await AuthSession.collection.updateMany({userId: legacy.user._id}, {$unset: {authenticatedAt: ''}});
    await request(app).post('/api/v1/auth/set-password').set('Authorization', legacy.authorization).send({newPassword: password}).expect(403);
  });
  it('cannot set two competing passwords concurrently', async () => {
    const f = await fixture();
    const responses = await Promise.all([password, 'OtherGoogle2026!'].map(newPassword => request(app)
      .post('/api/v1/auth/set-password').set('Authorization', f.authorization).send({newPassword})));
    expect(responses.filter(r => r.status === 200)).toHaveLength(1);
    expect(responses.filter(r => [400, 401, 409].includes(r.status))).toHaveLength(1);
  });
});
