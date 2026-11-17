import {ClientSession, Types} from 'mongoose';
import {User} from '../models/User.model';
import {guestRetentionStatus, GUEST_RETENTION_MS} from './guest-retention.service';
import {isSyntheticCanary} from './synthetic-canary.service';
import {loadChainTransition} from './session-chain.service';

export function cleanupScanFilter(now: Date) {
  return {isGuest: true, guestConvertedAt: {$exists: false},
    $or: [{guestGrantedAt: {$lte: new Date(+now - GUEST_RETENTION_MS)}}, {guestGrantedAt: null}]};
}
export async function syntheticCleanupExempt(userId: Types.ObjectId, now: Date) {
  if (!await isSyntheticCanary(userId)) return false;
  try {
    const transition = await loadChainTransition();
    return !!transition && transition.sunsetAt instanceof Date && Number.isFinite(+transition.sunsetAt) && +now < +transition.sunsetAt + 1800000;
  } catch {return false;}
}
/** Metadata only; the same server evaluator gates status/conversion and physical expiry. */
export async function cleanupClassification(userId: Types.ObjectId, now: Date, session?: ClientSession) {
  const user = await User.findById(userId).select('isGuest guestConvertedAt').session(session ?? null).lean();
  if (!user?.isGuest || user.guestConvertedAt) return {category: 'converted_permanent_skipped' as const, deadline: null};
  const status = await guestRetentionStatus(userId, session, now);
  const deadline = status.dataRetainedUntil ?? null;
  if (!deadline || +now < +deadline) return {category: 'not_due' as const, deadline};
  if (await syntheticCleanupExempt(userId, now)) return {category: 'synthetic_exempt' as const, deadline};
  return {category: status.startedAt ? 'ordinary_expired' as const : 'legacy_unknown' as const, deadline};
}
