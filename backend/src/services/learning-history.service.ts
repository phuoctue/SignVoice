import { Types } from 'mongoose';
import { LearningEvent } from '../models/LearningEvent.model';
import { WordProgress } from '../models/Learning.model';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { Category } from '../models/Category.model';
import { pagination, regexLiteral, PAGE_SIZE } from './learning.service';

/** Older data is a labeled last-state snapshot, never a fabricated series of past events. */
export async function learningHistory(userId: Types.ObjectId, page: number, search = '', entryId?: Types.ObjectId) {
  const owner = { userId, ...(entryId ? { entryId } : {}) };
  const [data] = await LearningEvent.aggregate([
    { $match: owner },
    { $project: { userId: 0, __v: 0 } },
    { $unionWith: { coll: WordProgress.collection.name, pipeline: [
      { $match: owner },
      { $lookup: { from: LearningEvent.collection.name, let: { entry: '$entryId' }, pipeline: [
        { $match: { userId, $expr: { $eq: ['$entryId', '$$entry'] } } }, { $limit: 1 },
      ], as: 'events' } },
      { $match: { events: { $size: 0 } } },
      { $lookup: { from: DictionaryEntry.collection.name, localField: 'entryId', foreignField: '_id', as: 'entry' } },
      { $lookup: { from: Category.collection.name, localField: 'topicId', foreignField: '_id', as: 'topic' } },
      { $project: { _id: 1, entryId: 1, topicId: 1, stage: 1,
        kind: { $literal: 'RECORDED_PROGRESS' }, applied: { $literal: true },
        word: { $ifNull: [{ $first: '$entry.word' }, 'Từ đã được gỡ'] },
        topicName: { $ifNull: [{ $first: '$topic.name' }, 'Chủ đề đã được gỡ'] },
        createdAt: { $ifNull: ['$reviewedAt', '$updatedAt'] },
      } },
    ] } },
    ...(search ? [{ $match: { $or: [
      { word: { $regex: regexLiteral(search), $options: 'i' } },
      { topicName: { $regex: regexLiteral(search), $options: 'i' } },
    ] } }] : []),
    { $sort: { createdAt: -1, _id: -1 } },
    { $facet: { count: [{ $count: 'total' }], items: [{ $skip: (page - 1) * PAGE_SIZE }, { $limit: PAGE_SIZE }] } },
  ]);
  return { items: data?.items || [], pagination: pagination(page, data?.count[0]?.total || 0) };
}
