import {beforeAll, afterAll, beforeEach, afterEach, it, expect, vi} from 'vitest';
import mongoose, {Types} from 'mongoose';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {User} from '../src/models/User.model';
import {GuestCleanupControl} from '../src/models/GuestCleanupControl.model';
import {createGuestAccount} from '../src/services/auth.service';
import {GuestLifecycleOutbox} from '../src/models/GuestLifecycle.model';
import {setLegacyActivation} from '../scripts/guest-retention-activate';
import {changeCleanupControl, waitForCleanupDrain} from '../scripts/guest-cleanup-control';
import {assertOperatorTarget} from '../scripts/guest-cleanup-operator';
import {guestCleanupDryRun} from '../src/services/guest-cleanup-report.service';
import {Conversation} from '../src/models/Conversation.model';
import {syntheticCanaryRegistry} from '../src/services/synthetic-canary.service';
import * as chain from '../src/services/session-chain.service';
import {spawn} from 'node:child_process';
import path from 'node:path';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';

const day = 86400000, attest = {confirm: true, tasksAccepted: true, clientReleased: true};
beforeAll(async () => {await connectDatabase(); await User.init();});
beforeEach(async () => {
  await User.deleteMany({}); await GuestLifecycleOutbox.deleteMany({}); await GuestCleanupControl.deleteMany({});
  await mongoose.connection.collection('guest_retention_activation').deleteMany({});
});
afterEach(() => vi.restoreAllMocks());
afterAll(async () => {await mongoose.connection.dropDatabase(); await disconnectDatabase();});

it('requires confirmation and both release attestations, sets activation once using DB time, and refuses overwrite', async () => {
  const db = mongoose.connection.db!;
  for (const input of [{...attest, confirm: false}, {...attest, tasksAccepted: false}, {...attest, clientReleased: false}]) {
    await expect(setLegacyActivation(db, input)).rejects.toThrow();
  }
  expect(await db.collection('guest_retention_activation').countDocuments()).toBe(0);
  const before = (await db.command({hello: 1})).localTime;
  const result = await setLegacyActivation(db, attest);
  const after = (await db.command({hello: 1})).localTime;
  expect(Date.parse(result.activatedAt)).toBeGreaterThanOrEqual(+before);
  expect(Date.parse(result.activatedAt)).toBeLessThanOrEqual(+after);
  expect(Date.parse(result.expiresAt) - Date.parse(result.activatedAt)).toBe(7 * day);
  await expect(setLegacyActivation(db, attest)).rejects.toThrow();
  expect(await db.collection('guest_retention_activation').countDocuments()).toBe(1);
});

it('authenticates operator targets and requires a named matching copy for non-loopback', () => {
  expect(() => assertOperatorTarget('mongodb://example.test/live')).toThrow();
  expect(() => assertOperatorTarget('mongodb://operator:secret@example.test/live', 'copy_approved')).toThrow();
  expect(() => assertOperatorTarget('mongodb://operator:secret@example.test/copy_approved', 'copy_approved')).not.toThrow();
  expect(() => assertOperatorTarget('mongodb://127.0.0.1/live', undefined, true)).toThrow();
  expect(() => assertOperatorTarget(process.env.MONGODB_URI!, undefined, true, true)).not.toThrow();
  for (const uri of ['mongodb://127.0.0.1,example.test/live', 'mongodb://127.0.0.1/live?proxyHost=example.test', 'mongodb://localhost/live?authSource=admin']) {
    expect(() => assertOperatorTarget(uri, undefined, true)).toThrow();
  }
});

it('pause/resume use mandatory reason and version CAS and drain does not certify a held lease', async () => {
  const db = mongoose.connection.db!;
  const input = {paused: false, expectedVersion: 0, reason: 'explicit resume', operator: 'qa'};
  await expect(changeCleanupControl(db, {...input, reason: ''})).rejects.toThrow();
  const resumed = await changeCleanupControl(db, input);
  expect(resumed.version).toBe(1);
  await expect(changeCleanupControl(db, input)).rejects.toThrow();
  await GuestCleanupControl.updateOne({_id: 'guest-cleanup'}, {$set: {lease: {holder: 'active-job', expiresAt: new Date(Date.now() + day), revision: 0}}});
  const paused = await changeCleanupControl(db, {...input, paused: true, expectedVersion: 1, reason: 'K+S B2 freeze'});
  expect(paused.paused).toBe(true);
  await expect(waitForCleanupDrain(db, paused.version, {maxWaitMs: 0})).rejects.toThrow();
  // An expired lease is not proof that a stalled process or filesystem call has exited.
  await GuestCleanupControl.updateOne({_id: 'guest-cleanup'}, {$set: {'lease.expiresAt': new Date(0)}});
  await expect(waitForCleanupDrain(db, paused.version, {maxWaitMs: 0})).rejects.toThrow();
  await GuestCleanupControl.updateOne({_id: 'guest-cleanup'}, {$unset: {lease: ''}});
  await expect(waitForCleanupDrain(db, paused.version, {maxWaitMs: 0})).resolves.toBeUndefined();
  await changeCleanupControl(db, {...input, expectedVersion: 2});
  await expect(waitForCleanupDrain(db, paused.version, {maxWaitMs: 0})).rejects.toThrow();
});

