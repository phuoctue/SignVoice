import { Types } from 'mongoose';
import { DictionaryEntry, EntryStatus, IDictionaryEntry } from '../models/DictionaryEntry.model';
import { Category } from '../models/Category.model';
import { SearchHistory } from '../models/SearchHistory.model';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';
import { userTransaction } from './user-data.service';

/**
 * Get published dictionary entries with filters
 */
export async function getPublishedEntries(options: {
  categoryId?: string;
  search?: string;
  difficulty?: string;
  sort?: 'word_asc' | 'word_desc';
  limit?: number;
  skip?: number;
}): Promise<{ entries: IDictionaryEntry[]; total: number }> {
  const activeCategories = await Category.find({status: 'ACTIVE'}).distinct('_id');
  const filter: any = { status: EntryStatus.PUBLISHED, categoryId: {$in: activeCategories} };
  
  if (options.categoryId) {
    filter.categoryId = {$in: activeCategories.filter(id => String(id) === options.categoryId)};
  }
  
  if (options.difficulty) {
    filter.difficulty = options.difficulty;
  }
  
  const limit = Math.min(options.limit || 20, 100);
  const skip = options.skip || 0;
  
  if (options.search) filter.$text = {$search: options.search};
  let listingFilter = filter;
  let matchedTotal: number | undefined;
  if (options.sort && options.search) {
    // Mongo text indexes require simple collation. Resolve matches first, then
    // order those same entries using Vietnamese collation before pagination.
    const matches = await DictionaryEntry.find(filter).select('_id').lean();
    listingFilter = {...filter, _id: {$in: matches.map(entry => entry._id)}};
    delete listingFilter.$text;
    matchedTotal = matches.length;
  }
  const query = DictionaryEntry.find(listingFilter);
  if (options.sort) {
    const direction = options.sort === 'word_asc' ? 1 : -1;
    query.collation({locale: 'vi', strength: 3, numericOrdering: true})
      .sort({word: direction, _id: direction});
  } else if (options.search) {
    query.select({score: {$meta: 'textScore'}})
      .sort({score: {$meta: 'textScore'}, viewCount: -1, _id: 1});
  } else {
    query.sort({publishedAt: -1, _id: -1});
  }
  const [entries, total] = await Promise.all([
    query.limit(limit).skip(skip).populate('categoryId', 'name slug icon').exec(),
    matchedTotal ?? DictionaryEntry.countDocuments(filter),
  ]);
  return {entries, total};
}

/**
 * Get dictionary entry by ID
 */
export async function getEntryById(
  entryId: string,
  userId?: Types.ObjectId
): Promise<IDictionaryEntry> {
  if (!Types.ObjectId.isValid(entryId)) {
    throw new AppError('Invalid entry ID', 400, ErrorCodes.BAD_REQUEST);
  }
  
  const entry = await DictionaryEntry.findById(entryId)
    .populate('categoryId', 'name slug icon status')
    .populate('createdBy', 'displayName')
    .exec();
  
  if (!entry) {
    throw new AppError('Entry not found', 404, ErrorCodes.DICT_ENTRY_NOT_FOUND);
  }
  
  if (entry.status !== EntryStatus.PUBLISHED) {
    throw new AppError('Entry not available', 404, ErrorCodes.DICT_NOT_PUBLISHED);
  }
  if (!entry.categoryId || (entry.categoryId as any).status !== 'ACTIVE') {
    throw new AppError('Danh mục không còn hoạt động.', 404, ErrorCodes.DICT_NOT_PUBLISHED);
  }
  
  // Increment view count asynchronously
  entry.incrementViewCount().catch(err => console.error('Failed to increment view count:', err));
  
  // Record search history if user is authenticated
  if (userId) {
    await userTransaction(userId, session => SearchHistory.findOneAndUpdate(
      { userId, entryId: entry._id },
      { $set: { viewedAt: new Date() } },
      { upsert: true, session }
    ).exec());
  }
  
  return entry;
}

/**
 * Get popular entries
 */
export async function getPopularEntries(limit: number = 10): Promise<IDictionaryEntry[]> {
  const activeCategories = await Category.find({status: 'ACTIVE'}).distinct('_id');
  return await DictionaryEntry.find({ status: EntryStatus.PUBLISHED, categoryId: {$in: activeCategories} })
    .sort({ viewCount: -1, publishedAt: -1 })
    .limit(Math.min(limit, 50))
    .populate('categoryId', 'name slug icon')
    .exec();
}

