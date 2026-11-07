import { beforeAll, afterAll, describe, it, expect, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { Types } from 'mongoose';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { Category, DictionaryEntry, User, AuthSession, UserSettings } from '../src/models';
import { ReviewQuiz } from '../src/models/ReviewQuiz.model';
import { TopicEnrollment, WordProgress } from '../src/models/Learning.model';
import { LearningEvent } from '../src/models/LearningEvent.model';
import { SignCollection } from '../src/models/SignCollection.model';
import { matchingBoard } from '../src/services/review-match';
import { reviewQuizAdvice } from '../src/services/review-quiz-advice.service';

let app:Awaited<ReturnType<typeof createApp>>, owner:Types.ObjectId, other:Types.ObjectId, topic:Types.ObjectId;
let auth:string, otherAuth:string, id:string;
const entries:Types.ObjectId[]=[];
const endpoint=()=>`/api/v1/learning/quizzes/${id}`;
const start=()=>request(app).post(`/api/v1/learning/topics/${topic}/quiz`).set('Authorization',auth).send({format:'VIDEO_MATCH'});
const pair=(entryId:string,optionId:string,requestId=randomUUID())=>request(app).post(endpoint()+'/match').set('Authorization',auth).send({entryId,optionId,requestId});
beforeAll(async()=>{
  await connectDatabase(); app=await createApp();
  await Promise.all([ReviewQuiz.init(),TopicEnrollment.init(),WordProgress.init()]);
  const a=await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  const b=await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  owner=new Types.ObjectId(a.body.data.user.id);other=new Types.ObjectId(b.body.data.user.id);
  auth=`Bearer ${a.body.data.tokens.accessToken}`;otherAuth=`Bearer ${b.body.data.tokens.accessToken}`;
  topic=(await Category.create({name:'Ghép cặp QA',slug:'match-'+Date.now(),status:'ACTIVE'}))._id;
  await TopicEnrollment.create({userId:owner,topicId:topic});
  for(const [i,word] of ['gia đình','xin chào','tạm biệt','cảm ơn','bạn'].entries()) {
    const entry=await DictionaryEntry.create({word,aliases:[],definition:'Nội dung đã duyệt '+word,
      categoryId:topic,createdBy:owner,status:'PUBLISHED',videoUrl:`https://example.com/match-${i}.mp4`});
    entries.push(entry._id);
    await WordProgress.create({userId:owner,topicId:topic,entryId:entry._id,stage:'REVIEW',reviewedAt:new Date(Date.now()-60000)});
  }
});
afterAll(async()=>{
  await DictionaryEntry.deleteMany({_id:{$in:entries}});await Category.deleteOne({_id:topic});
  for(const userId of [owner,other])for(const model of [ReviewQuiz,WordProgress,TopicEnrollment,LearningEvent,SignCollection,AuthSession,UserSettings,User]) {
    await model.collection.deleteMany(model===User?{_id:userId}:{userId});
  }
  await disconnectDatabase();
});

describe('Matching review game',()=>{
  it('builds unambiguous boards with 2–4 cards per round and opaque answer tokens',()=>{
    const candidate=(i:number)=>({entryId:String(i),word:'từ '+i,aliases:[],videoUrl:'sample-'+i,imageUrls:[]});
    for(const count of [2,3,4,5,6,7,8,9,10]) {
      const board=matchingBoard(Array.from({length:count},(_,i)=>candidate(i)));
      for(const round of new Set(board.matchOptions.map(o=>o.round))) {
        expect(board.matchOptions.filter(o=>o.round===round).length).toBeGreaterThanOrEqual(2);
        expect(board.matchOptions.filter(o=>o.round===round).length).toBeLessThanOrEqual(4);
      }
    }
    const ambiguous=[candidate(0),{...candidate(1),aliases:['TỪ 0']},candidate(2),{...candidate(3),videoUrl:'sample-2'}];
    expect(matchingBoard(ambiguous).questions).toHaveLength(2);
    expect(()=>matchingBoard([0,1].map(i=>({...candidate(i),videoUrl:'',thumbnailUrl:'same.jpg'})))).toThrow('ít nhất 2 từ');
    expect(()=>matchingBoard([candidate(0)])).toThrow('ít nhất 2 từ');
  });
  it('requires enrollment, hides the answer mapping and resumes drafts across formats',async()=>{
    await request(app).post(`/api/v1/learning/topics/${topic}/quiz`).send({format:'VIDEO_MATCH'}).expect(401);
    await request(app).post(`/api/v1/learning/topics/${topic}/quiz`).set('Authorization',otherAuth).send({format:'VIDEO_MATCH'}).expect(409);
    const quiz=(await start().expect(200)).body.data;id=quiz._id;
    expect(quiz.kind).toBe('VIDEO_MATCH');expect(quiz.questions).toHaveLength(5);
    expect(quiz.matchOptions).toHaveLength(5);
    for(const q of quiz.questions) {
      for(const key of ['word','aliases','matchOptionId','correctOptionId','definition'])expect(q).not.toHaveProperty(key);
      expect(q.response).toBeNull();expect(q.hintOptionId).toBeNull();
    }
    expect((await start().expect(200)).body.data).toEqual(quiz);
    const resume=await request(app).post(`/api/v1/learning/topics/${topic}/quiz`).set('Authorization',auth).send({format:'VIDEO_RECALL'}).expect(200);
    expect(resume.body.data._id).toBe(id);
    await request(app).get(endpoint()).set('Authorization',otherAuth).expect(404);
  });
  it('validates ownership, round and payload, and refuses submission before all pairs match',async()=>{
    const quiz=(await start()).body.data;
    const q=quiz.questions[0], foreign=quiz.matchOptions.find((o:any)=>o.round!==q.round);
    await pair(q.entryId,foreign.value).expect(400);
    await pair(String(new Types.ObjectId()),quiz.matchOptions[0].value).expect(400);
    await request(app).post(endpoint()+'/match').set('Authorization',otherAuth).send({entryId:q.entryId,optionId:quiz.matchOptions[0].value,requestId:randomUUID()}).expect(404);
    await request(app).post(endpoint()+'/match').set('Authorization',auth).send({entryId:q.entryId,optionId:quiz.matchOptions[0].value,requestId:randomUUID(),firstCorrect:true}).expect(400);
    await request(app).patch(endpoint()+'/answers').set('Authorization',auth).send({answers:Array(5).fill('')}).expect(409);
    await request(app).post(endpoint()+'/submit').set('Authorization',auth).send({}).expect(400);
  });
  it('keeps the first attempt, retries a network request idempotently and persists hints',async()=>{
    const quiz=(await start()).body.data, raw=await ReviewQuiz.findById(id).lean();
    const q=raw!.questions[0], correct=q.matchOptionId;
    const round=raw!.matchOptions.find((o:any)=>o.value===correct).round;
    const wrong=raw!.matchOptions.find((o:any)=>o.round===round && o.value!==correct).value;
    const operation=randomUUID();
    let value=(await pair(q.entryId,wrong,operation).expect(200)).body.data;
    expect(value.questions[0].response).toMatchObject({matched:false,attempts:1,firstCorrect:false});
    value=(await pair(q.entryId,wrong,operation).expect(200)).body.data;
    expect(value.questions[0].response.attempts).toBe(1);
    await pair(q.entryId,correct,operation).expect(409);
    value=(await pair(q.entryId,correct).expect(200)).body.data;
    expect(value.questions[0].response).toMatchObject({matched:true,attempts:2,firstCorrect:false});
    expect(value.questions[1].hintOptionId).toBeNull();
    const hinted=raw!.questions[1];
    await request(app).post(endpoint()+'/match-hint').set('Authorization',auth).send({entryId:hinted.entryId}).expect(200);
    const restored=(await request(app).get(endpoint()).set('Authorization',auth).expect(200)).body.data;
    expect(restored.questions[1].hintOptionId).toBe(hinted.matchOptionId);
    expect(restored.questions[1].response.usedHint).toBe(true);
    expect(quiz.questions[1].response).toBeNull();
  });
  it('saves scores and history once, separates assisted results and never promotes matching to remembered',async()=>{
    const raw=await ReviewQuiz.findById(id).lean();
    for(const q of raw!.questions.slice(1))await pair(q.entryId,q.matchOptionId).expect(200);
    const finished=(await request(app).post(endpoint()+'/submit').set('Authorization',auth).send({}).expect(200)).body.data;
    expect(finished.result).toMatchObject({source:'video-match',score:6,gamePoints:400,summary:{firstTry:3,practiced:2}});
    expect(finished.result.items.every((item:any)=>item.stage==='REVIEW')).toBe(true);
    expect(await WordProgress.countDocuments({userId:owner,stage:'REMEMBERED'})).toBe(0);
    await request(app).post(endpoint()+'/submit').set('Authorization',auth).send({}).expect(200);
    expect(await LearningEvent.countDocuments({userId:owner,quizId:id})).toBe(5);
    await pair(raw!.questions[0].entryId,raw!.questions[0].matchOptionId).expect(409);
  });
  it('supports collection games and preserves a pending recall draft when matching is selected',async()=>{
    await User.updateOne({_id:owner},{$set:{isGuest:false,accountType:'GOOGLE'}});
    const collection=await SignCollection.create({userId:owner,name:'Bộ ôn ghép cặp',entryIds:entries.slice(0,3)});
    const url=`/api/v1/sign-collections/${collection._id}/quiz`;
    const started=await request(app).post(url).set('Authorization',auth).send({format:'VIDEO_MATCH'}).expect(200);
    expect(started.body.data).toMatchObject({collectionId:String(collection._id),kind:'VIDEO_MATCH'});
    const resume=await request(app).post(url).set('Authorization',auth).send({}).expect(200);
    expect(resume.body.data._id).toBe(started.body.data._id);
    const stored=await ReviewQuiz.findById(started.body.data._id).lean();
    const first=stored!.questions[0],second=stored!.questions[1];
    await WordProgress.updateOne({userId:owner,entryId:first.entryId},{$set:{stage:'REMEMBERED',reviewedAt:new Date(Date.now()-60000),nextReviewAt:new Date(Date.now()+86400000)}});
    await WordProgress.updateOne({userId:owner,entryId:second.entryId},{$set:{stage:'LEARNING',reviewedAt:new Date(Date.now()+60000)}});
    const game=`/api/v1/learning/quizzes/${stored!._id}`;
    for(const q of stored!.questions) await request(app).post(game+'/match').set('Authorization',auth).send({entryId:q.entryId,optionId:q.matchOptionId,requestId:randomUUID()}).expect(200);
    await request(app).post(game+'/submit').set('Authorization',auth).send({}).expect(200);
    expect((await WordProgress.findOne({userId:owner,entryId:first.entryId}))!.stage).toBe('REMEMBERED');
    expect((await WordProgress.findOne({userId:owner,entryId:second.entryId}))!.stage).toBe('LEARNING');
    const recall=await request(app).post(url).set('Authorization',auth).send({}).expect(200);
    const preserved=await request(app).post(url).set('Authorization',auth).send({format:'VIDEO_MATCH'}).expect(200);
    expect(preserved.body.data._id).toBe(recall.body.data._id);
    expect(preserved.body.data.kind).toBe('VIDEO_RECALL');
  });
  it('uses optional AI feedback only for practice advice and keeps saved scores authoritative',async()=>{
    const fetch=vi.spyOn(globalThis,'fetch').mockResolvedValue(new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:'Xem lại mẫu, che thẻ nghĩa và thử tự nhớ.'}}]})));
    try {
      const advice=await reviewQuizAdvice(owner,new Types.ObjectId(id));
      expect(advice.source).toBe('lm-studio');expect(advice.advice).toContain('3/5 cặp');
      const prompt=JSON.parse(fetch.mock.calls[0][1]!.body as string);
      const data=JSON.parse(prompt.messages.find((m:any)=>m.role==='user').content);
      expect(Object.keys(data)).toEqual(['practice']);
      expect(data.practice.every((row:any)=>!('selectedAnswer' in row) && !('matched' in row))).toBe(true);
      fetch.mockRejectedValue(new Error('provider unavailable'));
      expect((await reviewQuizAdvice(owner,new Types.ObjectId(id))).source).toBe('rules');
      expect((await ReviewQuiz.findById(id))!.result.gamePoints).toBe(400);
    } finally {fetch.mockRestore();}
  });
});
