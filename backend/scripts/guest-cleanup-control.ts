import {mongo} from 'mongoose';
import {parseArgs} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import {performance} from 'node:perf_hooks';
import {CleanupControl, validCleanupControl} from '../src/models/GuestCleanupControl.model';
import {operatorDatabase, readOperatorUri, serverTime} from './guest-cleanup-operator';

export async function changeCleanupControl(db: mongo.Db, input: {paused: boolean; expectedVersion: number; reason: string; operator: string}) {
  if (typeof input.paused !== 'boolean' || !Number.isSafeInteger(input.expectedVersion) || input.expectedVersion < 0 ||
      input.expectedVersion >= Number.MAX_SAFE_INTEGER || typeof input.reason !== 'string' || !input.reason.trim() ||
      // eslint-disable-next-line no-control-regex -- Operator audit reasons must reject ASCII control characters.
      input.reason.length > 200 || /[\x00-\x1f]/.test(input.reason) || !/^[a-z0-9_-]{1,64}$/i.test(input.operator)) throw new Error('Explicit CAS, reason and operator alias required');
  const collection = db.collection<CleanupControl>('guest_cleanup_control');
  const previous = await collection.findOne({_id: 'guest-cleanup'});
  const changedAt = await serverTime(db);
  const fields = {paused: input.paused, reason: input.reason.trim(), changedAt, changedBy: input.operator, version: input.expectedVersion + 1};
  if (!previous && input.expectedVersion === 0) {
    await collection.insertOne({_id: 'guest-cleanup', ...fields}, {writeConcern: {w: 'majority', j: true}});
  } else {
    if (!validCleanupControl(previous)) throw new Error('Malformed control requires separate operator investigation');
    const result = await collection.updateOne({_id: 'guest-cleanup', version: input.expectedVersion}, {$set: fields}, {writeConcern: {w: 'majority', j: true}});
    if (!result.matchedCount) throw new Error('Control version changed; re-read and confirm');
  }
  return fields;
}
export async function waitForCleanupDrain(db: mongo.Db, version: number, options = {maxWaitMs: 35000}) {
  const started = performance.now();
  for (;;) {
    const row = await db.collection<CleanupControl>('guest_cleanup_control').findOne({_id: 'guest-cleanup'});
    if (!validCleanupControl(row) || !row.paused || row.version !== version) throw new Error('Freeze state changed; drain not certified');
    // Expiry fences future writes, but cannot prove a stalled filesystem call has drained.
    if (!row.lease) return;
    if (performance.now() - started >= options.maxWaitMs) throw new Error('Cleanup has not drained');
    await delay(100);
  }
}
if (require.main === module) {
  (async () => {
    const {values, positionals} = parseArgs({allowPositionals: true, options: {
      'expected-version': {type: 'string'}, reason: {type: 'string'}, operator: {type: 'string'}, 'wait-drain': {type: 'boolean'},
    }});
    if (positionals.length !== 1 || !['pause', 'resume'].includes(positionals[0]) || !/^\d+$/.test(values['expected-version'] ?? '') ||
        values['wait-drain'] && positionals[0] !== 'pause') throw new Error();
    const {client, db} = await operatorDatabase(await readOperatorUri());
    try {
      const result = await changeCleanupControl(db, {paused: positionals[0] === 'pause', expectedVersion: Number(values['expected-version']),
        reason: values.reason ?? '', operator: values.operator ?? ''});
      if (values['wait-drain']) await waitForCleanupDrain(db, result.version);
      console.log(JSON.stringify({...result, drained: values['wait-drain'] === true}));
    } finally {await client.close();}
  })().catch(() => {console.error('Cleanup control refused or drain not certified; inspect control and lease before retrying.'); process.exitCode = 1;});
}
