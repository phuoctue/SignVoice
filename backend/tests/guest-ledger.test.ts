import {afterAll, afterEach, beforeAll, expect, it, vi} from 'vitest';
import {mkdtemp, readFile, writeFile, rm, open} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import mongoose from 'mongoose';
import request from 'supertest';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {createApp} from '../src/app';
import {LifecycleEvent, GuestLifecycleOutbox, GuestLifecycleCounter} from '../src/models/GuestLifecycle.model';
import {appendCoverageBarrier, ensureGuestOutbox} from '../src/services/guest-lifecycle-outbox.service';
import {guestGrantBody} from './guest-fixture';
import {authClock} from '../src/services/auth-clock';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';

vi.mock('node:fs', async () => {
  const actual = await vi.importActual<typeof import('node:fs')>('node:fs');
  return {...actual, createReadStream: vi.fn(actual.createReadStream)};
});

const dirs: string[] = [];
const key = 'test-ledger-hmac-key-at-least-32-characters';
async function directory() {const dir = await mkdtemp(path.join(tmpdir(), 'signvoice-ledger-')); dirs.push(dir); return dir;}
const barrier = (streamEpoch: string, sequence: number): LifecycleEvent => ({streamEpoch, sequence, eventId: randomUUID(),
  kind: 'BARRIER', committedAt: '2026-11-14T12:00:00.000Z', payload: {coveredAt: '2026-11-14T12:00:00.000Z'}});
beforeAll(connectDatabase);
afterEach(async () => {vi.restoreAllMocks(); for (const dir of dirs.splice(0)) await rm(dir, {recursive: true, force: true});});
afterAll(async () => {await mongoose.connection.dropDatabase(); await disconnectDatabase();});
async function resetStream() {
  await ensureGuestOutbox();
  await GuestLifecycleOutbox.deleteMany({});
  await GuestLifecycleCounter.updateOne({_id: 'lifecycle'}, {$set: {streamEpoch: randomUUID(), sequence: 0, exportedSequence: 0},
    $unset: {exportedHash: '', coveredAt: '', lastBarrierAt: '', lastBarrierSequence: ''}});
}
it('reuses successful outbox initialization without repeated database lookups or majority upserts', async () => {
  const failure = vi.spyOn(GuestLifecycleCounter, 'exists').mockRejectedValueOnce(new Error('bootstrap unavailable'));
  await expect(ensureGuestOutbox()).rejects.toThrow('bootstrap unavailable');
  failure.mockRestore();
  await ensureGuestOutbox();
  const read = vi.spyOn(GuestLifecycleCounter, 'exists'), write = vi.spyOn(GuestLifecycleCounter, 'updateOne');
  await ensureGuestOutbox(); await ensureGuestOutbox();
  expect(read).not.toHaveBeenCalled();
  expect(write).not.toHaveBeenCalled();
});

it('distinguishes a held ledger lock requiring an operator from a transient exporter failure', async () => {
  const {JsonlLedgerSink, GuestLedgerExporter} = await import('../src/services/guest-ledger.service');
  await resetStream();
  const stream = (await GuestLifecycleCounter.findById('lifecycle'))!.streamEpoch, dir = await directory();
  const owner = new JsonlLedgerSink(dir, key, stream), blocked = new JsonlLedgerSink(dir, key, stream);
  try {
    await owner.checkpoint();
    const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
    await expect(new GuestLedgerExporter(blocked).exportOnce()).rejects.toThrow(/operator.*fence/i);
    const logged = warning.mock.calls.flat().join(' ');
    expect(logged).toMatch(/operator.*stale lock/i);
    expect(logged).not.toContain(key);
    expect(logged).not.toContain(dir);
  } finally {await blocked.close(); await owner.close();}
});

it('durably appends contiguous events, verifies HMAC/hash chain, and replays idempotently after reopen', async () => {
  const {JsonlLedgerSink, verifyGuestLedger} = await import('../src/services/guest-ledger.service');
  const dir = await directory(), stream = randomUUID(), first = barrier(stream, 1), second = barrier(stream, 2);
  let sink = new JsonlLedgerSink(dir, key, stream);
  try {
    await sink.append([first, second]);
    expect(await sink.checkpoint()).toMatchObject({sequence: 2, coveredAt: second.payload.coveredAt});
  } finally {await sink.close();}
  const file = path.join(dir, stream + '.jsonl'), before = await readFile(file, 'utf8');
  sink = new JsonlLedgerSink(dir, key, stream);
  try {
    await sink.append([first, second]);
    expect(await readFile(file, 'utf8')).toBe(before);
    await expect(sink.append([barrier(stream, 4)])).rejects.toThrow(/gap/i);
    await expect(sink.append([{...first, eventId: randomUUID()}])).rejects.toThrow(/replay/i);
    await expect(sink.append([{...barrier(stream, 3), payload: {coveredAt: '2026-11-14T12:00:00.000Z', token: 'raw'}} as any])).rejects.toThrow();
  } finally {await sink.close();}
  const records = before.trim().split('\n').map(line => JSON.parse(line));
  expect(records[1].previousHash).toBe(records[0].hash);
  records[0].event.payload.coveredAt = '2026-11-14T13:00:00.000Z';
  await writeFile(file, records.map(record => JSON.stringify(record)).join('\n') + '\n');
  // Normal reopen trusts its signed checkpoint; a full historical audit is explicit.
  await expect(verifyGuestLedger(dir, key, stream)).rejects.toThrow(/integrity/i);
});

