/** Import prepared reference media only; dry-run by default. Never changes AI files. */
import {readFileSync, writeFileSync, existsSync} from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {parseArgs} from 'node:util';
import mongoose, {Types} from 'mongoose';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {DictionaryEntry, EntryStatus} from '../src/models/DictionaryEntry.model';
import {Category} from '../src/models/Category.model';
import {User} from '../src/models/User.model';
import {env} from '../src/config/env';
import {referenceAliases, referenceCategories, referenceCategory, referenceSlug} from '../src/services/sign-library-categories';

export type ReferenceRow = {
  word: string; media_id: string; source: string; source_url: string; license: string | null;
  source_sha256: string; source_path: string; source_split: string; alias_of?: string; keyframe_index?: number;
};
const normalize = (value: string) => value.normalize('NFC').toLocaleLowerCase('vi').trim().replace(/\s+/gu, ' ');
const tagFor = (word: string) => 'svlib:' + createHash('sha256').update(normalize(word)).digest('hex').slice(0, 32);

export function validateReferenceRows(rows: ReferenceRow[], media?: string) {
  if (!Array.isArray(rows) || !rows.length || rows.length > 10000) throw new Error('Invalid catalog size');
  const words = new Set<string>();
  for (const row of rows) {
    if (typeof row.word !== 'string' || !row.word.trim() || row.word.length > 200 || words.has(normalize(row.word)) ||
        !/^[a-f0-9]{64}$/.test(row.media_id) || !/^[a-f0-9]{64}$/.test(row.source_sha256) ||
        (row.keyframe_index !== undefined && (!Number.isInteger(row.keyframe_index) || row.keyframe_index < 1 || row.keyframe_index > 5))) {
      throw new Error('Invalid or duplicate reference entry');
    }
    const provided = row.source === 'user_Dataset.tgz' && row.license === null && ['', 'train'].includes(row.source_split);
    const publishedSource = row.source_split === 'train' && (
      row.source === 'namwu/ViSignLanguage-Video' && row.license === 'cc-by-4.0' ||
      row.source === 'KhangCN/Video_VSL' && row.license === 'apache-2.0'
    );
    if (!provided && !publishedSource) throw new Error('Unsupported source or split');
    words.add(normalize(row.word));
    if (media) {
      for (const file of [row.media_id + '.mp4', ...[1, 2, 3, 4, 5].map(n => row.media_id + '-' + n + '.jpg')]) {
        if (!existsSync(path.join(media, file))) throw new Error('Prepared media missing: ' + row.word);
      }
    }
  }
}
export function referenceEntry(row: ReferenceRow, origin: string, categoryId: Types.ObjectId) {
  const aliases = referenceAliases(row.word);
  const source = row.source === 'user_Dataset.tgz'
    ? 'Từ điển trong dataset do người vận hành cung cấp (Dataset.tgz). Archive không kèm văn bản giấy phép riêng.'
    : row.source + ' (' + row.source_url + '); giấy phép ' + row.license + '. Văn bản giấy phép: ' + origin + '/sign-media/license/' + row.license + '.';
  return {
    word: row.word, aliases, categoryId,
    definition: 'Mẫu ký hiệu tham khảo cho “' + row.word + '”, theo nhãn trong dataset nguồn.',
    videoUrl: origin + '/sign-media/' + row.media_id + '.mp4',
    thumbnailUrl: origin + '/sign-media/' + row.media_id + '-' + (row.keyframe_index || 3) + '.jpg',
    imageUrls: [1, 2, 3, 4, 5].map(n => origin + '/sign-media/' + row.media_id + '-' + n + '.jpg'),
    notes: 'Nguồn: ' + source + ' Video bỏ âm thanh, chuyển H.264; 5 ảnh theo thứ tự thời gian. ' +
      'Nhãn theo nguồn; chưa xác nhận chuyên gia về nghĩa và phương ngữ. ' +
      (row.alias_of ? 'Cụm hiển thị dùng chung mẫu “' + row.alias_of + '”. ' : '') +
      'SHA256 gốc: ' + row.source_sha256 + '.',
    tags: [tagFor(row.word), 'mau-tham-khao', ...aliases],
    status: EntryStatus.PUBLISHED,
  };
}