it('permits an explicitly authenticated remote mutation target without imposing the read-only copy rule', () => {
  expect(() => assertOperatorTarget('mongodb://operator:secret@example.test/signvoice', undefined, true)).not.toThrow();
});

it('dry-run counts the categories and deletion documents without writing, including foreign reports on owned collections', async () => {
  const ordinary = await createGuestAccount({}), legacy = await createGuestAccount({}), synthetic = await createGuestAccount({}), permanent = await createGuestAccount({});
  const now = new Date(), expired = new Date(+now - 8 * day);
  await User.collection.updateMany({_id: {$in: [ordinary, synthetic].map(a => new Types.ObjectId(a.user.id))}}, {$set: {guestGrantedAt: expired}});
  await User.updateOne({_id: permanent.user.id}, {$set: {isGuest: false, guestConvertedAt: now}});
  await mongoose.connection.collection('guest_retention_activation').insertOne({_id: 'legacy-retention' as any, activatedAt: expired});
  await Conversation.create({userId: ordinary.user.id, content: 'must never appear', direction: 'TEXT'});
  const collectionId = new Types.ObjectId();
  await mongoose.connection.collection('learning_sign_collections').insertOne({_id: collectionId, userId: new Types.ObjectId(ordinary.user.id)});
  await mongoose.connection.collection('collection_reports').insertOne({collectionId, userId: new Types.ObjectId(permanent.user.id)});
  vi.spyOn(syntheticCanaryRegistry, 'contains').mockImplementation(async id => String(id) === synthetic.user.id);
  vi.spyOn(chain, 'loadChainTransition').mockResolvedValue({_id: 'session-chain-transition', sunsetAt: now} as any);
  const snapshot = async () => {
    const collections = await mongoose.connection.db!.listCollections().toArray();
    return Object.fromEntries(await Promise.all(collections.map(async c => [c.name,
      await mongoose.connection.db!.collection(c.name).find().sort({_id: 1}).toArray()])));
  };
  const before = await snapshot();
  const client = mongoose.connection.getClient(), commands: string[] = [];
  client.monitorCommands = true;
  const record = (event: {commandName: string}) => {commands.push(event.commandName);};
  client.on('commandStarted', record);
  let result: Awaited<ReturnType<typeof guestCleanupDryRun>>;
  try {result = await guestCleanupDryRun(now);}
  finally {client.off('commandStarted', record); client.monitorCommands = false;}
  expect(commands.filter(c => ['insert', 'update', 'delete', 'findAndModify', 'create', 'createIndexes', 'drop', 'dropDatabase'].includes(c))).toEqual([]);
  expect(result.counts).toEqual({ordinary_expired: 1, legacy_unknown: 1, synthetic_exempt: 1, converted_permanent_skipped: 1, not_due: 0});
  expect(result.documents.conversations).toBe(1);
  expect(result.documents.collection_reports).toBe(1);
  expect(result.documents.users).toBe(2);
  expect(result.list.find(r => r.userId === legacy.user.id)?.deadline).toBe(new Date(+expired + 7 * day).toISOString());
  expect(JSON.stringify(result)).not.toContain('must never appear');
  expect(JSON.stringify(result)).not.toContain(ordinary.tokens.accessToken);
  expect(await snapshot()).toEqual(before);
});

