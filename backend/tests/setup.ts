// Executed before application imports. Never fall back to the user's normal database.
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { afterAll, vi } from 'vitest';
import { cleanupFileDatabases } from './database-cleanup';

const testUri = process.env.TEST_MONGODB_URI;
if (!testUri) throw new Error('Tests require explicit TEST_MONGODB_URI targeting signvoice_test_*');
const parsed = new URL(testUri);
const database = parsed.pathname.slice(1);
if (parsed.protocol !== 'mongodb:' || parsed.hostname !== '127.0.0.1' || parsed.username || parsed.password ||
    [...parsed.searchParams.keys()].some(key => key !== 'replicaSet') || !/^signvoice_test_[a-z0-9_]+$/i.test(database)) {
  throw new Error('Refusing unsafe test database; expected signvoice_test_*');
}
if (!process.env.SIGNVOICE_ENV_FILE || path.basename(process.env.SIGNVOICE_ENV_FILE) !== 'dummy-config') {
  throw new Error('Tests require an explicit disposable dummy-config file');
}
const control = process.env.SESSION_CHAIN_CONTROL_DB;
if (!control || !/^signvoice_test_control_[a-z0-9_]+$/i.test(control) || control === database ||
    process.env.SESSION_CHAIN_CONTROL_COLLECTION !== 'transitions') {
  throw new Error('Tests require a separate disposable session chain control namespace');
}
const fileId = randomUUID().replace(/-/g, '').slice(0, 12);
parsed.pathname = `/${database}_${fileId}`;
process.env.SESSION_CHAIN_CONTROL_DB = `${control}_${fileId}`;
process.env.NODE_ENV = 'test';
process.env.MONGODB_URI = parsed.toString();
process.env.JWT_ACCESS_SECRET = 'isolated-test-access-secret-at-least-32-chars';
process.env.JWT_REFRESH_SECRET = 'isolated-test-refresh-secret-at-least-32-chars';

// Capture ownership now: individual tests may later replace environment values.
const fileUri = parsed.toString();
const fileControl = `${control}_${fileId}`;
// Vitest 1 defaults to parallel hooks; existing disconnect/drop hooks must finish first.
vi.setConfig({ sequence: { hooks: 'stack' } });
afterAll(() => cleanupFileDatabases(fileUri, fileControl, fileId));
