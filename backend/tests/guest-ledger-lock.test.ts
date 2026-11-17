import {afterEach, beforeAll, expect, it, vi} from 'vitest';
import * as fs from 'node:fs/promises';
import {hostname, tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {GuestLedgerLockError, JsonlLedgerSink, verifyGuestLedger} from '../src/services/guest-ledger-file.service';

vi.mock('node:fs/promises', async () => {
  const actual = await vi.importActual<typeof import('node:fs/promises')>('node:fs/promises');
  return {...actual, open: vi.fn(actual.open)};
});

const dirs: string[] = [], sinks: JsonlLedgerSink[] = [];
const key = 'test-ledger-hmac-key-at-least-32-characters';
let deadPid: number;
beforeAll(() => {
  const child = spawnSync(process.execPath, ['-e', ''], {timeout: 10000});
  expect(child.status).toBe(0);
  deadPid = child.pid;
  expect(() => process.kill(deadPid, 0)).toThrowError(expect.objectContaining({code: 'ESRCH'}));
});
afterEach(async () => {
  vi.restoreAllMocks();
  for (const sink of sinks.splice(0)) await sink.close();
  for (const dir of dirs.splice(0)) await fs.rm(dir, {recursive: true, force: true});
});
async function directory() {
  const dir = await fs.mkdtemp(path.join(tmpdir(), 'signvoice-ledger-lock-')); dirs.push(dir); return dir;
}
function sink(dir: string, stream = randomUUID()) {
  const value = new JsonlLedgerSink(dir, key, stream); sinks.push(value); return value;
}
const lockFile = (dir: string) => path.join(dir, '.guest-ledger.lock');
const owner = (overrides = {}) => ({pid: deadPid, hostname: hostname(), token: randomUUID(),
  acquiredAt: '2026-11-17T00:00:00.000Z', ...overrides});

it('records an owner and releases its own lock on close', async () => {
  const dir = await directory(), value = sink(dir);
  await value.checkpoint();
  const record = JSON.parse(await fs.readFile(lockFile(dir), 'utf8'));
  expect(record).toMatchObject({pid: process.pid, hostname: hostname()});
  expect(record.token).toMatch(/^[a-f0-9-]{36}$/);
  expect(Number.isNaN(Date.parse(record.acquiredAt))).toBe(false);
  await value.close();
  await expect(fs.stat(lockFile(dir))).rejects.toMatchObject({code: 'ENOENT'});
});

it('takes over a dead local owner, keeps its exact record for audit and resumes writes', async () => {
  const dir = await directory(), stream = randomUUID(), previous = JSON.stringify(owner());
  await fs.writeFile(lockFile(dir), previous);
  const value = sink(dir, stream);
  await value.append([{streamEpoch: stream, sequence: 1, eventId: randomUUID(), kind: 'BARRIER',
    committedAt: '2026-11-17T00:00:00.000Z', payload: {coveredAt: '2026-11-17T00:00:00.000Z'}}]);
  expect(await value.checkpoint()).toMatchObject({sequence: 1});
  const archived = (await fs.readdir(dir)).filter(name => name.startsWith('.guest-ledger.lock.stale-'));
  expect(archived).toHaveLength(1);
  expect(await fs.readFile(path.join(dir, archived[0]), 'utf8')).toBe(previous);
});

it('recovers the real owner record left by a hard-killed Node writer', async () => {
  const dir = await directory(), stream = randomUUID();
  const child = spawnSync(process.execPath, ['--import', 'tsx', '-e', `
    const {JsonlLedgerSink} = require('./src/services/guest-ledger-file.service');
    const value = new JsonlLedgerSink(${JSON.stringify(dir)}, ${JSON.stringify(key)}, ${JSON.stringify(stream)});
    value.checkpoint().then(() => {process.stdout.write('ready'); process.kill(process.pid, 'SIGKILL');});
  `], {timeout: 10000, encoding: 'utf8'});
  expect(child.error).toBeUndefined();
  expect(child.stdout).toBe('ready');
  const previous = await fs.readFile(lockFile(dir), 'utf8');
  expect(JSON.parse(previous).pid).toBe(child.pid);
  expect(() => process.kill(child.pid, 0)).toThrowError(expect.objectContaining({code: 'ESRCH'}));
  expect(await sink(dir, stream).checkpoint()).toMatchObject({sequence: 0});
  const archived = (await fs.readdir(dir)).find(name => name.startsWith('.guest-ledger.lock.stale-'))!;
  expect(await fs.readFile(path.join(dir, archived), 'utf8')).toBe(previous);
});

it.each([
  ['alive', () => JSON.stringify(owner({pid: process.pid}))],
  ['foreign-host', () => JSON.stringify(owner({hostname: hostname() + '-foreign'}))],
  ['unparsable', () => ''],
  ['unparsable', () => '{broken sensitive-owner-data'],
  ['unparsable', () => JSON.stringify(owner({pid: -1}))],
  ['unparsable', () => 'x'.repeat(10000)],
])('refuses %s owners without changing evidence or logging owner data', async (reason, record) => {
  const dir = await directory(), previous = record();
  await fs.writeFile(lockFile(dir), previous);
  const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
  await expect(sink(dir).checkpoint()).rejects.toBeInstanceOf(GuestLedgerLockError);
  expect(await fs.readFile(lockFile(dir), 'utf8')).toBe(previous);
  expect(await fs.readdir(dir)).toEqual(['.guest-ledger.lock']);
  const logged = warning.mock.calls.flat().join(' ');
  expect(logged).toContain(reason);
  expect(logged).not.toContain(dir);
  expect(logged).not.toContain('sensitive-owner-data');
  expect(logged).not.toContain(key);
});

it('fails closed when the OS cannot establish that the local pid is dead', async () => {
  const dir = await directory();
  await fs.writeFile(lockFile(dir), JSON.stringify(owner()));
  vi.spyOn(process, 'kill').mockImplementation(() => {throw Object.assign(new Error('denied'), {code: 'EPERM'});});
  await expect(sink(dir).checkpoint()).rejects.toBeInstanceOf(GuestLedgerLockError);
  expect(await fs.readdir(dir)).toEqual(['.guest-ledger.lock']);
});

it('allows exactly one concurrent takeover after both contenders observe the stale owner', async () => {
  const dir = await directory(), previous = JSON.stringify(owner());
  await fs.writeFile(lockFile(dir), previous);
  const actual = await vi.importActual<typeof fs>('node:fs/promises');
  let readers = 0, release!: () => void;
  const bothOpened = new Promise<void>(resolve => {release = resolve;});
  vi.mocked(fs.open).mockImplementation(async (...args: Parameters<typeof fs.open>) => {
    const file = await actual.open(...args);
    if (args[0] === lockFile(dir) && args[1] === 'r' && readers < 2) {
      if (++readers === 2) release();
      await bothOpened;
    }
    return file;
  });
  const first = sink(dir), second = sink(dir);
  const results = await Promise.allSettled([first.checkpoint(), second.checkpoint()]);
  expect(results.filter(result => result.status === 'fulfilled')).toHaveLength(1);
  const rejected = results.find(result => result.status === 'rejected') as PromiseRejectedResult;
  expect(rejected.reason).toBeInstanceOf(GuestLedgerLockError);
  expect((await fs.readdir(dir)).filter(name => name.startsWith('.guest-ledger.lock.stale-'))).toHaveLength(1);
  const winner = results[0].status === 'fulfilled' ? first : second;
  expect(await winner.checkpoint()).toMatchObject({sequence: 0});
  expect(JSON.parse(await fs.readFile(lockFile(dir), 'utf8')).pid).toBe(process.pid);
});

it('never removes a lock whose ownership token changed', async () => {
  const dir = await directory(), value = sink(dir);
  await value.checkpoint();
  const replacement = JSON.stringify(owner({pid: process.pid}));
  await fs.writeFile(lockFile(dir), replacement);
  await value.close();
  expect(await fs.readFile(lockFile(dir), 'utf8')).toBe(replacement);
});

it('uses the same dead-owner takeover and release for offline verification', async () => {
  const dir = await directory(), stream = randomUUID(), value = sink(dir, stream);
  await value.checkpoint(); await value.close();
  await fs.writeFile(lockFile(dir), JSON.stringify(owner()));
  expect(await verifyGuestLedger(dir, key, stream)).toMatchObject({sequence: 0});
  await expect(fs.stat(lockFile(dir))).rejects.toMatchObject({code: 'ENOENT'});
  expect((await fs.readdir(dir)).filter(name => name.startsWith('.guest-ledger.lock.stale-'))).toHaveLength(1);
});
