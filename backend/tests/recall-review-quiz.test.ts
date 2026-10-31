import {beforeAll, afterAll, afterEach, describe, it, expect, vi} from 'vitest';
import request from 'supertest';
import {Types} from 'mongoose';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {Category, DictionaryEntry, User, AuthSession, UserSettings} from '../src/models';
import {TopicEnrollment, WordProgress} from '../src/models/Learning.model';
import {ReviewQuiz} from '../src/models/ReviewQuiz.model';
import {LearningEvent} from '../src/models/LearningEvent.model';
import {reviewQuizAdvice} from '../src/services/review-quiz-advice.service';
import {randomBytes} from 'node:crypto';
import {mkdirSync,writeFileSync,unlinkSync} from 'node:fs';
import nodePath from 'node:path';

const previewName=`${randomBytes(32).toString('hex')}-1.jpg`;
const previewDirectory=nodePath.resolve(__dirname,'../../.runtime/sign-library-media');
const previewFilename=nodePath.join(previewDirectory,previewName);
const previewBytes=Buffer.from([255,216,255,10,20]);

let app:Awaited<ReturnType<typeof createApp>>,owner:Types.ObjectId,other:Types.ObjectId;
let auth:string,otherAuth:string,id:string;
const topics:Types.ObjectId[]=[],entries:Types.ObjectId[]=[];
const words=['bàn bạc','cảm ơn','bạn','gia đình','tạm biệt','xin lỗi','ăn cơm','vui vẻ','ngày mai'];
const path=()=>`/api/v1/learning/quizzes/${id}`;
beforeAll(async()=>{
  mkdirSync(previewDirectory,{recursive:true});
  writeFileSync(previewFilename,previewBytes,{flag:'wx'});
  await connectDatabase();app=await createApp();
  await Promise.all([ReviewQuiz.init(),TopicEnrollment.init(),WordProgress.init()]);
  const a=await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  const b=await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  owner=new Types.ObjectId(a.body.data.user.id);other=new Types.ObjectId(b.body.data.user.id);
  auth=`Bearer ${a.body.data.tokens.accessToken}`;otherAuth=`Bearer ${b.body.data.tokens.accessToken}`;
  const topic=await Category.create({name:'Recall '+Date.now(),slug:'recall-'+Date.now(),status:'ACTIVE'});topics.push(topic._id);
  await TopicEnrollment.create({userId:owner,topicId:topic._id});
  for(let i=0;i<words.length;i++) {
    const entry=await DictionaryEntry.create({word:words[i],aliases:i===0?['thảo luận']:i===1?['cám ơn']:[],
      ...(i===0?{thumbnailUrl:`/sign-media/${previewName}`} : {}),
      definition:`Mô tả đã duyệt cho ${words[i]}.`,usageExample:`Ví dụ đã duyệt ${words[i]}.`,
      videoUrl:i===8?`http://localhost/sign-media/${'f'.repeat(64)}.mp4`:`https://example.com/recall-${i}.mp4`,
      categoryId:topic._id,createdBy:owner,status:'PUBLISHED'});
    entries.push(entry._id);
    await WordProgress.create({userId:owner,topicId:topic._id,entryId:entry._id,stage:i===7?'REMEMBERED':'REVIEW',
      nextReviewAt:i===7?new Date(Date.now()-60000):null,reviewedAt:new Date(Date.now()-60000)});
  }
});
afterEach(()=>vi.restoreAllMocks());
afterAll(async()=>{
  unlinkSync(previewFilename);
  await DictionaryEntry.deleteMany({categoryId:{$in:topics}});await Category.deleteMany({_id:{$in:topics}});
  for(const userId of [owner,other])for(const model of [ReviewQuiz,TopicEnrollment,WordProgress,LearningEvent,AuthSession,UserSettings,User]) {
    await model.collection.deleteMany(model===User?{_id:userId}:{userId});
  }
  await disconnectDatabase();
});
const check=(i:number,answer:string,skip=false)=>request(app).post(path()+'/check').set('Authorization',auth).send({entryId:String(entries[i]),answer,skip});
const question=(data:any,i:number)=>data.questions.find((q:any)=>q.entryId===String(entries[i]));

