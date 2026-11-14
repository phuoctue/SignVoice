import {realpath} from 'node:fs/promises';
import path from 'node:path';
import {GuestLifecycleCounter, GuestLifecycleOutbox, lifecycleEventSchema} from '../models/GuestLifecycle.model';
import {appendCoverageBarrier, ensureGuestOutbox} from './guest-lifecycle-outbox.service';
import {authClock} from './auth-clock';
import {env} from '../config/env';
import {JsonlLedgerSink, GuestLedgerSink, GuestLedgerLockError} from './guest-ledger-file.service';
export {JsonlLedgerSink, verifyGuestLedger} from './guest-ledger-file.service';
export type {GuestLedgerSink, LedgerCheckpoint} from './guest-ledger-file.service';
export class GuestLedgerExporter {
  readonly status = {degraded: true, retryMs: 1000, lagMs: 0};
  private active?: Promise<void>;
  constructor(private readonly sink: GuestLedgerSink) {}
  exportOnce(): Promise<void> {
    if (this.active) return this.active;
    this.active = this.exportBatch().finally(() => {this.active = undefined;});
    return this.active;
  }
  async checkLag() {
    const counter = await GuestLifecycleCounter.findById('lifecycle');
    if (!counter || counter.streamEpoch !== this.sink.streamEpoch) throw new Error('Ledger stream fenced or unavailable');
    const oldest = await GuestLifecycleOutbox.findOne({streamEpoch: counter.streamEpoch, sequence: {$gt: counter.exportedSequence}}).sort({sequence: 1});
    this.status.lagMs = oldest ? Math.max(0, +authClock.now() - Date.parse(oldest.committedAt)) : 0;
    if (this.status.lagMs > 60000) {
      this.status.degraded = true;
      console.warn('Guest ledger export lag exceeds 60s; disaster recovery degraded');
    }
    return counter;
  }
  private async exportBatch() {
    try {
      const counter = await this.checkLag();
      const checkpoint = await this.sink.checkpoint();
      if (checkpoint.sequence > counter.sequence) throw new Error('Ledger ahead of database; restore reconciliation required');
      if (checkpoint.sequence < counter.exportedSequence || checkpoint.sequence === counter.exportedSequence &&
          counter.exportedHash && checkpoint.hash !== counter.exportedHash) throw new Error('Ledger checkpoint regressed or truncated');
      // Re-send the acknowledged prefix too when a DB checkpoint lagged a durable external append.
      const from = Math.min(checkpoint.sequence, counter.exportedSequence);
      const rows = await GuestLifecycleOutbox.find({streamEpoch: counter.streamEpoch, sequence: {$gt: from}}).sort({sequence: 1}).limit(100).lean();
      let expected = from + 1;
      const events = rows.map(row => {
        if (row.sequence !== expected++) throw new Error('Outbox sequence gap');
        const {eventId, streamEpoch, sequence, kind, committedAt, payload} = row;
        return lifecycleEventSchema.parse({eventId, streamEpoch, sequence, kind, committedAt, payload});
      });
      if (!events.length && from < counter.sequence) throw new Error('Outbox sequence gap');
      await this.sink.append(events);
      const durable = await this.sink.checkpoint();
      const updated = await GuestLifecycleCounter.updateOne({_id: 'lifecycle', streamEpoch: counter.streamEpoch,
        sequence: {$gte: durable.sequence}}, {$set: {exportedSequence: durable.sequence, exportedHash: durable.hash, coveredAt: durable.coveredAt}});
      if (!updated.matchedCount) throw new Error('Ledger stream fenced');
      this.status.degraded = this.status.lagMs > 60000 && durable.sequence < counter.sequence;
      this.status.retryMs = 1000;
    } catch (error) {
      this.status.degraded = true;
      this.status.retryMs = Math.min(60000, this.status.retryMs * 2);
      console.warn(error instanceof GuestLedgerLockError ? error.message + '; disaster recovery degraded'
        : 'Guest ledger exporter unavailable; disaster recovery degraded');
      throw error;
    }
  }
}

export async function startGuestLedgerExporter(config = {directory: env.GUEST_LEDGER_DIRECTORY, hmacKey: env.GUEST_LEDGER_HMAC_KEY}) {
  const disabled = {status: {degraded: true}, stop: async () => {}};
  let sink: JsonlLedgerSink;
  try {
    if (!config.directory || !config.hmacKey) throw new Error('Missing ledger configuration');
    const resolved = await realpath(config.directory), repository = await realpath(path.resolve(__dirname, '../../..'));
    const relative = path.relative(repository, resolved);
    if (!relative || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) throw new Error('Ledger must be outside repository');
    await ensureGuestOutbox();
    const counter = (await GuestLifecycleCounter.findById('lifecycle'))!;
    sink = new JsonlLedgerSink(resolved, config.hmacKey, counter.streamEpoch);
  } catch {
    console.warn('Guest ledger exporter disabled: external directory/key unavailable; disaster recovery degraded');
    return disabled;
  }
  const exporter = new GuestLedgerExporter(sink);
  let timer: ReturnType<typeof setTimeout> | undefined, stopped = false, running: Promise<void> | undefined;
  let monitoring: Promise<void> | undefined;
  // Monitor independently so a hung filesystem operation cannot silence the lag alarm.
  const monitor = setInterval(() => {
    if (monitoring) return;
    monitoring = exporter.checkLag().then(() => {}, () => {
      exporter.status.degraded = true;
      console.warn('Guest ledger lag monitor unavailable; disaster recovery degraded');
    }).finally(() => {monitoring = undefined;});
  }, 10000);
  monitor.unref();
  const performTick = async () => {
    let barrierHealthy = true;
    try {await appendCoverageBarrier(true);}
    catch {
      barrierHealthy = false;
      exporter.status.degraded = true;
      exporter.status.retryMs = Math.min(60000, exporter.status.retryMs * 2);
      console.warn('Guest ledger barrier unavailable; disaster recovery degraded');
    }
    try {await exporter.exportOnce();} catch { /* exporter logs sanitized failures */ }
    if (!barrierHealthy) exporter.status.degraded = true;
    if (!stopped) {timer = setTimeout(tick, exporter.status.retryMs); timer.unref();}
  };
  const tick = async () => {running = performTick(); await running;};
  // Background only: neither startup nor user acknowledgements wait for the external sink.
  timer = setTimeout(tick, 0); timer.unref();
  return {status: exporter.status, stop: async () => {
    stopped = true; clearTimeout(timer); clearInterval(monitor); await running; await monitoring; await sink.close();
  }};
}
