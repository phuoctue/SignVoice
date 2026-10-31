import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { rateLimit } from 'express-rate-limit';
import {requireActiveTrial} from '../common/middlewares/guest-trial.middleware';
import { requireAuth, requirePermanentAccount } from '../common/middlewares/auth.middleware';
import { AppError } from '../common/errors/AppError';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { PersonalWord, TopicEnrollment, WordProgress } from '../models/Learning.model';
import { exploreTopics, enrolledTopics, objectId, pagination, regexLiteral, topicOrFail, topicWords, PAGE_SIZE } from '../services/learning.service';
import { learningAdvice } from '../services/learning-coach.service';
import { analyzeLearningProgress } from '../services/learning-analysis.service';
import {startLearningAiJob,getLearningAiJob} from '../services/learning-ai-jobs.service';
import { learningHistory } from '../services/learning-history.service';
import { LearningEvent } from '../models/LearningEvent.model';
import { learningInsights, learningToday, learningDayWords } from '../services/learning-insights.service';
import { UserSettings } from '../models/UserSettings.model';
import { userTransaction } from '../services/user-data.service';
import { startReviewQuiz, getReviewQuiz, saveReviewAnswers, saveReviewCapture, submitReviewQuiz, hintReviewRecall, checkReviewRecall, assessReviewRecall } from '../services/review-quiz.service';

const router = Router();
router.use(requireAuth);
router.use((req, res, next) => {
  const publicPreview = req.method === 'GET' && (req.path === '/topics' ||
    /^\/topics\/[a-f0-9]{24}$/i.test(req.path) && (!req.query.stage || req.query.stage === 'ALL'));
  if (publicPreview) return next();
  return requireActiveTrial(req, res, next);
});
router.use('/my-words', requirePermanentAccount);
router.use((_req, res, next) => { res.setHeader('Cache-Control', 'no-store'); next(); });
const wrap = (fn: (req: Request, res: Response) => Promise<unknown>) => (req: Request, res: Response, next: NextFunction) => { void fn(req, res).catch(next); };
const pageSchema = z.coerce.number().int().min(1).max(10000).default(1);
function parse<S extends z.ZodTypeAny>(schema: S, value: unknown): z.output<S> {
  const parsed = schema.safeParse(value);
  if (!parsed.success) throw new AppError('Dữ liệu chưa hợp lệ. Vui lòng kiểm tra lại.', 400, 'INVALID_LEARNING_INPUT');
  return parsed.data;
}
const querySchema = z.object({ page: pageSchema, search: z.string().trim().max(80).default('') });
const stageSchema = z.enum(['LEARNING', 'REMEMBERED', 'REVIEW']);
const optionalStage = z.enum(['ALL', 'LEARNING', 'REMEMBERED', 'REVIEW']).default('ALL');

router.get('/insights', wrap(async (req, res) => {
  const query = parse(z.object({ days: z.enum(['7', '30']).default('7'), page: pageSchema }).strict(), req.query);
  return res.json({ success: true, data: await learningInsights(req.user!.id, query.days === '30' ? 30 : 7, query.page) });
}));
router.get('/today', wrap(async (req, res) => {
  parse(z.object({}).strict(), req.query);
  return res.json({ success: true, data: await learningToday(req.user!.id) });
}));
router.get('/activity', wrap(async (req, res) => {
  const query = parse(z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), kind: z.enum(['learned', 'reviewed']).default('learned'), page: pageSchema }).strict(), req.query);
  return res.json({ success: true, data: await learningDayWords(req.user!.id, query.date, query.kind, query.page) });
}));
router.patch('/goals', wrap(async (req, res) => {
  const goals = parse(z.object({ newWords: z.number().int().min(1).max(100), reviewWords: z.number().int().min(1).max(200) }).strict(), req.body);
  await userTransaction(req.user!.id, session => UserSettings.updateOne({ userId: req.user!.id }, { $set: { learningGoals: goals } }, { upsert: true, runValidators: true, session }));
  return res.json({ success: true, data: goals });
}));

