import { createHash, randomUUID } from 'node:crypto';
import mongoose, { ClientSession, Types } from 'mongoose';
import { AuthSession, IAuthSession, SessionStatus } from '../models/AuthSession.model';
import { ISessionChain, SessionChain } from '../models/SessionChain.model';
import { IChainTransition, sessionChainTransitionModel } from '../models/SessionChainTransition.model';
import { AppError } from '../common/errors/AppError';
import { authClock } from './auth-clock';
import { loadSessionUser, sessionEpoch } from './session-fence.service';
import { User, AccountStatus } from '../models/User.model';

export const chainWriteConcern = {w: 'majority' as const, j: true};
const invalid = () => new AppError('Session not found or expired', 401, 'AUTH_SESSION_INVALID');
const integrity = () => new Error('Invalid session chain state');
export function validChainId(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= 200 && value.trim() === value;
}
export function validateChain(row: ISessionChain | null, userId: Types.ObjectId, chainId: string): ISessionChain {
  if (!row || String(row.userId) !== String(userId) || row.chainId !== chainId ||
      typeof row.legacyDerived !== 'boolean' || !['ACTIVE', 'REVOKED'].includes(row.status) ||
      !Number.isSafeInteger(row.guardRevision) || row.guardRevision < 0 ||
      (row.status === 'REVOKED' && (!(row.revokedAt instanceof Date) || !Number.isFinite(+row.revokedAt)))) throw integrity();
  return row;
}
export function transitionDigest(row: IChainTransition): string {
  return createHash('sha256').update(JSON.stringify([
    row._id, row.transitionId, row.policyVersion, row.windowMs, row.clockBudgetMs,
    +row.cutoverAt, +row.sunsetAt,
  ])).digest('hex');
}
let pinnedIdentity: string | undefined;
function positiveInteger(raw: string | undefined): number {
  const value = raw && /^\d+$/.test(raw) ? Number(raw) : NaN;
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error('Invalid session chain policy');
  return value;
}
export function readChainTransitionRecord(): Promise<IChainTransition | null> {
  const collection = sessionChainTransitionModel().collection as unknown as mongoose.mongo.Collection<IChainTransition>;
  return collection.findOne({_id: 'session-chain-transition'}, {
    readPreference: 'primary', readConcern: {level: 'linearizable'}, maxTimeMS: 5000,
  });
}
/** No date fallback or positive cache. This always executes outside a transaction. */
export async function loadChainTransition(): Promise<IChainTransition | null> {
  const mode = process.env.SESSION_CHAIN_MODE;
  if (mode !== 'compat' && mode !== 'enforcement') throw new Error('Explicit session chain mode required');
  const row = await readChainTransitionRecord();
  if (mode === 'compat') {
    if (row || pinnedIdentity || process.env.SESSION_CHAIN_DIGEST || process.env.SESSION_CHAIN_WINDOW_MS ||
        process.env.SESSION_CHAIN_CLOCK_BUDGET_MS) throw new Error('Compatibility requires inactive transition');
    return null;
  }
  const windowMs = positiveInteger(process.env.SESSION_CHAIN_WINDOW_MS);
  const clockBudgetMs = positiveInteger(process.env.SESSION_CHAIN_CLOCK_BUDGET_MS);
  if (!row || !process.env.SESSION_CHAIN_TRANSITION_ID || process.env.SESSION_CHAIN_POLICY_VERSION !== '1' ||
      row.transitionId !== process.env.SESSION_CHAIN_TRANSITION_ID || row.policyVersion !== '1' ||
      row.windowMs !== windowMs || row.clockBudgetMs !== clockBudgetMs ||
      !(row.cutoverAt instanceof Date) || !(row.sunsetAt instanceof Date) ||
      !Number.isSafeInteger(+row.cutoverAt) || !Number.isSafeInteger(+row.sunsetAt) ||
      !Number.isSafeInteger(+row.cutoverAt + windowMs) || +row.sunsetAt !== +row.cutoverAt + windowMs) {
    throw new Error('Invalid session chain transition');
  }
  const identity = transitionDigest(row);
  if (identity !== process.env.SESSION_CHAIN_DIGEST || (pinnedIdentity && identity !== pinnedIdentity)) {
    throw new Error('Session chain transition changed or mismatched');
  }
  pinnedIdentity = identity;
  return row;
}
export function assertChainDeadline(chain: ISessionChain, transition: IChainTransition | null): void {
  if (transition && chain.legacyDerived && +authClock.now() + transition.clockBudgetMs >= +transition.sunsetAt) throw invalid();
}
export async function assertSessionChain(row: Pick<IAuthSession, 'userId' | 'chainId'>, transaction?: ClientSession): Promise<{
  chain: ISessionChain | null; transition: IChainTransition | null;
}> {
  const transition = await loadChainTransition();
  if (row.chainId === undefined) {
    if (transition) throw invalid();
    return {chain: null, transition};
  }
  if (!validChainId(row.chainId)) throw integrity();
  const stored = transaction
    ? await SessionChain.collection.findOne<ISessionChain>({userId: row.userId, chainId: row.chainId}, {session: transaction})
    : await SessionChain.collection.findOne<ISessionChain>({userId: row.userId, chainId: row.chainId}, {
      readPreference: 'primary', readConcern: {level: 'linearizable'}, maxTimeMS: 5000,
    });
  const chain = validateChain(stored, row.userId, row.chainId);
  if (chain.status !== 'ACTIVE') throw invalid();
  assertChainDeadline(chain, transition);
  if (transaction) {
    if (chain.guardRevision === Number.MAX_SAFE_INTEGER) throw integrity();
    const result = await SessionChain.updateOne({userId: row.userId, chainId: row.chainId,
      status: 'ACTIVE', guardRevision: chain.guardRevision}, {$inc: {guardRevision: 1}}, {session: transaction});
    if (!result.matchedCount) throw invalid();
  }
  return {chain, transition};
}
export async function createFreshChain(userId: Types.ObjectId, transaction?: ClientSession): Promise<string> {
  await loadChainTransition();
  const chainId = randomUUID();
  try {
    await SessionChain.collection.insertOne({userId, chainId, legacyDerived: false, status: 'ACTIVE', guardRevision: 0},
      transaction ? {session: transaction} : {writeConcern: chainWriteConcern});
  } catch (error: any) {
    // A duplicate aborts a transaction; outside one, freshly honor any terminal winner.
    if (error.code === 11000 && !transaction) await assertSessionChain({userId, chainId});
    throw error;
  }
  await assertSessionChain({userId, chainId}, transaction);
  return chainId;
}
/** Terminal write precedes physical cleanup, including when creation never completed. */
export async function tombstoneChain(userId: Types.ObjectId, chainId: string, transaction?: ClientSession): Promise<void> {
  if (!validChainId(chainId)) throw integrity();
  const options = transaction ? {session: transaction} : {writeConcern: chainWriteConcern};
  const stored = await SessionChain.collection.findOne<ISessionChain>({userId, chainId}, transaction ? {session: transaction} : {
    readPreference: 'primary', readConcern: {level: 'linearizable'}, maxTimeMS: 5000,
  });
  if (stored) {
    const chain = validateChain(stored, userId, chainId);
    if (chain.status === 'REVOKED') return;
    if (chain.guardRevision === Number.MAX_SAFE_INTEGER) throw integrity();
    await SessionChain.collection.updateOne({userId, chainId, status: 'ACTIVE'}, {
      $set: {status: 'REVOKED', revokedAt: authClock.now()}, $inc: {guardRevision: 1},
    }, options);
  } else {
    try {
      await SessionChain.collection.insertOne({userId, chainId, legacyDerived: true,
        status: 'REVOKED', revokedAt: authClock.now(), guardRevision: 0}, options);
    } catch (error: any) {
      if (error.code !== 11000 || transaction) throw error;
      await tombstoneChain(userId, chainId);
    }
  }
}
export async function revokeSessionChain(target: IAuthSession, transaction?: ClientSession): Promise<void> {
  const transition = await loadChainTransition();
  if (target.chainId !== undefined) {
    await tombstoneChain(target.userId, target.chainId, transaction);
  } else if (transition) {
    throw new AppError('Historical session lineage is unavailable; this request did not revoke a descendant chain.',
      409, 'SESSION_CHAIN_UNRESOLVABLE');
  }
  const filter = target.chainId !== undefined ? {userId: target.userId, chainId: target.chainId}
    : target.sessionFamily ? {userId: target.userId, sessionFamily: target.sessionFamily} : {_id: target._id};
  await AuthSession.updateMany({...filter, status: SessionStatus.ACTIVE}, {
    $set: {status: SessionStatus.REVOKED, revokedAt: authClock.now()},
  }, transaction ? {session: transaction} : {writeConcern: chainWriteConcern});
}
export function sameSessionChain(a: IAuthSession, b: IAuthSession): boolean {
  return a.chainId !== undefined && b.chainId !== undefined ? a.chainId === b.chainId
    : !!a.sessionFamily && a.sessionFamily === b.sessionFamily;
}
export async function deleteOwnedSession(userId: Types.ObjectId, targetId: string, currentId: Types.ObjectId): Promise<boolean> {
  return mongoose.connection.transaction(async transaction => {
    const lock = await User.updateOne({_id: userId, status: AccountStatus.ACTIVE}, {$inc: {dataVersion: 1}}, {session: transaction});
    if (!lock.matchedCount) throw new AppError('Session not found', 404, 'NOT_FOUND');
    const target = await AuthSession.findOne({_id: targetId, userId}).session(transaction);
    if (!target) throw new AppError('Session not found', 404, 'NOT_FOUND');
    const current = await AuthSession.findOne({_id: currentId, userId}).session(transaction);
    await revokeSessionChain(target, transaction);
    return !!current && sameSessionChain(target, current);
  }, {writeConcern: chainWriteConcern});
}
/** Effective validity is computed before callers paginate; errors never become valid rows. */
export async function effectiveSessions(filter: Record<string, unknown> = {}): Promise<IAuthSession[]> {
  await loadChainTransition();
  const rows = await AuthSession.find({...filter, status: SessionStatus.ACTIVE, expiresAt: {$gt: authClock.now()}}).sort({lastUsedAt: -1});
  const effective: IAuthSession[] = [];
  for (const row of rows) {
    const user = await loadSessionUser(row.userId);
    if (!user?.isActive() || row.passwordVersion !== user.passwordVersion ||
        sessionEpoch(row.userEpoch) !== sessionEpoch(user.sessionRevocationEpoch)) continue;
    try { await assertSessionChain(row); effective.push(row); }
    catch (error) { if (!(error instanceof AppError) || error.statusCode !== 401) throw error; }
  }
  return effective;
}
