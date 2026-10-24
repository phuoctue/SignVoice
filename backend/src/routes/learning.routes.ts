import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { rateLimit } from 'express-rate-limit';
import { requireAuth } from '../common/middlewares/auth.middleware';
import { AppError } from '../common/errors/AppError';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { PersonalWord, TopicEnrollment, WordProgress } from '../models/Learning.model';
import { exploreTopics, enrolledTopics, objectId, pagination, regexLiteral, topicOrFail, topicWords, PAGE_SIZE } from '../services/learning.service';
import { learningAdvice } from '../services/learning-coach.service';
import { userTransaction } from '../services/user-data.service';
import { startReviewQuiz, getReviewQuiz, saveReviewAnswers, saveReviewCapture, submitReviewQuiz } from '../services/review-quiz.service';

const router = Router();
router.use(requireAuth);
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
  await topicOrFail(topicId);
  if (!await DictionaryEntry.exists({ categoryId: topicId, status: 'PUBLISHED' })) throw new AppError('Chủ đề chưa có từ để học.', 409, 'EMPTY_TOPIC');
  try {
    await userTransaction(req.user!.id, async session => {
      await TopicEnrollment.updateOne({ userId: req.user!.id, topicId }, { $setOnInsert: { userId: req.user!.id, topicId } }, { upsert: true, session });
    });
  } catch (error) { if ((error as { code?: number }).code !== 11000) throw error; }
  return res.json({ success: true, data: { enrolled: true } });
}));
router.patch('/words/:id/progress', wrap(async (req, res) => {
  const { stage } = parse(z.object({ stage: stageSchema }).strict(), req.body);
  const entry = await DictionaryEntry.findOne({ _id: objectId(req.params.id), status: 'PUBLISHED' }).select('categoryId').lean();
  if (!entry) throw new AppError('Từ không còn khả dụng.', 404, 'WORD_NOT_FOUND');
  const progress = await userTransaction(req.user!.id, async session => {
    if (!await TopicEnrollment.exists({ userId: req.user!.id, topicId: entry.categoryId }).session(session)) throw new AppError('Hãy bắt đầu học chủ đề trước.', 409, 'NOT_ENROLLED');
    const previous = await WordProgress.findOne({ userId: req.user!.id, entryId: entry._id }).session(session);
    const reviewing = previous && (previous.stage === 'REVIEW' ||
      previous.stage === 'REMEMBERED' && previous.nextReviewAt && previous.nextReviewAt <= new Date());
    if (reviewing && stage !== 'REVIEW') throw new AppError('Hãy hoàn tất quiz camera để cập nhật từ ôn tập.', 409, 'QUIZ_REQUIRED');
    return WordProgress.findOneAndUpdate({ userId: req.user!.id, entryId: entry._id }, {
      $set: { topicId: entry.categoryId, stage, reviewedAt: new Date(), nextReviewAt: stage === 'REMEMBERED' ? new Date(Date.now() + 3 * 86400000) : null },
    }, { upsert: true, new: true, runValidators: true, session });
  });
  return res.json({ success: true, data: progress });
}));

const quizLimit = rateLimit({ windowMs: 60000, limit: 15 });
router.post('/topics/:id/quiz', quizLimit, wrap(async (req, res) => {
  parse(z.object({}).strict(), req.body);
  return res.json({ success: true, data: await startReviewQuiz(req.user!.id, objectId(req.params.id)) });
}));
router.get('/quizzes/:id', wrap(async (req, res) => {
  return res.json({ success: true, data: await getReviewQuiz(req.user!.id, objectId(req.params.id)) });
}));
router.patch('/quizzes/:id/answers', wrap(async (req, res) => {
  const { answers } = parse(z.object({ answers: z.array(z.string().trim().max(1000)).min(1).max(10) }).strict(), req.body);
  return res.json({ success: true, data: await saveReviewAnswers(req.user!.id, objectId(req.params.id), answers) });
}));
router.patch('/quizzes/:id/captures', wrap(async (req, res) => {
  const body = parse(z.object({ entryId: z.string().regex(/^[a-f0-9]{24}$/i), recognizedLabel: z.string().trim().max(200) }).strict(), req.body);
  return res.json({ success: true, data: await saveReviewCapture(req.user!.id, objectId(req.params.id), body.entryId, body.recognizedLabel) });
}));
router.post('/quizzes/:id/submit', quizLimit, wrap(async (req, res) => {
  parse(z.object({}).strict(), req.body);
  return res.json({ success: true, data: await submitReviewQuiz(req.user!.id, objectId(req.params.id)) });
}));

router.post('/coach', rateLimit({ windowMs: 60000, limit: 6 }), wrap(async (req, res) => {
  return res.json({ success: true, data: await learningAdvice(req.user!.id) });
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
