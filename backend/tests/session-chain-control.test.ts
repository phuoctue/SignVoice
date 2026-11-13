import mongoose from 'mongoose';
import {afterAll, afterEach, beforeAll, expect, it, vi} from 'vitest';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {IChainTransition} from '../src/models/SessionChainTransition.model';
import {loadChainTransition, transitionDigest, assertChainDeadline} from '../src/services/session-chain.service';

const now = new Date(Math.floor(Date.now() / 1000) * 1000);
const record: IChainTransition = {_id: 'session-chain-transition', transitionId: 'approved-control', policyVersion: '1',
  windowMs: 3600000, clockBudgetMs: 120000, cutoverAt: new Date(+now - 1800000), sunsetAt: new Date(+now + 1800000)};
const control = () => mongoose.connection.getClient().db(process.env.SESSION_CHAIN_CONTROL_DB!)
  .collection<IChainTransition>(process.env.SESSION_CHAIN_CONTROL_COLLECTION!);
function enforce() {
  for (const [name, value] of Object.entries({SESSION_CHAIN_MODE: 'enforcement', SESSION_CHAIN_TRANSITION_ID: record.transitionId,
    SESSION_CHAIN_POLICY_VERSION: '1', SESSION_CHAIN_WINDOW_MS: '3600000', SESSION_CHAIN_CLOCK_BUDGET_MS: '120000',
    SESSION_CHAIN_DIGEST: transitionDigest(record)})) vi.stubEnv(name, value);
}
beforeAll(async () => {
  await connectDatabase();
  expect(mongoose.connection.host).toBe('127.0.0.1');
  expect(process.env.SESSION_CHAIN_CONTROL_DB).toMatch(/^signvoice_test_/);
});
afterEach(async () => {
  vi.restoreAllMocks(); vi.unstubAllEnvs();
  await control().deleteMany({});
  await mongoose.connection.db!.collection('session_chain_transition').deleteMany({});
});
afterAll(async () => {
  await mongoose.connection.getClient().db(process.env.SESSION_CHAIN_CONTROL_DB!).dropDatabase();
  await mongoose.connection.dropDatabase(); await disconnectDatabase();
});
it('R1 B2: compat refuses an activated control store even when the app DB is empty', async () => {
  await control().insertOne(record);
  await expect(loadChainTransition()).rejects.toThrow();
});
it.each(['SESSION_CHAIN_CONTROL_DB', 'SESSION_CHAIN_CONTROL_COLLECTION'])('R1 B2: missing %s is not inactive compatibility', async name => {
  for (const value of [undefined, '']) {
    vi.stubEnv(name, value);
    await expect(loadChainTransition()).rejects.toThrow();
  }
});
it('R1 B2: app-DB and malformed control namespaces fail closed', async () => {
  for (const db of [mongoose.connection.name, mongoose.connection.name.toUpperCase(), 'bad.database', ' ', 'production_control']) {
    vi.stubEnv('SESSION_CHAIN_CONTROL_DB', db);
    await expect(loadChainTransition()).rejects.toThrow();
  }
});
it.each(['bad.collection', '$control'])('R1 B2: malformed control collection %j fails closed', async collection => {
  vi.stubEnv('SESSION_CHAIN_CONTROL_COLLECTION', collection);
  await expect(loadChainTransition()).rejects.toThrow();
});
it('R1 B2: app-DB decoys cannot become enforcing authority or a fallback', async () => {
  enforce();
  const decoy = {...record, clockBudgetMs: 300000};
  vi.stubEnv('SESSION_CHAIN_CLOCK_BUDGET_MS', '300000');
  vi.stubEnv('SESSION_CHAIN_DIGEST', transitionDigest(decoy));
  await mongoose.connection.db!.collection('session_chain_transition').insertOne(decoy as any);
  await expect(loadChainTransition()).rejects.toThrow();
});
it.each(['', '0', '-1', 'NaN', '1.5', '9007199254740992'])('R1 B1: invalid clock budget %j fails closed', async budget => {
  enforce(); await control().insertOne(record);
  vi.stubEnv('SESSION_CHAIN_CLOCK_BUDGET_MS', budget);
  await expect(loadChainTransition()).rejects.toThrow();
});
it.each([undefined, 0, NaN, 120001])('R1 B1: invalid or mismatched record clock budget %j fails closed', async clockBudgetMs => {
  enforce(); await control().insertOne({...record, clockBudgetMs} as any);
  await expect(loadChainTransition()).rejects.toThrow();
});
it('R1 B1: an approved non-default budget comes from the control record and policy', async () => {
  enforce(); await control().insertOne(record);
  // The old implementation's app-DB row isolates its literal-threshold failure from namespace routing.
  await mongoose.connection.db!.collection('session_chain_transition').insertOne(record as any);
  expect(await loadChainTransition()).toMatchObject({clockBudgetMs: 120000});
  vi.spyOn((await import('../src/services/auth-clock')).authClock, 'now').mockReturnValue(new Date(+record.sunsetAt - 120001));
  const chain = {userId: new mongoose.Types.ObjectId(), chainId: 'fixture', legacyDerived: true, status: 'ACTIVE' as const, guardRevision: 0};
  expect(() => assertChainDeadline(chain, record)).not.toThrow();
  vi.spyOn((await import('../src/services/auth-clock')).authClock, 'now').mockReturnValue(new Date(+record.sunsetAt - 120000));
  expect(() => assertChainDeadline(chain, record)).toThrow();
});
