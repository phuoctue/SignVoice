import {mongo} from 'mongoose';
import {parseArgs} from 'node:util';
import {operatorDatabase, readOperatorUri} from './guest-cleanup-operator';

/** Ingress and ALL writers must remain stopped through verification and reopening approval. */
export async function invalidateRestoredSessions(db: mongo.Db, confirm: boolean): Promise<{revoked: number}> {
  if (confirm !== true) throw new Error('Explicit confirmation required');
  const sessions = db.collection('auth_sessions');
  const result = await sessions.updateMany({status: 'ACTIVE'}, {$set: {status: 'REVOKED'}, $currentDate: {revokedAt: true}},
    {writeConcern: {w: 'majority', j: true}, timeoutMS: 30000});
  if (await sessions.countDocuments({status: 'ACTIVE'}, {maxTimeMS: 5000})) throw new Error('Active sessions remain; check all writers');
  return {revoked: result.modifiedCount};
}

if (require.main === module) {
  (async () => {
    const {values} = parseArgs({options: {confirm: {type: 'boolean'}, 'writers-stopped': {type: 'boolean'}}});
    if (!values.confirm || !values['writers-stopped']) throw new Error();
    const {client, db} = await operatorDatabase(await readOperatorUri());
    try {console.log(JSON.stringify(await invalidateRestoredSessions(db, true)));}
    finally {await client.close();}
  })().catch(() => {console.error('Restored-session invalidation refused or incomplete; keep ingress closed. Credentials are suppressed.'); process.exitCode = 1;});
}
