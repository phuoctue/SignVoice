import mongoose, {ClientSession, Types} from 'mongoose';
import {randomUUID} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {CleanupControl, GuestCleanupControl, validCleanupControl} from '../models/GuestCleanupControl.model';
import {User} from '../models/User.model';
import {env} from '../config/env';
import {authClock} from './auth-clock';
import {guestRetentionStatus} from './guest-retention.service';
import {cleanupClassification, cleanupScanFilter, loadSyntheticCleanupRegistry, syntheticCleanupExempt} from './guest-cleanup-candidates.service';
import {deleteGuestOwnedData, guestDataVersionFilter} from './guest-data.service';
import {sessionEpoch, userEpochFilter} from './session-fence.service';
import {appendGuestEvent, ensureGuestOutbox} from './guest-lifecycle-outbox.service';
import {retryGuestMediaCleanup} from './guest-media-cleanup.service';
import {chainWriteConcern} from './session-chain.service';
import {SyntheticCanaryRegistry} from './synthetic-canary.service';

class CleanupStopped extends Error {}
interface Budget {check: (session?: ClientSession) => Promise<void>; remaining: () => number}
interface Candidate {userId: Types.ObjectId; dataVersion: number}

/** Original candidate version remains pinned across bounded transaction retries. */
async function cleanupExpiredCandidate(candidate: Candidate, budget: Budget, registry: SyntheticCanaryRegistry) {
  const session = await mongoose.startSession();
  let attempts = 0;
  try {
    return await session.withTransaction(async () => {
      if (++attempts > 3) throw new CleanupStopped('Cleanup conflict retry limit');
      await budget.check(session);
      const user = await User.findById(candidate.userId).select('+dataVersion +sessionRevocationEpoch +guestTrialId').session(session);
      if (!user?.isGuest || user.guestConvertedAt || user.dataVersion !== candidate.dataVersion) return 'skipped' as const;
      if (!Number.isSafeInteger(user.dataVersion) || user.dataVersion < 0 || user.dataVersion >= Number.MAX_SAFE_INTEGER) return 'skipped' as const;
      const status = await guestRetentionStatus(user._id, session);
      if (!status.dataRetainedUntil || +authClock.now() < +status.dataRetainedUntil || await syntheticCleanupExempt(user._id, authClock.now(), registry)) return 'skipped' as const;
      const epoch = sessionEpoch(user.sessionRevocationEpoch);
      const lock = await User.updateOne({_id: user._id, isGuest: true, guestConvertedAt: {$exists: false},
        ...guestDataVersionFilter(candidate.dataVersion), ...userEpochFilter(epoch)}, {$inc: {dataVersion: 1}}, {session});
      if (!lock.matchedCount) return 'skipped' as const;
      await deleteGuestOwnedData(user, candidate.dataVersion, epoch, session);
      await appendGuestEvent('EXPIRED_CLEANED', {guestUserId: String(user._id), deadline: status.dataRetainedUntil.toISOString(),
        deletedAt: authClock.now().toISOString(), reason: status.startedAt ? 'ordinary_expired' : 'legacy_unknown', dataVersion: candidate.dataVersion}, session);
      await budget.check(session);
      return 'deleted' as const;
    }, {writeConcern: chainWriteConcern, timeoutMS: Math.max(1, budget.remaining())});
  } finally {await session.endSession();}
}

