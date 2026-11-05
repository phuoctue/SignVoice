// Explicitly scoped manual QA fixtures. Never reads or copies production users.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const dotenv = require('dotenv');
const root = path.resolve(__dirname, '../..');
const config = dotenv.parse(fs.readFileSync(path.join(root, 'backend/.env.test')));
if (new URL(config.MONGODB_URI).pathname !== '/signvoice_test') throw Error('Expected signvoice_test database');
Object.assign(process.env, config, {NODE_ENV: 'test', SIGNVOICE_ENV_FILE: path.join(root, 'backend/.env.test')});
require('tsx/cjs');
const mongoose = require('mongoose');
const argon2 = require('argon2');
const {User} = require('../src/models/User.model.ts');
const {UserSettings} = require('../src/models/UserSettings.model.ts');
const {SignCollection} = require('../src/models/SignCollection.model.ts');
const {DictionaryEntry} = require('../src/models/DictionaryEntry.model.ts');
const {importReferenceRows, validateReferenceRows} = require('./import-sign-library.ts');

(async () => {
  await mongoose.connect(config.MONGODB_URI);
  const credentialsFile = path.join(root, '.runtime/testing/accounts.json');
  const saved = fs.existsSync(credentialsFile) ? JSON.parse(fs.readFileSync(credentialsFile, 'utf8')) : [];
  const accounts = [];
  for (const role of ['USER', 'STAFF', 'ADMIN']) {
    const email = `qa-${role.toLowerCase()}@signvoice.test`;
    let user = await User.findOne({email});
    let password = saved.find(row => row.email === email)?.password;
    if (!user) {
      password = 'Qa2026!' + crypto.randomBytes(12).toString('hex');
      user = await User.create({email, displayName: `QA ${role} (test)`, role, status: 'ACTIVE',
        accountType: 'LOCAL', isGuest: false, passwordHash: await argon2.hash(password)});
      await UserSettings.create({userId: user._id});
    }
    accounts.push({role, email, password: password || '(existing account; password unchanged)'});
  }
  fs.mkdirSync(path.dirname(credentialsFile), {recursive: true});
  fs.writeFileSync(credentialsFile, JSON.stringify(accounts, null, 2));
  const catalog = path.join(root, '.runtime/speech-sign-library/dictionary-20261024/library.json');
  const rows = JSON.parse(fs.readFileSync(catalog, 'utf8'));
  validateReferenceRows(rows, path.join(root, '.runtime/sign-library-media'));
  const admin = await User.findOne({email: 'qa-admin@signvoice.test'});
  await importReferenceRows(rows, 'http://localhost:3003', admin._id);
  const entries = await DictionaryEntry.find({status: 'PUBLISHED'}).limit(8).select('_id').lean();
  await SignCollection.updateOne({userId: admin._id, name: 'QA · Bộ mẫu công khai'}, {$setOnInsert: {
    userId: admin._id, name: 'QA · Bộ mẫu công khai', description: 'Dữ liệu mẫu chỉ dùng trong môi trường test.',
    entryIds: entries.map(row => row._id), discoverable: true, publishedAt: new Date(),
    shareToken: crypto.randomBytes(16).toString('hex'), moderationState: 'CLEAR',
  }}, {upsert: true});
  console.log(JSON.stringify({database: mongoose.connection.name, accounts: accounts.length,
    publishedEntries: await DictionaryEntry.countDocuments({status: 'PUBLISHED'}), credentialsFile}));
})().catch(error => { console.error(error.name + ': ' + error.message.replace(/mongodb(?:\+srv)?:\/\/\S+/gi, '[redacted]')); process.exitCode = 1; })
  .finally(() => mongoose.disconnect());
