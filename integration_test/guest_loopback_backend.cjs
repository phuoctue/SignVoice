// Disposable fixture only: no production configuration, URLs, or databases.
// Run: node integration_test/guest_loopback_backend.cjs <existing-backend-node_modules>
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const {randomUUID} = require('node:crypto');
const {createRequire} = require('node:module');
const allowed = new Set(['SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATH', 'PATHEXT', 'TEMP', 'TMP',
  'USERPROFILE', 'HOME', 'LOCALAPPDATA', 'APPDATA', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE']);
process.env = Object.fromEntries(Object.entries(process.env).filter(([k]) => allowed.has(k.toUpperCase())));
const modules = path.resolve(process.argv[2]);
const load = createRequire(path.join(modules, '../package.json'));
process.env.NODE_PATH = modules;
require('node:module').Module._initPaths();
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'signvoice-flutter-fixture-'));
const config = path.join(scratch, 'dummy-config');
fs.writeFileSync(config, '');
Object.assign(process.env, {NODE_ENV: 'test', SIGNVOICE_ENV_FILE: config,
  JWT_ACCESS_SECRET: 'isolated-flutter-access-secret-at-least-32-chars',
  JWT_REFRESH_SECRET: 'isolated-flutter-refresh-secret-at-least-32-chars',
  SESSION_CHAIN_MODE: 'compat', SESSION_CHAIN_CONTROL_DB: 'signvoice_test_control_flutter',
  SESSION_CHAIN_CONTROL_COLLECTION: 'transitions',
  MONGOMS_RUNTIME_DOWNLOAD: 'false', MONGOMS_VERSION: '7.0.24'});
const {MongoMemoryReplSet} = load('mongodb-memory-server-core');
const {MongoClient} = load('mongodb');
const mongo = new MongoMemoryReplSet({instanceOpts: [{ip: '127.0.0.1'}],
  replSet: {count: 1, ip: '127.0.0.1', storageEngine: 'wiredTiger'}, binary: {version: '7.0.24'}});
let server, mongoose, stopping = false;
async function stop() {
  if (stopping) return;
  stopping = true;
  if (server) await new Promise(resolve => server.close(resolve));
  if (mongoose) {await mongoose.connection.dropDatabase(); await mongoose.disconnect();}
  const exits = [];
  for (const s of mongo.servers) {
    const proc = s.instanceInfo?.instance?.mongodProcess;
    if (!proc || proc.exitCode !== null) continue;
    exits.push(new Promise(resolve => proc.once('exit', resolve)));
    const client = new MongoClient(s.getUri('admin'), {directConnection: true, serverSelectionTimeoutMS: 5000});
    try {await client.db('admin').command({shutdown: 1, force: true, timeoutSecs: 1});}
    catch (e) {if (!/closed|ECONNRESET/.test(e.message)) throw e;}
    finally {await client.close();}
  }
  await Promise.all(exits);
  await mongo.stop({doCleanup: true, force: true});
  fs.rmSync(scratch, {recursive: true, force: true});
  console.log('FIXTURE_STOPPED: disposable DB and scratch removed');
}
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => stop().catch(console.error));
(async () => {
  await mongo.start();
  process.env.MONGODB_URI = mongo.getUri(`signvoice_test_flutter_${randomUUID().replaceAll('-', '')}`);
  load('tsx/cjs');
  load('tsx/esm/api').register();
  const root = path.resolve(__dirname, '../backend/src');
  const {authClock} = require(path.join(root, 'services/auth-clock.ts'));
  let clockOffset = 0;
  authClock.now = () => new Date(Date.now() + clockOffset);
  mongoose = load('mongoose');
  await require(path.join(root, 'config/database.ts')).connectDatabase();
  const {User, AuthSession, UserSettings, Conversation} = require(path.join(root, 'models/index.ts'));
  const {GuestTrial} = require(path.join(root, 'models/GuestTrial.model.ts'));
  await Promise.all([User, AuthSession, UserSettings, Conversation, GuestTrial].map(m => m.init()));
  const api = await require(path.join(root, 'app.ts')).createApp();
  const express = load('express');
  const app = express();
  app.use(express.json());
  app.post('/__fixture/advance', (req, res) => {
    if (req.body.minutes !== 16) return res.sendStatus(400);
    clockOffset += 16 * 60000;
    res.json({advanced: true});
  });
  // This fixture represents pre-existing guest-owned data; public guest writes are guarded.
  app.post('/__fixture/seed', async (req, res) => {
    const user = await User.findById(req.body.userId);
    if (!user?.isGuest) return res.sendStatus(400);
    await Conversation.create({userId: user.id, content: 'Hội thoại cần giữ lại', direction: 'TEXT'});
    res.json({seeded: true});
  });
  app.get('/__fixture/check/:id', async (req, res) => res.json({
    userExists: !!await User.exists({_id: req.params.id}),
    conversations: await Conversation.countDocuments({userId: req.params.id}),
    cooldownRows: await GuestTrial.countDocuments(),
  }));
  app.post('/__fixture/stop', (_req, res) => {res.json({stopping: true}); setImmediate(() => stop().catch(console.error));});
  app.use(api);
  server = app.listen(39147, '127.0.0.1', () => console.log('FIXTURE_READY http://127.0.0.1:39147'));
})().catch(async e => {console.error(e); await stop(); process.exitCode = 1;});
