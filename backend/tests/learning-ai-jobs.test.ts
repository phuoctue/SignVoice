import {beforeAll,afterAll,afterEach,describe,it,expect,vi} from 'vitest';
import request from 'supertest';
import {Types} from 'mongoose';
import {randomBytes} from 'crypto';
import {createApp} from '../src/app';
import {connectDatabase,disconnectDatabase} from '../src/config/database';
import {User,AuthSession,UserSettings} from '../src/models';
import {AuditLog} from '../src/models/AuditLog.model';
import * as analysis from '../src/services/learning-analysis.service';
import * as coach from '../src/services/learning-coach.service';
import {startLearningAiJob,getLearningAiJob} from '../src/services/learning-ai-jobs.service';

let app:Awaited<ReturnType<typeof createApp>>;
const owners:Types.ObjectId[]=[],release:(()=>void)[]=[];
const key=()=>randomBytes(16).toString('hex');
beforeAll(async()=>{await connectDatabase();app=await createApp();});
afterEach(()=>{release.splice(0).forEach(fn=>fn());vi.useRealTimers();vi.restoreAllMocks();});
afterAll(async()=>{
  await Promise.all([User.deleteMany({_id:{$in:owners}}),AuthSession.deleteMany({userId:{$in:owners}}),
    UserSettings.deleteMany({userId:{$in:owners}}),AuditLog.deleteMany({userId:{$in:owners}})]);
  await disconnectDatabase();
});
async function account(){
  const r=await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  const id=new Types.ObjectId(r.body.data.user.id);owners.push(id);
  return {id,auth:`Bearer ${r.body.data.tokens.accessToken}`};
}
function generation(feature:'analysis'|'coach'='analysis'){
  let resolve!:(value:any)=>void,reject!:(reason:Error)=>void;
  const gate=new Promise<any>((yes,no)=>{resolve=yes;reject=no;});
  release.push(()=>resolve({source:'rules'}));
  const spy=feature==='analysis'?vi.spyOn(analysis,'analyzeLearningProgress').mockReturnValue(gate)
    :vi.spyOn(coach,'learningAdvice').mockReturnValue(gate);
  return {resolve,reject,spy};
}
describe('Short-request learning AI jobs',()=>{
  it('acknowledges a slow generation before completion and makes starts idempotent',async()=>{
    const owner=await account(),g=generation(),requestKey=key();
    const started=await request(app).post('/api/v1/learning/analysis').set('Authorization',owner.auth)
      .send({async:true,requestKey}).expect(202);
    const job=started.body.data;
    expect(job.state).toBe('pending');expect(job.id).toMatch(/^[a-f0-9-]{36}$/);
    expect(started.headers['cache-control']).toBe('no-store');
    const duplicate=await request(app).post('/api/v1/learning/analysis').set('Authorization',owner.auth)
      .send({async:true,requestKey}).expect(202);
    expect(duplicate.body.data.id).toBe(job.id);expect(g.spy).toHaveBeenCalledTimes(1);
    expect((await request(app).get(`/api/v1/learning/ai-jobs/${job.id}`).set('Authorization',owner.auth).expect(200)).body.data.state).toBe('pending');
    g.resolve({source:'lm-studio',analysis:'Actual result',summary:{total:10}});
    const done=await request(app).get(`/api/v1/learning/ai-jobs/${job.id}`).set('Authorization',owner.auth).expect(200);
    expect(done.body.data).toMatchObject({state:'completed',result:{source:'lm-studio',summary:{total:10}}});
    expect(done.body.data).not.toHaveProperty('owner');expect(done.body.data).not.toHaveProperty('requestKey');
  });
  it('requires current authentication and never returns another account job',async()=>{
    const a=await account(),b=await account(),g=generation('coach');
    const r=await request(app).post('/api/v1/learning/coach').set('Authorization',a.auth).send({async:true,requestKey:key()}).expect(202);
    const path=`/api/v1/learning/ai-jobs/${r.body.data.id}`;
    await request(app).get(path).expect(401);
    await request(app).get(path).set('Authorization',b.auth).expect(404);
    g.resolve({source:'lm-studio',advice:'Only owner may see this'});
    await request(app).get(path).set('Authorization',b.auth).expect(404);
    await User.updateOne({_id:a.id},{$set:{status:'SUSPENDED'}});
    await request(app).get(path).set('Authorization',a.auth).expect(401);
  });
  it('reports failures without exposing provider error or leaving requests hanging',async()=>{
    const a=await account(),g=generation();
    const r=await request(app).post('/api/v1/learning/analysis').set('Authorization',a.auth).send({async:true,requestKey:key()}).expect(202);
    g.reject(new Error('private provider credential and prompt'));
    const failed=await request(app).get(`/api/v1/learning/ai-jobs/${r.body.data.id}`).set('Authorization',a.auth).expect(200);
    expect(failed.body.data.state).toBe('failed');expect(failed.body.data.message).toBeTruthy();
    expect(JSON.stringify(failed.body)).not.toContain('credential');
  });
  it('rejects injected owner/prompt and malformed async requests',async()=>{
    const a=await account();
    for(const body of [{async:true},{async:true,requestKey:key(),userId:String(a.id)},
      {async:true,requestKey:key(),prompt:'override'},{requestKey:key()}]){
      await request(app).post('/api/v1/learning/coach').set('Authorization',a.auth).send(body).expect(400);
    }
    await request(app).get('/api/v1/learning/ai-jobs/not-an-id').set('Authorization',a.auth).expect(400);
  });
  it('bounds parallel jobs per account and expires results',async()=>{
    const owner=new Types.ObjectId(),g=generation();
    const a=startLearningAiJob(owner,'analysis',key()),b=startLearningAiJob(owner,'analysis',key());
    expect(a.id).not.toBe(b.id);
    expect(()=>startLearningAiJob(owner,'analysis',key())).toThrowError(/AI đang xử lý/);
    g.resolve({source:'lm-studio'});await new Promise(resolve=>setImmediate(resolve));
    expect(getLearningAiJob(owner,a.id).state).toBe('completed');
    vi.useFakeTimers({toFake:['Date']});vi.setSystemTime(Date.now()+300001);
    expect(()=>getLearningAiJob(owner,a.id)).toThrowError(/hết hạn/);
  });
});
