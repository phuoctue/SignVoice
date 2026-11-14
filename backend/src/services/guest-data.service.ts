import mongoose, {ClientSession, Types} from 'mongoose';
import {User, AccountStatus} from '../models/User.model';
import {AuthSession, SessionStatus} from '../models/AuthSession.model';
import {SessionChain} from '../models/SessionChain.model';
import {AppError} from '../common/errors/AppError';
import {assertSessionEpoch, sessionEpoch, userEpochFilter} from './session-fence.service';
import {assertChainDeadline, assertSessionChain, chainWriteConcern, loadChainTransition, tombstoneChain} from './session-chain.service';
import {guestTrialStatus} from './guest-trial.service';
import {clearOwnedData} from './user-data.service';
import {appendGuestEvent, ensureGuestOutbox} from './guest-lifecycle-outbox.service';
import {authClock} from './auth-clock';
import {AuditLog} from '../models/AuditLog.model';
import {GuestTrial} from '../models/GuestTrial.model';
import {GuestMediaCleanup} from '../models/GuestMediaCleanup.model';
import {ownedAvatarPath} from './avatar-media.service';
import {retryGuestMediaCleanup} from './guest-media-cleanup.service';

const invalid = () => new AppError('Current guest session required.', 401, 'AUTH_SESSION_INVALID');
const stale = () => new AppError('Guest data changed. Please confirm again.', 409, 'GUEST_DATA_CHANGED');
// Historical rows without the field use the existing schema's version-zero default.
export const guestDataVersionFilter = (version: number) => ({dataVersion: version === 0 ? {$in: [0, null]} : version});
export async function pinGuestAuthority(userId: Types.ObjectId, sessionId: Types.ObjectId) {
  const user = await User.findById(userId).select('+sessionRevocationEpoch +dataVersion');
  const caller = await AuthSession.findOne({_id: sessionId, userId});
  if (!user?.isActive() || !caller?.isValid() || caller.passwordVersion !== user.passwordVersion) throw invalid();
  if (!user.canConvertFromGuest()) throw stale();
  assertSessionEpoch(caller, user);
  await assertSessionChain(caller);
  return {userId, sessionId, epoch: sessionEpoch(caller.userEpoch), chainId: caller.chainId, passwordVersion: caller.passwordVersion};
}
export type GuestAuthority = Awaited<ReturnType<typeof pinGuestAuthority>>;

/** Caller predicates stay pinned across transaction retries; a device key never identifies this target. */
export async function discardGuestInTransaction(authority: GuestAuthority, expectedDataVersion: number, session: ClientSession, replacement = false) {
  const {userId, sessionId, epoch} = authority;
  const user = await User.findById(userId).select('+sessionRevocationEpoch +dataVersion +guestTrialId').session(session);
  const caller = await AuthSession.findOne({_id: sessionId, userId}).session(session);
  if (!user?.isActive() || !caller?.isValid() || caller.chainId !== authority.chainId ||
      caller.passwordVersion !== authority.passwordVersion || user.passwordVersion !== authority.passwordVersion ||
      sessionEpoch(caller.userEpoch) !== epoch) throw invalid();
  if (!user.canConvertFromGuest() || user.dataVersion !== expectedDataVersion) throw stale();
  assertSessionEpoch(caller, user);
  const {chain} = await assertSessionChain(caller, session);
  const status = await guestTrialStatus(userId, session);
  if (replacement && status.dataState === 'legacy_unknown') throw new AppError('Discard this legacy guest separately first.', 409, 'GUEST_LEGACY_REPLACEMENT_DENIED');
  if (!status.allowedActions?.includes('discard')) throw stale();
  const locked = await User.updateOne({_id: userId, isGuest: true, guestConvertedAt: {$exists: false},
    status: AccountStatus.ACTIVE, ...guestDataVersionFilter(expectedDataVersion), ...userEpochFilter(epoch)}, {$inc: {dataVersion: 1}}, {session});
  if (!locked.matchedCount) throw stale();
  if (user.guestTrialId) {
    // A disappearing binding must never make another legacy guest's anchor look proven.
    await GuestTrial.collection.updateOne({_id: user.guestTrialId, lastGrantRequestHash: {$exists: false},
      legacyFallbackDisabledAt: {$exists: false}}, {$set: {legacyFallbackDisabledAt: authClock.now()}}, {session});
  }
  await clearOwnedData(userId, session);
  await AuditLog.deleteMany({$or: [{userId}, {resourceType: 'User', resourceId: userId}]}, {session});
  await GuestMediaCleanup.create([{_id: String(userId), paths: [ownedAvatarPath(String(userId))], createdAt: authClock.now()}], {session});
  const roots = await SessionChain.find({userId}).session(session);
  for (const root of roots) await tombstoneChain(userId, root.chainId, session);
  await AuthSession.updateMany({userId, status: SessionStatus.ACTIVE}, {$set: {status: SessionStatus.REVOKED, revokedAt: authClock.now()}}, {session});
  const deleted = await User.deleteOne({_id: userId, isGuest: true, guestConvertedAt: {$exists: false},
    dataVersion: expectedDataVersion + 1, ...userEpochFilter(epoch)}, {session});
  if (!deleted.deletedCount) throw stale();
  await appendGuestEvent('DISCARDED', {guestUserId: String(userId), guestGrantedAt: status.startedAt?.toISOString() ?? null,
    dataVersion: expectedDataVersion, committedAt: authClock.now().toISOString()}, session);
  return async () => {
    const transition = await loadChainTransition();
    if (chain) assertChainDeadline(chain, transition);
    else if (transition) throw invalid();
    if (!caller.isValid()) throw invalid();
  };
}
export async function discardGuest(userId: Types.ObjectId, sessionId: Types.ObjectId, expectedDataVersion: number) {
  const authority = await pinGuestAuthority(userId, sessionId);
  await ensureGuestOutbox();
  await mongoose.connection.transaction(async session => {
    const finalFence = await discardGuestInTransaction(authority, expectedDataVersion, session);
    await finalFence();
  }, {writeConcern: chainWriteConcern});
  await retryGuestMediaCleanup(String(userId));
}
