import {beforeAll,afterAll,it,expect,vi} from 'vitest';
import request from 'supertest';
import {Types} from 'mongoose';
import {createApp} from '../src/app';
import {connectDatabase,disconnectDatabase} from '../src/config/database';
import {User,UserRole} from '../src/models/User.model';
import {Role} from '../src/models/Role.model';
import {Category} from '../src/models/Category.model';
import {DictionaryEntry} from '../src/models/DictionaryEntry.model';
import {SignCollection,SignNote,CollectionReport} from '../src/models/SignCollection.model';
import {PersonalWord,WordProgress} from '../src/models/Learning.model';
import {AuditLog,AuditAction} from '../src/models/AuditLog.model';
import {ensureLearningIndexes} from '../src/services/learning-indexes.service';

let app:Awaited<ReturnType<typeof createApp>>,owner:string,staff:string,admin:string,reader:string,reporter:string,guest:string;
let ownerId:Types.ObjectId,staffId:Types.ObjectId,reporterId:Types.ObjectId,topic:Types.ObjectId,entry:Types.ObjectId;
const base='/api/v1/sign-collections',manage='/api/v1/admin/collections';
const headers=(token:string)=>({Authorization:`Bearer ${token}`});
const photo='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=';
beforeAll(async()=>{
  await connectDatabase();app=await createApp();await ensureLearningIndexes();await AuditLog.init();
  const actors=[];
  for(let i=0;i<6;i++){
    const response=(await request(app).post('/api/v1/auth/guest').send({}).expect(201)).body.data;
    actors.push(response);
    if(i!==5)await User.updateOne({_id:response.user.id},{$set:{isGuest:false,displayName:i===0?'OWNER_PRIVATE_IDENTITY':i===1?'Nhân viên kiểm duyệt':'Người kiểm tra',role:i===1?UserRole.STAFF:i===2?UserRole.ADMIN:UserRole.USER}});
  }
  [owner,staff,admin,reader,reporter,guest]=actors.map(row=>row.tokens.accessToken);
  ownerId=new Types.ObjectId(actors[0].user.id);staffId=new Types.ObjectId(actors[1].user.id);reporterId=new Types.ObjectId(actors[4].user.id);
  const role=await Role.create({name:'Collection reader',key:'COLLECTION_READER',permissions:['staff:access','collections:read']});
  await User.updateOne({_id:actors[3].user.id},{$set:{customRoleId:role._id}});
  topic=(await Category.create({name:'Moderation QA',slug:'moderation-qa-'+Date.now(),status:'ACTIVE'}))._id;
  entry=(await DictionaryEntry.create({word:'Ký hiệu công khai',definition:'Đã duyệt',createdBy:ownerId,status:'PUBLISHED',categoryId:topic,videoUrl:'https://example.com/public.mp4'}))._id;
});
afterAll(async()=>{await disconnectDatabase();});
async function make(name:string,publish=true){
  const id=(await request(app).post(base).set(headers(owner)).send({name,description:'Mô tả công khai',avatarImage:photo}).expect(201)).body.data._id;
  await request(app).post(base+'/'+id+'/entries').set(headers(owner)).send({entryIds:[String(entry)]}).expect(200);
  const shared=(await request(app).post(base+'/'+id+'/share').set(headers(owner)).send({enabled:true}).expect(200)).body.data;
  if(publish)await request(app).post(base+'/'+id+'/discovery').set(headers(owner)).send({enabled:true}).expect(200);
  return {id,code:shared.shareCode};
}
async function metadata(id:string,token=staff){return (await request(app).get(manage+'/'+id).set(headers(token)).expect(200)).body.data.collection;}
async function moderate(id:string,state:string,token=staff){
  const row=await metadata(id,token);
  return request(app).post(manage+'/'+id+'/moderation').set(headers(token)).send({state,reason:'Lý do kiểm tra rõ ràng',version:row.moderationVersion}).expect(200);
}
it('enforces backend permissions and never exposes private collections, owner identity, words, notes or progress',async()=>{
  const {id}=await make('Bộ quyền và riêng tư');
  const privateSet=await make('PRIVATE_COLLECTION_NAME',false);
  await PersonalWord.create({userId:ownerId,collectionId:id,word:'PRIVATE_CUSTOM_WORD',definition:'PRIVATE_DEFINITION',notes:'PRIVATE_CUSTOM_NOTE',imageUrl:'https://example.com/private.jpg'});
  await SignNote.create({userId:ownerId,entryId:entry,text:'PRIVATE_PERSONAL_NOTE'});
  await WordProgress.create({userId:ownerId,entryId:entry,topicId:topic,stage:'REMEMBERED'});
  await request(app).get(manage).expect(401);
  await request(app).get(manage).set(headers(owner)).expect(403);
  for(const actor of [staff,admin,reader]){
    const list=(await request(app).get(manage).set(headers(actor)).expect(200)).body;
    const detail=(await request(app).get(manage+'/'+id).set(headers(actor)).expect(200)).body;
    for(const value of ['PRIVATE_COLLECTION_NAME','OWNER_PRIVATE_IDENTITY',String(ownerId),'PRIVATE_CUSTOM_WORD','PRIVATE_DEFINITION','PRIVATE_PERSONAL_NOTE','private.jpg','personalNote','progress','shareCode','shareToken']){
      expect(JSON.stringify(list)).not.toContain(value);expect(JSON.stringify(detail)).not.toContain(value);
    }
    expect(detail.data.collection.avatarImage).toBe(photo);expect(detail.data.items).toHaveLength(1);
    await request(app).get(manage+'/'+privateSet.id).set(headers(actor)).expect(404);
  }
  const row=await metadata(id,reader);
  await request(app).post(manage+'/'+id+'/moderation').set(headers(reader)).send({state:'HIDDEN',reason:'Tôi không có quyền',version:row.moderationVersion}).expect(403);
  for(const resource of ['users','roles','sessions'])await request(app).get('/api/v1/admin/'+resource).set(headers(staff)).expect(403);
  await request(app).post(manage+'/'+id+'/moderation').set(headers(staff)).send({state:'HIDDEN',reason:'x',version:row.moderationVersion}).expect(400);
});
it('hides discovery independently, blocks links/imports, prevents owner bypass and restores without deleting original data',async()=>{
  const {id,code}=await make('Bộ vòng đời kiểm duyệt');
  const imported=(await request(app).post(base+'/import').set(headers(reporter)).send({code}).expect(200)).body.data._id;
  const version=(await metadata(id)).moderationVersion;
  await moderate(id,'HIDDEN');
  const discovered=(await request(app).get('/api/v1/shared-collections').expect(200)).body.data.items;
  expect(discovered.some((row:any)=>row._id===id)).toBe(false);
  await request(app).get('/api/v1/shared-collections/'+code).expect(200);
  await request(app).post(base+'/'+id+'/discovery').set(headers(owner)).send({enabled:true}).expect(409);
  await request(app).post(manage+'/'+id+'/moderation').set(headers(admin)).send({state:'BLOCKED',reason:'Thao tác với phiên bản cũ',version}).expect(409);
  await moderate(id,'BLOCKED',admin);
  await request(app).get('/api/v1/shared-collections/'+code).expect(404);
  await request(app).post(base+'/import').set(headers(reporter)).send({code}).expect(404);
  await request(app).post(base+'/'+id+'/share').set(headers(owner)).send({enabled:true}).expect(409);
  await request(app).patch(base+'/'+id).set(headers(owner)).send({name:'Chỉnh sửa nội dung',moderationState:'CLEAR'}).expect(400);
  expect(await SignCollection.findById(id)).not.toBeNull();expect(await SignCollection.findById(imported)).not.toBeNull();
  await request(app).get(base+'/'+id).set(headers(owner)).expect(200).then(result=>expect(result.body.data.collection.moderationState).toBe('BLOCKED'));
  await moderate(id,'CLEAR');
  await request(app).get('/api/v1/shared-collections/'+code).expect(200);
  const history=(await request(app).get(manage+'/'+id+'/history').set(headers(staff)).expect(200)).body.data.items;
  expect(history).toHaveLength(3);expect(history.some((row:any)=>row.actorName==='Nhân viên kiểm duyệt')).toBe(true);
  expect(history.every((row:any)=>row.reason.length>=5)).toBe(true);
});
it('uses public snapshots after withdrawal and requires an explicit updated submission before restoring changed shared content',async()=>{
  const {id,code}=await make('Bản công khai trước đây');
  await request(app).post(base+'/'+id+'/discovery').set(headers(owner)).send({enabled:false}).expect(200);
  await request(app).patch(base+'/'+id).set(headers(owner)).send({name:'NEW_PRIVATE_NAME',description:'NEW_PRIVATE_DESCRIPTION',avatarImage:''}).expect(200);
  const row=await metadata(id);
  expect(row.name).toBe('Bản công khai trước đây');expect(JSON.stringify(row)).not.toContain('NEW_PRIVATE');
  await moderate(id,'BLOCKED');
  const blocked=await metadata(id);
  await request(app).post(manage+'/'+id+'/moderation').set(headers(staff)).send({state:'CLEAR',reason:'Cần kiểm tra bản mới',version:blocked.moderationVersion}).expect(409);
  await request(app).post(manage+'/'+id+'/moderation').set(headers(staff)).send({state:'HIDDEN',reason:'Không được mở lại link cũ',version:blocked.moderationVersion}).expect(409);
  await request(app).post(base+'/'+id+'/moderation-review').set(headers(reporter)).send({}).expect(404);
  await request(app).post(base+'/'+id+'/moderation-review').set(headers(owner)).send({}).expect(200);
  await request(app).post(base+'/'+id+'/moderation-review').set(headers(owner)).send({}).expect(409);
  expect((await metadata(id)).name).toBe('NEW_PRIVATE_NAME');
  const pending=(await request(app).get(manage).query({status:'REVIEW_REQUESTED'}).set(headers(staff)).expect(200)).body.data.items;
  expect(pending.some((row:any)=>row._id===id)).toBe(true);
  const history=(await request(app).get(manage+'/'+id+'/history').set(headers(staff))).body.data;
  expect(JSON.stringify(history)).not.toContain('OWNER_PRIVATE_IDENTITY');
  await moderate(id,'CLEAR');
  await request(app).get('/api/v1/shared-collections/'+code).expect(200);
  const listing=(await request(app).get('/api/v1/shared-collections').expect(200)).body.data.items;
  expect(listing.some((item:any)=>item._id===id)).toBe(false);
});
it('accepts one open report per account, hides reporter identity and audits resolution separately from collection state',async()=>{
  const {id,code}=await make('Bộ được báo cáo');
  await request(app).post('/api/v1/shared-collections/'+code+'/reports').send({category:'SPAM'}).expect(401);
  await request(app).post('/api/v1/shared-collections/'+code+'/reports').set(headers(guest)).send({category:'SPAM'}).expect(403);
  await request(app).post('/api/v1/shared-collections/'+code+'/reports').set(headers(owner)).send({category:'SPAM'}).expect(400);
  for(let i=0;i<2;i++){
    const result=(await request(app).post('/api/v1/shared-collections/'+code+'/reports').set(headers(reporter)).send({category:'SPAM',details:'Mô tả báo cáo công khai'}).expect(200)).body.data;
    expect(result.alreadyReported).toBe(i===1);
  }
  expect(await CollectionReport.countDocuments({collectionId:id,status:'OPEN'})).toBe(1);
  const list=(await request(app).get(manage).query({status:'REPORTED'}).set(headers(staff)).expect(200)).body.data.items;
  expect(list.find((row:any)=>row._id===id).openReports).toBe(1);
  const reports=(await request(app).get(manage+'/'+id+'/reports').set(headers(staff)).expect(200)).body.data;
  expect(JSON.stringify(reports)).not.toContain(String(reporterId));expect(reports.items[0]).not.toHaveProperty('userId');
  const reportId=reports.items[0]._id;
  await request(app).post(manage+'/'+id+'/reports/'+reportId+'/resolve').set(headers(reader)).send({status:'RESOLVED',reason:'Không có quyền xử lý'}).expect(403);
  await request(app).post(manage+'/'+id+'/reports/'+reportId+'/resolve').set(headers(staff)).send({status:'RESOLVED',reason:'Đã xem nội dung và xử lý'}).expect(200);
  await request(app).post(manage+'/'+id+'/reports/'+reportId+'/resolve').set(headers(admin)).send({status:'DISMISSED',reason:'Đã được xử lý trước đó'}).expect(409);
  expect((await metadata(id)).moderationState).toBe('CLEAR');
  expect(await AuditLog.countDocuments({resourceId:id,action:AuditAction.COLLECTION_REPORT_RESOLVE})).toBe(1);
  await request(app).get(manage+'/'+id+'/reports').set(headers(staff)).expect(200).then(result=>expect(result.body.data.items).toEqual([]));
});
it('only makes an unlisted shared snapshot available to management after an explicit report',async()=>{
  const {id,code}=await make('Bộ gửi bằng liên kết',false);
  await request(app).get(manage+'/'+id).set(headers(staff)).expect(404);
  await request(app).post('/api/v1/shared-collections/'+code+'/reports').set(headers(reporter)).send({category:'MISLEADING',details:'Cần đối chiếu nội dung'}).expect(200);
  expect((await metadata(id)).name).toBe('Bộ gửi bằng liên kết');
});
it('rolls back a moderation change if its audit write fails and paginates server-side',async()=>{
  const {id}=await make('Bộ kiểm tra transaction');
  const version=(await metadata(id)).moderationVersion;
  const audit=vi.spyOn(AuditLog,'create').mockRejectedValueOnce(new Error('Audit unavailable'));
  await request(app).post(manage+'/'+id+'/moderation').set(headers(staff)).send({state:'BLOCKED',reason:'Kiểm tra tính nguyên tử',version}).expect(500);
  audit.mockRestore();expect((await metadata(id)).moderationState).toBe('CLEAR');
  await SignCollection.insertMany(Array.from({length:12},(_,i)=>({userId:ownerId,name:'Phân trang '+i,discoverable:true,entryIds:[entry]})));
  const collectionSpy=vi.spyOn(SignCollection,'aggregate'),reportSpy=vi.spyOn(CollectionReport,'aggregate');
  const result=(await request(app).get(manage).query({page:2,search:'Phân trang'}).set(headers(staff)).expect(200)).body.data;
  expect(result.items).toHaveLength(2);expect(result.pagination).toMatchObject({page:2,total:12,pages:2});
  expect(collectionSpy).toHaveBeenCalledOnce();expect(reportSpy).toHaveBeenCalledOnce();collectionSpy.mockRestore();reportSpy.mockRestore();
  await request(app).get(manage).query({search:'[not-a-regex]'}).set(headers(staff)).expect(200).then(response=>expect(response.body.data.pagination.total).toBe(0));
  const explain=await CollectionReport.find({collectionId:new Types.ObjectId(id),status:'OPEN'}).sort({createdAt:-1,_id:1}).explain('executionStats');
  expect(JSON.stringify(explain)).toContain('IXSCAN');
  const indexes=await SignCollection.collection.indexes();
  expect(indexes.find(index=>index.name==='moderation_submitted_time')?.partialFilterExpression).toEqual({'moderationSnapshot.capturedAt':{$exists:true}});
});
