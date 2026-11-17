import {open, stat, unlink, rename, FileHandle} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash, createHmac, randomUUID, timingSafeEqual} from 'node:crypto';
import path from 'node:path';
import {hostname} from 'node:os';
import {z} from 'zod';
import {LifecycleEvent, lifecycleEventSchema} from '../models/GuestLifecycle.model';

export interface LedgerCheckpoint {sequence: number; hash: string; coveredAt?: string}
export interface GuestLedgerSink {
  readonly streamEpoch: string;
  checkpoint(): Promise<LedgerCheckpoint>;
  append(events: readonly LifecycleEvent[]): Promise<void>;
  close(): Promise<void>;
}
const replayWindow = 100, maxRecordBytes = 8192, maxCheckpointBytes = 65536;
const zeroHash = '0'.repeat(64), hashSchema = z.string().regex(/^[a-f0-9]{64}$/);
const digest = (previousHash: string, event: LifecycleEvent) => createHash('sha256').update(previousHash + '\n' + JSON.stringify(event)).digest('hex');
const fingerprint = (event: LifecycleEvent) => createHash('sha256').update(JSON.stringify(event)).digest('hex');
const mac = (key: string, text: string) => createHmac('sha256', key).update(text).digest('hex');
const validMac = (key: string, text: string, signature: string) => timingSafeEqual(Buffer.from(signature, 'hex'), Buffer.from(mac(key, text), 'hex'));
const recordSchema = z.object({event: lifecycleEventSchema, previousHash: hashSchema, hash: hashSchema, hmac: hashSchema}).strict();
const checkpointSchema = z.object({streamEpoch: z.string().uuid(), sequence: z.number().int().nonnegative().safe(), hash: hashSchema,
  coveredAt: z.string().datetime().optional(), offset: z.number().int().nonnegative().safe(), lastRecordOffset: z.number().int().nonnegative().safe(),
  recent: z.array(z.object({sequence: z.number().int().positive().safe(), fingerprint: hashSchema}).strict()).max(replayWindow),
}).strict();
type StoredCheckpoint = z.infer<typeof checkpointSchema>;
export class GuestLedgerLockError extends Error {
  constructor() {super('Guest ledger lock is held; an operator must fence the old writer before renaming a stale lock');}
}
const empty = (streamEpoch: string): StoredCheckpoint => ({streamEpoch, sequence: 0, hash: zeroHash, offset: 0, lastRecordOffset: 0, recent: []});
const integrity = () => new Error('Ledger integrity: invalid checkpoint, record, chain or HMAC');
async function syncDirectory(directory: string) {
  if (process.platform === 'win32') return;
  const handle = await open(directory, 'r');
  try {await handle.sync();} finally {await handle.close();}
}
/** Bounded byte buffers, including for a corrupt file containing a huge unterminated line. */
async function* records(filename: string, start: number, end: number) {
  if (start >= end) return;
  let pending = Buffer.alloc(0), offset = start;
  for await (const chunk of createReadStream(filename, {start, end: end - 1, highWaterMark: 65536})) {
    pending = Buffer.concat([pending, chunk as Buffer]);
    let newline: number;
    while ((newline = pending.indexOf(10)) >= 0) {
      if (!newline || newline > maxRecordBytes) throw integrity();
      let record: z.infer<typeof recordSchema>;
      try {record = recordSchema.parse(JSON.parse(pending.subarray(0, newline).toString('utf8')));} catch {throw integrity();}
      yield {record, start: offset, end: offset + newline + 1};
      offset += newline + 1;
      pending = pending.subarray(newline + 1);
    }
    if (pending.length > maxRecordBytes) throw integrity();
  }
  if (pending.length) throw integrity();
}
function verifyRecord(record: z.infer<typeof recordSchema>, key: string, stream: string) {
  if (record.event.streamEpoch !== stream || record.hash !== digest(record.previousHash, record.event) || !validMac(key, record.hash, record.hmac)) throw integrity();
}
function accept(checkpoint: StoredCheckpoint, event: LifecycleEvent, hash: string, start: number, end: number) {
  if (event.sequence !== checkpoint.sequence + 1) throw integrity();
  checkpoint.sequence = event.sequence; checkpoint.hash = hash; checkpoint.lastRecordOffset = start; checkpoint.offset = end;
  if (event.kind === 'BARRIER') checkpoint.coveredAt = (event.payload as {coveredAt: string}).coveredAt;
  checkpoint.recent.push({sequence: event.sequence, fingerprint: fingerprint(event)});
  if (checkpoint.recent.length > replayWindow) checkpoint.recent.shift();
}
async function readCheckpoint(filename: string, key: string, stream: string): Promise<StoredCheckpoint | null> {
  let file: FileHandle;
  try {file = await open(filename, 'r');} catch (error) {if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null; throw error;}
  try {
    const buffer = Buffer.alloc(maxCheckpointBytes + 1);
    let size = 0;
    while (size < buffer.length) {
      const {bytesRead} = await file.read(buffer, size, buffer.length - size, size);
      if (!bytesRead) break;
      size += bytesRead;
    }
    if (size > maxCheckpointBytes) throw integrity();
    const value = z.object({checkpoint: checkpointSchema, hmac: hashSchema}).strict().parse(JSON.parse(buffer.subarray(0, size).toString('utf8')));
    if (value.checkpoint.streamEpoch !== stream || !validMac(key, JSON.stringify(value.checkpoint), value.hmac)) throw integrity();
    return value.checkpoint;
  } catch {throw integrity();} finally {await file.close();}
}
async function writeCheckpoint(filename: string, key: string, checkpoint: StoredCheckpoint) {
  const temporary = filename + '.' + randomUUID() + '.tmp';
  const canonical = checkpointSchema.parse(checkpoint);
  try {
    const file = await open(temporary, 'wx', 0o600);
    try {await file.writeFile(JSON.stringify({checkpoint: canonical, hmac: mac(key, JSON.stringify(canonical))}), 'utf8'); await file.sync();}
    finally {await file.close();}
    await rename(temporary, filename);
    await syncDirectory(path.dirname(filename));
  } finally {
    await unlink(temporary).catch(error => {if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;});
  }
}
const lockOwnerSchema = z.object({pid: z.number().int().positive().max(2147483647), hostname: z.string().min(1).max(255),
  processStart: z.string().datetime().optional(), token: z.string().uuid(), acquiredAt: z.string().datetime()}).strict();
