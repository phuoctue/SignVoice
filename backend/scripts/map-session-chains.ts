import mongoose, { Types } from 'mongoose';
import { createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { AuthSession } from '../src/models/AuthSession.model';
import { User } from '../src/models/User.model';
import { SessionChain, ISessionChain } from '../src/models/SessionChain.model';
import { chainWriteConcern, readChainTransitionRecord, tombstoneChain, validChainId, validateChain } from '../src/services/session-chain.service';
import { sessionEpoch } from '../src/services/session-fence.service';

export interface MapperPolicy {
  transitionId: string;
  allStopped: true;
  maxDurationMs: number;
  /** Operator-approved app-DB ledger namespace, pinned across retries; no grants are provisioned here. */
  ledgerCollection: string;
  caps: {users: number; units: number; guests: number; guestUnits: number};
  baseline: {users: number; units: number};
  impactFraction: number;
}
interface Ledger {
  _id: string;
  policyHash: string;
  revision: number;
  users: string[];
  units: string[];
  guests: string[];
  guestUnits: string[];
}
type Raw = Record<string, any>;
type Checkpoint = (point: 'root' | 'stamp' | 'reserved' | 'tombstone') => Promise<void>;

/** Production execution is deliberately unavailable in this implementation task. */
export function assertMapperTarget(uri: string, operatorTarget = false): void {
  if (operatorTarget) throw new Error('Non-loopback operator execution is not implemented');
  const parsed = new URL(uri);
  if (parsed.protocol !== 'mongodb:' || !['127.0.0.1', 'localhost', '[::1]'].includes(parsed.hostname) ||
      parsed.username || parsed.password || !/^\/signvoice_test_[a-z0-9_]+$/i.test(parsed.pathname) ||
      /[,\/]/.test(parsed.host) || [...parsed.searchParams.keys()].some(key => /^proxy/i.test(key))) {
    throw new Error('Mapper requires an explicit loopback signvoice_test_* target');
  }
}
function validatePolicy(policy: MapperPolicy) {
  if (!policy || !policy.transitionId?.trim() || policy.allStopped !== true ||
      typeof policy.ledgerCollection !== 'string' || !/^[a-zA-Z0-9_-]+$/.test(policy.ledgerCollection) ||
      [AuthSession.collection.name, SessionChain.collection.name, User.collection.name].includes(policy.ledgerCollection) ||
      !Number.isSafeInteger(policy.maxDurationMs) || policy.maxDurationMs <= 0 ||
      !Number.isFinite(policy.impactFraction) || policy.impactFraction <= 0 || policy.impactFraction > 1 ||
      !policy.caps || !policy.baseline ||
      ![...Object.values(policy.caps), ...Object.values(policy.baseline)].every(n => Number.isSafeInteger(n) && n >= 0) ||
      Object.keys(policy.caps).sort().join() !== 'guestUnits,guests,units,users' ||
      Object.keys(policy.baseline).sort().join() !== 'units,users') throw new Error('Explicit approved mapper policy required');
}
function bindingValid(row: Raw): boolean {
  try {
    return row.userId instanceof Types.ObjectId && validChainId(row.sessionFamily) &&
      ['ACCESS', 'REFRESH'].includes(row.sessionType) && /^[a-f0-9]{64}$/.test(row.tokenHash) &&
      Number.isSafeInteger(row.passwordVersion) && row.passwordVersion >= 0 &&
      Number.isSafeInteger(sessionEpoch(row.userEpoch)) &&
      (row.authenticatedAt === undefined || row.authenticatedAt instanceof Date && Number.isFinite(+row.authenticatedAt));
  } catch { return false; }
}
/** Stable stopped data is rescanned on every retry; no checkpoint grants authority. */
export async function mapSessionChains(uri: string, policy: MapperPolicy, now: Date, checkpoint?: Checkpoint,
  monotonicNow = () => performance.now()) {
  assertMapperTarget(uri);
  validatePolicy(policy);
  const started = monotonicNow();
  const checkBudget = () => {
    const elapsed = monotonicNow() - started;
    if (!Number.isFinite(elapsed) || elapsed < 0 || elapsed >= policy.maxDurationMs) throw new Error('Mapper time budget exhausted; abort before next mutation');
  };
  if (!(now instanceof Date) || !Number.isFinite(+now) || mongoose.connection.readyState !== 1) throw new Error('Mapper requires a connected test database and explicit UTC');
  const connected = mongoose.connection;
  const target = new URL(uri);
  if (!['127.0.0.1', 'localhost', '::1'].includes(connected.host) || connected.name !== target.pathname.slice(1)) {
    throw new Error('Mapper connection does not match the checked loopback target');
  }
  if (await readChainTransitionRecord()) {
    throw new Error('Mapping is forbidden after activation');
  }
  await SessionChain.init();
  const active = await AuthSession.collection.find({status: 'ACTIVE', expiresAt: {$gt: now}}).toArray();
  const groups = new Map<string, Raw[]>();
  for (const row of active) {
    const key = row.userId instanceof Types.ObjectId && validChainId(row.sessionFamily)
      ? `${row.userId}:${row.sessionFamily}` : `unresolved:${row._id}`;
    if (!groups.has(key)) groups.set(key, row.userId instanceof Types.ObjectId && validChainId(row.sessionFamily)
      ? await AuthSession.collection.find({userId: row.userId, sessionFamily: row.sessionFamily}).toArray() : [row]);
  }
  const liveUsers = new Set(active.map(row => String(row.userId)));
  const validRoots = new Set<string>();
  for (const row of await SessionChain.collection.find({}).toArray()) {
    try { validateChain(row as unknown as ISessionChain, row.userId, row.chainId); validRoots.add(`${row.userId}:${row.chainId}`); }
    catch { /* Malformed records are never an observed valid unit. */ }
  }
  const rowUnit = (row: Raw) => validRoots.has(`${row.userId}:${row.chainId}`)
    ? `${row.userId}:root:${row.chainId}` : validChainId(row.sessionFamily)
      ? `${row.userId}:pair:${row.sessionFamily}` : `unresolved:${row._id}`;
  const liveUnits = new Set(active.map(rowUnit));
  const limits = {...policy.caps,
    users: Math.min(policy.caps.users, Math.floor(Math.min(policy.baseline.users, liveUsers.size) * policy.impactFraction)),
    units: Math.min(policy.caps.units, Math.floor(Math.min(policy.baseline.units, liveUnits.size) * policy.impactFraction)),
  };
  const ledgers = connected.db!.collection<Ledger>(policy.ledgerCollection);
  const policyHash = createHash('sha256').update(JSON.stringify([policy.transitionId, policy.ledgerCollection, policy.caps.users,
    policy.caps.units, policy.caps.guests, policy.caps.guestUnits, policy.baseline.users,
    policy.baseline.units, policy.impactFraction])).digest('hex');
  checkBudget();
  try { await ledgers.insertOne({_id: policy.transitionId, policyHash, revision: 0, users: [], units: [], guests: [], guestUnits: []}, {writeConcern: chainWriteConcern}); }
  catch (error: any) { if (error.code !== 11000) throw error; }
  let ledger = (await ledgers.findOne({_id: policy.transitionId}, {readConcern: {level: 'majority'}}))!;
  const within = (row: Ledger) => (['users', 'units', 'guests', 'guestUnits'] as const).every(key => row[key].length <= limits[key]);
  if (ledger.policyHash !== policyHash || !within(ledger)) throw new Error('Mapper policy changed or cumulative impact exceeds tightened limits');
  const result = {groups: 0, mappedRows: 0, quarantinedRows: 0, inactiveGroups: 0, reasons: {} as Record<string, number>};
  const expectedMarkers = new Map<string, boolean>();
  for (const rows of groups.values()) {
    checkBudget();
    result.groups++;
    const first = rows[0];
    const user = first.userId instanceof Types.ObjectId ? await User.findById(first.userId).select('+sessionRevocationEpoch').lean() : null;
    let reason: string | undefined;
    if (!rows.every(bindingValid)) reason = 'binding';
    if (rows.filter(row => row.sessionType === 'ACCESS').length > 1 || rows.filter(row => row.sessionType === 'REFRESH').length > 1) reason = 'duplicate';
    const eligible = user?.status === 'ACTIVE' && rows.some(row => bindingValid(row) && row.status === 'ACTIVE' && row.expiresAt > now &&
      row.passwordVersion === user.passwordVersion && sessionEpoch(row.userEpoch) === sessionEpoch(user.sessionRevocationEpoch));
    if (!reason && !eligible) { result.inactiveGroups++; continue; }
    const stamped = rows.filter(row => row.chainId !== undefined);
    const roots = [...new Set(stamped.map(row => row.chainId))];
    let root: string | undefined;
    let record: ISessionChain | null = null;
    if (roots.length > 1 || roots.some(id => !validChainId(id))) reason = 'conflicting-root';
    else if (roots.length === 1) {
      root = roots[0];
      const stored = await SessionChain.collection.findOne<ISessionChain>({userId: first.userId, chainId: root});
      try {
        record = validateChain(stored, first.userId, root!);
        if (stamped.length !== rows.length && (root !== first.sessionFamily || !record.legacyDerived)) reason = 'partial-provenance';
      } catch { reason = 'missing-or-invalid-record'; }
    } else if (!reason) {
      root = first.sessionFamily;
      const existing = await SessionChain.collection.findOne<ISessionChain>({userId: first.userId, chainId: root});
      if (existing) {
        try { record = validateChain(existing, first.userId, root!); if (!record.legacyDerived) reason = 'own-sid-collision'; }
        catch { reason = 'invalid-record'; }
      } else if (await SessionChain.collection.findOne({chainId: root, userId: {$ne: first.userId}})) {
        reason = 'foreign-root-collision';
      }
    }
    if (reason) {
      // Unknown ownership/guest classification cannot be bounded and therefore cannot mutate.
      if (!user || typeof user.isGuest !== 'boolean') throw new Error('Cannot bound quarantine ownership or guest impact');
      const implicatedRoots: string[] = [];
      for (const id of [...new Set([...roots, ...(root ? [root] : [])])]) {
        if (!validChainId(id)) continue;
        const candidate = await SessionChain.collection.findOne<ISessionChain>({userId: user._id, chainId: id});
        if (candidate) { try { validateChain(candidate, user._id, id); implicatedRoots.push(id); } catch { /* Rows still quarantine; malformed records never gain authority. */ } }
      }
      const implicated = await AuthSession.collection.find({$or: [{_id: {$in: rows.map(row => row._id)}},
        {userId: user._id, chainId: {$in: implicatedRoots}}]}).toArray();
      const implicatedUnits = [...new Set(implicated.map(rowUnit))];
      const next = {...ledger, revision: ledger.revision + 1,
        users: [...new Set([...ledger.users, String(user._id)])], units: [...new Set([...ledger.units, ...implicatedUnits])],
        guests: [...new Set([...ledger.guests, ...(user.isGuest ? [String(user._id)] : [])])],
        guestUnits: [...new Set([...ledger.guestUnits, ...(user.isGuest ? implicatedUnits : [])])],
      };
      if (!within(next)) throw new Error('Quarantine cap would be exceeded; abort before mutation');
      checkBudget();
      const reserved = await ledgers.replaceOne({_id: policy.transitionId, revision: ledger.revision, policyHash}, next, {writeConcern: chainWriteConcern});
      if (!reserved.matchedCount) throw new Error('Concurrent mapper or uncertain reservation; reconcile before continuing');
      ledger = next;
      // Once reserved, finish this quarantine group even if the next budget check will abort.
      await checkpoint?.('reserved');
      for (const id of implicatedRoots) await tombstoneChain(user._id, id);
      await checkpoint?.('tombstone');
      const changed = await AuthSession.collection.updateMany({_id: {$in: implicated.map(row => row._id)}, status: {$ne: 'REVOKED'}},
        [{$set: {status: 'REVOKED', revokedAt: {$ifNull: ['$revokedAt', now]}}}], {writeConcern: chainWriteConcern});
      result.quarantinedRows += changed.modifiedCount;
      result.reasons[reason] = (result.reasons[reason] || 0) + 1;
      continue;
    }
    if (!record) {
      checkBudget();
      try { await SessionChain.collection.insertOne({userId: first.userId, chainId: root,
        legacyDerived: true, status: 'ACTIVE', guardRevision: 0}, {writeConcern: chainWriteConcern}); }
      catch (error: any) { if (error.code !== 11000) throw error; }
      record = validateChain(await SessionChain.collection.findOne<ISessionChain>({userId: first.userId, chainId: root}), first.userId, root!);
      if (!record.legacyDerived) throw new Error('Concurrent root collision; abort mapping');
    }
    await checkpoint?.('root');
    expectedMarkers.set(`${first.userId}:${root}`, record.legacyDerived);
    for (const row of rows) {
      if (row.chainId !== undefined) continue;
      checkBudget();
      const changed = await AuthSession.collection.updateOne({_id: row._id, chainId: {$exists: false},
        userId: row.userId, sessionFamily: row.sessionFamily, tokenHash: row.tokenHash,
        passwordVersion: row.passwordVersion, userEpoch: row.userEpoch === undefined ? {$exists: false} : row.userEpoch,
        authenticatedAt: row.authenticatedAt === undefined ? {$exists: false} : row.authenticatedAt},
      {$set: {chainId: root}}, {writeConcern: chainWriteConcern});
      if (!changed.matchedCount) {
        const current = await AuthSession.collection.findOne({_id: row._id});
        if (current && current.chainId !== root) throw new Error('Mapping CAS conflict; abort');
      }
      result.mappedRows += changed.modifiedCount;
      await checkpoint?.('stamp');
    }
  }
  const originalIds = new Set(active.map(row => String(row._id)));
  checkBudget();
  for (const row of await AuthSession.collection.find({status: 'ACTIVE', expiresAt: {$gt: now}}).toArray()) {
    if (!originalIds.has(String(row._id))) throw new Error('Unknown writer invalidated the all-stopped barrier');
    const user = row.userId instanceof Types.ObjectId ? await User.findById(row.userId).select('+sessionRevocationEpoch').lean() : null;
    if (!bindingValid(row) || !user) throw new Error('Unclassified mapping candidate');
    if (user.status !== 'ACTIVE' || row.passwordVersion !== user.passwordVersion ||
        sessionEpoch(row.userEpoch) !== sessionEpoch(user.sessionRevocationEpoch)) continue;
    if (!validChainId(row.chainId)) throw new Error('Unclassified mapping candidate');
    const record = validateChain(await SessionChain.collection.findOne<ISessionChain>({userId: row.userId, chainId: row.chainId}), row.userId, row.chainId);
    const expected = expectedMarkers.get(`${row.userId}:${row.chainId}`);
    if (expected !== undefined && record.legacyDerived !== expected) throw new Error('Mapper provenance changed');
  }
  checkBudget();
  return {...result, cumulative: {users: ledger.users.length, units: ledger.units.length,
    guests: ledger.guests.length, guestUnits: ledger.guestUnits.length}};
}

if (require.main === module) {
  // Arguments are explicit: no environment file, inherited DB URI or default caps.
  const [uri, policyJson] = process.argv.slice(2);
  (async () => {
    assertMapperTarget(uri, process.argv.includes('--operator-target'));
    const policy = JSON.parse(policyJson) as MapperPolicy;
    validatePolicy(policy);
    await mongoose.connect(uri, {serverSelectionTimeoutMS: 5000});
    try { console.log(JSON.stringify(await mapSessionChains(uri, policy, new Date()))); }
    finally { await mongoose.disconnect(); }
  })().catch(() => { console.error('Session chain mapping aborted; reconcile protected ledger before retry'); process.exitCode = 1; });
}