async function operatorCommand(script: string, uri: string, args: string[] = []) {
  const child = spawn(process.execPath, [path.resolve('node_modules/tsx/dist/cli.mjs'), script, ...args],
    {env: {SystemRoot: process.env.SystemRoot, PATH: process.env.PATH, TEMP: process.env.TEMP, TMP: process.env.TMP,
      SESSION_CHAIN_MODE: 'compat', SESSION_CHAIN_CONTROL_DB: process.env.SESSION_CHAIN_CONTROL_DB,
      SESSION_CHAIN_CONTROL_COLLECTION: process.env.SESSION_CHAIN_CONTROL_COLLECTION}, stdio: ['pipe', 'pipe', 'pipe']});
  let stdout = '', stderr = '';
  child.stdout.on('data', b => {stdout += String(b);}); child.stderr.on('data', b => {stderr += String(b);});
  child.stdin.end(uri + '\n');
  const code = await new Promise<number | null>((resolve, reject) => {child.once('error', reject); child.once('exit', resolve);});
  return {code, stdout, stderr};
}
const dryCommand = (uri: string, args: string[] = []) => operatorCommand('scripts/guest-cleanup-dry-run.ts', uri, args);
it('the real dry-run CLI reads --synthetic-registry, reports exemptions and refuses invalid files', async () => {
  const a = await createGuestAccount({});
  await User.collection.updateOne({_id: new Types.ObjectId(a.user.id)}, {$set: {guestGrantedAt: new Date(Date.now() - 8 * day)}});
  const directory = await mkdtemp(path.join(tmpdir(), 'synthetic-dry-run-')), file = path.join(directory, 'registry.json');
  try {
    await writeFile(file, JSON.stringify({accounts: [{alias: 'G-QA', kind: 'guest', userId: a.user.id, status: 'active', privateExtra: 'never-print-me'}]}));
    const result = await dryCommand(process.env.MONGODB_URI!, ['--synthetic-registry', file]);
    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout).counts.synthetic_exempt).toBe(1);
    expect(JSON.parse(result.stdout).list).toContainEqual({userId: a.user.id, deadline: expect.any(String), category: 'synthetic_exempt'});
    expect(result.stdout + result.stderr).not.toContain('never-print-me');
    await writeFile(file, '{');
    const refused = await dryCommand(process.env.MONGODB_URI!, ['--synthetic-registry', file]);
    expect(refused.code).toBe(1);
    expect(refused.stdout).toBe('');
    expect(await User.exists({_id: a.user.id})).not.toBeNull();
  } finally {await rm(directory, {recursive: true, force: true});}
});
it('the actual dry-run CLI never auto-creates collections on an empty DB and suppresses refused URI credentials', async () => {
  const uri = new URL(process.env.MONGODB_URI!);
  const empty = mongoose.connection.name + '_dry';
  uri.pathname = '/' + empty;
  const db = mongoose.connection.getClient().db(empty);
  try {
    expect(await db.listCollections().toArray()).toEqual([]);
    const result = await dryCommand(uri.toString());
    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout).list).toEqual([]);
    expect(await db.listCollections().toArray()).toEqual([]);
    const refused = await dryCommand('mongodb://operator:do-not-print@example.test/live');
    expect(refused.code).toBe(1);
    expect(refused.stdout + refused.stderr).not.toContain('do-not-print');
  } finally {await db.dropDatabase();}
});

it('the real operator CLIs require authentication and confirmation, activate once and revoke all sessions', async () => {
  const db = mongoose.connection.db!, uri = new URL(process.env.MONGODB_URI!);
  await db.command({createUser: 'cleanup_operator', pwd: 'isolated-operator-password', roles: ['readWrite']});
  try {
  uri.username = 'cleanup_operator'; uri.password = 'isolated-operator-password';
  uri.searchParams.set('authSource', db.databaseName);
  const flags = ['--confirm', '--tasks-2-4-accepted', '--client-released'];
  expect((await operatorCommand('scripts/guest-retention-activate.ts', process.env.MONGODB_URI!, flags)).code).toBe(1);
  expect((await operatorCommand('scripts/guest-retention-activate.ts', uri.toString(), flags.slice(1))).code).toBe(1);
  const first = await operatorCommand('scripts/guest-retention-activate.ts', uri.toString(), flags);
  expect(first.code).toBe(0);
  expect(Date.parse(JSON.parse(first.stdout).activatedAt)).toBeGreaterThan(0);
  expect((await operatorCommand('scripts/guest-retention-activate.ts', uri.toString(), flags)).code).toBe(1);
  await db.collection('auth_sessions').insertOne({status: 'ACTIVE'});
  expect((await operatorCommand('scripts/guest-restore-invalidate-sessions.ts', uri.toString())).code).toBe(1);
  expect(await db.collection('auth_sessions').countDocuments({status: 'ACTIVE'})).toBeGreaterThan(0);
  const invalidated = await operatorCommand('scripts/guest-restore-invalidate-sessions.ts', uri.toString(), ['--confirm', '--writers-stopped']);
  expect(invalidated.code).toBe(0);
  expect(JSON.parse(invalidated.stdout).revoked).toBeGreaterThan(0);
  expect(await db.collection('auth_sessions').countDocuments({status: 'ACTIVE'})).toBe(0);
  expect(first.stdout + first.stderr + invalidated.stdout + invalidated.stderr).not.toContain('isolated-operator-password');
  } finally {await db.command({dropUser: 'cleanup_operator'});}
}, 60000);