it('rejects concurrent ledger writers and wrong keys or truncated records', async () => {
  const {JsonlLedgerSink} = await import('../src/services/guest-ledger.service');
  const dir = await directory(), stream = randomUUID(), sink = new JsonlLedgerSink(dir, key, stream);
  const second = new JsonlLedgerSink(dir, key, stream);
  try {
    await sink.append([barrier(stream, 1)]);
    await expect(second.checkpoint()).rejects.toThrow();
  } finally {await second.close(); await sink.close();}
  const wrong = new JsonlLedgerSink(dir, 'wrong-key-at-least-32-characters-long', stream);
  try {await expect(wrong.checkpoint()).rejects.toThrow(/integrity/i);} finally {await wrong.close();}
  const file = path.join(dir, stream + '.jsonl');
  await writeFile(file, (await readFile(file, 'utf8')).trimEnd());
  const truncated = new JsonlLedgerSink(dir, key, stream);
  try {await expect(truncated.checkpoint()).rejects.toThrow(/integrity/i);} finally {await truncated.close();}
});

it('exports barriers through the shared counter, checkpoints only contiguous durable batches and alarms on lag/gaps', async () => {
  const {JsonlLedgerSink, GuestLedgerExporter} = await import('../src/services/guest-ledger.service');
  await ensureGuestOutbox();
  const first = await appendCoverageBarrier(), dir = await directory();
  const sink = new JsonlLedgerSink(dir, key, first.streamEpoch), exporter = new GuestLedgerExporter(sink);
  try {
    await exporter.exportOnce();
    const checkpoint = await sink.checkpoint();
    expect(checkpoint.sequence).toBeGreaterThanOrEqual(first.sequence);
    expect(checkpoint.coveredAt).toBeDefined();
    expect((await GuestLifecycleCounter.findById('lifecycle'))!.exportedSequence).toBe(checkpoint.sequence);
    const late = await appendCoverageBarrier();
    await GuestLifecycleOutbox.collection.updateOne({eventId: late.eventId}, {$set: {committedAt: new Date(Date.now() - 61000).toISOString()}});
    const alarm = vi.spyOn(console, 'warn').mockImplementation(() => {});
    await exporter.exportOnce();
    expect(alarm.mock.calls.some(args => String(args[0]).includes('60s'))).toBe(true);
    expect(exporter.status.degraded).toBe(false);
    const gap = await appendCoverageBarrier();
    await GuestLifecycleOutbox.deleteOne({eventId: gap.eventId});
    await expect(exporter.exportOnce()).rejects.toThrow(/gap/i);
    expect(exporter.status.degraded).toBe(true);
  } finally {await sink.close();}
});

it('never waits for an unreachable external sink before acknowledging discard, and retries with backoff', async () => {
  const {GuestLedgerExporter} = await import('../src/services/guest-ledger.service');
  const app = await createApp();
  const a = (await request(app).post('/api/v1/auth/guest').send(guestGrantBody()).expect(201)).body.data;
  const counter = (await GuestLifecycleCounter.findById('lifecycle'))!;
  const exporter = new GuestLedgerExporter({streamEpoch: counter.streamEpoch,
    checkpoint: async () => {throw new Error('offline');}, append: async () => {throw new Error('offline');}, close: async () => {}});
  await expect(exporter.exportOnce()).rejects.toThrow('offline');
  expect(exporter.status).toMatchObject({degraded: true, retryMs: 2000});
  await expect(exporter.exportOnce()).rejects.toThrow('offline');
  expect(exporter.status.retryMs).toBe(4000);
  const status = await request(app).get('/api/v1/guest-trial/status').set('Authorization', 'Bearer ' + a.tokens.accessToken).expect(200);
  await request(app).post('/api/v1/guest-data/discard').set('Authorization', 'Bearer ' + a.tokens.accessToken)
    .send({confirmDiscard: true, expectedDataVersion: status.body.data.dataVersion}).expect(200);
  expect(await GuestLifecycleOutbox.countDocuments({kind: 'DISCARDED', 'payload.guestUserId': a.user.id})).toBe(1);
});

