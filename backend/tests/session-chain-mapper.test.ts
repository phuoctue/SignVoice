import {randomBytes, randomUUID} from 'node:crypto';
import mongoose from 'mongoose';
import {afterAll, afterEach, beforeAll, beforeEach, expect, it} from 'vitest';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {env} from '../src/config/env';
import {AuthSession} from '../src/models/AuthSession.model';
import {SessionChain} from '../src/models/SessionChain.model';
import {User} from '../src/models/User.model';
import {assertMapperTarget, mapSessionChains, MapperPolicy} from '../scripts/map-session-chains';

const now = new Date();
const policy: MapperPolicy = {transitionId: 'mapper-fixture', allStopped: true,
  ledgerCollection: 'session_chain_mapper_fixture',
  maxDurationMs: 60000,
  caps: {users: 10, units: 10, guests: 0, guestUnits: 0}, baseline: {users: 10, units: 10}, impactFraction: 1};
beforeAll(async () => {await connectDatabase(); await SessionChain.init();});
beforeEach(async () => {
  await AuthSession.deleteMany({}); await SessionChain.deleteMany({}); await User.deleteMany({});
  await mongoose.connection.db!.collection(policy.ledgerCollection).deleteMany({});
});
afterEach(async () => {
  await mongoose.connection.getClient().db(process.env.SESSION_CHAIN_CONTROL_DB!)
    .collection(process.env.SESSION_CHAIN_CONTROL_COLLECTION!).deleteMany({});
});
afterAll(async () => {
  await mongoose.connection.getClient().db(process.env.SESSION_CHAIN_CONTROL_DB!).dropDatabase();
  await mongoose.connection.dropDatabase(); await disconnectDatabase();
});
async function pair(guest = false) {
  const userId = new mongoose.Types.ObjectId(), sid = randomUUID();
  await User.collection.insertOne({_id: userId, displayName: 'Mapper', isGuest: guest, accountType: guest ? 'GUEST' : 'LOCAL',
    status: 'ACTIVE', role: 'USER', passwordVersion: 0});
  const rows = ['ACCESS', 'REFRESH'].map(sessionType => ({_id: new mongoose.Types.ObjectId(), userId, sessionFamily: sid,
    sessionType, passwordVersion: 0, tokenHash: randomBytes(32).toString('hex'), status: 'ACTIVE',
    authenticatedAt: new Date(1000), expiresAt: new Date(+now + 600000), createdAt: now}));
  await AuthSession.collection.insertMany(rows);
  return {userId, sid, rows};
}
it.each(['mongodb://remote.example/signvoice_test_x', 'mongodb+srv://127.0.0.1/signvoice_test_x',
  'mongodb://user:pass@127.0.0.1/signvoice_test_x', 'mongodb://127.0.0.1/production',
  'mongodb://127.0.0.1,remote.example/signvoice_test_x',
  'mongodb://127.0.0.1/signvoice_test_x?proxyHost=remote.example',
  'mongodb://127.0.0.1/signvoice_test_x?PROXYHOST=127.0.0.1'])('K1 refuses unsafe target %s', uri => {
  expect(() => assertMapperTarget(uri)).toThrow();
});
it('K1 operator override cannot enable a non-loopback run', () => {
  expect(() => assertMapperTarget('mongodb://127.0.0.1/signvoice_test_x', true)).toThrow('not implemented');
});
it('K1 requires explicit caps, impact bounds, a stop certificate, and a matching connection', async () => {
  for (const invalid of [{...policy, caps: undefined}, {...policy, allStopped: false}, {...policy, impactFraction: undefined}]) {
    await expect(mapSessionChains(env.MONGODB_URI, invalid as any, now)).rejects.toThrow('policy');
  }
  await expect(mapSessionChains('mongodb://127.0.0.1/signvoice_test_other', policy, now)).rejects.toThrow('match');
});
it('K1 stamps only the own sid, preserving raw absent epochs and consumed siblings', async () => {
  const {userId, sid, rows} = await pair();
  await AuthSession.collection.updateOne({_id: rows[0]._id}, {$set: {status: 'REVOKED', revokedAt: new Date(2000)}});
  const before = await AuthSession.collection.find({userId}).sort({_id: 1}).toArray();
  const result = await mapSessionChains(env.MONGODB_URI, policy, now);
  expect(result.mappedRows).toBe(2);
  const after = await AuthSession.collection.find({userId}).sort({_id: 1}).toArray();
  expect(after.map(({chainId, ...row}) => row)).toEqual(before);
  expect(after.every(row => row.chainId === sid && row.userEpoch === undefined)).toBe(true);
  expect((await SessionChain.findOne({userId, chainId: sid}))!.legacyDerived).toBe(true);
  expect((await mapSessionChains(env.MONGODB_URI, policy, now)).mappedRows).toBe(0);
});
it.each(['root', 'stamp'] as const)('K1 crash after %s resumes by rescan without rewriting provenance', async pause => {
  const {userId, sid} = await pair();
  let crashed = false;
  await expect(mapSessionChains(env.MONGODB_URI, policy, now, async point => {
    if (point === pause && !crashed) {crashed = true; throw new Error('Injected crash');}
  })).rejects.toThrow('crash');
  const result = await mapSessionChains(env.MONGODB_URI, policy, now);
  expect(result.quarantinedRows).toBe(0);
  expect(await AuthSession.countDocuments({userId, chainId: sid})).toBe(2);
  expect(await SessionChain.countDocuments({userId, chainId: sid})).toBe(1);
});
it('K1 preserves a terminal tombstone and never recreates a TTL-deleted sibling', async () => {
  const {userId, sid, rows} = await pair();
  const revokedAt = new Date(1000);
  await SessionChain.create({userId, chainId: sid, legacyDerived: true, status: 'REVOKED', revokedAt, guardRevision: 0});
  await AuthSession.deleteOne({_id: rows[0]._id});
  await mapSessionChains(env.MONGODB_URI, policy, now);
  expect(await AuthSession.countDocuments({userId})).toBe(1);
  const root = (await SessionChain.findOne({userId, chainId: sid}))!;
  expect(root.status).toBe('REVOKED'); expect(root.revokedAt).toEqual(revokedAt);
});
it('K1 treats an old writer dropping a false root as a new legacy pair', async () => {
  const {userId, sid} = await pair();
  await SessionChain.create({userId, chainId: randomUUID(), legacyDerived: false, status: 'ACTIVE', guardRevision: 0});
  await mapSessionChains(env.MONGODB_URI, policy, now);
  expect((await SessionChain.findOne({userId, chainId: sid}))!.legacyDerived).toBe(true);
});
it.each(['duplicate', 'conflict', 'missing-record', 'collision', 'marker'] as const)('K1 quarantines %s as REVOKED without data mutation', async kind => {
  const {userId, sid, rows} = await pair();
  if (kind === 'duplicate') await AuthSession.collection.insertOne({...rows[0], _id: new mongoose.Types.ObjectId(), tokenHash: randomBytes(32).toString('hex')});
  if (kind === 'conflict') {
    for (let i = 0; i < 2; i++) {
      const chainId = randomUUID();
      await SessionChain.create({userId, chainId, legacyDerived: true, status: 'ACTIVE', guardRevision: 0});
      await AuthSession.collection.updateOne({_id: rows[i]._id}, {$set: {chainId}});
    }
  }
  if (kind === 'missing-record') await AuthSession.collection.updateMany({userId}, {$set: {chainId: randomUUID()}});
  if (kind === 'collision') await SessionChain.create({userId, chainId: sid, legacyDerived: false, status: 'ACTIVE', guardRevision: 0});
  if (kind === 'marker') {
    await SessionChain.collection.insertOne({userId, chainId: sid, status: 'ACTIVE', guardRevision: 0});
    await AuthSession.collection.updateMany({userId}, {$set: {chainId: sid}});
  }
  await mongoose.connection.db!.collection('favorites').insertOne({userId, value: 'preserve'});
  const before = await User.collection.findOne({_id: userId});
  const result = await mapSessionChains(env.MONGODB_URI, policy, now);
  expect(result.quarantinedRows).toBeGreaterThanOrEqual(2);
  expect(await AuthSession.countDocuments({userId, status: 'ACTIVE'})).toBe(0);
  expect(await User.collection.findOne({_id: userId})).toEqual(before);
  expect(await mongoose.connection.db!.collection('favorites').countDocuments({userId})).toBe(1);
});
it('K1 guest cap aborts before the first reservation or auth mutation', async () => {
  const {rows, userId} = await pair(true);
  await AuthSession.collection.updateOne({_id: rows[0]._id}, {$set: {chainId: randomUUID()}});
  await expect(mapSessionChains(env.MONGODB_URI, policy, now)).rejects.toThrow('cap');
  expect(await AuthSession.countDocuments({userId, status: 'ACTIVE'})).toBe(2);
  expect(await SessionChain.countDocuments({userId})).toBe(0);
});
it('K1 quarantines an own-sid collision with a foreign root without revoking its owner', async () => {
  const {userId, sid} = await pair(), foreignId = new mongoose.Types.ObjectId();
  await SessionChain.create({userId: foreignId, chainId: sid, legacyDerived: false, status: 'ACTIVE', guardRevision: 0});
  const result = await mapSessionChains(env.MONGODB_URI, policy, now);
  expect(result.quarantinedRows).toBe(2);
  expect(await AuthSession.countDocuments({userId, chainId: {$exists: true}})).toBe(0);
  expect(await SessionChain.countDocuments({userId})).toBe(0);
  expect((await SessionChain.findOne({userId: foreignId, chainId: sid}))!.status).toBe('ACTIVE');
});
it('K1 reservations survive a crash and caps cannot be reset by a retry', async () => {
  const {rows, userId} = await pair();
  await AuthSession.collection.updateOne({_id: rows[0]._id}, {$set: {chainId: randomUUID()}});
  await expect(mapSessionChains(env.MONGODB_URI, policy, now, async point => {
    if (point === 'reserved') throw new Error('Reservation crash');
  })).rejects.toThrow('crash');
  const resumed = await mapSessionChains(env.MONGODB_URI, policy, now);
  expect(resumed.cumulative.users).toBe(1);
  expect(await AuthSession.countDocuments({userId, status: 'ACTIVE'})).toBe(0);
  await expect(mapSessionChains(env.MONGODB_URI, {...policy, caps: {...policy.caps, users: 0}}, now)).rejects.toThrow('policy changed');
});
it('K1 final reconciliation catches a linkage-losing writer after the scan begins', async () => {
  const {rows} = await pair();
  let wrote = false;
  await expect(mapSessionChains(env.MONGODB_URI, policy, now, async point => {
    if (point === 'stamp' && !wrote) {
      wrote = true;
      await AuthSession.collection.insertOne({...rows[0], _id: new mongoose.Types.ObjectId(), sessionFamily: randomUUID(), tokenHash: randomBytes(32).toString('hex')});
    }
  })).rejects.toThrow('Unknown writer');
  // A new complete stopped scan handles that old-writer birth as legacy.
  const resumed = await mapSessionChains(env.MONGODB_URI, policy, now);
  expect(resumed.mappedRows).toBe(1);
});
it('K1 requires an explicit time budget', async () => {
  await expect(mapSessionChains(env.MONGODB_URI, {...policy, maxDurationMs: undefined} as any, now)).rejects.toThrow('policy');
});
it('K1 stops before the next stamp when its time budget expires', async () => {
  const {userId, rows} = await pair();
  let elapsed = 0;
  await expect(mapSessionChains(env.MONGODB_URI, policy, now, async point => {
    if (point === 'root') elapsed = 60000;
  }, () => elapsed)).rejects.toThrow('time budget');
  expect(await AuthSession.countDocuments({_id: {$in: rows.map(row => row._id)}, chainId: {$exists: true}})).toBe(0);
  expect(await SessionChain.countDocuments({userId})).toBe(1);
  expect((await mapSessionChains(env.MONGODB_URI, policy, now)).mappedRows).toBe(2);
});
it('K1 resumes an interrupted quarantine after its terminal root write', async () => {
  const {userId, sid, rows} = await pair();
  await SessionChain.create({userId, chainId: sid, legacyDerived: false, status: 'ACTIVE', guardRevision: 0});
  await expect(mapSessionChains(env.MONGODB_URI, policy, now, async point => {
    if (point === 'tombstone') throw new Error('Quarantine crash');
  })).rejects.toThrow('crash');
  const result = await mapSessionChains(env.MONGODB_URI, policy, now);
  expect(result.cumulative.users).toBe(1);
  expect(await AuthSession.countDocuments({_id: {$in: rows.map(row => row._id)}, status: 'ACTIVE'})).toBe(0);
  expect((await SessionChain.findOne({userId, chainId: sid}))!.status).toBe('REVOKED');
});
it('R1 S1: mapper requires an explicit ledger namespace before mutation', async () => {
  const {userId} = await pair();
  await expect(mapSessionChains(env.MONGODB_URI, {...policy, ledgerCollection: undefined} as any, now)).rejects.toThrow('policy');
  expect(await SessionChain.countDocuments({userId})).toBe(0);
});
it('R1 S1: mapper reservations use only the configured ledger collection', async () => {
  await pair();
  await mapSessionChains(env.MONGODB_URI, policy, now);
  expect(await mongoose.connection.db!.collection(policy.ledgerCollection).countDocuments({_id: policy.transitionId} as any)).toBe(1);
  expect(await mongoose.connection.db!.collection('session_chain_mapper_ledger').countDocuments({})).toBe(0);
});
it('R1 B2: mapper refuses control-DB activation without writing a root or stamp', async () => {
  const {userId} = await pair();
  await mongoose.connection.getClient().db(process.env.SESSION_CHAIN_CONTROL_DB!)
    .collection(process.env.SESSION_CHAIN_CONTROL_COLLECTION!).insertOne({_id: 'session-chain-transition'} as any);
  await expect(mapSessionChains(env.MONGODB_URI, policy, now)).rejects.toThrow('activation');
  expect(await SessionChain.countDocuments({userId})).toBe(0);
  expect(await AuthSession.countDocuments({userId, chainId: {$exists: true}})).toBe(0);
});