/**
 * Create draft entry (STAFF/ADMIN only)
 */
export async function createDraftEntry(
  userId: Types.ObjectId,
  data: {
    word: string;
    definition: string;
    videoUrl: string;
    thumbnailUrl?: string;
    imageUrls?: string[];
    categoryId: string;
    tags?: string[];
    difficulty?: string;
    usageExample?: string;
    notes?: string;
  }
): Promise<IDictionaryEntry> {
  // Validate category
  if (!Types.ObjectId.isValid(data.categoryId)) {
    throw new AppError('Invalid category ID', 400, ErrorCodes.BAD_REQUEST);
  }
  
  const category = await Category.findById(data.categoryId);
  if (!category || !category.isActive()) {
    throw new AppError('Category not found or inactive', 404, ErrorCodes.CATEGORY_NOT_FOUND);
  }
  
  // Create draft
  const entry = await DictionaryEntry.create({
    ...data,
    status: EntryStatus.DRAFT,
    createdBy: userId,
    viewCount: 0,
    favoriteCount: 0,
  });
  
  return entry;
}

/**
 * Update draft entry (STAFF/ADMIN only)
 */
export async function updateDraftEntry(
  entryId: string,
  userId: Types.ObjectId,
  userRole: string,
  data: Partial<{
    word: string;
    definition: string;
    videoUrl: string;
    thumbnailUrl: string;
    imageUrls: string[];
    categoryId: string;
    tags: string[];
    difficulty: string;
    usageExample: string;
    notes: string;
  }>
): Promise<IDictionaryEntry> {
  if (!Types.ObjectId.isValid(entryId)) {
    throw new AppError('Invalid entry ID', 400, ErrorCodes.BAD_REQUEST);
  }
  
  const entry = await DictionaryEntry.findById(entryId);
  
  if (!entry) {
    throw new AppError('Entry not found', 404, ErrorCodes.DICT_ENTRY_NOT_FOUND);
  }
  
  // Check ownership for STAFF (ADMIN can edit any)
  if (userRole === 'STAFF' && !entry.createdBy.equals(userId)) {
    throw new AppError('Not authorized to edit this entry', 403, ErrorCodes.AUTH_FORBIDDEN);
  }
  
  // Only drafts can be edited
  if (entry.status !== EntryStatus.DRAFT) {
    throw new AppError('Only draft entries can be edited', 400, ErrorCodes.DICT_NOT_DRAFT);
  }
  
  // Update fields
  Object.assign(entry, data);
  entry.lastModifiedBy = userId;
  
  await entry.save();
  return entry;
}

/**
 * Publish entry (ADMIN only)
 */
export async function publishEntry(entryId: string): Promise<IDictionaryEntry> {
  if (!Types.ObjectId.isValid(entryId)) {
    throw new AppError('Invalid entry ID', 400, ErrorCodes.BAD_REQUEST);
  }
  
  const entry = await DictionaryEntry.findById(entryId);
  
  if (!entry) {
    throw new AppError('Entry not found', 404, ErrorCodes.DICT_ENTRY_NOT_FOUND);
  }
  
  if (entry.status === EntryStatus.PUBLISHED) {
    throw new AppError('Entry already published', 400, ErrorCodes.BAD_REQUEST);
  }
  
  entry.status = EntryStatus.PUBLISHED;
  entry.publishedAt = new Date();
  await entry.save();
  
  // Update category word count
  await Category.findByIdAndUpdate(entry.categoryId, {
    $inc: { wordCount: 1 },
  });
  
  return entry;
}

/**
 * Archive entry (ADMIN only)
 */
export async function archiveEntry(entryId: string): Promise<IDictionaryEntry> {
  if (!Types.ObjectId.isValid(entryId)) {
    throw new AppError('Invalid entry ID', 400, ErrorCodes.BAD_REQUEST);
  }
  
  const entry = await DictionaryEntry.findById(entryId);
  
  if (!entry) {
    throw new AppError('Entry not found', 404, ErrorCodes.DICT_ENTRY_NOT_FOUND);
  }
  
  const wasPublished = entry.status === EntryStatus.PUBLISHED;
  
  entry.status = EntryStatus.ARCHIVED;
  await entry.save();
  
  // Update category word count if was published
  if (wasPublished) {
    await Category.findByIdAndUpdate(entry.categoryId, {
      $inc: { wordCount: -1 },
    });
  }
  
  return entry;
}
