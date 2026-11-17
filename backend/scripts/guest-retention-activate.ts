import {mongo} from 'mongoose';
import {parseArgs} from 'node:util';
import {operatorDatabase, readOperatorUri, serverTime} from './guest-cleanup-operator';

export async function setLegacyActivation(db: mongo.Db, input: {confirm: boolean; tasksAccepted: boolean; clientReleased: boolean}) {
  if (input.confirm !== true || input.tasksAccepted !== true || input.clientReleased !== true) throw new Error('Confirmation and both release attestations are required');
  const collection = db.collection<{_id: string; activatedAt: Date}>('guest_retention_activation');
  if (await collection.findOne({_id: 'legacy-retention'})) throw new Error('Activation already exists and cannot be changed');
  const activatedAt = await serverTime(db);
  // The unique singleton id resolves concurrent operators; no update or upsert can reset it.
  await collection.insertOne({_id: 'legacy-retention', activatedAt}, {writeConcern: {w: 'majority', j: true}});
  return {activatedAt: activatedAt.toISOString(), expiresAt: new Date(+activatedAt + 7 * 86400000).toISOString()};
}
if (require.main === module) {
  (async () => {
    const {values} = parseArgs({options: {confirm: {type: 'boolean'}, 'tasks-2-4-accepted': {type: 'boolean'}, 'client-released': {type: 'boolean'}}});
    const input = {confirm: values.confirm === true, tasksAccepted: values['tasks-2-4-accepted'] === true, clientReleased: values['client-released'] === true};
    if (!input.confirm || !input.tasksAccepted || !input.clientReleased) throw new Error();
    const {client, db} = await operatorDatabase(await readOperatorUri());
    try {console.log(JSON.stringify(await setLegacyActivation(db, input)));}
    finally {await client.close();}
  })().catch(() => {console.error('Legacy activation refused or failed; no overwrite is permitted. Verify the sanitized stored result before retrying.'); process.exitCode = 1;});
}
