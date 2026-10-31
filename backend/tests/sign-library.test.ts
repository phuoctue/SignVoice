import {beforeAll, afterAll, describe, it, expect} from 'vitest';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {User, Category, DictionaryEntry, Favorite} from '../src/models';
import {referenceCategory, referenceAliases, reviewedReferenceCategories} from '../src/services/sign-library-categories';
import {getPublishedEntries} from '../src/services/dictionary.service';
import {createApp} from '../src/app';
import request from 'supertest';
import {reclassifyReferenceEntries} from '../scripts/reclassify-sign-library';
import {importReferenceRows, validateReferenceRows, ReferenceRow} from '../scripts/import-sign-library';

const row = (word: string): ReferenceRow => ({word, media_id: 'a'.repeat(64), source: 'user_Dataset.tgz',
  source_url: '', license: null, source_sha256: 'b'.repeat(64), source_path: 'sources/user_dictionary/Videos/example.mp4', source_split: ''});
beforeAll(async () => {
  await connectDatabase();
  await Promise.all([User, Category, DictionaryEntry, Favorite].map(model => model.init()));
});
afterAll(disconnectDatabase);

describe('reference library import', () => {
  it('moves only reviewed fallback words, preserving media, ids, favorites and later manual categories', async () => {
    const author = await User.create({email: 'topics@example.test', displayName: 'Topic Author', role: 'ADMIN', accountType: 'LOCAL', status: 'ACTIVE', passwordHash: 'test-only'});
    const fallback = await Category.create({name: 'Từ vựng khác', slug: 'tham-khao-tu-vung-khac', wordCount: 3});
    const manual = await Category.create({name: 'Custom topic', slug: 'custom-topic'});
    const make = (word: string, categoryId = fallback._id) => DictionaryEntry.create({word, categoryId,
      definition: 'Preserve this content.', videoUrl: 'https://example.org/original.mp4',
      imageUrls: ['https://example.org/original.jpg'], createdBy: author._id, status: 'PUBLISHED', favoriteCount: 1});
    const first = await make('ưu điểm'), second = await make('thần kì');
    const keep = await make('unreviewed word'), custom = await make('đề phòng', manual._id);
    await Favorite.create({userId: author._id, entryId: first._id});
    const before = first.toObject();
    expect(await reclassifyReferenceEntries()).toHaveLength(2);
    expect(await reclassifyReferenceEntries()).toHaveLength(0);
    const after = (await DictionaryEntry.findById(first._id))!.toObject();
    const {categoryId: _oldCategory, updatedAt: _oldTime, ...original} = before;
    const {categoryId: _newCategory, updatedAt: _newTime, ...preserved} = after;
    expect(preserved).toEqual(original);
    expect((await Category.findById(after.categoryId))!.name).toBe('Học tập và công việc');
    expect((await Category.findById((await DictionaryEntry.findById(second._id))!.categoryId))!.name).toBe('Văn hóa, tín ngưỡng và truyện kể');
    expect((await DictionaryEntry.findById(keep._id))!.categoryId).toEqual(fallback._id);
    expect((await DictionaryEntry.findById(custom._id))!.categoryId).toEqual(manual._id);
    expect((await Category.findById(fallback._id))!.wordCount).toBe(1);
    expect(await Favorite.exists({entryId: first._id})).toBeTruthy();
    // Other import tests start with their own managed categories.
    await DictionaryEntry.deleteMany({_id: {$in: [first._id, second._id, keep._id, custom._id]}});
    await Category.deleteOne({_id: fallback._id});
  });
  it('assigns all 152 reviewed labels to specific topics', () => {
    expect(Object.keys(reviewedReferenceCategories)).toHaveLength(152);
    for (const [word, category] of Object.entries(reviewedReferenceCategories)) {
      expect(referenceCategory(word)).toBe(category);
      expect(category).not.toBe('Từ vựng khác');
    }
    expect(referenceCategory('ưu điểm')).toBe('Học tập và công việc');
    expect(referenceCategory('đề phòng')).toBe('Hành động và tương tác');
    expect(referenceCategory('thần kì')).toBe('Văn hóa, tín ngưỡng và truyện kể');
    expect(referenceCategory('hối lộ')).toBe('Xã hội và pháp luật');
  });
  it('sorts the whole filtered catalog with Vietnamese and numeric order before paging', async () => {
    const author = await User.create({email: 'ordering@example.test', displayName: 'Sort Author', role: 'ADMIN', accountType: 'LOCAL', status: 'ACTIVE', passwordHash: 'test-only'});
    const category = await Category.create({name: 'Sort verification', slug: 'sort-verification'});
    const words = ['2', '10', 'an', 'ăn', 'ân', 'ba', 'da', 'đa', 'em', 'êm', 'ong', 'ông', 'ơn', 'u', 'ư'];
    await DictionaryEntry.insertMany([...words].reverse().map(word => ({word, categoryId: category._id,
      definition: 'sortfixture nội dung kiểm tra.', tags: ['sortfixture'],
      videoUrl: 'https://example.org/sort.mp4', createdBy: author._id, status: 'PUBLISHED'})));
    const options = {categoryId: category.id, search: 'sortfixture', limit: 100};
    expect((await getPublishedEntries({...options, sort: 'word_asc'})).entries.map(row => row.word)).toEqual(words);
    const reverse = (await getPublishedEntries({...options, sort: 'word_desc'})).entries;
    expect(reverse.map(row => row.word)).toEqual([...words].reverse());
    const app = await createApp();
    const response = await request(app).get('/api/v1/dictionary').query({categoryId: category.id,
      sort: 'word_desc', limit: 3, skip: 3, search: 'sortfixture'}).expect(200);
    expect(response.body.data.map((row: any) => row.word)).toEqual([...words].reverse().slice(3, 6));
    expect(response.body.pagination.total).toBe(words.length);
    await request(app).get('/api/v1/dictionary?sort=invalid').expect(400);
    const first = await getPublishedEntries({categoryId: category.id, sort: 'word_asc', limit: 4});
    const second = await getPublishedEntries({categoryId: category.id, sort: 'word_asc', limit: 4, skip: 4});
    expect([...first.entries, ...second.entries].map(row => row.word)).toEqual(words.slice(0, 8));
  });
  it('uses the supplied daily topics and explicit number aliases', () => {
    expect(referenceCategory('bạn')).toBe('Gia đình và quan hệ');
    expect(referenceCategory('bàn tay')).toBe('Cơ thể và sức khỏe');
    expect(referenceCategory('trường tiểu học')).toBe('Học tập và công việc');
    expect(referenceCategory('l')).toBe('Chữ cái và số');
    expect(referenceCategory('nước mắm')).toBe('Ăn uống');
    expect(referenceCategory('tiền giang')).toBe('Đi lại và vị trí');
    expect(referenceCategory('buồn nôn')).toBe('Cơ thể và sức khỏe');
    expect(referenceCategory('băng dính')).toBe('Sinh hoạt và đồ dùng');
    expect(referenceAliases('0 (số không)')).toEqual(['0', 'số không']);
    expect(referenceAliases('anh (nước Anh)')).toEqual(['nước anh']);
    expect(referenceAliases('gỏi/nộm')).toEqual(['gỏi', 'nộm']);
    expect(referenceAliases('trẻ con/con nít')).toEqual(['trẻ con', 'con nít']);
  });
  it('rejects duplicate, held-out or unsupported sources before database writes', () => {
    expect(() => validateReferenceRows([row('bạn'), row('BẠN')])).toThrow();
    expect(() => validateReferenceRows([{...row('bạn'), source_split: 'test'}])).toThrow();
    expect(() => validateReferenceRows([{...row('bạn'), source: 'personal_glyphs'}])).toThrow();
    expect(() => validateReferenceRows([{...row('bạn'), media_id: '../private'}])).toThrow();
  });
  it('keeps ids and favorites on repeated imports and preserves manually authored content', async () => {
    const author = await User.create({email: 'library@example.test', displayName: 'Library Author', role: 'ADMIN', accountType: 'LOCAL', status: 'ACTIVE', passwordHash: 'test-only'});
    const manualCategory = await Category.create({name: 'Manual category', slug: 'manual-library-test'});
    const manual = await DictionaryEntry.create({word: 'tôi', definition: 'Keep this manually authored definition.',
      videoUrl: 'https://example.org/manual.mp4', createdBy: author._id, categoryId: manualCategory._id, status: 'PUBLISHED'});
    const rows = [row('bạn'), row('l'), row('a'), row('tôi')];
    await importReferenceRows(rows, 'http://localhost:3002', author._id);
    const first = await DictionaryEntry.findOne({word: 'bạn'});
    await Favorite.create({userId: author._id, entryId: first!._id});
    await importReferenceRows(rows, 'http://localhost:3002', author._id);
    const second = await DictionaryEntry.findOne({word: 'bạn'});
    expect(second!.id).toBe(first!.id);
    expect(await DictionaryEntry.countDocuments({word: 'bạn'})).toBe(1);
    expect(await Favorite.exists({entryId: first!._id})).toBeTruthy();
    expect(second!.imageUrls).toHaveLength(5);
    expect((await Category.findById(second!.categoryId))!.wordCount).toBe(1);
    expect((await DictionaryEntry.findById(manual._id))!.definition).toBe('Keep this manually authored definition.');
    expect((await Category.findById(manualCategory._id))!.wordCount).toBe(1);
  });
});
