import { PipelineStage, Types } from 'mongoose';
import { AppError } from '../common/errors/AppError';
import { LearningEvent } from '../models/LearningEvent.model';
import { ReviewQuiz } from '../models/ReviewQuiz.model';
import { UserSettings } from '../models/UserSettings.model';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { Category } from '../models/Category.model';
import { TopicEnrollment } from '../models/Learning.model';
import { pagination, PAGE_SIZE, withAvailableMedia } from './learning.service';

const DAY = 86400000, VN_OFFSET = 7 * 3600000;
interface WeakWord extends Record<string, unknown> { _id: Types.ObjectId; missRate: number }
interface WeakFacet { items: WeakWord[]; count: { total: number }[] }
export function learningCalendar(days: 1 | 7 | 30, now = new Date()) {
  const localDate = new Date(now.getTime() + VN_OFFSET).toISOString().slice(0, 10);
  const midnight = Date.parse(`${localDate}T00:00:00Z`);
  const dates = Array.from({ length: days }, (_, i) => new Date(midnight - (days - 1 - i) * DAY).toISOString().slice(0, 10));
  return { dates, start: new Date(midnight - (days - 1) * DAY - VN_OFFSET), now, startDate: dates[0], endDate: localDate };
}

function studyStages(userId: Types.ObjectId, start: Date, now: Date): PipelineStage[] {
  return [
    { $match: { userId, kind: 'SELF_RATED', entryId: { $ne: null }, createdAt: { $gte: start, $lte: now } } },
    { $group: { _id: { day: { $dateToString: { date: '$createdAt', format: '%Y-%m-%d', timezone: '+07:00' } }, entry: '$entryId' },
      first: { $max: { $cond: [{ $eq: ['$firstLearning', true] }, 1, 0] } } } },
    { $group: { _id: '$_id.day', learned: { $sum: 1 }, newWords: { $sum: '$first' } } },
  ];
}
function reviewStages(userId: Types.ObjectId, start: Date, now: Date): PipelineStage[] {
  return [
    { $match: { userId, status: 'COMPLETED', 'result.source': { $in: ['sign-ai-camera', 'video-choice', 'video-recall'] }, completedAt: { $gte: start, $lte: now } } },
    { $unwind: '$result.items' },
    { $match: { 'result.items.entryId': { $type: 'string' }, 'result.items.score': { $in: [0, 10] } } },
    { $group: { _id: { day: { $dateToString: { date: '$completedAt', format: '%Y-%m-%d', timezone: '+07:00' } }, entry: '$result.items.entryId' }, lastQuizAt: { $max: '$completedAt' } } },
    { $group: { _id: '$_id.day', reviewed: { $sum: 1 }, lastQuizAt: { $max: '$lastQuizAt' } } },
  ];
}
function savedGoals(settings: { learningGoals?: { newWords?: number; reviewWords?: number } } | null) {
  return { newWords: settings?.learningGoals?.newWords || 5, reviewWords: settings?.learningGoals?.reviewWords || 10 };
}
export async function learningToday(userId: Types.ObjectId, now = new Date()) {
  const period = learningCalendar(1, now);
  const [studies, reviews, settings] = await Promise.all([
    LearningEvent.aggregate(studyStages(userId, period.start, now)),
    ReviewQuiz.aggregate(reviewStages(userId, period.start, now)),
    UserSettings.findOne({ userId }).select('learningGoals').lean(),
  ]);
  return { timeZone: 'Asia/Ho_Chi_Minh', today: fillLearningDays(period, studies, reviews)[0], goals: savedGoals(settings), lastQuizAt: reviews[0]?.lastQuizAt || null };
}

