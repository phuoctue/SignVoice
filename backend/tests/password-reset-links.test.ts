import {beforeAll, afterAll, afterEach, it, expect, vi} from 'vitest';
import request from 'supertest';
import nodemailer from 'nodemailer';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {env} from '../src/config/env';
import {sendPasswordResetEmail} from '../src/services/mail.service';
let app: Awaited<ReturnType<typeof createApp>>;
const original = {...env};
const originalFingerprint = process.env.ANDROID_APP_LINK_SHA256;
beforeAll(async () => {await connectDatabase(); app = await createApp();});
afterEach(() => {Object.assign(env, original); vi.restoreAllMocks();
  if (originalFingerprint === undefined) delete process.env.ANDROID_APP_LINK_SHA256;
  else process.env.ANDROID_APP_LINK_SHA256 = originalFingerprint;});
afterAll(disconnectDatabase);
it('provides a private reset bridge without echoing tokens from requests', async () => {
  const token = 'b'.repeat(64);
  const r = await request(app).get('/auth/reset-password?token=' + token).expect(200);
  expect(r.headers['cache-control']).toBe('no-store');
  expect(r.headers['referrer-policy']).toBe('no-referrer');
  expect(r.text).not.toContain(token);
  expect(r.text).toContain('location.hash');
  expect(r.text).toContain('intent://reset-password?token=');
  expect(r.text).toContain('/#/reset-password?token=');
});
it('publishes App Links only with a valid explicit signing fingerprint', async () => {
  delete process.env.ANDROID_APP_LINK_SHA256;
  await request(app).get('/.well-known/assetlinks.json').expect(404);
  process.env.ANDROID_APP_LINK_SHA256 = 'bad';
  await request(app).get('/.well-known/assetlinks.json').expect(404);
  process.env.ANDROID_APP_LINK_SHA256 = Array(32).fill('AA').join(':'); // Fixture, not an actual signing key.
  const r = await request(app).get('/.well-known/assetlinks.json').expect(200);
  expect(r.body[0].relation).toContain('delegate_permission/common.handle_all_urls');
  expect(r.body[0].target.package_name).toBe('com.example.sign_voice');
});
it('sends native and browser links with the token only in fragments', async () => {
  Object.assign(env, {SMTP_HOST: 'smtp.example.test', SMTP_USER: 'fixture@example.test', SMTP_PASS: 'fixture',
    SMTP_FROM: 'fixture@example.test', SMTP_PORT: 465, SMTP_SECURE: true, PASSWORD_RESET_ORIGIN: 'http://localhost:3003'});
  const sendMail = vi.fn().mockResolvedValue({accepted: ['fixture@example.test']});
  vi.spyOn(nodemailer, 'createTransport').mockReturnValue({sendMail} as any);
  const token = 'c'.repeat(64);
  await sendPasswordResetEmail('fixture@example.test', token);
  const message = sendMail.mock.calls[0][0];
  expect(message.text).toContain('/auth/reset-password#token=' + token);
  expect(message.text).toContain('/#/reset-password?token=' + token);
  expect(message.html).toContain('/auth/reset-password#token=' + token);
  expect(message.subject).not.toContain(token);
});
