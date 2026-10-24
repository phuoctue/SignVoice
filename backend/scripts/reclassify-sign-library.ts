/** Move reviewed words out of the fallback topic, without rewriting any media/content. */
import {writeFileSync, mkdirSync} from 'node:fs';
import path from 'node:path';
import {parseArgs} from 'node:util';
import mongoose from 'mongoose';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {DictionaryEntry} from '../src/models/DictionaryEntry.model';
import {Category} from '../src/models/Category.model';
import {referenceCategories, referenceSlug, reviewedReferenceCategories} from '../src/services/sign-library-categories';

const fallbackSlug = 'tham-khao-tu-vung-khac';
export async function reclassifyReferenceEntries() {
  return mongoose.connection.transaction(async session => {
    const fallback = await Category.findOne({slug: fallbackSlug}).session(session);
    if (!fallback) throw new Error('Reference fallback category not found');
    const entries = await DictionaryEntry.find({categoryId: fallback._id,
      word: {$in: Object.keys(reviewedReferenceCategories)}}).session(session).lean();
    const destinations = new Map<string, mongoose.Types.ObjectId>();
    for (const name of new Set(entries.map(entry => reviewedReferenceCategories[entry.word]))) {
      if (!referenceCategories.includes(name)) throw new Error('Unknown destination: ' + name);
      const category = await Category.findOneAndUpdate({slug: 'tham-khao-' + referenceSlug(name)}, {
        $setOnInsert: {name, status: 'ACTIVE', sortOrder: referenceCategories.indexOf(name),
          description: 'Chủ đề của kho ảnh/video ký hiệu tham khảo.'},
        $inc: {mutationVersion: 1},
      }, {upsert: true, new: true, session, setDefaultsOnInsert: true});
      if (category.status !== 'ACTIVE') throw new Error('Destination category is not active: ' + name);
      destinations.set(name, category._id);
    }
    const ledger = entries.map(entry => ({id: String(entry._id), word: entry.word,
      from: fallback.name, to: reviewedReferenceCategories[entry.word]}));
    if (entries.length) {
      const result = await DictionaryEntry.bulkWrite(entries.map(entry => ({updateOne: {
        filter: {_id: entry._id, categoryId: fallback._id},
        update: {$set: {categoryId: destinations.get(reviewedReferenceCategories[entry.word])}},
      }})), {session});
      if (result.modifiedCount !== entries.length) throw new Error('Entries changed during review');
    }
    if (entries.length) {
      await Category.updateOne({_id: fallback._id}, {$inc: {mutationVersion: 1}}, {session});
      const affected = [fallback._id, ...destinations.values()];
      for (const categoryId of affected) {
        const wordCount = await DictionaryEntry.countDocuments({categoryId, status: 'PUBLISHED'}).session(session);
        await Category.updateOne({_id: categoryId}, {$set: {wordCount}}, {session});
      }
    }
    return ledger;
  });
}

async function main() {
  const {values} = parseArgs({options: {apply: {type: 'boolean', default: false}}});
  await connectDatabase();
  try {
    const fallback = await Category.findOne({slug: fallbackSlug}).lean();
    if (!fallback) throw new Error('Reference fallback category not found');
    const entries = await DictionaryEntry.find({categoryId: fallback._id,
      word: {$in: Object.keys(reviewedReferenceCategories)}}).lean();
    const plan = entries.map(entry => ({id: String(entry._id), word: entry.word, to: reviewedReferenceCategories[entry.word]}));
    console.log(JSON.stringify({dryRun: !values.apply, reviewedLabels: Object.keys(reviewedReferenceCategories).length,
      entriesToMove: plan.length, destinations: plan.reduce<Record<string, number>>((counts, entry) => {
        counts[entry.to] = (counts[entry.to] || 0) + 1; return counts;
      }, {})}));
    if (!values.apply) return;
    const folder = path.resolve(__dirname, '../../.runtime/dictionary-topic-review');
    mkdirSync(folder, {recursive: true});
    const backup = path.join(folder, 'before-reclassification-' + Date.now() + '.json');
    writeFileSync(backup, JSON.stringify({entries, categories: await Category.find().lean(), plan}, null, 2));
    const ledger = await reclassifyReferenceEntries();
    writeFileSync(path.join(folder, 'reclassification-ledger.json'), JSON.stringify(ledger, null, 2));
    // Preserve backup identity for the separate read-only comparison after import.
    writeFileSync(path.join(folder, 'latest-backup.json'), JSON.stringify({path: backup}));
    console.log(JSON.stringify({moved: ledger.length, backup}));
  } finally { await disconnectDatabase(); }
}
if (require.main === module) main().catch(error => {console.error(error.message); process.exitCode = 1;});
