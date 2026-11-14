import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { stripVTControlCharacters } from 'node:util';
import { MongoClient } from 'mongodb';
import { expect, it } from 'vitest';
import { cleanupFileDatabases } from './database-cleanup';

it('cleans after failed tests and hooks, preserves original errors, and reports cleanup errors separately', async () => {
  const directory = mkdtempSync(path.resolve('tests/cleanup-fixture-'));
  const scenarios = ['test', 'beforeAll', 'afterAll', 'afterEach', 'cleanup', 'both'];
  const client = new MongoClient(process.env.MONGODB_URI!);
  const owned: { uri: string; control: string; fileId: string; scenario: string }[] = [];
  try {
    for (const scenario of scenarios) {
      writeFileSync(path.join(directory, `${scenario}.test.ts`), `
import { MongoClient } from 'mongodb';
import { beforeAll, afterAll, afterEach, it, expect, vi } from 'vitest';
const uri = process.env.MONGODB_URI;
const control = process.env.SESSION_CHAIN_CONTROL_DB;
const client = new MongoClient(uri);
console.log('R2_OWNED=' + JSON.stringify({ uri, control, fileId: new URL(uri).pathname.slice(-12), scenario: '${scenario}' }));
beforeAll(async () => {
  await client.db().collection('proof').insertOne({ value: 1 });
  await client.db(control).collection('proof').insertOne({ value: 1 });
  ${scenario === 'beforeAll' ? "throw new Error('R2 original beforeAll');" : ''}
});
afterEach(() => { ${scenario === 'afterEach' ? "throw new Error('R2 original afterEach');" : ''} });
afterAll(async () => {
  expect(await client.db().collection('proof').countDocuments()).toBe(1);
  const db = client.db();
  await client.close();
  console.log('R2_TEARDOWN=${scenario}');
  ${scenario === 'afterAll' ? "throw new Error('R2 original afterAll');" : ''}
  ${['cleanup', 'both'].includes(scenario) ? "vi.spyOn(Object.getPrototypeOf(db), 'dropDatabase').mockImplementation(() => new Promise((_, reject) => setTimeout(() => reject(new Error('R2 deliberate drop failure')), 100)));" : ''}
});
it('fixture', () => { ${['test', 'both'].includes(scenario) ? `throw new Error('R2 original ${scenario}');` : 'expect(true).toBe(true);'} });
`);
    }
    const result = spawnSync(process.execPath, [path.resolve('node_modules/vitest/vitest.mjs'), 'run', directory,
      '--config', 'tests/database-cleanup.config.ts', '--maxWorkers=1', '--minWorkers=1', '--no-cache',
      '--sequence.shuffle', '--sequence.seed=42'],
    { encoding: 'utf8', timeout: 60000, env: { ...process.env,
      SESSION_CHAIN_CONTROL_DB: new URL(process.env.TEST_MONGODB_URI!).pathname.slice(1)
        .replace('signvoice_test_app_', 'signvoice_test_control_'),
    }, maxBuffer: 4 * 1024 * 1024 });
    const output = stripVTControlCharacters(result.stdout + result.stderr);
    for (const line of output.split(/\r?\n/)) {
      const match = line.match(/R2_OWNED=(\{.*\})/);
      if (match) owned.push(JSON.parse(match[1]));
    }
    expect(result.error, output).toBeUndefined();
    expect(result.status, output).toBe(1);
    expect(owned, output).toHaveLength(scenarios.length);
    const { databases } = await client.db('admin').admin().listDatabases({ nameOnly: true });
    const names = databases.map(database => database.name);
    for (const item of owned) {
      expect(output).toContain(`R2_TEARDOWN=${item.scenario}`);
      if (item.scenario !== 'cleanup') expect(output).toContain(`Error: R2 original ${item.scenario}`);
      const app = new URL(item.uri).pathname.slice(1);
      for (const name of [app, item.control]) {
        expect(names.includes(name), item.scenario).toBe(['cleanup', 'both'].includes(item.scenario));
      }
      if (['cleanup', 'both'].includes(item.scenario)) {
        expect(output).toContain(`${item.scenario}.test.ts: Error: R2 deliberate drop failure`);
        expect(output).toContain('DB cleanup failed for');
      }
    }
  } finally {
    for (const item of owned) await cleanupFileDatabases(item.uri, item.control, item.fileId);
    await client.close();
    rmSync(directory, { recursive: true, force: true });
  }
}, 90000);
