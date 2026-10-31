import { randomInt, randomUUID } from 'node:crypto';
import { Types } from 'mongoose';
import { z } from 'zod';
import { ReviewQuiz } from '../models/ReviewQuiz.model';
import { WordProgress, TopicEnrollment } from '../models/Learning.model';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { Category } from '../models/Category.model';
import { LearningEvent } from '../models/LearningEvent.model';
import { AppError } from '../common/errors/AppError';
import { topicWords, topicOrFail, withAvailableMedia } from './learning.service';
import { userTransaction } from './user-data.service';
import { addInlineThumbnails } from './sign-media-preview.service';
import {SignCollection} from '../models/SignCollection.model';
import {ownedCollection} from './sign-collection.service';

type Question = { entryId: string; word: string; aliases: string[]; videoUrl: string; thumbnailUrl: string; imageUrls: string[];
  topicId?:string;topicName?:string;
  options?: { value: string; label: string }[]; correctOptionId?: string; definition?: string; usageExample?: string };
type Capture = { entryId: string; recognizedLabel: string };
type RecallResponse = {entryId:string;answer:string;usedHint:boolean;match:'EXACT'|'CLOSE'|'DIFFERENT'|'SKIPPED';assessment:'SAME_MEANING'|'REVIEW'|null};
type Attempt = { _id: Types.ObjectId; userId: Types.ObjectId; topicId?: Types.ObjectId;collectionId?:Types.ObjectId;collectionName?:string;
  status: string; kind?: string; questions: Question[]; answers?: string[]; captures?: Capture[]; result: any;
  libraryChanged?:boolean;
  hintedEntries?:string[];recallResponses?:RecallResponse[];
  gradingToken?: string; gradingUntil?: Date | null; createdAt: Date };
const missingQuiz = () => new AppError('Không tìm thấy bài ôn tập của bạn.', 404, 'QUIZ_NOT_FOUND');
function normalize(value: string) { return value.normalize('NFC').trim().toLocaleLowerCase('vi').replace(/_/g, ' ').replace(/\s+/g, ' '); }
function normalizeRecall(value:string) { return normalize(value).replace(/^[\p{P}\p{S}\s]+|[\p{P}\p{S}\s]+$/gu,'').trim(); }
function hintFor(word:string) {
  const words=normalize(word).split(' '), first=Array.from(words[0]);
  return first.length===1 && words.length===1 ? 'Đây là một ký tự. Hãy quan sát hình dạng bàn tay trong mẫu.'
    : `Gồm ${words.length} tiếng, bắt đầu bằng chữ “${first[0]}”.`;
}
function dto(quiz: Attempt) {
  const captures = quiz.captures || [];
  const choice = quiz.kind === 'VIDEO_CHOICE';
  const recall = quiz.kind === 'VIDEO_RECALL';
  return { _id: String(quiz._id), ...(quiz.topicId?{topicId:String(quiz.topicId)}:{}),
    ...(quiz.collectionId?{collectionId:String(quiz.collectionId),collectionName:quiz.collectionName}:{}), status: quiz.status, kind: quiz.kind,
    ...(choice || recall ? { answers: quiz.questions.map((_, i) => quiz.answers?.[i] || '') } : {}),
    questions: quiz.questions.map((q) => {
      if(recall) {
        const response=quiz.recallResponses?.find(row=>row.entryId===q.entryId);
        return {entryId:q.entryId,prompt:'Ký hiệu này có nghĩa là gì?',videoUrl:q.videoUrl,thumbnailUrl:q.thumbnailUrl,imageUrls:q.imageUrls,
          hint:quiz.hintedEntries?.includes(q.entryId)?hintFor(q.word):null,
          response:response?{...response,correctAnswer:q.word.normalize('NFC'),definition:q.definition || '',usageExample:q.usageExample || ''}:null};
      }
      return choice ? ({ entryId: q.entryId,
      prompt: 'Ký hiệu trong video hoặc chuỗi ảnh có nghĩa là gì?', options: q.options,
      videoUrl: q.videoUrl, thumbnailUrl: q.thumbnailUrl, imageUrls: q.imageUrls,
    }) : ({ entryId: q.entryId, word: q.word.normalize('NFC'), aliases: (q.aliases || []).map(label => label.normalize('NFC')),
      prompt: `Hãy thực hiện ký hiệu “${q.word}” trước camera.`, videoUrl: q.videoUrl,
      thumbnailUrl: q.thumbnailUrl, imageUrls: q.imageUrls,
      recognizedLabel: captures.find(c => c.entryId === q.entryId)?.recognizedLabel ?? '' });}),
    result: quiz.result,libraryChanged:!!quiz.libraryChanged, grading: !!quiz.gradingUntil && quiz.gradingUntil > new Date(), createdAt: quiz.createdAt };
}
async function owned(userId: Types.ObjectId, id: Types.ObjectId) {
  const quiz = await ReviewQuiz.findOne({ _id: id, userId }).lean() as unknown as Attempt | null;
  if (!quiz) throw missingQuiz();
  return quiz;
}
async function previewDto(quiz: Attempt) {
  const value = dto(quiz);
  if(quiz.status==='COMPLETED') {
    const entries=await DictionaryEntry.find({_id:{$in:quiz.questions.map(q=>q.entryId)},status:'PUBLISHED'}).select('categoryId videoUrl thumbnailUrl imageUrls').lean();
    const active=new Set((await Category.find({_id:{$in:entries.map(row=>row.categoryId)},status:'ACTIVE'}).select('_id').lean()).map(row=>String(row._id)));
    const media=new Map(entries.filter(row=>active.has(String(row.categoryId))).map(row=>[String(row._id),withAvailableMedia(row as unknown as Record<string,unknown>)]));
    value.questions=value.questions.map(q=>({...q,...(media.get(q.entryId)?{videoUrl:media.get(q.entryId)!.videoUrl,thumbnailUrl:media.get(q.entryId)!.thumbnailUrl,imageUrls:media.get(q.entryId)!.imageUrls}:{videoUrl:'',thumbnailUrl:'',imageUrls:[],mediaUnavailable:true})}));
  }
  if (quiz.kind === 'VIDEO_RECALL') value.questions = await addInlineThumbnails(value.questions);
  return value;
}
export async function getReviewQuiz(userId: Types.ObjectId, id: Types.ObjectId) { return previewDto(await owned(userId, id)); }

