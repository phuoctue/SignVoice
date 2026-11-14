const { spawn, spawnSync } = require('node:child_process');
const { mkdtempSync, writeFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

// Strip application credentials/config before loading MongoDB or starting any child.
const allowed = new Set(['SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATH', 'PATHEXT', 'TEMP', 'TMP',
  'USERPROFILE', 'HOME', 'LOCALAPPDATA', 'APPDATA', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE']);
const isolated = Object.fromEntries(Object.entries(process.env).filter(([key]) => allowed.has(key.toUpperCase())));
if (process.env.MONGOMS_SYSTEM_BINARY) isolated.MONGOMS_SYSTEM_BINARY = process.env.MONGOMS_SYSTEM_BINARY;
Object.assign(isolated, { NODE_ENV: 'test', MONGOMS_RUNTIME_DOWNLOAD: 'false', MONGOMS_VERSION: '7.0.24' });
process.env = isolated;
const { MongoMemoryReplSet } = require('mongodb-memory-server-core');
const { MongoClient, MongoNetworkError } = require('mongodb');
const root = path.resolve(__dirname, '..');
const scratch = mkdtempSync(path.join(tmpdir(), 'signvoice-test-'));
const id = randomUUID().replace(/-/g, '').slice(0, 24);
Object.assign(isolated, {
  SIGNVOICE_ENV_FILE: path.join(scratch, 'dummy-config'),
  JWT_ACCESS_SECRET: 'isolated-test-access-secret-at-least-32-chars',
  JWT_REFRESH_SECRET: 'isolated-test-refresh-secret-at-least-32-chars',
  SESSION_CHAIN_MODE: 'compat', SESSION_CHAIN_CONTROL_DB: `signvoice_test_control_${id}`,
  SESSION_CHAIN_CONTROL_COLLECTION: 'transitions',
});
writeFileSync(isolated.SIGNVOICE_ENV_FILE, '');
const db = new MongoMemoryReplSet({instanceOpts: [{ip: '127.0.0.1', launchTimeout: 30000}],
  replSet: {count: 1, storageEngine: 'wiredTiger', ip: '127.0.0.1'}, binary: {version: '7.0.24'}});
let child;
let stopping = false;
let unexpectedMongoExit = false;
const mongoExits = [];
db.on('stateChange', (state, error) => {
  console.error('[isolated mongo] state', state, error || '');
});
async function bounded(operation, milliseconds, label) {
  let timer;
  try {
    return await Promise.race([operation, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${label} timed out`)), milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}
async function stopMongo() {
  for (const server of db.servers) {
    const instance = server.instanceInfo?.instance;
    if (!instance?.mongodProcess || instance.mongodProcess.exitCode !== null || instance.mongodProcess.signalCode !== null) continue;
    const client = new MongoClient(server.getUri('admin'), {directConnection: true,
      serverSelectionTimeoutMS: 5000, socketTimeoutMS: 5000, connectTimeoutMS: 5000});
    try {
      await client.db('admin').command({shutdown: 1, force: true, timeoutSecs: 1});
    } catch (error) {
      if (!(error instanceof MongoNetworkError && (
        /^connection \d+ to 127\.0\.0\.1:\d+ closed$/.test(error.message) ||
        (error.message === 'read ECONNRESET' && error.cause?.code === 'ECONNRESET')
      ))) throw error;
    } finally { await client.close(); }
  }
  // The helper's Windows SIGINT interrupts WiredTiger close; let mongod exit first.
  await Promise.all(mongoExits);
  return db.stop({doCleanup: false});
}
async function finish(code) {
  if (stopping) return;
  stopping = true;
  clearTimeout(deadline);
  // A hung child/Mongo teardown must not leave the test command waiting indefinitely.
  const teardown = setTimeout(() => { console.error('Isolated test teardown timed out'); process.exit(1); }, 60000);
  try {
    if (child && child.exitCode === null && child.signalCode === null) {
      if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], {timeout: 5000, stdio: 'ignore'});
      else process.kill(-child.pid, 'SIGKILL');
    }
    if (await bounded(stopMongo(), 25000, 'MongoDB stop') === false) {
      throw new Error('Unable to stop disposable MongoDB');
    }
    process.exitCode = unexpectedMongoExit ? 1 : code;
  } catch (error) { console.error(error); process.exitCode = 1; }
  finally {
    // Windows can report termination before the heavy full-suite process actually exits.
    try {
      if (db.servers.some(server => server.instanceInfo?.instance.mongodProcess)) {
        await bounded(Promise.all(mongoExits), 15000, 'MongoDB exit');
        await bounded(db.stop({doCleanup: false}), 5000, 'MongoDB final stop');
      }
    } catch (error) { console.error(error); process.exitCode = 1; }
    try { await bounded(db.cleanup({doCleanup: true, force: true}), 10000, 'MongoDB cleanup'); }
    catch (error) { console.error(error); process.exitCode = 1; }
    finally {
      try { rmSync(scratch, {recursive: true, force: true}); }
      catch (error) { console.error(error); process.exitCode = 1; }
      clearTimeout(teardown);
    }
  }
}
const deadline = setTimeout(() => { console.error('Isolated tests exceeded 900 seconds'); void finish(1); }, 900000);
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { void finish(1); });
(async () => {
  await db.start();
  for (const server of db.servers) {
    const instance = server.instanceInfo.instance;
    console.error('[isolated mongo] started', instance.mongodProcess.pid, server.instanceInfo.dbPath, scratch);
    instance.on('instanceError', error => console.error('[isolated mongo] instanceError', error));
    instance.on('instanceClosed', (code, signal) => console.error('[isolated mongo] instanceClosed', {code, signal, stopping}));
    instance.on('instanceSTDOUT', line => {
      if (/shut.?down|terminat|fatal|signal/i.test(line)) console.error('[isolated mongo] output', line.trim());
    });
    mongoExits.push(new Promise(resolve => instance.mongodProcess.once('exit', (code, signal) => {
      if (!stopping || code !== 0) unexpectedMongoExit = true;
      console.error('[isolated mongo] exit', {code, signal, stopping});
      resolve();
    })));
  }
  if (stopping) return;
  isolated.TEST_MONGODB_URI = db.getUri(`signvoice_test_app_${id}`);
  child = spawn(process.execPath, [path.join(root, 'node_modules/vitest/vitest.mjs'), 'run',
    '--maxWorkers=2', '--minWorkers=1', '--no-cache',
    '--config', path.join(root, 'tests/database-cleanup.config.ts'), ...process.argv.slice(2)],
  {cwd: root, stdio: 'inherit', env: isolated, detached: process.platform !== 'win32'});
  const code = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', code => resolve(code ?? 1));
  });
  const audit = new MongoClient(isolated.TEST_MONGODB_URI, {serverSelectionTimeoutMS: 5000,
    connectTimeoutMS: 5000, socketTimeoutMS: 5000, timeoutMS: 5000});
  try {
    const { databases } = await audit.db('admin').admin().listDatabases({nameOnly: true});
    const remaining = databases.map(database => database.name).filter(name => name.startsWith('signvoice_test_'));
    console.error('[isolated mongo] test databases before shutdown', JSON.stringify(remaining));
  } finally { await audit.close(); }
  await finish(code);
})().catch(async error => { console.error(error); await finish(1); });
