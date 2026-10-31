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

let app: Awaited<ReturnType<typeof createApp>>, owner: Types.ObjectId, other: Types.ObjectId;
let auth: string, otherAuth: string, topic: Types.ObjectId, id: string;
const entries: Types.ObjectId[] = [];
beforeAll(async () => {
  await connectDatabase(); app = await createApp();
  await Promise.all([ReviewQuiz.init(), TopicEnrollment.init(), WordProgress.init()]);
  const a = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  const b = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  owner = new Types.ObjectId(a.body.data.user.id); other = new Types.ObjectId(b.body.data.user.id);
  auth = `Bearer ${a.body.data.tokens.accessToken}`; otherAuth = `Bearer ${b.body.data.tokens.accessToken}`;
  topic = (await Category.create({name:'Video quiz '+Date.now(),slug:'video-quiz-'+Date.now(),status:'ACTIVE'}))._id;
  await TopicEnrollment.create({userId:owner,topicId:topic});
  for(let i=0;i<6;i++) {
    const row = await DictionaryEntry.create({word:`Nghĩa ${i}`,aliases:[`Tên khác ${i}`],definition:`Định nghĩa đã lưu ${i}.`,
      usageExample:`Ví dụ đã lưu ${i}.`, videoUrl:`https://example.com/quiz-${i}.mp4`,categoryId:topic,createdBy:owner,status:'PUBLISHED'});
    entries.push(row._id);
    await WordProgress.create({userId:owner,topicId:topic,entryId:row._id,stage:i<2?'REVIEW':'LEARNING',reviewedAt:new Date(Date.now()-60000)});
  }
});
afterEach(()=>vi.restoreAllMocks());
afterAll(async()=>{
  await DictionaryEntry.deleteMany({categoryId:topic}); await Category.deleteOne({_id:topic});
  for(const userId of [owner,other]) for(const model of [ReviewQuiz,TopicEnrollment,WordProgress,LearningEvent,AuthSession,UserSettings,User]) {
    await model.collection.deleteMany(model===User?{_id:userId}:{userId});
  }
  await disconnectDatabase();
});
const path = () => `/api/v1/learning/quizzes/${id}`;