export async function runGuestCleanup(options: {enabled?: boolean; monotonicNow?: () => number} = {}) {
  const result = {state: 'disabled', considered: 0, deleted: 0, skipped: 0, syntheticExempt: 0, failed: 0,
    pendingCount: 0, oldestPendingAgeMs: 0, pendingCountExact: false};
  if (!(options.enabled ?? env.GUEST_CLEANUP_ENABLED)) return result;
  let registry: SyntheticCanaryRegistry;
  try {registry = await loadSyntheticCleanupRegistry(process.env.GUEST_SYNTHETIC_REGISTRY_FILE);}
  catch (error) {
    result.state = 'failed'; result.failed++;
    const reason = error instanceof Error && error.message === 'SYNTHETIC_TRANSITION_UNAVAILABLE' ? error.message : 'SYNTHETIC_REGISTRY_INVALID';
    console.warn('Guest cleanup ALERT: run aborted before deletion', {reason});
    console.info('Guest cleanup summary', result);
    return result;
  }
  result.state = 'paused';
  const monotonic = options.monotonicNow ?? (() => performance.now()), started = monotonic();
  const remaining = () => {
    const elapsed = monotonic() - started;
    if (!Number.isFinite(elapsed) || elapsed < 0) throw new CleanupStopped('Invalid cleanup clock');
    return Math.max(0, Math.ceil(30000 - elapsed));
  };
  const control = await GuestCleanupControl.findById('guest-cleanup').lean().maxTimeMS(5000);
  if (!validCleanupControl(control) || control.paused) {
    console.warn('Guest cleanup paused: missing, malformed or explicitly paused control; backlog not measured');
    return result;
  }
  const holder = randomUUID(), collection = GuestCleanupControl.collection as unknown as mongoose.mongo.Collection<CleanupControl>;
  const leased = await collection.findOneAndUpdate({_id: 'guest-cleanup', paused: false, version: control.version,
    lease: {$exists: false}},
  [{$set: {lease: {holder, expiresAt: {$add: ['$$NOW', remaining()]}, revision: 0}}}], {returnDocument: 'after', writeConcern: chainWriteConcern, timeoutMS: Math.max(1, remaining())});
  if (!leased) {
    console.warn(control.lease && +control.lease.expiresAt <= +authClock.now()
      ? 'Guest cleanup ALERT: stale run lease; certify the old process stopped before clearing; backlog not measured'
      : 'Guest cleanup lease not acquired; another run or control change; backlog not measured');
    return result;
  }
  result.state = 'running';
  const budget: Budget = {remaining, check: async session => {
    if (remaining() <= 0) throw new CleanupStopped('Cleanup 30s budget exhausted');
    const checked = await collection.findOneAndUpdate({_id: 'guest-cleanup', paused: false, version: control.version, 'lease.holder': holder,
      $expr: {$gt: ['$lease.expiresAt', '$$NOW']}}, {$inc: {'lease.revision': 1}}, {returnDocument: 'after',
      ...(session ? {session} : {writeConcern: chainWriteConcern, timeoutMS: Math.max(1, remaining())})});
    if (!validCleanupControl(checked)) throw new CleanupStopped('Cleanup paused, malformed or lease lost');
  }};
  try {
    await budget.check();
    await ensureGuestOutbox();
    await budget.check();
    // Failed media jobs must progress even when the candidate batch uses the whole budget.
    await retryGuestMediaCleanup(undefined, {check: budget.check});
    await budget.check();
    const now = authClock.now(), filter = cleanupScanFilter(now);
    let rows = await User.find({...filter, ...(control.cursor ? {_id: {$gt: control.cursor}} : {})})
      .select('_id +dataVersion').sort({_id: 1}).hint({isGuest: 1, _id: 1}).limit(25).lean().maxTimeMS(Math.max(1, remaining()));
    if (rows.length < 25 && control.cursor) {
      const wrap = await User.find({...filter, _id: {$lte: control.cursor}}).select('_id +dataVersion')
        .sort({_id: 1}).hint({isGuest: 1, _id: 1}).limit(25 - rows.length).lean().maxTimeMS(Math.max(1, remaining()));
      rows = [...rows, ...wrap];
    }
    for (const row of rows) {
      await budget.check();
      result.considered++;
      try {
        if (await syntheticCleanupExempt(row._id, authClock.now(), registry)) result.syntheticExempt++;
        else if (await cleanupExpiredCandidate({userId: row._id, dataVersion: row.dataVersion ?? 0}, budget, registry) === 'deleted') result.deleted++;
        else result.skipped++;
      } catch (error) {
        if (error instanceof CleanupStopped) throw error;
        result.failed++;
        console.warn('Guest cleanup candidate failed; transaction rolled back or commit uncertain; retry next run');
      }
      await collection.updateOne({_id: 'guest-cleanup', 'lease.holder': holder}, {$set: {cursor: row._id}}, {writeConcern: chainWriteConcern, timeoutMS: Math.max(1, remaining())});
    }
    // Best-effort read-only census shares the same remaining budget.
    const pending = User.find(filter).select('_id').lean().maxTimeMS(Math.max(1, remaining())).cursor();
    try {
      for await (const row of pending) {
        await budget.check();
        const classified = await cleanupClassification(row._id, authClock.now(), undefined, registry);
        if (classified.category === 'ordinary_expired' || classified.category === 'legacy_unknown') {
          result.pendingCount++;
          result.oldestPendingAgeMs = Math.max(result.oldestPendingAgeMs, +authClock.now() - +classified.deadline!);
        }
      }
      result.pendingCountExact = true;
    } finally {await pending.close();}
    result.state = 'finished';
  } catch (error) {
    result.state = error instanceof CleanupStopped ? 'stopped' : 'failed';
    if (!(error instanceof CleanupStopped)) result.failed++;
    console.warn('Guest cleanup stopped; pending census may be incomplete');
  } finally {
    await collection.updateOne({_id: 'guest-cleanup', 'lease.holder': holder}, {$unset: {lease: ''}}, {writeConcern: chainWriteConcern, timeoutMS: 5000});
  }
  if (result.oldestPendingAgeMs > 86400000) console.warn('Guest cleanup ALERT: pending deletion exceeds 24h target');
  if (!result.pendingCountExact) console.warn('Guest cleanup ALERT: pending count/age incomplete; investigate backlog');
  console.info('Guest cleanup summary', result);
  return result;
}

export function startGuestCleanup(enabled = env.GUEST_CLEANUP_ENABLED) {
  let timer: ReturnType<typeof setTimeout> | undefined, active: Promise<unknown> | undefined, stopped = false;
  const tick = () => {
    active = runGuestCleanup({enabled}).catch(() => {console.warn('Guest cleanup unavailable; no completion claimed');}).finally(() => {
      if (!stopped) {timer = setTimeout(tick, 15 * 60 * 1000); timer.unref();}
    });
  };
  if (enabled) {timer = setTimeout(tick, 15 * 60 * 1000); timer.unref();}
  return {stop: async () => {stopped = true; clearTimeout(timer); await active;}};
}