export async function startCollectionQuiz(userId:Types.ObjectId,collectionId:Types.ObjectId) {
  const collection=await ownedCollection(userId,collectionId);
  const draft=await ReviewQuiz.findOne({userId,collectionId,status:'DRAFT'}).lean() as unknown as Attempt|null;
  if(draft)return previewDto(draft);
  const topics=await Category.find({status:'ACTIVE'}).select('name').lean();
  const topicNames=new Map(topics.map(topic=>[String(topic._id),topic.name]));
  const [entries,progress,last]=await Promise.all([
    DictionaryEntry.find({_id:{$in:collection.entryIds},status:'PUBLISHED',categoryId:{$in:topics.map(topic=>topic._id)}})
      .select('word aliases categoryId videoUrl thumbnailUrl imageUrls definition usageExample').lean(),
    WordProgress.find({userId,entryId:{$in:collection.entryIds}}).select('entryId stage nextReviewAt').lean(),
    ReviewQuiz.findOne({userId,collectionId,status:'COMPLETED'}).sort({completedAt:-1}).select('questions').lean(),
  ]);
  const states=new Map(progress.map(row=>[String(row.entryId),row]));
  const seen=new Set((last?.questions || []).map((q:Question)=>q.entryId));
  const priority=(id:string)=>{const row=states.get(id);return row?.stage==='REVIEW' || row?.stage==='REMEMBERED' && row.nextReviewAt && row.nextReviewAt<=new Date()?0:row?.stage==='REMEMBERED'?2:1;};
  const questions:Question[]=entries.sort((a,b)=>priority(String(a._id))-priority(String(b._id)) || Number(seen.has(String(a._id)))-Number(seen.has(String(b._id))) || a.word.localeCompare(b.word,'vi'))
    .flatMap(entry=>{
      const media=withAvailableMedia(entry as unknown as Record<string,unknown>);
      return media.mediaUnavailable || !normalizeRecall(entry.word)?[]:[{entryId:String(entry._id),word:entry.word.normalize('NFC'),aliases:entry.aliases || [],
        topicId:String(entry.categoryId),topicName:topicNames.get(String(entry.categoryId)),videoUrl:String(media.videoUrl || ''),
        thumbnailUrl:String(media.thumbnailUrl || ''),imageUrls:media.imageUrls,definition:entry.definition,usageExample:entry.usageExample || ''}];
    }).slice(0,10);
  if(!questions.length)throw new AppError('Bộ chưa có từ với ảnh hoặc video khả dụng. Hãy thêm từ từ thư viện.',409,'QUIZ_MEDIA_UNAVAILABLE');
  try {
    const created=await userTransaction(userId,async session=>{
      const current=await ownedCollection(userId,collectionId,session);
      const ids=new Set(current.entryIds.map(String)),selected=questions.filter(q=>ids.has(q.entryId));
      if(!selected.length)throw new AppError('Nội dung bộ đã thay đổi. Hãy tải lại.',409,'COLLECTION_CHANGED');
      const [row]=await ReviewQuiz.create([{userId,collectionId,collectionName:current.name,kind:'VIDEO_RECALL',questions:selected,answers:selected.map(()=> '')}],{session});
      return row.toObject() as unknown as Attempt;
    });
    return previewDto(created);
  } catch(error) {
    if((error as {code?:number}).code!==11000)throw error;
    const existing=await ReviewQuiz.findOne({userId,collectionId,status:'DRAFT'}).lean() as unknown as Attempt|null;
    if(!existing)throw error;return previewDto(existing);
  }
}