it('disables exporter without a configured external location and never chooses a repository default', async () => {
  const {startGuestLedgerExporter} = await import('../src/services/guest-ledger.service');
  const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
  const disabled = await startGuestLedgerExporter({directory: '', hmacKey: ''});
  expect(disabled.status.degraded).toBe(true);
  expect(warning).toHaveBeenCalled();
  await disabled.stop();
  const inside = await startGuestLedgerExporter({directory: process.cwd(), hmacKey: key});
  expect(inside.status.degraded).toBe(true);
  await inside.stop();
});

it('fails closed if an acknowledged ledger tail disappears, rather than silently rebuilding a lower watermark', async () => {
  const {JsonlLedgerSink, GuestLedgerExporter} = await import('../src/services/guest-ledger.service');
  // A separate database stream avoids depending on the earlier deliberate outbox-gap fixture.
  await resetStream();
  await ensureGuestOutbox();
  const first = await appendCoverageBarrier(), dir = await directory();
  let sink = new JsonlLedgerSink(dir, key, first.streamEpoch);
  await new GuestLedgerExporter(sink).exportOnce();
  await sink.close();
  await writeFile(path.join(dir, first.streamEpoch + '.jsonl'), '');
  sink = new JsonlLedgerSink(dir, key, first.streamEpoch);
  const exporter = new GuestLedgerExporter(sink);
  try {
    await expect(exporter.exportOnce()).rejects.toThrow(/regress|truncat/i);
    expect(exporter.status.degraded).toBe(true);
  } finally {await sink.close();}
});

it('resumes after external commit but before DB checkpoint without duplicating records or skipping a batch', async () => {
  const {JsonlLedgerSink, GuestLedgerExporter} = await import('../src/services/guest-ledger.service');
  await resetStream();
  await ensureGuestOutbox();
  const first = await appendCoverageBarrier(), dir = await directory();
  const sink = new JsonlLedgerSink(dir, key, first.streamEpoch), exporter = new GuestLedgerExporter(sink);
  const save = vi.spyOn(GuestLifecycleCounter, 'updateOne').mockRejectedValueOnce(new Error('checkpoint unavailable'));
  try {
    await expect(exporter.exportOnce()).rejects.toThrow('checkpoint unavailable');
    const committed = await readFile(path.join(dir, first.streamEpoch + '.jsonl'), 'utf8');
    save.mockRestore();
    await exporter.exportOnce();
    expect(await readFile(path.join(dir, first.streamEpoch + '.jsonl'), 'utf8')).toBe(committed);
    expect((await GuestLifecycleCounter.findById('lifecycle'))!.exportedSequence).toBe(first.sequence);
  } finally {save.mockRestore(); await sink.close();}
});

it('reopens and verifies an uncertain file append after a transient fsync failure before retrying', async () => {
  const {JsonlLedgerSink} = await import('../src/services/guest-ledger.service');
  const dir = await directory(), stream = randomUUID(), sink = new JsonlLedgerSink(dir, key, stream);
  const first = barrier(stream, 1), second = barrier(stream, 2);
  try {
    await sink.checkpoint();
    const probe = await open(path.join(dir, 'probe'), 'a+');
    const sync = vi.spyOn(Object.getPrototypeOf(probe), 'sync').mockRejectedValueOnce(new Error('disk offline'));
    await probe.close();
    await expect(sink.append([first])).rejects.toThrow('disk offline');
    sync.mockRestore();
    await sink.append([first, second]);
    expect(await sink.checkpoint()).toMatchObject({sequence: 2});
    expect((await readFile(path.join(dir, stream + '.jsonl'), 'utf8')).trim().split('\n')).toHaveLength(2);
  } finally {await sink.close();}
});

it('alarms on lag even while an external sink call is stuck', async () => {
  const {GuestLedgerExporter} = await import('../src/services/guest-ledger.service');
  await resetStream();
  const first = await appendCoverageBarrier();
  let release!: () => void, entered!: () => void;
  const gate = new Promise<void>(resolve => {release = resolve;}), reached = new Promise<void>(resolve => {entered = resolve;});
  const exporter = new GuestLedgerExporter({streamEpoch: first.streamEpoch, checkpoint: async () => {
    entered(); await gate; throw new Error('unreachable');
  }, append: async () => {}, close: async () => {}});
  const pending = exporter.exportOnce().catch(error => error);
  try {
    await reached;
    vi.spyOn(authClock, 'now').mockReturnValue(new Date(Date.parse(first.committedAt) + 61000));
    const warning = vi.spyOn(console, 'warn').mockImplementation(() => {});
    await exporter.checkLag();
    expect(exporter.status).toMatchObject({degraded: true, lagMs: 61000});
    expect(warning.mock.calls.some(args => String(args[0]).includes('60s'))).toBe(true);
  } finally {release(); await pending;}
});

