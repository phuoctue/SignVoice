import fs from 'node:fs';
import path from 'node:path';
import mongoose from 'mongoose';
import { env } from '../src/config/env';
import { DictionaryEntry, SearchHistory, AuditLog } from '../src/models';

/** Dry-run by default. Replaces only conflicting schema indexes, never documents. */
async function main() {
  const apply = process.argv.includes('--apply');
  await mongoose.connect(env.MONGODB_URI, {autoIndex: false, serverSelectionTimeoutMS: 5000});
  try {
    const repairs: {collection: string; index: string}[] = [];
    const backup: unknown[] = [];
    for (const model of [DictionaryEntry, SearchHistory, AuditLog]) {
      const indexes = await model.collection.indexes().catch((error: any) => { if (error.code === 26) return []; throw error; });
      for (const index of indexes) {
        const legacyText = model.modelName === 'DictionaryEntry' && index.textIndexVersion !== undefined &&
          JSON.stringify(index.weights) !== JSON.stringify({definition: 5, tags: 3, word: 10});
        const legacyHistory = model.modelName === 'SearchHistory' && Object.keys(index.key).length === 1 &&
          index.key.viewedAt === 1 && index.expireAfterSeconds !== 7776000;
        const legacyAudit = model.modelName === 'AuditLog' && Object.keys(index.key).length === 1 &&
          index.key.timestamp === 1 && index.expireAfterSeconds !== 31536000;
        if ((legacyText || legacyHistory || legacyAudit) && index.name) {
          repairs.push({collection: model.collection.name, index: index.name});
          backup.push({collection: model.collection.name, definition: index});
        }
      }
    }
    console.log(JSON.stringify({mode: apply ? 'apply' : 'dry-run', repairs}, null, 2));
    if (apply) {
      const folder = path.resolve(__dirname, '../../.runtime');
      fs.mkdirSync(folder, {recursive: true});
      fs.writeFileSync(path.join(folder, 'index-backup-' + Date.now() + '.json'), JSON.stringify(backup, null, 2));
      for (const repair of repairs) await mongoose.connection.collection(repair.collection).dropIndex(repair.index);
      for (const model of [DictionaryEntry, SearchHistory, AuditLog]) await model.createIndexes();
      console.log('Schema indexes ready; no documents were changed.');
    } else { console.log('To apply after review: npm run db:indexes -- --apply'); }
  } finally { await mongoose.disconnect(); }
}
main().catch(error => { console.error('Index check failed:', error.message); process.exitCode = 1; });