router.get('/history', wrap(async (req, res) => {
  const query = parse(querySchema.extend({ entryId: z.string().regex(/^[a-f0-9]{24}$/i).optional(), pageSize: z.coerce.number().int().refine(value => [10, 20, 50].includes(value)).default(10) }).strict(), req.query);
  return res.json({ success: true, data: await learningHistory(req.user!.id, query.page, query.search,
    query.entryId ? objectId(query.entryId) : undefined, query.pageSize) });
}));

router.get('/topics', wrap(async (req, res) => {
  const query = parse(querySchema, req.query);
  return res.json({ success: true, data: await exploreTopics(req.user!.id, query.page, query.search) });
}));
router.get('/progress', wrap(async (req, res) => {
  const page = parse(pageSchema, req.query.page);
  const stage = parse(optionalStage, req.query.stage);
  return res.json({ success: true, data: await enrolledTopics(req.user!.id, page, stage === 'ALL' ? undefined : stage.toLowerCase()) });
}));
router.get('/topics/:id', wrap(async (req, res) => {
  const stage = parse(optionalStage, req.query.stage);
  return res.json({ success: true, data: await topicWords(req.user!.id, objectId(req.params.id), parse(pageSchema, req.query.page), stage === 'ALL' ? undefined : stage) });
}));
router.post('/topics/:id/start', wrap(async (req, res) => {
  const topicId = objectId(req.params.id);
  const topic = await topicOrFail(topicId);
  if (!await DictionaryEntry.exists({ categoryId: topicId, status: 'PUBLISHED' })) throw new AppError('Chủ đề chưa có từ để học.', 409, 'EMPTY_TOPIC');
  try {
    await userTransaction(req.user!.id, async session => {
      const enrolled = await TopicEnrollment.updateOne({ userId: req.user!.id, topicId }, { $setOnInsert: { userId: req.user!.id, topicId } }, { upsert: true, session });
      if (enrolled.upsertedCount) await LearningEvent.create([{ userId: req.user!.id, topicId,
        kind: 'TOPIC_STARTED', topicName: topic.name }], { session });
    });
  } catch (error) { if ((error as { code?: number }).code !== 11000) throw error; }
  return res.json({ success: true, data: { enrolled: true } });
}));
router.patch('/words/:id/progress', wrap(async (req, res) => {
  const { stage } = parse(z.object({ stage: stageSchema }).strict(), req.body);
  const entry = await DictionaryEntry.findOne({ _id: objectId(req.params.id), status: 'PUBLISHED' }).select('categoryId word').lean();
  if (!entry) throw new AppError('Từ không còn khả dụng.', 404, 'WORD_NOT_FOUND');
  const topic = await topicOrFail(entry.categoryId);
  const progress = await userTransaction(req.user!.id, async session => {
    if (!await TopicEnrollment.exists({ userId: req.user!.id, topicId: entry.categoryId }).session(session)) throw new AppError('Hãy bắt đầu học chủ đề trước.', 409, 'NOT_ENROLLED');
    const previous = await WordProgress.findOne({ userId: req.user!.id, entryId: entry._id }).session(session);
    const reviewing = previous && (previous.stage === 'REVIEW' ||
      previous.stage === 'REMEMBERED' && previous.nextReviewAt && previous.nextReviewAt <= new Date());
    if (reviewing && stage !== 'REVIEW') throw new AppError('Hãy hoàn tất quiz camera để cập nhật từ ôn tập.', 409, 'QUIZ_REQUIRED');
    if (!previous || previous.stage !== stage) await LearningEvent.create([{ userId: req.user!.id,
      topicId: entry.categoryId, entryId: entry._id, word: entry.word, topicName: topic.name,
      kind: 'SELF_RATED', stage, firstLearning: !previous }], { session });
    return WordProgress.findOneAndUpdate({ userId: req.user!.id, entryId: entry._id }, {
      $set: { topicId: entry.categoryId, stage, reviewedAt: new Date(), nextReviewAt: stage === 'REMEMBERED' ? new Date(Date.now() + 3 * 86400000) : null },
    }, { upsert: true, new: true, runValidators: true, session });
  });
  return res.json({ success: true, data: progress });
}));

