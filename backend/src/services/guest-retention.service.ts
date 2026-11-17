import {ClientSession, Types} from 'mongoose';
import {GuestTrial} from '../models/GuestTrial.model';
import {User} from '../models/User.model';
import {GuestRetentionActivation} from '../models/GuestRetentionActivation.model';
import {AppError} from '../common/errors/AppError';
import {authClock} from './auth-clock';

export const GUEST_TRIAL_SECONDS = 600;
export const GUEST_COOLDOWN_MS = 86400000;
export const GUEST_RETENTION_MS = 7 * GUEST_COOLDOWN_MS;
export async function guestRetentionStatus(userId: Types.ObjectId, transaction?: ClientSession, at?: Date) {
  const user = await User.findById(userId).select('isGuest status dataVersion createdAt +guestTrialId +guestGrantedAt').session(transaction ?? null);
  if (!user) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_USER_NOT_FOUND');
  if (!user.isGuest) return {accountActive: user.isActive(), state: 'unlimited', serverNow: authClock.now(), durationSeconds: GUEST_TRIAL_SECONDS, remainingSeconds: null, expiresAt: undefined, startedAt: undefined};
  const trial = user.guestTrialId ? await GuestTrial.findById(user.guestTrialId).select('+lastGrantRequestHash').session(transaction ?? null) : null;
  // A v1 grant invalidates mutable legacy dates; it must never unlock an older bound guest.
  let legacyGrant: Date | undefined;
  if (!user.guestGrantedAt && trial?.lastGrantRequestHash === undefined && !trial?.legacyFallbackDisabledAt && trial?.startedAt && +trial.startedAt >= +user.createdAt &&
      await User.countDocuments({guestTrialId: trial._id}).session(transaction ?? null) === 1) {
    // A nontransactional status read may straddle discard; re-check the durable evidence after counting.
    const proven = await GuestTrial.findOne({_id: trial._id, startedAt: trial.startedAt,
      lastGrantRequestHash: {$exists: false}, legacyFallbackDisabledAt: {$exists: false}}).session(transaction ?? null);
    if (proven) legacyGrant = trial.startedAt;
  }
  const now = at ?? authClock.now();
  const startedAt = user.guestGrantedAt ?? legacyGrant;
  const expiresAt = startedAt ? new Date(+startedAt + GUEST_TRIAL_SECONDS * 1000) : undefined;
  const activation = !startedAt ? await GuestRetentionActivation.findById('legacy-retention').session(transaction ?? null).lean() : null;
  if (activation && (!(activation.activatedAt instanceof Date) || !Number.isFinite(+activation.activatedAt))) throw new Error('Invalid legacy activation');
  const dataRetainedUntil = startedAt ? new Date(+startedAt + GUEST_RETENTION_MS)
    : activation ? new Date(+activation.activatedAt + GUEST_RETENTION_MS) : null;
  const nextTrialAvailableAt = trial?.startedAt ? new Date(+trial.startedAt + GUEST_COOLDOWN_MS) : null;
  const remainingSeconds = expiresAt ? Math.max(0, Math.ceil((+expiresAt - +now) / 1000)) : 0;
  const dataState = dataRetainedUntil && +now >= +dataRetainedUntil ? 'expired' : !startedAt ? 'legacy_unknown'
    : remainingSeconds > 0 ? 'trial_active' : 'retained';
  const allowedActions = ['status', 'auth_me', 'refresh', 'logout'];
  if (dataState !== 'expired') allowedActions.push('convert');
  allowedActions.push('discard');
  if (startedAt && nextTrialAvailableAt && +nextTrialAvailableAt <= +now) allowedActions.push('new_trial');
  return {accountActive: user.isActive(), state: remainingSeconds > 0 ? 'active' : 'expired', serverNow: now, startedAt, expiresAt,
    durationSeconds: GUEST_TRIAL_SECONDS, remainingSeconds,
    nextTrialAvailableAt, dataRetainedUntil, dataState, dataVersion: user.dataVersion, allowedActions};
}
export async function guestTrialStatus(userId: Types.ObjectId, transaction?: ClientSession, at?: Date) {
  const {accountActive, ...status} = await guestRetentionStatus(userId, transaction, at);
  if (!accountActive) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_USER_NOT_FOUND');
  return status;
}
