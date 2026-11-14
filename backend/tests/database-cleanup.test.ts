import { MongoClient } from 'mongodb';
import { describe, expect, it, vi } from 'vitest';
import { cleanupFileDatabases } from './database-cleanup';

const uri = process.env.MONGODB_URI!;
const control = process.env.SESSION_CHAIN_CONTROL_DB!;
const app = new URL(uri).pathname.slice(1);
const fileId = app.slice(-12);

describe('per-file database cleanup', () => {
  it('drops both owned databases, leaves a sibling intact, and can run twice', async () => {
    const client = new MongoClient(uri);
    const sibling = `${app.slice(0, -12)}abcdefabcdef`;
    try {
      await client.db(app).collection('proof').insertOne({ value: 1 });
      await client.db(control).collection('proof').insertOne({ value: 1 });
      await client.db(sibling).collection('proof').insertOne({ value: 1 });
      await cleanupFileDatabases(uri, control, fileId);
      expect(await client.db(app).listCollections().toArray()).toEqual([]);
      expect(await client.db(control).listCollections().toArray()).toEqual([]);
      expect(await client.db(sibling).collection('proof').countDocuments()).toBe(1);
      await cleanupFileDatabases(uri, control, fileId);
    } finally {
      // This fixture alone owns the sibling database it creates.
      const siblingUri = new URL(uri);
      siblingUri.pathname = `/${sibling}`;
      await cleanupFileDatabases(siblingUri.toString(),
        `${control.slice(0, -12)}abcdefabcdef`, 'abcdefabcdef');
      await client.close();
    }
  });

  it.each([
    ['remote host', uri.replace('127.0.0.1', 'localhost'), control, fileId],
    ['wrong prefix', uri.replace(app, 'customer_data_' + fileId), control, fileId],
    ['wrong file', uri, control, 'abcdefabcdef'],
    ['wrong control', uri, 'signvoice_test_control_other_abcdefabcdef', fileId],
    ['same database', uri, app, fileId],
  ])('refuses %s before connecting', async (_label, target, controlName, id) => {
    await expect(cleanupFileDatabases(target, controlName, id)).rejects.toThrow(/unsafe/i);
  });

  it('surfaces drop failures', async () => {
    const failure = new Error('deliberate drop failure');
    const drop = vi.spyOn(MongoClient.prototype, 'db').mockImplementation(() => {
      throw failure;
    });
    try {
      await expect(cleanupFileDatabases(uri, control, fileId)).rejects.toBe(failure);
    } finally { drop.mockRestore(); }
  });

  it('bounds and surfaces a stalled drop', async () => {
    const db = new MongoClient(uri).db();
    const drop = vi.spyOn(Object.getPrototypeOf(db), 'dropDatabase').mockImplementation(
      () => new Promise(() => {}),
    );
    const started = Date.now();
    try {
      await expect(cleanupFileDatabases(uri, control, fileId, 40)).rejects.toThrow(/timed out/i);
      expect(Date.now() - started).toBeLessThan(2000);
    } finally { drop.mockRestore(); }
  });
});
