const { MongoMemoryReplSet } = require('mongodb-memory-server-core');
const { spawn } = require('node:child_process');
const path = require('node:path');

(async () => {
  const db = await MongoMemoryReplSet.create({instanceOpts: [{ip: '127.0.0.1'}],
    replSet: {count: 1, storageEngine: 'wiredTiger', ip: '127.0.0.1'}, binary: {version: '7.0.24'}});
  try {
    const uri = db.getUri('signvoice_test_isolated');
    const child = spawn(process.execPath, [path.resolve('node_modules/vitest/vitest.mjs'), 'run', ...process.argv.slice(2)],
      {stdio: 'inherit', env: {...process.env, TEST_MONGODB_URI: uri, NODE_ENV: 'test'}});
    const code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('exit', resolve); });
    process.exitCode = code ?? 1;
  } finally { await db.stop(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