const processStart = new Date(Date.now() - process.uptime() * 1000).toISOString();
interface LedgerLock {file: FileHandle; token: string}
function refuseLock(reason: 'alive' | 'foreign-host' | 'unparsable' | 'contended'): never {
  console.warn('Guest ledger lock refused: ' + reason);
  throw new GuestLedgerLockError();
}
async function readLockOwner(filename: string) {
  try {
    const file = await open(filename, 'r');
    try {
      const buffer = Buffer.alloc(1025);
      let size = 0;
      while (size < buffer.length) {
        const {bytesRead} = await file.read(buffer, size, buffer.length - size, size);
        if (!bytesRead) break;
        size += bytesRead;
      }
      if (size > 1024) return null;
      return lockOwnerSchema.parse(JSON.parse(buffer.subarray(0, size).toString('utf8')));
    } finally {await file.close();}
  } catch {return null;}
}
async function createLock(filename: string): Promise<LedgerLock> {
  const file = await open(filename, 'wx', 0o600), token = randomUUID();
  try {
    await file.writeFile(JSON.stringify({pid: process.pid, hostname: hostname(), processStart, token, acquiredAt: new Date().toISOString()}), 'utf8');
    await file.sync();
    return {file, token};
  } catch (error) {await file.close(); throw error;}
}
async function acquireLock(directory: string): Promise<LedgerLock> {
  const filename = path.join(directory, '.guest-ledger.lock');
  try {return await createLock(filename);}
  catch (error) {if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error;}
  const owner = await readLockOwner(filename);
  if (!owner) return refuseLock('unparsable');
  if (owner.hostname !== hostname()) return refuseLock('foreign-host');
  let dead = false;
  try {process.kill(owner.pid, 0);}
  catch (error) {dead = (error as NodeJS.ErrnoException).code === 'ESRCH';}
  if (!dead) return refuseLock('alive');
  // All contenders for this owner reserve the same audit path, so a delayed loser cannot rename a new writer's lock.
  const stale = filename + '.stale-' + new Date(owner.acquiredAt).toISOString().replace(/[:.]/g, '-') + '-' + owner.token;
  try {
    const reservation = await open(stale, 'wx', 0o600);
    await reservation.close();
    await rename(filename, stale);
    await syncDirectory(directory);
    return await createLock(filename);
  } catch (error) {
    if (['EEXIST', 'ENOENT'].includes((error as NodeJS.ErrnoException).code ?? '')) return refuseLock('contended');
    throw error;
  }
}
async function releaseLock(directory: string, lock: LedgerLock) {
  await lock.file.close();
  const filename = path.join(directory, '.guest-ledger.lock');
  if ((await readLockOwner(filename))?.token === lock.token) {
    await unlink(filename).catch(error => {if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;});
  }
}
function validateConfig(directory: string, key: string, stream: string) {
  z.string().uuid().parse(stream);
  if (!path.isAbsolute(directory) || key.length < 32) throw new Error('Ledger requires an absolute directory and a >=32 character HMAC key');
}

