const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const util = require('node:util');
const dotenv = require('dotenv');
const envPath = path.resolve(__dirname, '../.env.test');
const config = dotenv.parse(fs.readFileSync(envPath));
const signingPath = path.resolve(__dirname, '../../.runtime/testing/android-app-links.json');
const signing = fs.existsSync(signingPath) ? JSON.parse(fs.readFileSync(signingPath, 'utf8').replace(/^\uFEFF/, '')) : null;
let uri;
try { uri = new URL(config.MONGODB_URI); } catch { throw new Error('Invalid test MongoDB URI'); }
if (uri.pathname !== '/signvoice_test') throw new Error('Test database must be signvoice_test');
for (const key of Object.keys(process.env)) {
  if (/^(SMTP_|GOOGLE_|FACEBOOK_|FIREBASE_|JWT_|MONGODB_|TEST_MONGODB_|ADMIN_|SIGNVOICE_ENV_FILE)/.test(key)) delete process.env[key];
}
Object.assign(process.env, config, {
  SIGNVOICE_ENV_FILE: envPath, NODE_ENV: 'test', PORT: '3003',
  JWT_ACCESS_SECRET: config.JWT_ACCESS_SECRET || crypto.randomBytes(48).toString('hex'),
  JWT_REFRESH_SECRET: config.JWT_REFRESH_SECRET || crypto.randomBytes(48).toString('hex'),
  AI_PUBLIC_PROXY: 'true', AI_PROXY_TARGET: 'http://127.0.0.1:8002',
  ANDROID_APP_LINK_SHA256: config.ANDROID_APP_LINK_SHA256 || signing?.sha256 || '',
});
for (const method of ['log', 'info', 'warn', 'error']) {
  const original = console[method].bind(console);
  console[method] = (...args) => {
    let message = util.format(...args).replace(/mongodb(?:\+srv)?:\/\/[^\s'"<>]+/gi, '[REDACTED_MONGODB_URI]');
    if (uri.password) message = message.split(decodeURIComponent(uri.password)).join('[REDACTED_PASSWORD]');
    original(message);
  };
}
require('../dist/server.js').startServer();