interface DayWord extends Record<string, unknown> { _id: Types.ObjectId | string; isNew?: number }
interface DayFacet { items: DayWord[]; count: { total: number }[] }
export function learningDayRange(date: string) {
  const midnight = Date.parse(`${date}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(midnight) || new Date(midnight).toISOString().slice(0, 10) !== date) {
    throw new AppError('Ngày chưa hợp lệ.', 400, 'INVALID_LEARNING_DATE');
  }
  return { start: new Date(midnight - VN_OFFSET), end: new Date(midnight + DAY - VN_OFFSET) };
}
export async function learningDayWords(userId: Types.ObjectId, date: string, kind: 'learned' | 'reviewed', page = 1, now = new Date()) {
  const { start, end } = learningDayRange(date);
  const range = { $gte: start, $lt: end, $lte: now };
  const tail: PipelineStage[] = [{ $sort: { occurredAt: -1, _id: 1 } },
    { $facet: { count: [{ $count: 'total' }], items: [{ $skip: (page - 1) * PAGE_SIZE }, { $limit: PAGE_SIZE }] } }];
  const rows = kind === 'learned'
    ? await LearningEvent.aggregate<DayFacet>([
      { $match: { userId, kind: 'SELF_RATED', entryId: { $ne: null }, createdAt: range } },
      { $sort: { createdAt: -1, _id: -1 } },
      { $group: { _id: '$entryId', word: { $first: '$word' }, topicName: { $first: '$topicName' },
        occurredAt: { $first: '$createdAt' }, stage: { $first: '$stage' }, isNew: { $max: { $cond: [{ $eq: ['$firstLearning', true] }, 1, 0] } } } },
      ...tail,
    ])
    : await ReviewQuiz.aggregate<DayFacet>([
      { $match: { userId, status: 'COMPLETED', 'result.source': { $in: ['sign-ai-camera', 'video-choice', 'video-recall'] }, completedAt: range } },
      { $unwind: '$result.items' },
      { $match: { 'result.items.entryId': { $type: 'string' }, 'result.items.score': { $in: [0, 10] } } },
      { $sort: { completedAt: -1, _id: -1 } },
      { $group: { _id: '$result.items.entryId', word: { $first: '$result.items.word' }, topicId: { $first: '$topicId' },
        occurredAt: { $first: '$completedAt' }, matched: { $first: { $eq: ['$result.items.score', 10] } }, attempts: { $sum: 1 } } },
      { $lookup: { from: Category.collection.name, localField: 'topicId', foreignField: '_id', as: 'topic' } },
      { $project: { word: 1, occurredAt: 1, matched: 1, attempts: 1,
        topicName: { $ifNull: [{ $first: '$topic.name' }, 'Chủ đề đã được gỡ'] } } },
      ...tail,
    ]);
  const result = rows[0];
  return { date, kind, timeZone: 'Asia/Ho_Chi_Minh', items: (result?.items || []).map(({ _id, ...item }) =>
    ({ ...item, entryId: String(_id), isNew: Boolean(item.isNew) })), pagination: pagination(page, result?.count[0]?.total || 0) };
}
export function fillLearningDays(period: ReturnType<typeof learningCalendar>, studies: { _id: string; learned: number; newWords: number }[], reviews: { _id: string; reviewed: number }[]) {
  const study = new Map(studies.map(row => [row._id, row]));
  const review = new Map(reviews.map(row => [row._id, row.reviewed]));
  return period.dates.map(date => ({ date, learned: study.get(date)?.learned || 0,
    newWords: study.get(date)?.newWords || 0, reviewed: review.get(date) || 0 }));
}

export async function learningInsights(userId: Types.ObjectId, days: 7 | 30, page = 1, now = new Date()) {
  const period = learningCalendar(days, now);
  const weakPeriod = learningCalendar(30, now);
  const quizFilter = (start: Date) => ({ userId, status: 'COMPLETED', 'result.source': { $in: ['sign-ai-camera', 'video-choice', 'video-recall'] }, completedAt: { $gte: start, $lte: now } });
  const [studies, reviews, weak, settings] = await Promise.all([
    LearningEvent.aggregate(studyStages(userId, period.start, now)),
    ReviewQuiz.aggregate(reviewStages(userId, period.start, now)),
    ReviewQuiz.aggregate<WeakFacet>([
      { $match: quizFilter(weakPeriod.start) }, { $unwind: '$result.items' },
      { $match: { 'result.items.score': { $in: [0, 10] } } },
      { $set: { entryObjectId: { $convert: { input: '$result.items.entryId', to: 'objectId', onError: null, onNull: null } } } },
      { $match: { entryObjectId: { $ne: null } } },
      { $sort: { completedAt: -1, _id: -1 } },
      { $group: { _id: '$entryObjectId', attempts: { $sum: 1 }, misses: { $sum: { $cond: [{ $eq: ['$result.items.score', 0] }, 1, 0] } },
        lastScore: { $first: '$result.items.score' }, lastReviewedAt: { $first: '$completedAt' } } },
      { $match: { misses: { $gt: 0 } } },
      { $lookup: { from: DictionaryEntry.collection.name, localField: '_id', foreignField: '_id', as: 'entry' } },
      { $unwind: '$entry' }, { $match: { 'entry.status': 'PUBLISHED' } },
      { $lookup: { from: Category.collection.name, localField: 'entry.categoryId', foreignField: '_id', as: 'topic' } },
      { $unwind: '$topic' }, { $match: { 'topic.status': 'ACTIVE' } },
      { $lookup: { from: TopicEnrollment.collection.name, let: { topic: '$entry.categoryId' }, pipeline: [
        { $match: { userId, $expr: { $eq: ['$topicId', '$$topic'] } } }, { $limit: 1 },
      ], as: 'enrollment' } },
      { $match: { 'enrollment.0': { $exists: true } } },
      { $project: { _id: 1, attempts: 1, misses: 1, lastReviewedAt: 1,
        latestMatched: { $eq: ['$lastScore', 10] }, missRate: { $multiply: [{ $divide: ['$misses', '$attempts'] }, 100] },
        word: '$entry.word', definition: '$entry.definition', usageExample: '$entry.usageExample', notes: '$entry.notes',
        thumbnailUrl: '$entry.thumbnailUrl', imageUrls: '$entry.imageUrls', videoUrl: '$entry.videoUrl',
        topicId: '$entry.categoryId', topicName: '$topic.name' } },
      { $sort: { misses: -1, missRate: -1, lastReviewedAt: -1, _id: 1 } },
      { $facet: { count: [{ $count: 'total' }], items: [{ $skip: (page - 1) * PAGE_SIZE }, { $limit: PAGE_SIZE }] } },
    ]),
    UserSettings.findOne({ userId }).select('learningGoals').lean(),
  ]);
  const activity = fillLearningDays(period, studies, reviews);
  const goals = savedGoals(settings);
  const weakData = weak[0];
  return { timeZone: 'Asia/Ho_Chi_Minh', days, startDate: period.startDate, endDate: period.endDate,
    activity, today: activity[activity.length - 1], goals, lastQuizAt: reviews.find(row => row._id === period.endDate)?.lastQuizAt || null,
    weakWords: { items: (weakData?.items || []).map(item => ({ ...withAvailableMedia(item), entryId: String(item._id), missRate: Math.round(item.missRate) })),
      pagination: pagination(page, weakData?.count[0]?.total || 0) } };
}
