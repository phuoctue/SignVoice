/** Import only the prepared source-attributed reference catalog. Idempotent by library tag.
 * Default is dry run. --apply is required for database writes; never changes AI models.
 */
import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { DictionaryEntry, EntryStatus } from '../src/models/DictionaryEntry.model';
import { Category, CategoryStatus } from '../src/models/Category.model';
import { User } from '../src/models/User.model';
import { env } from '../src/config/env';

async function main() {
  const root = path.resolve(__dirname, '../..');
  const input = path.join(root, '.runtime/speech-sign-library/expanded/library.json');
  const settings = JSON.parse(readFileSync(path.join(root, '.runtime/public-settings.json'), 'utf8').replace(/^\uFEFF/, ''));
  const origin = new URL(settings.publicOrigin).origin;
  if (!origin.startsWith('https://')) throw new Error('HTTPS public origin required');
  const rows = JSON.parse(readFileSync(input, 'utf8')) as Array<{
    word: string; media_id: string; source: string; source_url: string; license: string;
    source_sha256: string; source_path: string; source_split: string; alias_of?: string; keyframe_index?: number;
  }>;
  const words = new Set<string>();
  for (const row of rows) {
    if (!row.word || words.has(row.word) || row.source_split !== 'train' ||
        !/^[a-f0-9]{64}$/.test(row.media_id) || !['cc-by-4.0', 'apache-2.0'].includes(row.license)) {
      throw new Error('Invalid, duplicate, or unsupported catalog record');
    }
    words.add(row.word);
    for (const file of [`${row.media_id}.mp4`, ...[1, 2, 3, 4, 5].map(n => `${row.media_id}-${n}.jpg`)]) {
      if (!existsSync(path.join(root, '.runtime/sign-library-media', file))) throw new Error('Prepared media missing');
    }
  }
  if (!process.argv.includes('--apply')) { console.log(JSON.stringify({ dryRun: true, entries: rows.length, origin })); return; }
  await connectDatabase();
  try {
    const author = await User.findOne({ email: env.ADMIN_EMAIL, role: 'ADMIN', status: 'ACTIVE' }).select('_id');
    if (!author) throw new Error('Configured active admin account not found');
    let category = await Category.findOne({ slug: 'ky-hieu-tham-khao' });
    if (!category) category = await Category.create({ name: 'Ký hiệu tham khảo', slug: 'ky-hieu-tham-khao',
      description: 'Ảnh và video mẫu theo nguồn dataset, có ghi nguồn và giấy phép.', status: CategoryStatus.ACTIVE });
    const ledger: Array<Record<string, unknown>> = [];
    for (const row of rows) {
      const tag = `svlib:${createHash('sha256').update(row.word).digest('hex').slice(0, 32)}`;
      let entry = await DictionaryEntry.findOne({ tags: tag });
      const existing = await DictionaryEntry.findOne({ word: row.word, status: EntryStatus.PUBLISHED, tags: { $ne: tag } });
      if (existing) { ledger.push({ word: row.word, action: 'kept_existing', id: String(existing._id) }); continue; }
      const data = {
        word: row.word, definition: `Mẫu ký hiệu tham khảo cho “${row.word}”, theo nhãn của nguồn ${row.source}.`,
        videoUrl: `${origin}/sign-media/${row.media_id}.mp4`,
        thumbnailUrl: `${origin}/sign-media/${row.media_id}-${row.keyframe_index || 3}.jpg`,
        imageUrls: [1, 2, 3, 4, 5].map(n => `${origin}/sign-media/${row.media_id}-${n}.jpg`),
        categoryId: category._id,
        notes: `Nguồn: ${row.source} (${row.source_url}); giấy phép ${row.license}. ` +
          `Văn bản giấy phép: ${origin}/sign-media/license/${row.license}. ` +
          `Video đã bỏ âm thanh, chuyển H.264; ảnh trích theo thứ tự thời gian. ` +
          `Nhãn theo nguồn; chưa xác nhận chuyên gia về nghĩa và phương ngữ. ` +
          (row.alias_of ? `Cụm hiển thị dùng chung mẫu “${row.alias_of}”. ` : '') +
          `SHA256 gốc: ${row.source_sha256}.`,
        tags: [tag, 'mau-tham-khao'], status: EntryStatus.PUBLISHED,
      };
      const action = entry ? 'updated_managed_entry' : 'created';
      if (entry) { Object.assign(entry, data); await entry.save(); }
      else entry = await DictionaryEntry.create({ ...data, createdBy: author._id, publishedAt: new Date() });
      ledger.push({ word: row.word, action, id: String(entry._id), source: row.source, source_path: row.source_path });
    }
    category.wordCount = await DictionaryEntry.countDocuments({ categoryId: category._id, status: EntryStatus.PUBLISHED });
    await category.save();
    writeFileSync(path.join(root, '.runtime/speech-sign-library/expanded/import-ledger.json'), JSON.stringify(ledger, null, 2));
    console.log(JSON.stringify({ processed: ledger.length, categoryEntries: category.wordCount, origin }));
  } finally { await disconnectDatabase(); }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