describe('Recall quiz: first recall, hints and self-assessment',()=>{
  it('creates media-backed recall questions without answer keys, options or definitions and resumes the same draft',async()=>{
    await request(app).post(`/api/v1/learning/topics/${topics[0]}/quiz`).send({format:'VIDEO_RECALL'}).expect(401);
    await request(app).post(`/api/v1/learning/topics/${topics[0]}/quiz`).set('Authorization',otherAuth).send({format:'VIDEO_RECALL'}).expect(409);
    const response=await request(app).post(`/api/v1/learning/topics/${topics[0]}/quiz`).set('Authorization',auth).send({format:'VIDEO_RECALL'}).expect(200);
    const quiz=response.body.data;id=quiz._id;
    expect(quiz.kind).toBe('VIDEO_RECALL');expect(quiz.questions).toHaveLength(8);
    expect(question(quiz,0).thumbnailDataUrl).toBe(`data:image/jpeg;base64,${previewBytes.toString('base64')}`);
    for(const q of quiz.questions) {
      expect(q.response).toBeNull();expect(q.hint).toBeNull();
      for(const key of ['word','aliases','options','definition','correctAnswer','correctOptionId'])expect(q).not.toHaveProperty(key);
    }
    expect(JSON.stringify(quiz)).not.toContain('Mô tả đã duyệt');
    const resumed=await request(app).post(`/api/v1/learning/topics/${topics[0]}/quiz`).set('Authorization',auth).send({format:'VIDEO_RECALL'}).expect(200);
    expect(resumed.body.data).toEqual(quiz);
    await request(app).get(path()).set('Authorization',otherAuth).expect(404);
    await request(app).post(`/api/v1/learning/topics/${topics[0]}/quiz`).set('Authorization',auth).send({format:'VIDEO_CHOICE'}).expect(409);
  });
  it('saves partial text drafts and rejects forged hint state, empty checks and another owner',async()=>{
    const current=(await request(app).get(path()).set('Authorization',auth)).body.data;
    const answers=current.answers.map((_:string,i:number)=>i===0?'Bản nháp đang nhớ':'');
    await request(app).patch(path()+'/answers').set('Authorization',auth).send({answers}).expect(200);
    expect((await request(app).get(path()).set('Authorization',auth)).body.data.answers).toEqual(answers);
    await request(app).post(path()+'/check').set('Authorization',otherAuth).send({entryId:String(entries[0]),answer:'bàn bạc'}).expect(404);
    await request(app).post(path()+'/hint').set('Authorization',auth).send({entryId:String(new Types.ObjectId())}).expect(400);
    await check(0,'   ').expect(400);await check(0,'!!!').expect(400);
    await request(app).post(path()+'/check').set('Authorization',auth).send({entryId:String(entries[0]),answer:'bàn bạc',usedHint:false}).expect(400);
    await request(app).post(path()+'/submit').set('Authorization',auth).send({}).expect(400);
  });
  it('matches approved aliases, NFC accents, case and outer punctuation without rewriting the first checked answer',async()=>{
    const reads=vi.spyOn(ReviewQuiz,'findOne');
    const first=await check(0,'  THẢO   LUẬN!  ').expect(200);
    expect(reads).toHaveBeenCalledTimes(1);
    reads.mockRestore();
    expect(question(first.body.data,0).response).toMatchObject({match:'EXACT',usedHint:false,correctAnswer:'bàn bạc'});
    expect(question(first.body.data,0)).not.toHaveProperty('thumbnailDataUrl');
    expect(question(first.body.data,2).response).toBeNull();
    await check(0,'  THẢO   LUẬN!  ').expect(200);
    await check(0,'bàn bạc').expect(409);
    const nfc=await check(1,'CẢM ƠN'.normalize('NFD')).expect(200);
    expect(question(nfc.body.data,1).response.match).toBe('EXACT');
    const forged=nfc.body.data.answers.map((v:string)=>v);forged[nfc.body.data.questions.findIndex((q:any)=>q.entryId===String(entries[0]))]='đổi kết quả';
    await request(app).patch(path()+'/answers').set('Authorization',auth).send({answers:forged}).expect(409);
    await request(app).post(path()+'/hint').set('Authorization',auth).send({entryId:String(entries[0])}).expect(409);
    expect((await WordProgress.findOne({userId:owner,entryId:entries[0]}))!.stage).toBe('REVIEW');
    expect((await ReviewQuiz.findById(id))!.recallResponses).toHaveLength(2);
  });
  it('persists hints and distinguishes spelling suggestions from verified matches',async()=>{
    const reads=vi.spyOn(ReviewQuiz,'findOne');
    const hinted=await request(app).post(path()+'/hint').set('Authorization',auth).send({entryId:String(entries[3])}).expect(200);
    expect(reads).toHaveBeenCalledTimes(1);
    expect(question(hinted.body.data,3).hint).toContain('2 tiếng');
    expect(question(hinted.body.data,3).hint).not.toContain('gia đình');
    const assisted=await check(3,'gia đình').expect(200);
    expect(question(assisted.body.data,3).response).toMatchObject({match:'EXACT',usedHint:true});
    const near=await check(2,'ban').expect(200);
    expect(question(near.body.data,2).response).toMatchObject({match:'CLOSE',assessment:null});
    await request(app).post(path()+'/assessment').set('Authorization',auth).send({entryId:String(entries[2]),assessment:'AUTO_CORRECT'}).expect(400);
    reads.mockClear();
    const self=await request(app).post(path()+'/assessment').set('Authorization',auth).send({entryId:String(entries[2]),assessment:'SAME_MEANING'}).expect(200);
    expect(reads).toHaveBeenCalledTimes(1);
    expect(question(self.body.data,2).response).toMatchObject({match:'CLOSE',assessment:'SAME_MEANING'});
    await request(app).patch(path()+'/captures').set('Authorization',auth).send({entryId:String(entries[2]),recognizedLabel:'bạn'}).expect(409);
  });
  it('records review/skip independently and grades only unassisted exact recall, idempotently',async()=>{
    await check(4,'xin chào').expect(200);
    await request(app).post(path()+'/assessment').set('Authorization',auth).send({entryId:String(entries[4]),assessment:'REVIEW'}).expect(200);
    await check(5,'',true).expect(200);
    await check(6,'ăn cơm').expect(200);await check(7,'vui vẻ').expect(200);
    await WordProgress.updateOne({userId:owner,entryId:entries[6]},{$set:{stage:'LEARNING',reviewedAt:new Date(Date.now()+60000)}});
    const model=vi.spyOn(globalThis,'fetch');
    const finished=await request(app).post(path()+'/submit').set('Authorization',auth).send({}).expect(200);
    expect(model).not.toHaveBeenCalled();
    expect(finished.body.data.result).toMatchObject({source:'video-recall',score:5,total:8,summary:{independent:4,assisted:2,review:2}});
    const results=finished.body.data.result.items;
    expect(results.find((r:any)=>r.word==='gia đình')).toMatchObject({score:0,stage:'REVIEW',usedHint:true});
    expect(results.find((r:any)=>r.word==='bạn')).toMatchObject({score:0,stage:'REVIEW',selfAssessment:'SAME_MEANING'});
    expect(results.find((r:any)=>r.word==='ăn cơm').applied).toBe(false);
    expect((await WordProgress.findOne({userId:owner,entryId:entries[6]}))!.stage).toBe('LEARNING');
    await request(app).post(path()+'/submit').set('Authorization',auth).send({}).expect(200);
    expect(await LearningEvent.countDocuments({userId:owner,quizId:id})).toBe(8);
    expect((await request(app).get('/api/v1/learning/today').set('Authorization',auth)).body.data.today.reviewed).toBe(8);
    await check(0,'bàn bạc').expect(409);
  });
  it('provides read-only feedback with explicit recall categories and safe fallback',async()=>{
    const model=vi.spyOn(globalThis,'fetch').mockResolvedValue(new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:'Hãy xem lại video rồi che đáp án và tự nhớ nghĩa.'}}]})));
    const advice=await reviewQuizAdvice(owner,new Types.ObjectId(id));
    expect(advice.source).toBe('lm-studio');
    const prompt=JSON.parse(model.mock.calls[0][1]!.body as string);
    const data=JSON.parse(prompt.messages.find((message:any)=>message.role==='user').content);
    expect(data.summary).toBeUndefined();expect(data.correct).toBeUndefined();
    expect(data.practice.every((row:any)=>!('selectedAnswer' in row) && !('matched' in row))).toBe(true);
    expect(advice.advice).toContain('Bạn tự nhớ 4/8');
    expect(JSON.stringify(data)).not.toContain(String(owner));expect(JSON.stringify(data)).not.toContain('entryId');
    model.mockResolvedValue(new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:'Bạn trả lời đúng 8/8 câu.'}}]})));
    const misleading=await reviewQuizAdvice(owner,new Types.ObjectId(id));
    expect(misleading.source).toBe('rules');expect(misleading.advice).toContain('Bạn tự nhớ 4/8');
    model.mockRejectedValue(new Error('provider private failure'));
    const fallback=await reviewQuizAdvice(owner,new Types.ObjectId(id));
    expect(fallback.source).toBe('rules');expect(fallback.advice).toContain('tự nhớ 4/8');
    expect((await ReviewQuiz.findById(id))!.result.score).toBe(5);
  });
  it('supports one-word topics and preserves old drafts until usable media exists',async()=>{
    const topic=await Category.create({name:'One recall '+Date.now(),slug:'one-recall-'+Date.now(),status:'ACTIVE'});topics.push(topic._id);
    await TopicEnrollment.create({userId:owner,topicId:topic._id});
    const entry=await DictionaryEntry.create({word:'0',definition:'Chữ số không.',categoryId:topic._id,createdBy:owner,status:'PUBLISHED',videoUrl:`http://localhost/sign-media/${'e'.repeat(64)}.mp4`});
    await WordProgress.create({userId:owner,topicId:topic._id,entryId:entry._id,stage:'REVIEW'});
    const old=await ReviewQuiz.create({userId:owner,topicId:topic._id,kind:'VIDEO_CHOICE',questions:[]});
    await request(app).post(`/api/v1/learning/topics/${topic._id}/quiz`).set('Authorization',auth).send({format:'VIDEO_RECALL'}).expect(409);
    expect((await ReviewQuiz.findById(old._id))!.status).toBe('DRAFT');
    await DictionaryEntry.updateOne({_id:entry._id},{$set:{videoUrl:'https://example.com/zero.mp4'}});
    const single=await request(app).post(`/api/v1/learning/topics/${topic._id}/quiz`).set('Authorization',auth).send({format:'VIDEO_RECALL'}).expect(200);
    expect(single.body.data.questions).toHaveLength(1);expect((await ReviewQuiz.findById(old._id))!.status).toBe('ABANDONED');
    const hint=await request(app).post(`/api/v1/learning/quizzes/${single.body.data._id}/hint`).set('Authorization',auth).send({entryId:String(entry._id)}).expect(200);
    expect(hint.body.data.questions[0].hint).not.toContain('“0”');
  });
});
