const { MongoMemoryReplSet } = require('mongodb-memory-server-core');
const crypto = require('node:crypto');
const path = require('node:path');

let db;
(async () => {
  db = await MongoMemoryReplSet.create({instanceOpts: [{ip: '127.0.0.1'}], replSet: {count: 1, storageEngine: 'wiredTiger', ip: '127.0.0.1'}, binary: {version: '7.0.24'}});
  const port = Number(process.env.QA_PORT || 3105);
  Object.assign(process.env, {
    NODE_ENV: 'development', MONGODB_URI: db.getUri('signvoice_test_ui'),
    JWT_ACCESS_SECRET: crypto.randomBytes(48).toString('hex'), JWT_REFRESH_SECRET: crypto.randomBytes(48).toString('hex'),
    PORT: String(port), SERVE_WEB: 'true', WEB_BUILD_DIR: path.resolve('../build/web'),
    WEB_ORIGIN: 'http://127.0.0.1:' + port, PUBLIC_ORIGIN: '', CORS_ALLOWED_ORIGINS: 'http://127.0.0.1:' + port,
    GOOGLE_CLIENT_ID: '', FACEBOOK_APP_ID: '', SMTP_PASS: '',
    LOG_LEVEL: 'info',
  });
  const {connectDatabase, disconnectDatabase} = require('../dist/config/database');
  const {createApp} = require('../dist/app');
  const {registerUser} = require('../dist/services/auth.service');
  const {User, Category, DictionaryEntry} = require('../dist/models');
  await connectDatabase();
  const password = 'QaSignVoice2026!';
  const accounts = [];
  for (const role of ['USER', 'STAFF', 'ADMIN']) {
    const email = 'qa-' + role.toLowerCase() + '@signvoice.test';
    const result = await registerUser({email, password, displayName: 'QA ' + role});
    await User.updateOne({_id: result.user.id}, {$set: {role}});
    accounts.push({role, email});
  }
  const category = await Category.create({name: 'Kiểm thử giao diện', slug: 'qa-ui'});
  await DictionaryEntry.create({word: 'Nội dung kiểm thử QA', definition: 'Mục này chỉ tồn tại trong database kiểm thử tạm.',
    categoryId: category._id, createdBy: accounts.length && (await User.findOne({role: 'STAFF'}))._id,
    videoUrl: 'https://example.org/qa-only.mp4', status: 'DRAFT'});
  const app = await createApp();
  const server = app.listen(port, '127.0.0.1', () => {
    console.log(JSON.stringify({qa: true, url: 'http://127.0.0.1:' + port, password, accounts}));
  });
  const shutdown = async () => {
    server.closeAllConnections(); server.close();
    await disconnectDatabase(); await db.stop(); process.exit(0);
  };
  process.once('SIGINT', shutdown); process.once('SIGTERM', shutdown);
})().catch(async error => {
  console.error(error);
  await require('mongoose').disconnect().catch(() => {});
  if (db) await db.stop();
  process.exitCode = 1;
});
