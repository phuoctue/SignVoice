import { randomUUID } from 'node:crypto';
import { Types } from 'mongoose';
import { z } from 'zod';
import { ReviewQuiz } from '../models/ReviewQuiz.model';
import { WordProgress, TopicEnrollment } from '../models/Learning.model';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { AppError } from '../common/errors/AppError';
import { topicWords, topicOrFail } from './learning.service';
import { userTransaction } from './user-data.service';

type Question = { entryId: string; word: string; aliases: string[]; videoUrl: string; thumbnailUrl: string; imageUrls: string[] };
type Capture = { entryId: string; recognizedLabel: string };
type Attempt = { _id: Types.ObjectId; userId: Types.ObjectId; topicId: Types.ObjectId;
  status: string; kind?: string; questions: Question[]; captures?: Capture[]; result: any;
  gradingToken?: string; gradingUntil?: Date | null; createdAt: Date };
const missingQuiz = () => new AppError('Không tìm thấy bài ôn tập của bạn.', 404, 'QUIZ_NOT_FOUND');
function normalize(value: string) { return value.normalize('NFC').trim().toLocaleLowerCase('vi').replace(/_/g, ' ').replace(/\s+/g, ' '); }
function dto(quiz: Attempt) {
  const captures = quiz.captures || [];
  return { _id: String(quiz._id), topicId: String(quiz.topicId), status: quiz.status,
    questions: quiz.questions.map((q) => ({ entryId: q.entryId, word: q.word,
      prompt: `Hãy thực hiện ký hiệu “${q.word}” trước camera.`, videoUrl: q.videoUrl,
      thumbnailUrl: q.thumbnailUrl, imageUrls: q.imageUrls,
      recognizedLabel: captures.find(c => c.entryId === q.entryId)?.recognizedLabel ?? '' })),
    result: quiz.result, grading: !!quiz.gradingUntil && quiz.gradingUntil > new Date(), createdAt: quiz.createdAt };
}
async function owned(userId: Types.ObjectId, id: Types.ObjectId) {
  const quiz = await ReviewQuiz.findOne({ _id: id, userId }).lean() as unknown as Attempt | null;
  if (!quiz) throw missingQuiz();
  return quiz;
}
export async function getReviewQuiz(userId: Types.ObjectId, id: Types.ObjectId) { return dto(await owned(userId, id)); }

export async function startReviewQuiz(userId: Types.ObjectId, topicId: Types.ObjectId) {
  await topicOrFail(topicId);
  if (!await TopicEnrollment.exists({ userId, topicId })) throw new AppError('Hãy bắt đầu học chủ đề trước.', 409, 'NOT_ENROLLED');
  const previous = await ReviewQuiz.findOne({ userId, topicId, status: 'DRAFT' }).lean() as unknown as Attempt | null;
  if (previous?.kind === 'CAMERA') return dto(previous);
  if (previous) await ReviewQuiz.updateOne({ _id: previous._id, status: 'DRAFT' }, { $set: { status: 'ABANDONED' } });
  const review = await topicWords(userId, topicId, 1, 'REVIEW');
  if (!review.items.length) throw new AppError('Chủ đề chưa có từ cần ôn tập.', 409, 'EMPTY_REVIEW');
  const lastCompleted = await ReviewQuiz.findOne({ userId, topicId, status: 'COMPLETED', kind: 'CAMERA' })
    .sort({ completedAt: -1 }).select('questions').lean() as unknown as { questions?: Question[] } | null;
  const seen = new Set((lastCompleted?.questions || []).map(q => q.entryId));
  const selected: Record<string, unknown>[] = [];
  for (let page = 1; page <= review.pagination.pages && selected.length < 10; page++) {
    const data = page === 1 ? review : await topicWords(userId, topicId, page, 'REVIEW');
    selected.push(...data.items.filter(w => !seen.has(String(w._id))).slice(0, 10 - selected.length));
  }
  if (!selected.length) selected.push(...review.items);
  const ids = selected.map(w => new Types.ObjectId(String(w._id)));
  const entries = await DictionaryEntry.find({ _id: { $in: ids }, categoryId: topicId, status: 'PUBLISHED' })
    .select('word aliases').lean();
  const byId = new Map(entries.map(e => [String(e._id), e]));
  const questions = selected.flatMap(w => {
    const entry = byId.get(String(w._id));
    if (!entry) return [];
    return [{ entryId: String(entry._id), word: entry.word, aliases: entry.aliases || [],
      videoUrl: String(w.videoUrl || ''), thumbnailUrl: String(w.thumbnailUrl || ''),
      imageUrls: Array.isArray(w.imageUrls) ? w.imageUrls.map(String) : [] }];
  });
  if (!questions.length) throw new AppError('Không tìm thấy từ để tạo bài ôn tập.', 409, 'EMPTY_REVIEW');
  try {
    const quiz = await userTransaction(userId, async session => {
      const created = await ReviewQuiz.create([{ userId, topicId, kind: 'CAMERA', questions, captures: [] }], { session });
      return created[0].toObject() as unknown as Attempt;
    });
    return dto(quiz);
  } catch (error) {
    if ((error as { code?: number }).code !== 11000) throw error;
    const existing = await ReviewQuiz.findOne({ userId, topicId, status: 'DRAFT' }).lean() as unknown as Attempt | null;
    if (!existing) throw error;
    return dto(existing);
  }
}