it('bounds replay and reopen I/O for a large ledger, with full history checked only by explicit verification', async () => {
  const {JsonlLedgerSink, verifyGuestLedger} = await import('../src/services/guest-ledger.service');
  const dir = await directory(), stream = randomUUID(), first = barrier(stream, 1);
  let sink = new JsonlLedgerSink(dir, key, stream);
  try {
    for (let start = 1; start <= 10000; start += 100) {
      await sink.append(Array.from({length: 100}, (_, i) => start + i === 1 ? first : barrier(stream, start + i)));
    }
    await expect(sink.append([first])).rejects.toThrow(/replay.*window/i);
  } finally {await sink.close();}
  const probe = await open(path.join(dir, 'probe'), 'a+');
  const readWhole = vi.spyOn(Object.getPrototypeOf(probe), 'readFile').mockRejectedValue(new Error('whole-file reads forbidden'));
  await probe.close();
  const fs = await import('node:fs'), readStream = fs.createReadStream;
  let bytes = 0;
  const read = vi.spyOn(fs, 'createReadStream').mockImplementation((...args: any[]) => {
    const result = Reflect.apply(readStream, fs, args);
    result.on('data', chunk => {bytes += Buffer.byteLength(chunk);});
    return result;
  });
  sink = new JsonlLedgerSink(dir, key, stream);
  try {
    expect(await sink.checkpoint()).toMatchObject({sequence: 10000});
    expect(bytes).toBeLessThan(4096);
  } finally {await sink.close(); read.mockRestore(); readWhole.mockRestore();}
  expect(await verifyGuestLedger(dir, key, stream)).toMatchObject({sequence: 10000});
  const verified = await promisify(execFile)(process.execPath, [path.resolve('node_modules/tsx/dist/cli.mjs'),
    path.resolve('src/guest-ledger-verify.ts'), dir, stream], {env: {...process.env, GUEST_LEDGER_HMAC_KEY: key}, timeout: 20000});
  expect(JSON.parse(verified.stdout)).toMatchObject({sequence: 10000});
}, 90000);

it('starts, ticks and stops the real exporter without idle barrier flooding, then covers new events promptly', async () => {
  const {startGuestLedgerExporter} = await import('../src/services/guest-ledger.service');
  await resetStream();
  const dir = await directory(), scheduled: {callback: () => Promise<void>; handle: any; cancelled?: boolean}[] = [];
  const timeout = globalThis.setTimeout, clear = globalThis.clearTimeout;
  vi.spyOn(globalThis, 'setTimeout').mockImplementation(((callback: any, delay: number, ...args: any[]) => {
    if (callback.name !== 'tick') return timeout(callback, delay, ...args);
    const handle = {unref: () => handle}; scheduled.push({callback, handle}); return handle;
  }) as typeof setTimeout);
  vi.spyOn(globalThis, 'clearTimeout').mockImplementation((handle: any) => {
    const item = scheduled.find(item => item.handle === handle);
    if (item) item.cancelled = true; else clear(handle);
  });
  let now = new Date();
  vi.spyOn(authClock, 'now').mockImplementation(() => now);
  const worker = await startGuestLedgerExporter({directory: dir, hmacKey: key});
  try {
    expect(scheduled).toHaveLength(1);
    await scheduled[0].callback();
    for (let i = 1; i <= 8; i++) {now = new Date(+now + 1000); await scheduled[i].callback();}
    expect(await GuestLifecycleOutbox.countDocuments({kind: 'BARRIER'})).toBe(1);
    now = new Date(+now + 300000);
    await scheduled[9].callback();
    expect(await GuestLifecycleOutbox.countDocuments({kind: 'BARRIER'})).toBe(2);
    const app = await createApp();
    await request(app).post('/api/v1/auth/guest').send(guestGrantBody()).expect(201);
    await scheduled[10].callback();
    expect(await GuestLifecycleOutbox.countDocuments({kind: 'BARRIER'})).toBe(3);
    const counter = (await GuestLifecycleCounter.findById('lifecycle'))!;
    expect(counter.exportedSequence).toBe(counter.sequence);
    expect(worker.status.degraded).toBe(false);
  } finally {await worker.stop();}
  expect(scheduled.at(-1)?.cancelled).toBe(true);
});
