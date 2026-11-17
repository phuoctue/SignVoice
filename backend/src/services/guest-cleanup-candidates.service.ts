import {ClientSession, Types} from 'mongoose';
import {User} from '../models/User.model';
import {guestRetentionStatus, GUEST_RETENTION_MS} from './guest-retention.service';
import {isSyntheticCanary, loadSyntheticCanaryRegistry, syntheticCanaryRegistry, SyntheticCanaryRegistry} from './synthetic-canary.service';
import {loadChainTransition} from './session-chain.service';

export function cleanupScanFilter(now: Date) {
  return {isGuest: true, guestConvertedAt: {$exists: false},
    $or: [{guestGrantedAt: {$lte: new Date(+now - GUEST_RETENTION_MS)}}, {guestGrantedAt: null}]};
}
/** Validate control once before any writes, even if the registered guest is not a candidate. */
export async function loadSyntheticCleanupRegistry(file: string | undefined): Promise<SyntheticCanaryRegistry> {
  const registry = await loadSyntheticCanaryRegistry(file);
  if (!registry.hasActiveGuests) return registry;
  try {
    const transition = await loadChainTransition();
    if (transition !== null && (!(transition.sunsetAt instanceof Date) || !Number.isFinite(+transition.sunsetAt))) throw new Error();
    return {...registry, cleanupExemptUntil: transition === null ? Infinity : +transition.sunsetAt + 1800000};
  } catch {throw new Error('SYNTHETIC_TRANSITION_UNAVAILABLE');}
}
export async function syntheticCleanupExempt(userId: Types.ObjectId, now: Date, registry = syntheticCanaryRegistry) {
  if (!await isSyntheticCanary(userId, registry)) return false;
  if (registry.cleanupExemptUntil !== undefined) return +now < registry.cleanupExemptUntil;
  const transition = await loadChainTransition();
  return transition === null || transition.sunsetAt instanceof Date && Number.isFinite(+transition.sunsetAt) && +now < +transition.sunsetAt + 1800000;
}
/** Metadata only; the same server evaluator gates status/conversion and physical expiry. */
export async function cleanupClassification(userId: Types.ObjectId, now: Date, session?: ClientSession, registry = syntheticCanaryRegistry) {
  const user = await User.findById(userId).select('isGuest guestConvertedAt').session(session ?? null).lean();
  if (!user?.isGuest || user.guestConvertedAt) return {category: 'converted_permanent_skipped' as const, deadline: null};
  const status = await guestRetentionStatus(userId, session, now);
  const deadline = status.dataRetainedUntil ?? null;
  if (!deadline || +now < +deadline) return {category: 'not_due' as const, deadline};
  if (await syntheticCleanupExempt(userId, now, registry)) return {category: 'synthetic_exempt' as const, deadline};
  return {category: status.startedAt ? 'ordinary_expired' as const : 'legacy_unknown' as const, deadline};
}