const quizLimit = rateLimit({ windowMs: 60000, limit: 15 });
router.post('/topics/:id/quiz', quizLimit, wrap(async (req, res) => {
  const { format } = parse(z.object({ format: z.enum(['CAMERA', 'VIDEO_CHOICE', 'VIDEO_RECALL']).default('CAMERA') }).strict(), req.body);
  return res.json({ success: true, data: await startReviewQuiz(req.user!.id, objectId(req.params.id), format) });
}));
router.get('/quizzes/:id', wrap(async (req, res) => {
  return res.json({ success: true, data: await getReviewQuiz(req.user!.id, objectId(req.params.id)) });
}));
router.patch('/quizzes/:id/answers', wrap(async (req, res) => {
  const { answers } = parse(z.object({ answers: z.array(z.string().trim().max(1000)).min(1).max(10) }).strict(), req.body);
  return res.json({ success: true, data: await saveReviewAnswers(req.user!.id, objectId(req.params.id), answers) });
}));
const recallWordId=z.string().regex(/^[a-f0-9]{24}$/i);
router.post('/quizzes/:id/hint', wrap(async(req,res)=>{
  const {entryId}=parse(z.object({entryId:recallWordId}).strict(),req.body);
  return res.json({success:true,data:await hintReviewRecall(req.user!.id,objectId(req.params.id),entryId)});
}));
router.post('/quizzes/:id/check', wrap(async(req,res)=>{
  const body=parse(z.object({entryId:recallWordId,answer:z.string().trim().max(200),skip:z.boolean().default(false)}).strict(),req.body);
  return res.json({success:true,data:await checkReviewRecall(req.user!.id,objectId(req.params.id),body.entryId,body.answer,body.skip)});
}));
router.post('/quizzes/:id/assessment', wrap(async(req,res)=>{
  const body=parse(z.object({entryId:recallWordId,assessment:z.enum(['SAME_MEANING','REVIEW'])}).strict(),req.body);
  return res.json({success:true,data:await assessReviewRecall(req.user!.id,objectId(req.params.id),body.entryId,body.assessment)});
}));
router.patch('/quizzes/:id/captures', wrap(async (req, res) => {
  const body = parse(z.object({ entryId: z.string().regex(/^[a-f0-9]{24}$/i), recognizedLabel: z.string().trim().max(200) }).strict(), req.body);
  return res.json({ success: true, data: await saveReviewCapture(req.user!.id, objectId(req.params.id), body.entryId, body.recognizedLabel) });
}));
router.post('/quizzes/:id/submit', quizLimit, wrap(async (req, res) => {
  parse(z.object({}).strict(), req.body);
  return res.json({ success: true, data: await submitReviewQuiz(req.user!.id, objectId(req.params.id)) });
}));

const aiRequestSchema=z.object({async:z.literal(true).optional(),requestKey:z.string().regex(/^[a-f0-9]{32}$/).optional()}).strict()
  .refine(value=>value.async ? !!value.requestKey : !value.requestKey);
router.post('/quizzes/:id/advice', rateLimit({ windowMs: 60000, limit: 3, keyGenerator: req => String(req.user!.id) }), wrap(async (req, res) => {
  const body = parse(aiRequestSchema, req.body);
  if (!body.async) throw new AppError('Nhận xét quiz cần tác vụ nền.', 400, 'INVALID_AI_REQUEST');
  const id = objectId(req.params.id);
  const quiz = await getReviewQuiz(req.user!.id, id);
  if (!['VIDEO_CHOICE','VIDEO_RECALL'].includes(quiz.kind || '') || quiz.status !== 'COMPLETED') throw new AppError('Hãy hoàn tất quiz trước khi xem nhận xét AI.', 409, 'QUIZ_INCOMPLETE');
  return res.status(202).json({ success: true, data: startLearningAiJob(req.user!.id, 'quiz', body.requestKey!, id) });
}));
router.get('/ai-jobs/:id', wrap(async (req,res)=>{
  const id=parse(z.string().uuid(),req.params.id);
  return res.json({success:true,data:getLearningAiJob(req.user!.id,id)});
}));