/** Normal reopen verifies only the signed checkpoint anchor and at most one uncertain batch. */
export class JsonlLedgerSink implements GuestLedgerSink {
  private file?: FileHandle;
  private lock?: LedgerLock;
  private tail: StoredCheckpoint;
  constructor(private readonly directory: string, private readonly hmacKey: string, readonly streamEpoch: string) {
    validateConfig(directory, hmacKey, streamEpoch);
    this.tail = empty(streamEpoch);
  }
  private get filename() {return path.join(this.directory, this.streamEpoch + '.jsonl');}
  private get checkpointFile() {return path.join(this.directory, this.streamEpoch + '.checkpoint.json');}
  private async initialize() {
    if (this.file) return;
    try {
      if (!(await stat(this.directory)).isDirectory()) throw new Error('Ledger directory unavailable');
      this.lock = await acquireLock(this.directory);
      this.file = await open(this.filename, 'a+', 0o600);
      const size = (await this.file.stat()).size;
      const saved = await readCheckpoint(this.checkpointFile, this.hmacKey, this.streamEpoch);
      this.tail = saved ?? empty(this.streamEpoch);
      if (size < this.tail.offset) throw new Error('Ledger integrity: checkpoint regressed or truncated');
      if (this.tail.sequence) {
        let anchors = 0;
        for await (const {record} of records(this.filename, this.tail.lastRecordOffset, this.tail.offset)) {
          verifyRecord(record, this.hmacKey, this.streamEpoch);
          if (++anchors !== 1 || record.event.sequence !== this.tail.sequence || record.hash !== this.tail.hash) throw integrity();
        }
        if (anchors !== 1) throw integrity();
      } else if (this.tail.offset !== 0 || this.tail.hash !== zeroHash) throw integrity();
      if (size - this.tail.offset > replayWindow * (maxRecordBytes + 1)) throw new Error('Ledger recovery exceeds one batch; run explicit verification');
      let recovered = 0;
      for await (const {record, start, end} of records(this.filename, this.tail.offset, size)) {
        if (++recovered > replayWindow) throw new Error('Ledger recovery exceeds one batch; run explicit verification');
        verifyRecord(record, this.hmacKey, this.streamEpoch);
        if (record.previousHash !== this.tail.hash) throw integrity();
        accept(this.tail, record.event, record.hash, start, end);
      }
      await this.file.sync();
      if (!saved || recovered) await writeCheckpoint(this.checkpointFile, this.hmacKey, this.tail);
    } catch (error) {await this.close(); throw error;}
  }
  async checkpoint(): Promise<LedgerCheckpoint> {
    await this.initialize();
    return {sequence: this.tail.sequence, hash: this.tail.hash, coveredAt: this.tail.coveredAt};
  }
  async append(events: readonly LifecycleEvent[]) {
    if (events.length > replayWindow) throw new Error('Ledger batch exceeds replay window');
    await this.initialize();
    let changed = false;
    try {
      for (const value of events) {
        const event = lifecycleEventSchema.parse(value);
        if (event.streamEpoch !== this.streamEpoch) throw new Error('Ledger stream mismatch');
        if (event.sequence <= this.tail.sequence) {
          const previous = this.tail.recent.find(item => item.sequence === event.sequence);
          if (!previous) throw new Error('Ledger replay outside checkpoint window; reconciliation required');
          if (previous.fingerprint !== fingerprint(event)) throw new Error('Ledger replay mismatch');
          continue;
        }
        if (event.sequence !== this.tail.sequence + 1) throw new Error('Ledger sequence gap');
        const hash = digest(this.tail.hash, event);
        const line = JSON.stringify({event, previousHash: this.tail.hash, hash, hmac: mac(this.hmacKey, hash)}) + '\n';
        if (Buffer.byteLength(line) > maxRecordBytes + 1) throw integrity();
        await this.file!.writeFile(line, 'utf8');
        accept(this.tail, event, hash, this.tail.offset, this.tail.offset + Buffer.byteLength(line));
        changed = true;
      }
      if (changed) {await this.file!.sync(); await writeCheckpoint(this.checkpointFile, this.hmacKey, this.tail);}
    } catch (error) {await this.close(); throw error;}
  }
  async close() {
    try {await this.file?.close();} finally {
      this.file = undefined;
      if (this.lock) {
        const lock = this.lock; this.lock = undefined;
        await releaseLock(this.directory, lock);
      }
    }
  }
}

/** Explicit offline audit; rebuilds its signed checkpoint only after verifying every record. */
export async function verifyGuestLedger(directory: string, key: string, streamEpoch: string): Promise<LedgerCheckpoint> {
  validateConfig(directory, key, streamEpoch);
  const lock = await acquireLock(directory), checkpoint = empty(streamEpoch);
  try {
    const filename = path.join(directory, streamEpoch + '.jsonl'), size = (await stat(filename)).size;
    for await (const {record, start, end} of records(filename, 0, size)) {
      verifyRecord(record, key, streamEpoch);
      if (record.previousHash !== checkpoint.hash) throw integrity();
      accept(checkpoint, record.event, record.hash, start, end);
    }
    const saved = await readCheckpoint(path.join(directory, streamEpoch + '.checkpoint.json'), key, streamEpoch);
    if (saved && (saved.sequence > checkpoint.sequence || saved.offset > checkpoint.offset)) throw integrity();
    const file = await open(filename, 'r+');
    try {await file.sync();} finally {await file.close();}
    await writeCheckpoint(path.join(directory, streamEpoch + '.checkpoint.json'), key, checkpoint);
    return {sequence: checkpoint.sequence, hash: checkpoint.hash, coveredAt: checkpoint.coveredAt};
  } finally {await releaseLock(directory, lock);}
}