export async function startReviewQuiz(userId: Types.ObjectId, topicId: Types.ObjectId, format: 'CAMERA' | 'VIDEO_CHOICE' | 'VIDEO_RECALL' = 'CAMERA') {
  if (format !== 'CAMERA') return startVideoReviewQuiz(userId, topicId, format);
  await topicOrFail(topicId);
  if (!await TopicEnrollment.exists({ userId, topicId })) throw new AppError('Hãy bắt đầu học chủ đề trước.', 409, 'NOT_ENROLLED');
  const previous = await ReviewQuiz.findOne({ userId, topicId, status: 'DRAFT' }).lean() as unknown as Attempt | null;
  if (previous?.kind?.startsWith('VIDEO_')) throw new AppError('Hãy cập nhật ứng dụng để tiếp tục bài ôn tập.', 409, 'QUIZ_UPDATED');
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

function shuffled<T>(items: T[]) {
  const result = [...items];
  for (let i = result.length - 1; i > 0; i--) { const j = randomInt(i + 1); [result[i], result[j]] = [result[j], result[i]]; }
  return result;
}

/** Answers and definitions remain server-side until the attempt is submitted. */
async function startVideoReviewQuiz(userId: Types.ObjectId, topicId: Types.ObjectId, format:'VIDEO_CHOICE'|'VIDEO_RECALL') {
  await topicOrFail(topicId);
  if (!await TopicEnrollment.exists({ userId, topicId })) throw new AppError('Hãy bắt đầu học chủ đề trước.', 409, 'NOT_ENROLLED');
  const previous = await ReviewQuiz.findOne({ userId, topicId, status: 'DRAFT' }).lean() as unknown as Attempt | null;
  if (previous?.kind === format) return previewDto(previous);
  if (previous?.kind === 'VIDEO_RECALL') throw new AppError('Hãy cập nhật ứng dụng để tiếp tục bài tự nhớ nghĩa ký hiệu.',409,'QUIZ_UPDATED');
  const due = await WordProgress.find({ userId, topicId, $or: [
    { stage: 'REVIEW' }, { stage: 'REMEMBERED', nextReviewAt: { $ne: null, $lte: new Date() } },
  ] }).select('entryId').lean();
  if (!due.length) throw new AppError('Chủ đề chưa có từ cần ôn tập.', 409, 'EMPTY_REVIEW');
  const active = await Category.find({ status: 'ACTIVE' }).select('_id').lean();
  const fields = 'word aliases videoUrl thumbnailUrl imageUrls definition usageExample';
  const [sameTopic, otherTopics, last] = await Promise.all([
    DictionaryEntry.find({ categoryId: topicId, status: 'PUBLISHED' }).select(fields).limit(1000).lean(),
    format==='VIDEO_CHOICE'?DictionaryEntry.find({ categoryId: { $in: active.map(c => c._id).filter(id => !id.equals(topicId)) }, status: 'PUBLISHED' }).select(fields).limit(500).lean():Promise.resolve([]),
    ReviewQuiz.findOne({ userId, topicId, kind: format, status: 'COMPLETED' }).sort({ completedAt: -1 }).select('questions').lean(),
  ]);
  const pool = [...shuffled(sameTopic), ...shuffled(otherTopics)];
  const seen = new Set((last?.questions || []).map((q: Question) => q.entryId));
  const dueIds = new Set(due.map(row => String(row.entryId)));
  const candidates = sameTopic.filter(row => dueIds.has(String(row._id)))
    .sort((a, b) => Number(seen.has(String(a._id))) - Number(seen.has(String(b._id))) || a.word.localeCompare(b.word, 'vi'));
  const questions: Question[] = [];
  for (const candidate of candidates) {
    if (questions.length === 10) break;
    const entry = candidate;
    const media = withAvailableMedia(entry as unknown as Record<string, unknown>);
    if (media.mediaUnavailable) continue;
    if(format==='VIDEO_RECALL') {
      if(!normalizeRecall(entry.word))continue;
      questions.push({entryId:String(entry._id),word:entry.word.normalize('NFC'),aliases:entry.aliases || [],
        videoUrl:String(media.videoUrl || ''),thumbnailUrl:String(media.thumbnailUrl || ''),imageUrls:media.imageUrls,
        definition:entry.definition,usageExample:entry.usageExample || ''});
      continue;
    }
    const labels = new Set([entry.word, ...(entry.aliases || [])].map(normalize));
    const options = [{ value: randomUUID(), label: entry.word.normalize('NFC') }];
    const correctOptionId = options[0].value;
    for (const distractor of pool) {
      const names = [distractor.word, ...(distractor.aliases || [])].map(normalize);
      if (String(distractor._id) === String(entry._id) || names.some(name => labels.has(name)) ||
        (entry.videoUrl && distractor.videoUrl === entry.videoUrl)) continue;
      options.push({ value: randomUUID(), label: distractor.word.normalize('NFC') });
      names.forEach(name => labels.add(name));
      if (options.length === 4) break;
    }
    if (options.length !== 4) continue;
    questions.push({ entryId: String(entry._id), word: entry.word.normalize('NFC'), aliases: entry.aliases || [],
      videoUrl: String(media.videoUrl || ''), thumbnailUrl: String(media.thumbnailUrl || ''), imageUrls: media.imageUrls,
      options: shuffled(options), correctOptionId, definition: entry.definition, usageExample: entry.usageExample || '' });
  }
  if (!questions.length) throw new AppError(format==='VIDEO_RECALL'?'Chưa có mẫu ký hiệu khả dụng để ôn tập. Bạn có thể học các từ khác trong chủ đề.':'Chưa đủ mẫu ký hiệu và 4 đáp án khác nhau để tạo quiz. Bạn vẫn có thể xem mẫu và học trong chủ đề.', 409, 'QUIZ_MEDIA_UNAVAILABLE');
  try {
    const created = await userTransaction(userId, async session => {
      // Convert only the owner's old draft, and only once a valid new quiz is ready.
      await ReviewQuiz.updateMany({ userId, topicId, status: 'DRAFT', kind: { $ne: format } }, { $set: { status: 'ABANDONED' } }, { session });
      const rows = await ReviewQuiz.create([{ userId, topicId, kind: format, questions, answers: questions.map(() => '') }], { session });
      return rows[0].toObject() as unknown as Attempt;
    });
    return previewDto(created);
  } catch (error) {
    if ((error as { code?: number }).code !== 11000) throw error;
    const existing = await ReviewQuiz.findOne({ userId, topicId, kind: format, status: 'DRAFT' }).lean() as unknown as Attempt | null;
    if (!existing) throw error;
    return previewDto(existing);
  }
}

export async function saveReviewCapture(userId: Types.ObjectId, id: Types.ObjectId, entryId: string, recognizedLabel: string) {
  const label = z.string().trim().max(200).parse(recognizedLabel);
  await userTransaction(userId, async session => {
    const quiz = await ReviewQuiz.findOne({ _id: id, userId }).session(session).lean() as unknown as Attempt | null;
    if (!quiz) throw missingQuiz();
    if (quiz.kind?.startsWith('VIDEO_')) throw new AppError('Quiz này không dùng kết quả camera.', 409, 'QUIZ_UPDATED');
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

export async function saveReviewAnswers(userId: Types.ObjectId, id: Types.ObjectId, answers: string[]) {
  const updated = await userTransaction(userId, async session => {
    const quiz = await ReviewQuiz.findOne({ _id: id, userId }).session(session).lean() as unknown as Attempt | null;
    if (!quiz) throw missingQuiz();
    if (quiz.status !== 'DRAFT') throw new AppError('Bài đã hoàn tất, không thể sửa.', 409, 'QUIZ_COMPLETED');
    if (quiz.gradingUntil && quiz.gradingUntil > new Date()) throw new AppError('Bài đang được lưu kết quả.', 409, 'QUIZ_GRADING');
    if (answers.length !== quiz.questions.length) throw new AppError('Số câu trả lời không khớp bài ôn tập.', 400, 'INVALID_ANSWERS');
    if (quiz.kind === 'VIDEO_CHOICE' && answers.some((answer, i) => answer !== '' && !quiz.questions[i].options?.some(option => option.value === answer))) {
      throw new AppError('Đáp án không thuộc câu hỏi.', 400, 'INVALID_ANSWERS');
    }
    if(quiz.kind==='VIDEO_RECALL' && answers.some((answer,i)=>answer.length>200 ||
      (quiz.recallResponses?.some(row=>row.entryId===quiz.questions[i].entryId && row.answer!==answer)))) {
      throw new AppError('Câu đã kiểm tra được giữ nguyên để ghi nhận lần nhớ đầu tiên.',409,'QUIZ_ANSWER_CHECKED');
    }
    await ReviewQuiz.updateOne({ _id: id, userId }, { $set: { answers } }, { session });
    return { ...quiz, answers };
  });
  return dto(updated);
}

function editableRecall(quiz:Attempt|null) {
  if(!quiz)throw missingQuiz();
  if(quiz.kind!=='VIDEO_RECALL')throw new AppError('Bài này không dùng câu trả lời tự nhập.',409,'QUIZ_UPDATED');
  if(quiz.status!=='DRAFT')throw new AppError('Bài đã hoàn tất, không thể sửa.',409,'QUIZ_COMPLETED');
  if(quiz.gradingUntil && quiz.gradingUntil>new Date())throw new AppError('Bài đang được lưu kết quả.',409,'QUIZ_GRADING');
  return quiz;
}

function recallQuestion(quiz:Attempt,entryId:string) {
  const question=quiz.questions.find(q=>q.entryId===entryId);
  if(!question)throw new AppError('Từ này không thuộc bài ôn tập.',400,'INVALID_QUIZ_WORD');
  return question;
}

export async function hintReviewRecall(userId:Types.ObjectId,id:Types.ObjectId,entryId:string) {
  const updated = await userTransaction(userId,async session=>{
    const quiz=editableRecall(await ReviewQuiz.findOne({_id:id,userId}).session(session).lean() as unknown as Attempt|null);
    recallQuestion(quiz,entryId);
    if(quiz.recallResponses?.some(row=>row.entryId===entryId))throw new AppError('Câu này đã được đối chiếu.',409,'QUIZ_ANSWER_CHECKED');
    await ReviewQuiz.updateOne({_id:id,userId},{$addToSet:{hintedEntries:entryId}},{session});
    return { ...quiz, hintedEntries: [...new Set([...(quiz.hintedEntries || []), entryId])] };
  });
  return dto(updated);
}

function nearby(answer:string,expected:string) {
  // Removing accents is used only to suggest a spelling check, never to award a match.
  const plain=(s:string)=>s.normalize('NFD').replace(/\p{M}/gu,'').replace(/đ/g,'d');
  if(plain(answer)===plain(expected))return true;
  const limit=Math.max(answer.length,expected.length)>=8?2:1;
  if(Math.min(answer.length,expected.length)<3 || Math.abs(answer.length-expected.length)>limit)return false;
  let previous=Array.from({length:expected.length+1},(_,i)=>i);
  for(let i=1;i<=answer.length;i++) {
    const current=[i];
    for(let j=1;j<=expected.length;j++)current.push(Math.min(current[j-1]+1,previous[j]+1,previous[j-1]+Number(answer[i-1]!==expected[j-1])));
    previous=current;
  }
  return previous[expected.length]<=limit;
}

export async function checkReviewRecall(userId:Types.ObjectId,id:Types.ObjectId,entryId:string,answer:string,skip=false) {
  const text=z.string().trim().max(200).parse(answer);
  if(!skip && !normalizeRecall(text))throw new AppError('Hãy nhập nghĩa bạn nhớ, hoặc chọn Chưa nhớ.',400,'QUIZ_EMPTY_ANSWER');
  const updated = await userTransaction(userId,async session=>{
    const quiz=editableRecall(await ReviewQuiz.findOne({_id:id,userId}).session(session).lean() as unknown as Attempt|null);
    const question=recallQuestion(quiz,entryId);
    const existing=quiz.recallResponses?.find(row=>row.entryId===entryId);
    if(existing) {
      if(existing.answer===text && (existing.match==='SKIPPED')===skip)return quiz;
      throw new AppError('Câu này đã được kiểm tra. Kết quả lần đầu được giữ lại.',409,'QUIZ_ANSWER_CHECKED');
    }
    const accepted=[question.word,...(question.aliases || [])].map(normalizeRecall).filter(Boolean);
    const normalized=normalizeRecall(text);
    const match:RecallResponse['match']=skip?'SKIPPED':accepted.includes(normalized)?'EXACT':accepted.some(word=>nearby(normalized,word))?'CLOSE':'DIFFERENT';
    const responses: RecallResponse[]=[...(quiz.recallResponses || []),{entryId,answer:text,usedHint:!!quiz.hintedEntries?.includes(entryId),match,assessment:skip?'REVIEW':null}];
    const answers=quiz.questions.map((q,i)=>q.entryId===entryId?text:quiz.answers?.[i] || '');
    await ReviewQuiz.updateOne({_id:id,userId},{$set:{answers,recallResponses:responses}},{session});
    return { ...quiz, answers, recallResponses: responses };
  });
  return dto(updated);
}

export async function assessReviewRecall(userId:Types.ObjectId,id:Types.ObjectId,entryId:string,assessment:'SAME_MEANING'|'REVIEW') {
  const updated = await userTransaction(userId,async session=>{
    const quiz=editableRecall(await ReviewQuiz.findOne({_id:id,userId}).session(session).lean() as unknown as Attempt|null);
    recallQuestion(quiz,entryId);
    const row=quiz.recallResponses?.find(r=>r.entryId===entryId);
    if(!row || row.match==='EXACT' || row.match==='SKIPPED')throw new AppError('Hãy nhập và kiểm tra nghĩa trước khi tự đối chiếu.',409,'QUIZ_NOT_CHECKED');
    if (row.assessment === assessment) return quiz;
    const responses=quiz.recallResponses!.map(r=>r.entryId===entryId?{...r,assessment}:r);
    await ReviewQuiz.updateOne({_id:id,userId},{$set:{recallResponses:responses}},{session});
    return { ...quiz, recallResponses: responses };
  });
  return dto(updated);
}

function complete(quiz: Attempt) {
  if(quiz.kind==='VIDEO_RECALL')return quiz.questions.every(q=>quiz.recallResponses?.some(row=>row.entryId===q.entryId &&
    (row.match==='EXACT' || row.match==='SKIPPED' || !!row.assessment)));
  return quiz.kind === 'VIDEO_CHOICE'
    ? quiz.questions.every((q, i) => !!quiz.answers?.[i] && q.options?.some(option => option.value === quiz.answers![i]))
    : quiz.questions.every(q => quiz.captures?.some(c => c.entryId === q.entryId));
}

export async function submitReviewQuiz(userId: Types.ObjectId, id: Types.ObjectId) {
  const snapshot = await owned(userId, id);
  if (snapshot.status === 'COMPLETED') return previewDto(snapshot);
  if (snapshot.status !== 'DRAFT') throw new AppError('Lượt ôn này không còn khả dụng.',409,'QUIZ_UNAVAILABLE');
  if (!complete(snapshot)) {
    throw new AppError('Hãy trả lời đủ các câu trước khi nộp bài.', 400, 'QUIZ_INCOMPLETE');
  }
  const token = randomUUID();
  const quiz = await userTransaction(userId, async session => {
    const current = await ReviewQuiz.findOne({ _id: id, userId }).session(session).lean() as unknown as Attempt | null;
    if (!current) throw missingQuiz();
    if (current.status === 'COMPLETED') return current;
    if (current.status !== 'DRAFT') throw new AppError('Lượt ôn này không còn khả dụng.',409,'QUIZ_UNAVAILABLE');
    if (!complete(current)) {
      throw new AppError('Hãy trả lời đủ các câu trước khi nộp bài.', 400, 'QUIZ_INCOMPLETE');
    }
    if (current.gradingUntil && current.gradingUntil > new Date()) throw new AppError('Đang lưu kết quả. Hãy đợi rồi thử lại.', 409, 'QUIZ_GRADING');
    await ReviewQuiz.updateOne({ _id: id, userId }, { $set: { gradingToken: token, gradingUntil: new Date(Date.now() + 60000) } }, { session });
    return current;
  });
  if (quiz.status === 'COMPLETED') return previewDto(quiz);
  try {
    const completed = await userTransaction(userId, async session => {
      const current = await ReviewQuiz.findOne({ _id: id, userId, status: 'DRAFT', gradingToken: token }).session(session);
      if (!current) throw missingQuiz();
      const output = [];
      const entryIds=quiz.questions.map(question=>new Types.ObjectId(question.entryId));
      const progresses=await WordProgress.find({userId,entryId:{$in:entryIds}}).session(session).lean();
      const publishedEntries=await DictionaryEntry.find({_id:{$in:entryIds},status:'PUBLISHED'}).select('categoryId').session(session).lean();
      const topics=await Category.find({_id:{$in:quiz.questions.map(q=>q.topicId || quiz.topicId).filter(Boolean)}}).select('name status').session(session).lean();
      const progressMap=new Map(progresses.map(row=>[String(row.entryId),row]));
      const entriesMap=new Map(publishedEntries.map(row=>[String(row._id),row]));
      const topicsMap=new Map(topics.map(row=>[String(row._id),row]));
      const collection=quiz.collectionId?await SignCollection.findOne({_id:quiz.collectionId,userId}).session(session).lean():null;
      const members=new Set(collection?.entryIds.map(String) || []);
      const progressWrites:Parameters<typeof WordProgress.bulkWrite>[0]=[];
      const enrollments=new Map<string,Types.ObjectId>();
      const events:Record<string,unknown>[]=[];
      const choice = quiz.kind === 'VIDEO_CHOICE';
      const recall = quiz.kind === 'VIDEO_RECALL';
      for (const [index, question] of quiz.questions.entries()) {
        const capture = (quiz.captures || []).find(c => c.entryId === question.entryId);
        const selected = question.options?.find(option => option.value === quiz.answers?.[index]);
        const accepted = [question.word, ...(question.aliases || [])].map(normalize);
        const recalled = quiz.recallResponses?.find(row=>row.entryId===question.entryId);
        const matched = recall ? recalled?.match==='EXACT' && !recalled.usedHint : choice ? quiz.answers?.[index] === question.correctOptionId : accepted.includes(normalize(capture!.recognizedLabel));
        const score = matched ? 10 : 0;
        const topicId=question.topicId?new Types.ObjectId(question.topicId):quiz.topicId!;
        const topic=topicsMap.get(String(topicId));
        const previous=progressMap.get(question.entryId);
        const progress=previous && previous.topicId.equals(topicId)?previous:undefined;
        const stillReview = progress && (progress.stage === 'REVIEW' ||
          progress.stage === 'REMEMBERED' && progress.nextReviewAt && progress.nextReviewAt <= new Date());
        const published=entriesMap.get(question.entryId)?.categoryId.equals(topicId);
        const eligible=quiz.collectionId?members.has(question.entryId) && topic?.status==='ACTIVE' && (!previous || !!progress):stillReview;
        const applied = !!(eligible && published && (!progress?.reviewedAt || progress.reviewedAt <= quiz.createdAt));
        const stage = matched ? 'REMEMBERED' : 'REVIEW';
        if (applied) {
          progressWrites.push({updateOne:{filter:{userId,entryId:new Types.ObjectId(question.entryId)},
            update:{$set:{topicId,stage,reviewedAt:new Date(),nextReviewAt:matched?new Date(Date.now()+3*86400000):null}},upsert:!!quiz.collectionId}});
          if(quiz.collectionId)enrollments.set(String(topicId),topicId);
          if(quiz.collectionId && !previous)events.push({userId,topicId,entryId:question.entryId,word:question.word,topicName:topic?.name || question.topicName || 'Chủ đề',kind:'SELF_RATED',stage,firstLearning:true});
        }
        events.push({ userId, topicId, entryId: question.entryId, quizId: id,
          word: question.word, topicName: topic?.name || 'Chủ đề đã được gỡ', kind: 'QUIZ_REVIEWED',
          stage, score, applied });
        output.push({ entryId: question.entryId, word: question.word,
          ...(recall ? {selectedAnswer:recalled!.answer,correctAnswer:question.word,matchStatus:recalled!.match,
            usedHint:recalled!.usedHint,selfAssessment:recalled!.assessment,
            definition:question.definition || '',usageExample:question.usageExample || ''} : choice ? { selectedAnswer: selected?.label || '', correctAnswer: question.word,
            definition: question.definition || '', usageExample: question.usageExample || '' } : { recognizedLabel: capture!.recognizedLabel }),
          score, feedback: recall ? (matched?'Bạn tự nhớ đúng nghĩa ký hiệu.':'Từ đã dùng gợi ý hoặc đối chiếu được giữ ở Ôn tập để củng cố.') : choice ? (matched ? 'Bạn đã chọn đúng nghĩa của ký hiệu.' : 'Chưa đúng. Hãy xem lại mẫu ký hiệu và đáp án.')
            : matched ? 'Camera nhận diện đúng ký hiệu.' : 'Ký hiệu nhận diện chưa khớp. Hãy xem lại mẫu và ôn tập thêm.', stage, applied });
      }
      if(progressWrites.length)await WordProgress.bulkWrite(progressWrites,{session});
      if(enrollments.size)await TopicEnrollment.bulkWrite([...enrollments.values()].map(topicId=>({updateOne:{filter:{userId,topicId},update:{$setOnInsert:{userId,topicId}},upsert:true}})),{session});
      if(events.length)await LearningEvent.insertMany(events,{session});
      const score = Math.round(output.reduce((sum, item) => sum + item.score, 0) / output.length * 10) / 10;
      const independent=output.filter(item=>item.score===10).length;
      const assisted=recall?output.filter(item=>item.score===0 && ('matchStatus' in item) && (item.matchStatus==='EXACT' || item.selfAssessment==='SAME_MEANING')).length:0;
      const result = { source: recall?'video-recall':choice ? 'video-choice' : 'sign-ai-camera', score, total: output.length,
        ...(recall?{summary:{independent,assisted,review:output.length-independent-assisted}}:{}),
        feedback: recall?'Ghi nhận lần nhớ đầu tiên. Tự đánh giá và gợi ý được tách khỏi kết quả đối chiếu.':choice ? 'Điểm được tính bằng đáp án đã lưu, độc lập với nhận xét AI.' : 'Kết quả được đối chiếu với ký hiệu camera nhận diện cho từng từ.', items: output };
      current.status = 'COMPLETED';
      current.result = result;
      current.completedAt = new Date();
      current.gradingToken = '';
      current.gradingUntil = null;
      await current.save({ session });
      return current.toObject() as unknown as Attempt;
    });
    return previewDto(completed);
  } catch (error) {
    await ReviewQuiz.updateOne({ _id: id, userId, gradingToken: token }, { $set: { gradingToken: '', gradingUntil: null } });
    throw error;
  }
}