describe('Video-choice quiz',()=>{
  it('requires owner enrollment and creates stable options without revealing answer keys or definitions',async()=>{
    await request(app).post(`/api/v1/learning/topics/${topic}/quiz`).send({format:'VIDEO_CHOICE'}).expect(401);
    await request(app).post(`/api/v1/learning/topics/${topic}/quiz`).set('Authorization',otherAuth).send({format:'VIDEO_CHOICE'}).expect(409);
    const response=await request(app).post(`/api/v1/learning/topics/${topic}/quiz`).set('Authorization',auth).send({format:'VIDEO_CHOICE'}).expect(200);
    const quiz=response.body.data; id=quiz._id;
    expect(quiz.kind).toBe('VIDEO_CHOICE'); expect(quiz.questions).toHaveLength(2); expect(quiz.answers).toEqual(['','']);
    expect(JSON.stringify(quiz)).not.toMatch(/correctOptionId|Định nghĩa đã lưu|Ví dụ đã lưu/);
    for(const q of quiz.questions) {
      expect(q).not.toHaveProperty('word'); expect(q).not.toHaveProperty('aliases');
      expect(q.options).toHaveLength(4); expect(new Set(q.options.map((o:any)=>o.label)).size).toBe(4);
      expect(q.options.every((o:any)=>!entries.some(id=>String(id)===o.value))).toBe(true);
    }
    const resumed=await request(app).post(`/api/v1/learning/topics/${topic}/quiz`).set('Authorization',auth).send({format:'VIDEO_CHOICE'}).expect(200);
    expect(resumed.body.data).toEqual(quiz);
    await request(app).get(path()).set('Authorization',otherAuth).expect(404);
    await request(app).patch(path()+'/captures').set('Authorization',auth).send({entryId:String(entries[0]),recognizedLabel:'Nghĩa 0'}).expect(409);
  });

  it('validates selected option IDs, allows resumable partial answers and rejects incomplete submission',async()=>{
    const stored=await ReviewQuiz.findById(id).lean(); const questions=stored!.questions;
    await request(app).patch(path()+'/answers').set('Authorization',auth).send({answers:['forged','']}).expect(400);
    await request(app).patch(path()+'/answers').set('Authorization',auth).send({answers:[questions[1].options[0].value,'']}).expect(400);
    const partial=[questions[0].options[0].value,''];
    await request(app).patch(path()+'/answers').set('Authorization',otherAuth).send({answers:partial}).expect(404);
    await request(app).patch(path()+'/answers').set('Authorization',auth).send({answers:partial}).expect(200);
    expect((await request(app).get(path()).set('Authorization',auth)).body.data.answers).toEqual(partial);
    await request(app).post(path()+'/submit').set('Authorization',auth).send({}).expect(400);
    await request(app).post(path()+'/advice').set('Authorization',auth).send({async:true,requestKey:'a'.repeat(32)}).expect(409);
  });

  it('grades against persisted keys, records progress/history once and counts new quizzes in activity',async()=>{
    const stored=await ReviewQuiz.findById(id).lean(); const questions=stored!.questions;
    const answers=[questions[0].correctOptionId,questions[1].options.find((o:any)=>o.value!==questions[1].correctOptionId).value];
    await request(app).patch(path()+'/answers').set('Authorization',auth).send({answers}).expect(200);
    const generated=vi.spyOn(globalThis,'fetch');
    const response=await request(app).post(path()+'/submit').set('Authorization',auth).send({}).expect(200);
    expect(generated).not.toHaveBeenCalled();
    expect(response.body.data.result).toMatchObject({source:'video-choice',score:5,total:2});
    expect(response.body.data.result.items[0]).toMatchObject({score:10,stage:'REMEMBERED',correctAnswer:questions[0].word});
    expect(response.body.data.result.items[1]).toMatchObject({score:0,stage:'REVIEW',correctAnswer:questions[1].word});
    await request(app).post(path()+'/submit').set('Authorization',auth).send({}).expect(200);
    expect(await LearningEvent.countDocuments({userId:owner,quizId:id})).toBe(2);
    expect((await WordProgress.findOne({userId:owner,entryId:questions[0].entryId}))!.stage).toBe('REMEMBERED');
    expect((await WordProgress.findOne({userId:owner,entryId:questions[1].entryId}))!.stage).toBe('REVIEW');
    await request(app).patch(path()+'/answers').set('Authorization',auth).send({answers}).expect(409);
    const today=await request(app).get('/api/v1/learning/today').set('Authorization',auth).expect(200);
    expect(today.body.data.today.reviewed).toBe(2);
  });

  it('returns AI feedback through short private jobs without changing scores or sending account identifiers',async()=>{
    let resolve!: (value:Response)=>void;
    const pending=new Promise<Response>(done=>{resolve=done;});
    const mocked=vi.spyOn(globalThis,'fetch').mockReturnValue(pending);
    await request(app).post(path()+'/advice').set('Authorization',otherAuth).send({async:true,requestKey:'b'.repeat(32)}).expect(404);
    const start=await request(app).post(path()+'/advice').set('Authorization',auth).send({async:true,requestKey:'b'.repeat(32)}).expect(202);
    expect(start.body.data.state).toBe('pending');
    const job='/api/v1/learning/ai-jobs/'+start.body.data.id;
    await request(app).get(job).set('Authorization',otherAuth).expect(404);
    for(let i=0;i<30 && !mocked.mock.calls.length;i++) await new Promise(done=>setTimeout(done,10));
    const body=JSON.parse(mocked.mock.calls[0][1]!.body as string);
    expect(JSON.stringify(body)).not.toContain(String(owner)); expect(JSON.stringify(body)).not.toContain(String(other));
    expect(body.messages[1].content).toContain('Định nghĩa đã lưu');
    resolve(new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:'Hãy xem lại video từ trả lời sai và ôn trong 5 phút.'}}]})));
    let result:any;
    for(let i=0;i<30;i++) {result=(await request(app).get(job).set('Authorization',auth)).body.data; if(result.state==='completed')break; await new Promise(done=>setTimeout(done,10));}
    expect(result).toMatchObject({state:'completed',result:{source:'lm-studio'}});
    expect((await ReviewQuiz.findById(id))!.result.score).toBe(5);
  });

  it('falls back to factual feedback when the model fails, with no progress writes',async()=>{
    vi.spyOn(globalThis,'fetch').mockRejectedValue(new Error('private provider error'));
    const result=await reviewQuizAdvice(owner,new Types.ObjectId(id));
    expect(result.source).toBe('rules'); expect(result.advice).toContain('1/2');
    expect(result.advice).not.toContain('private provider error');
    expect(await LearningEvent.countDocuments({userId:owner,quizId:id})).toBe(2);
  });

  it('replaces an old camera draft only when a valid video quiz can be created',async()=>{
    const old=await ReviewQuiz.create({userId:owner,topicId:topic,kind:'CAMERA',questions:[{entryId:String(entries[1]),word:'Nghĩa 1'}]});
    await DictionaryEntry.updateMany({categoryId:topic},{$set:{videoUrl:'https://example.com/same.mp4'}});
    await request(app).post(`/api/v1/learning/topics/${topic}/quiz`).set('Authorization',auth).send({format:'VIDEO_CHOICE'}).expect(409);
    expect((await ReviewQuiz.findById(old._id))!.status).toBe('DRAFT');
    for(let i=0;i<entries.length;i++)await DictionaryEntry.updateOne({_id:entries[i]},{$set:{videoUrl:`https://example.com/quiz-${i}.mp4`}});
    const next=await request(app).post(`/api/v1/learning/topics/${topic}/quiz`).set('Authorization',auth).send({format:'VIDEO_CHOICE'}).expect(200);
    expect(next.body.data.kind).toBe('VIDEO_CHOICE');
    expect((await ReviewQuiz.findById(old._id))!.status).toBe('ABANDONED');
  });
});
