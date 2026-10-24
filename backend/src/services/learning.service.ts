import { PipelineStage, Types } from 'mongoose';
import { Category } from '../models/Category.model';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { TopicEnrollment, WordProgress } from '../models/Learning.model';
import { AppError } from '../common/errors/AppError';
import { existsSync } from 'node:fs';
import path from 'node:path';

export const PAGE_SIZE = 10;
export function objectId(value: string) {
  if (!/^[a-f0-9]{24}$/i.test(value)) throw new AppError('Mã không hợp lệ.', 400, 'INVALID_ID');
  return new Types.ObjectId(value);
}
export function regexLiteral(value: string) { return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
export function pagination(page: number, total: number) {
  return { page, pageSize: PAGE_SIZE, total, pages: Math.max(1, Math.ceil(total / PAGE_SIZE)) };
}
const projectedEntry = { word: 1, definition: 1, categoryId: 1, thumbnailUrl: 1, imageUrls: 1, videoUrl: 1, usageExample: 1, notes: 1 };
const mediaRoot = path.resolve(__dirname, '../../../.runtime/sign-library-media');
function availableMedia(value: unknown): string {
  if (typeof value !== 'string' || !value) return '';
  let filename: string;
  try { filename = new URL(value, 'http://localhost').pathname.split('/sign-media/')[1] || ''; }
  catch { return ''; }
  if (!filename) return value;
  return /^[a-f0-9]{64}(?:-[1-5])?\.(?:mp4|jpg)$/.test(filename) && existsSync(path.join(mediaRoot, filename)) ? value : '';
}
function withAvailableMedia(word: Record<string, unknown>) {
  const videoUrl = availableMedia(word.videoUrl);
  const thumbnailUrl = availableMedia(word.thumbnailUrl);
  const imageUrls = Array.isArray(word.imageUrls) ? word.imageUrls.map(availableMedia).filter(Boolean) : [];
  return { ...word, videoUrl, thumbnailUrl, imageUrls, mediaUnavailable: !videoUrl && !thumbnailUrl && !imageUrls.length };
}

export async function topicOrFail(id: Types.ObjectId) {
  const topic = await Category.findOne({ _id: id, status: 'ACTIVE' }).lean();
  if (!topic) throw new AppError('Chủ đề không còn khả dụng.', 404, 'TOPIC_NOT_FOUND');
  return topic;
}

export function progressStages(userId: Types.ObjectId): PipelineStage.FacetPipelineStage[] {
  return [
    { $lookup: { from: WordProgress.collection.name, let: { entry: '$_id' }, pipeline: [
      { $match: { userId, $expr: { $eq: ['$entryId', '$$entry'] } } },
      { $project: { stage: 1, nextReviewAt: 1, reviewedAt: 1 } },
    ], as: 'progress' } },
    { $set: { progress: { $first: '$progress' } } },
    { $set: { stage: { $cond: [
      { $and: [{ $eq: ['$progress.stage', 'REMEMBERED'] }, { $ne: [{ $ifNull: ['$progress.nextReviewAt', null] }, null] }, { $lte: ['$progress.nextReviewAt', new Date()] }] },
      'REVIEW', { $ifNull: ['$progress.stage', 'LEARNING'] },
    ] } } },
  ];
}

export async function topicWords(userId: Types.ObjectId, topicId: Types.ObjectId, page: number, stage?: string): Promise<{
  topic: Record<string, unknown>; enrolled: boolean;
  summary: { learning: number; remembered: number; review: number; total: number };
  items: Record<string, unknown>[]; pagination: ReturnType<typeof pagination>;
}> {
  const [topic, enrollment, result, learners] = await Promise.all([
    topicOrFail(topicId), TopicEnrollment.findOne({ userId, topicId }).lean(),
    DictionaryEntry.aggregate([
      { $match: { categoryId: topicId, status: 'PUBLISHED' } },
      { $project: projectedEntry }, ...progressStages(userId),
      { $facet: {
        summary: [{ $group: { _id: '$stage', count: { $sum: 1 } } }],
        count: [...(stage ? [{ $match: { stage } }] : []), { $count: 'total' }],
        items: [...(stage ? [{ $match: { stage } }] : []), { $sort: { word: 1, _id: 1 } }, { $skip: (page - 1) * PAGE_SIZE }, { $limit: PAGE_SIZE }],
      } },
    ]), TopicEnrollment.countDocuments({ topicId }),
  ]);
  const data = result[0];
  const summary = { learning: 0, remembered: 0, review: 0, total: 0 };
  for (const row of data.summary) {
    summary.total += row.count;
    if (row._id === 'REMEMBERED') summary.remembered += row.count;
    else if (row._id === 'REVIEW') summary.review += row.count;
    else summary.learning += row.count;
  }
  return { topic: { ...topic, learnerCount: learners }, enrolled: !!enrollment, summary, items: data.items.map(withAvailableMedia), pagination: pagination(page, data.count[0]?.total || 0) };
}

export async function exploreTopics(userId: Types.ObjectId, page: number, search = '') {
  const result = await Category.aggregate([
    { $match: { status: 'ACTIVE', ...(search ? { name: { $regex: regexLiteral(search), $options: 'i' } } : {}) } },
    { $lookup: { from: DictionaryEntry.collection.name, let: { topic: '$_id' }, pipeline: [
      { $match: { status: 'PUBLISHED', $expr: { $eq: ['$categoryId', '$$topic'] } } },
      { $sort: { _id: 1 } },
      { $group: { _id: null, count: { $sum: 1 }, image: { $first: '$thumbnailUrl' } } },
    ], as: 'words' } },
    { $set: { wordCount: { $ifNull: [{ $first: '$words.count' }, 0] }, imageUrl: { $first: '$words.image' } } },
    { $match: { wordCount: { $gt: 0 } } },
    { $lookup: { from: TopicEnrollment.collection.name, let: { topic: '$_id' }, pipeline: [
      { $match: { $expr: { $eq: ['$topicId', '$$topic'] } } },
      { $group: { _id: null, count: { $sum: 1 }, enrolled: { $max: { $cond: [{ $eq: ['$userId', userId] }, 1, 0] } } } },
    ], as: 'learners' } },
    { $set: { learnerCount: { $ifNull: [{ $first: '$learners.count' }, 0] }, enrolled: { $eq: [{ $first: '$learners.enrolled' }, 1] } } },
    { $project: { words: 0, learners: 0 } },
    { $sort: { sortOrder: 1, _id: 1 } },
    { $facet: { items: [{ $skip: (page - 1) * PAGE_SIZE }, { $limit: PAGE_SIZE }], count: [{ $count: 'total' }] } },
  ]);
  return { items: result[0].items.map((topic: Record<string, unknown>) => ({ ...topic, imageUrl: availableMedia(topic.imageUrl) })), pagination: pagination(page, result[0].count[0]?.total || 0) };
}

export async function enrolledTopics(userId: Types.ObjectId, page: number, stage?: string) {
  const result = await TopicEnrollment.aggregate([
    { $match: { userId } },
    { $lookup: { from: Category.collection.name, localField: 'topicId', foreignField: '_id', as: 'topic' } },
    { $unwind: '$topic' }, { $match: { 'topic.status': 'ACTIVE' } },
    { $lookup: { from: DictionaryEntry.collection.name, let: { topic: '$topicId' }, pipeline: [
      { $match: { status: 'PUBLISHED', $expr: { $eq: ['$categoryId', '$$topic'] } } },
      { $project: { _id: 1 } }, ...progressStages(userId),
      { $group: { _id: null, total: { $sum: 1 },
        learning: { $sum: { $cond: [{ $eq: ['$stage', 'LEARNING'] }, 1, 0] } },
        remembered: { $sum: { $cond: [{ $eq: ['$stage', 'REMEMBERED'] }, 1, 0] } },
        review: { $sum: { $cond: [{ $eq: ['$stage', 'REVIEW'] }, 1, 0] } },
      } },
    ], as: 'counts' } },
    { $set: { summary: { $first: '$counts' } } },
    { $match: { 'summary.total': { $gt: 0 } } },
    { $sort: { updatedAt: -1, _id: 1 } },
    { $facet: {
      totals: [{ $group: { _id: null, total: { $sum: '$summary.total' }, learning: { $sum: '$summary.learning' }, remembered: { $sum: '$summary.remembered' }, review: { $sum: '$summary.review' } } }],
      count: [...(stage ? [{ $match: { [`summary.${stage}`]: { $gt: 0 } } }] : []), { $count: 'total' }],
      items: [...(stage ? [{ $match: { [`summary.${stage}`]: { $gt: 0 } } }] : []), { $skip: (page - 1) * PAGE_SIZE }, { $limit: PAGE_SIZE }, { $project: { counts: 0 } }],
    } },
  ]);
  return { items: result[0].items, summary: result[0].totals[0] || { total: 0, learning: 0, remembered: 0, review: 0 }, pagination: pagination(page, result[0].count[0]?.total || 0) };
}