export async function saveReviewCapture(userId: Types.ObjectId, id: Types.ObjectId, entryId: string, recognizedLabel: string) {
  const label = z.string().trim().max(200).parse(recognizedLabel);
  await userTransaction(userId, async session => {
    const quiz = await ReviewQuiz.findOne({ _id: id, userId }).session(session).lean() as unknown as Attempt | null;
    if (!quiz) throw missingQuiz();
    if (quiz.status !== 'DRAFT') throw new AppError('Bài đã hoàn tất, không thể sửa kết quả nhận diện.', 409, 'QUIZ_COMPLETED');
    if (quiz.gradingUntil && quiz.gradingUntil > new Date()) throw new AppError('Bài đang được lưu kết quả.', 409, 'QUIZ_GRADING');
    const question = quiz.questions.find(q => q.entryId === entryId);
    if (!question) throw new AppError('Từ này không thuộc bài ôn tập.', 400, 'INVALID_QUIZ_WORD');
    const captures = (quiz.captures || []).filter(c => c.entryId !== entryId);
    captures.push({ entryId, recognizedLabel: label });
    await ReviewQuiz.updateOne({ _id: id, userId }, { $set: { captures } }, { session });
  });
  return getReviewQuiz(userId, id);
}

// Retained for existing clients while they reload into the camera quiz flow.
export async function saveReviewAnswers(userId: Types.ObjectId, id: Types.ObjectId, answers: string[]) {
  await userTransaction(userId, async session => {
    const quiz = await ReviewQuiz.findOne({ _id: id, userId }).session(session).lean() as unknown as Attempt | null;
    if (!quiz) throw missingQuiz();
    if (quiz.status !== 'DRAFT') throw new AppError('Bài đã hoàn tất, không thể sửa.', 409, 'QUIZ_COMPLETED');
    if (answers.length !== quiz.questions.length) throw new AppError('Số câu trả lời không khớp bài ôn tập.', 400, 'INVALID_ANSWERS');
    await ReviewQuiz.updateOne({ _id: id, userId }, { $set: { answers } }, { session });
  });
  return getReviewQuiz(userId, id);
}

export async function submitReviewQuiz(userId: Types.ObjectId, id: Types.ObjectId) {
  const snapshot = await owned(userId, id);
  if (snapshot.status === 'COMPLETED') return dto(snapshot);
  const snapshotCaptures = snapshot.captures || [];
  if (snapshot.questions.some(q => !snapshotCaptures.some(c => c.entryId === q.entryId))) {
    throw new AppError('Hãy ghi nhận kết quả camera cho từng câu trước khi nộp bài.', 400, 'QUIZ_INCOMPLETE');
  }
  const token = randomUUID();
  const quiz = await userTransaction(userId, async session => {
    const current = await ReviewQuiz.findOne({ _id: id, userId }).session(session).lean() as unknown as Attempt | null;
    if (!current) throw missingQuiz();
    if (current.status === 'COMPLETED') return current;
    const currentCaptures = current.captures || [];
    if (current.questions.some(q => !currentCaptures.some(c => c.entryId === q.entryId))) {
      throw new AppError('Hãy ghi nhận kết quả camera cho từng câu trước khi nộp bài.', 400, 'QUIZ_INCOMPLETE');
    }
    if (current.gradingUntil && current.gradingUntil > new Date()) throw new AppError('Đang lưu kết quả. Hãy đợi rồi thử lại.', 409, 'QUIZ_GRADING');
    await ReviewQuiz.updateOne({ _id: id, userId }, { $set: { gradingToken: token, gradingUntil: new Date(Date.now() + 60000) } }, { session });
    return current;
  });
  if (quiz.status === 'COMPLETED') return dto(quiz);
  try {
    await userTransaction(userId, async session => {
      const current = await ReviewQuiz.findOne({ _id: id, userId, status: 'DRAFT', gradingToken: token }).session(session);
      if (!current) throw missingQuiz();
      const output = [];
      for (const question of quiz.questions) {
        const capture = (quiz.captures || []).find(c => c.entryId === question.entryId)!;
        const accepted = [question.word, ...(question.aliases || [])].map(normalize);
        const matched = accepted.includes(normalize(capture.recognizedLabel));
        const score = matched ? 10 : 0;
        const progress = await WordProgress.findOne({ userId, entryId: question.entryId, topicId: quiz.topicId }).session(session);
        const stillReview = progress && (progress.stage === 'REVIEW' ||
          progress.stage === 'REMEMBERED' && progress.nextReviewAt && progress.nextReviewAt <= new Date());
        const published = await DictionaryEntry.exists({ _id: question.entryId, categoryId: quiz.topicId, status: 'PUBLISHED' }).session(session);
        const applied = !!(stillReview && published && (!progress!.reviewedAt || progress!.reviewedAt <= quiz.createdAt));
        const stage = matched ? 'REMEMBERED' : 'REVIEW';
        if (applied) {
          progress!.stage = stage;
          progress!.reviewedAt = new Date();
          progress!.nextReviewAt = matched ? new Date(Date.now() + 3 * 86400000) : null;
          await progress!.save({ session });
        }
        output.push({ entryId: question.entryId, word: question.word, recognizedLabel: capture.recognizedLabel,
          score, feedback: matched ? 'Camera nhận diện đúng ký hiệu.' : 'Ký hiệu nhận diện chưa khớp. Hãy xem lại mẫu và ôn tập thêm.', stage, applied });
      }
      const score = Math.round(output.reduce((sum, item) => sum + item.score, 0) / output.length * 10) / 10;
      const result = { source: 'sign-ai-camera', score, total: output.length, feedback: 'Kết quả được đối chiếu với ký hiệu camera nhận diện cho từng từ.', items: output };
      current.status = 'COMPLETED';
      current.result = result;
      current.completedAt = new Date();
      current.gradingToken = '';
      current.gradingUntil = null;
      await current.save({ session });
    });
    return getReviewQuiz(userId, id);
  } catch (error) {
    await ReviewQuiz.updateOne({ _id: id, userId, gradingToken: token }, { $set: { gradingToken: '', gradingUntil: null } });
    throw error;
  }
}
