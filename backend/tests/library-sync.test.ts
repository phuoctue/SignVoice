import {beforeAll,afterAll,describe,it,expect} from 'vitest';
import request from 'supertest';
import {Types} from 'mongoose';
import {randomBytes} from 'node:crypto';
import {mkdirSync,writeFileSync,unlinkSync} from 'node:fs';
import path from 'node:path';
import {connectDatabase,disconnectDatabase} from '../src/config/database';
import {createApp} from '../src/app';
import {User,DictionaryEntry,Category,AuthSession,UserSettings} from '../src/models';
import {SignCollection,SignNote} from '../src/models/SignCollection.model';
import {ReviewQuiz} from '../src/models/ReviewQuiz.model';
import {WordProgress,TopicEnrollment} from '../src/models/Learning.model';
import {LearningEvent} from '../src/models/LearningEvent.model';
import {LibraryRevision} from '../src/models/LibraryRevision.model';
import {importReferenceRows,ReferenceRow} from '../scripts/import-sign-library';
import {ensureLearningIndexes} from '../src/services/learning-indexes.service';

let app:Awaited<ReturnType<typeof createApp>>,author:Types.ObjectId,owner:Types.ObjectId,entry:Types.ObjectId;
let auth:string,collection:string,completed:string,draft:string,initialRevision:string;
const media=path.resolve(__dirname,'../../.runtime/sign-library-media'),files:string[]=[];
const clipA=randomBytes(32).toString('hex'),clipB=randomBytes(32).toString('hex'),clipC=randomBytes(32).toString('hex');
const word='từ đồng bộ '+randomBytes(4).toString('hex');
const row=(name:string,clip:string):ReferenceRow=>({word:name,media_id:clip,source_sha256:clip,source:'user_Dataset.tgz',source_url:'',license:null,source_path:'sources/user_dictionary/Videos/source.mp4',source_split:''});
beforeAll(async()=>{
  await connectDatabase();app=await createApp();await ensureLearningIndexes();await Promise.all([DictionaryEntry.init(),WordProgress.init(),TopicEnrollment.init()]);
  mkdirSync(media,{recursive:true});
  for(const clip of [clipA,clipB,clipC])for(const name of [clip+'.mp4',...[1,2,3,4,5].map(n=>clip+'-'+n+'.jpg')]){
    const file=path.join(media,name);writeFileSync(file,Buffer.from([255,216,255,1]),{flag:'wx'});files.push(file);
  }
  author=(await User.create({email:'library-sync-'+Date.now()+'@example.test',displayName:'Sync author',role:'ADMIN',accountType:'LOCAL',status:'ACTIVE',passwordHash:'test-only'}))._id;
  const user=await request(app).post('/api/v1/auth/guest').send({}).expect(201);owner=new Types.ObjectId(user.body.data.user.id);auth=`Bearer ${user.body.data.tokens.accessToken}`;
});
afterAll(async()=>{
  for(const file of files)unlinkSync(file);
  await DictionaryEntry.deleteMany({createdBy:author});await LibraryRevision.deleteOne({_id:'dictionary'});
  for(const userId of [owner,author])for(const model of [User,AuthSession,UserSettings,SignCollection,SignNote,ReviewQuiz,WordProgress,TopicEnrollment,LearningEvent])await model.collection.deleteMany(model===User?{_id:userId}:{userId});
  await disconnectDatabase();
});
describe('Canonical media package synchronization',()=>{
  it('imports stable entry IDs and publishes a public revision without owner data',async()=>{
    await importReferenceRows([row(word,clipA)],'http://localhost',author,{syncRemoved:true});
    entry=(await DictionaryEntry.findOne({word}))!._id;
    const version=await request(app).get('/api/v1/library/version').expect(200);
    initialRevision=version.body.data.revision;expect(initialRevision).toMatch(/^[a-f0-9]{64}$/);
    expect(JSON.stringify(version.body)).not.toContain(String(author));
    collection=(await request(app).post('/api/v1/sign-collections').set('Authorization',auth).send({name:'Bộ dùng media đồng bộ'}).expect(201)).body.data._id;
    await request(app).post('/api/v1/sign-collections/'+collection+'/entries').set('Authorization',auth).send({entryIds:[String(entry)]}).expect(200);
    completed=(await request(app).post('/api/v1/sign-collections/'+collection+'/quiz').set('Authorization',auth).send({}).expect(200)).body.data._id;
    await request(app).post('/api/v1/learning/quizzes/'+completed+'/check').set('Authorization',auth).send({entryId:String(entry),answer:word}).expect(200);
    await request(app).post('/api/v1/learning/quizzes/'+completed+'/submit').set('Authorization',auth).send({}).expect(200);
    draft=(await request(app).post('/api/v1/sign-collections/'+collection+'/quiz').set('Authorization',auth).send({}).expect(200)).body.data._id;
  });
  it('updates live media everywhere while retaining IDs, notes, progress and historical grades',async()=>{
    await SignNote.create({userId:owner,entryId:entry,text:'Keep my note'});
    const progress=await WordProgress.findOne({userId:owner,entryId:entry});
    await importReferenceRows([row(word,clipB)],'http://localhost',author,{syncRemoved:true});
    const current=await DictionaryEntry.findOne({word});expect(String(current!._id)).toBe(String(entry));
    const detail=await request(app).get('/api/v1/sign-collections/'+collection).set('Authorization',auth).expect(200);
    expect(detail.body.data.items[0].videoUrl).toContain(clipB);expect(detail.body.data.items[0].personalNote).toBe('Keep my note');
    const history=await request(app).get('/api/v1/learning/quizzes/'+completed).set('Authorization',auth).expect(200);
    expect(history.body.data.questions[0].videoUrl).toContain(clipB);expect(history.body.data.result.score).toBe(10);
    expect((await WordProgress.findOne({userId:owner,entryId:entry}))!.reviewedAt).toEqual(progress!.reviewedAt);
    const abandoned=await request(app).get('/api/v1/learning/quizzes/'+draft).set('Authorization',auth).expect(200);
    expect(abandoned.body.data).toMatchObject({status:'ABANDONED',libraryChanged:true});
    await request(app).post('/api/v1/learning/quizzes/'+draft+'/submit').set('Authorization',auth).send({}).expect(409);
    const version=await request(app).get('/api/v1/library/version').expect(200);expect(version.body.data.revision).not.toBe(initialRevision);
  });
  it('does not expire a draft when the same package is imported again',async()=>{
    const current=(await request(app).post('/api/v1/sign-collections/'+collection+'/quiz').set('Authorization',auth).send({}).expect(200)).body.data;
    const version=(await request(app).get('/api/v1/library/version')).body.data.revision;
    await importReferenceRows([row(word,clipB)],'http://localhost',author,{syncRemoved:true});
    expect((await ReviewQuiz.findById(current._id))!.status).toBe('DRAFT');
    expect((await request(app).get('/api/v1/library/version')).body.data.revision).toBe(version);
  });
  it('archives only missing managed words and restores the same ID when the word returns',async()=>{
    const manual=await DictionaryEntry.create({word:'Manual '+word,definition:'Kept manually',videoUrl:'https://example.com/manual.mp4',categoryId:(await Category.findOne({status:'ACTIVE'}))!._id,createdBy:author,status:'PUBLISHED'});
    await importReferenceRows([row(word+' mới',clipC)],'http://localhost',author,{syncRemoved:true});
    expect((await DictionaryEntry.findById(entry))!).toMatchObject({status:'ARCHIVED',referenceMissing:true});
    expect((await DictionaryEntry.findById(manual._id))!.status).toBe('PUBLISHED');
    expect((await request(app).get('/api/v1/sign-collections/'+collection).set('Authorization',auth)).body.data.items).toHaveLength(0);
    await importReferenceRows([row(word,clipB),row(word+' mới',clipC)],'http://localhost',author,{syncRemoved:true});
    expect((await DictionaryEntry.findOne({word}))!._id.toString()).toBe(String(entry));
    expect((await DictionaryEntry.findById(entry))!).toMatchObject({status:'PUBLISHED',referenceMissing:false});
    expect((await request(app).get('/api/v1/sign-collections/'+collection).set('Authorization',auth)).body.data.items[0].videoUrl).toContain(clipB);
  });
});