router.post('/coach', rateLimit({ windowMs: 60000, limit: 6, keyGenerator:req=>String(req.user!.id) }), wrap(async (req, res) => {
  const body=parse(aiRequestSchema,req.body);
  if(body.async)return res.status(202).json({success:true,data:startLearningAiJob(req.user!.id,'coach',body.requestKey!)});
  return res.json({ success: true, data: await learningAdvice(req.user!.id) });
}));

router.post('/analysis', rateLimit({ windowMs: 60000, limit: 3, keyGenerator: req => String(req.user!.id) }), wrap(async (req, res) => {
  const body=parse(aiRequestSchema,req.body);
  if(body.async)return res.status(202).json({success:true,data:startLearningAiJob(req.user!.id,'analysis',body.requestKey!)});
  return res.json({ success: true, data: await analyzeLearningProgress(req.user!.id) });
}));

const safeMedia = (value: string) => {
  if (!value) return true;
  try { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password; } catch { return false; }
};
const personalSchema = z.object({
  word: z.string().trim().min(1).max(100),
  definition: z.string().trim().min(1).max(2000),
  usageExample: z.string().trim().max(1000).default(''),
  notes: z.string().trim().max(2000).default(''),
  imageUrl: z.string().max(1500000).default('').refine(value => safeMedia(value) || /^data:image\/(?:jpeg|png|webp);base64,[A-Za-z0-9+/]+=*$/.test(value)),
  videoUrl: z.string().max(2000).default('').refine(safeMedia),
}).strict();

router.get('/my-words', wrap(async (req, res) => {
  const { page, search } = parse(querySchema, req.query);
  const filter = { userId: req.user!.id, ...(search ? { word: { $regex: regexLiteral(search), $options: 'i' } } : {}) };
  const [items, total] = await Promise.all([
    PersonalWord.find(filter).sort({ updatedAt: -1, _id: 1 }).skip((page - 1) * PAGE_SIZE).limit(PAGE_SIZE).lean(),
    PersonalWord.countDocuments(filter),
  ]);
  return res.json({ success: true, data: { items, pagination: pagination(page, total) } });
}));
router.post('/my-words', wrap(async (req, res) => {
  const body = parse(personalSchema, req.body);
  const word = await userTransaction(req.user!.id, async session => {
    const [created] = await PersonalWord.create([{ ...body, userId: req.user!.id }], {session});
    return created;
  });
  return res.status(201).json({ success: true, data: word });
}));
router.patch('/my-words/:id', wrap(async (req, res) => {
  const body = parse(personalSchema.partial(), req.body);
  const id = objectId(req.params.id);
  const word = await userTransaction(req.user!.id, async session => PersonalWord.findOneAndUpdate({ _id: id, userId: req.user!.id }, { $set: body }, { new: true, runValidators: true, session }));
  if (!word) throw new AppError('Không tìm thấy từ của bạn.', 404, 'PERSONAL_WORD_NOT_FOUND');
  return res.json({ success: true, data: word });
}));
router.delete('/my-words/:id', wrap(async (req, res) => {
  const id = objectId(req.params.id);
  const result = await userTransaction(req.user!.id, async session => PersonalWord.deleteOne({ _id: id, userId: req.user!.id }, {session}));
  if (!result.deletedCount) throw new AppError('Không tìm thấy từ của bạn.', 404, 'PERSONAL_WORD_NOT_FOUND');
  return res.json({ success: true });
}));
export default router;