export async function importReferenceRows(rows: ReferenceRow[], origin: string, authorId: Types.ObjectId) {
  validateReferenceRows(rows);
  const classified = rows.map(row => ({row, category: referenceCategory(row.word)}));
  return mongoose.connection.transaction(async session => {
    const categoryIds = new Map<string, Types.ObjectId>();
    for (const [sortOrder, name] of referenceCategories.entries()) {
      const category = await Category.findOneAndUpdate({slug: 'tham-khao-' + referenceSlug(name)}, {
        $set: {name, sortOrder, status: 'ACTIVE', description: 'Chủ đề của kho ảnh/video ký hiệu tham khảo.'},
        $inc: {mutationVersion: 1},
      }, {session, new: true, upsert: true, setDefaultsOnInsert: true});
      categoryIds.set(name, category._id);
    }
    const existing = await DictionaryEntry.find().session(session).lean();
    const byTag = new Map(existing.flatMap(item => (item.tags || []).filter(tag => tag.startsWith('svlib:')).map(tag => [tag, item] as const)));
    const manual = new Set(existing.filter(item => item.status === 'PUBLISHED' && !(item.tags || []).some(tag => tag.startsWith('svlib:')))
      .map(item => normalize(item.word)));
    const operations: any[] = [], ledger: Record<string, unknown>[] = [];
    for (const {row, category} of classified) {
      const tag = tagFor(row.word), current = byTag.get(tag);
      if (manual.has(normalize(row.word)) || current && (current.lastModifiedBy || current.status !== 'PUBLISHED')) {
        ledger.push({word: row.word, action: 'kept_manual_or_unpublished'});
        continue;
      }
      const data = referenceEntry(row, origin, categoryIds.get(category)!);
      operations.push({updateOne: {filter: current ? {_id: current._id} : {tags: tag},
        update: {$set: data, $setOnInsert: {createdBy: authorId, publishedAt: new Date()}}, upsert: !current}});
      ledger.push({word: row.word, category, action: current ? 'updated_managed_entry' : 'created',
        source: row.source, source_path: row.source_path});
    }
    for (let i = 0; i < operations.length; i += 250) {
      await DictionaryEntry.bulkWrite(operations.slice(i, i + 250), {session});
    }
    // Recount rather than increment so repeated imports cannot inflate category counts.
    const counts = await DictionaryEntry.aggregate([{$match: {status: 'PUBLISHED'}}, {$group: {_id: '$categoryId', count: {$sum: 1}}}]).session(session);
    await Category.updateMany({}, {$set: {wordCount: 0}}, {session});
    for (const item of counts) await Category.updateOne({_id: item._id}, {$set: {wordCount: item.count}}, {session});
    return ledger;
  });
}

async function main() {
  const root = path.resolve(__dirname, '../..');
  const {values} = parseArgs({options: {catalog: {type: 'string'}, origin: {type: 'string'}, apply: {type: 'boolean', default: false}}});
  const input = path.resolve(root, values.catalog || '.runtime/speech-sign-library/dictionary-20261024/library.json');
  const rows = JSON.parse(readFileSync(input, 'utf8')) as ReferenceRow[];
  const url = new URL(values.origin || env.PUBLIC_ORIGIN || env.WEB_ORIGIN);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.pathname !== '/' || url.search || url.hash) throw new Error('Use an HTTP/HTTPS origin without a path');
  const origin = url.origin;
  validateReferenceRows(rows, path.join(root, '.runtime/sign-library-media'));
  const categories: Record<string, number> = {};
  for (const row of rows) { const name = referenceCategory(row.word); categories[name] = (categories[name] || 0) + 1; }
  await connectDatabase();
  try {
    const author = await User.findOne({email: env.ADMIN_EMAIL, role: 'ADMIN', status: 'ACTIVE'}).select('_id');
    if (!author) throw new Error('Configured active admin not found');
    console.log(JSON.stringify({dryRun: !values.apply, catalogEntries: rows.length, existingPublished: await DictionaryEntry.countDocuments({status: 'PUBLISHED'}), origin, categories}));
    if (!values.apply) return;
    const backup = await DictionaryEntry.find({tags: /^svlib:/}).lean();
    const previousCategories = await Category.find().lean();
    const folder = path.dirname(input);
    writeFileSync(path.join(folder, 'before-import-' + Date.now() + '.json'), JSON.stringify({entries: backup, categories: previousCategories}, null, 2));
    const ledger = await importReferenceRows(rows, origin, author._id);
    writeFileSync(path.join(folder, 'import-ledger.json'), JSON.stringify(ledger, null, 2));
    console.log(JSON.stringify({processed: ledger.length, created: ledger.filter(row => row.action === 'created').length,
      updated: ledger.filter(row => row.action === 'updated_managed_entry').length,
      kept: ledger.filter(row => row.action === 'kept_manual_or_unpublished').length,
      publishedTotal: await DictionaryEntry.countDocuments({status: 'PUBLISHED'})}));
  } finally { await disconnectDatabase(); }
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
