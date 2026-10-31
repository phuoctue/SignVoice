import {Types} from 'mongoose';
import {SignCollection,CollectionReport} from '../models/SignCollection.model';
import {AuditLog,AuditAction} from '../models/AuditLog.model';
import {User} from '../models/User.model';
import {DictionaryEntry} from '../models/DictionaryEntry.model';
import {AppError} from '../common/errors/AppError';
import {pagination,regexLiteral} from './learning.service';
import {CollectionRow,collectionContents,snapshotOf,ownedCollection,activeCategoryIds} from './sign-collection.service';
import {userTransaction} from './user-data.service';

const missing=()=>new AppError('Không tìm thấy bản công khai của bộ.',404,'COLLECTION_PUBLIC_NOT_FOUND');
const scope={$or:[{discoverable:true},{'moderationSnapshot.capturedAt':{$exists:true}}]};
const stateOf=(row:CollectionRow)=>row.moderationState || 'CLEAR';
function snapshot(row:CollectionRow) {
  if(row.moderationSnapshot)return row.moderationSnapshot;
  if(row.discoverable)return snapshotOf(row);
  throw missing();
}
function dto(row:CollectionRow) {
  const publicCopy=snapshot(row);
  return {_id:String(row._id),name:publicCopy.name,description:publicCopy.description,avatarImage:publicCopy.avatarImage || '',
    wordCount:publicCopy.entryIds.length,capturedAt:publicCopy.capturedAt,moderationState:stateOf(row),moderationVersion:row.moderationVersion || 0,
    moderationReason:row.moderationReason || '',moderatedAt:row.moderatedAt,reviewRequestedAt:row.reviewRequestedAt,
    discoveryRequested:row.discoverable===true,sharingEnabled:!!row.shareToken};
}
export async function moderationList(page:number,search:string,status:string) {
  const filter={$and:[scope,...(search?[{$or:[{'moderationSnapshot.name':{$regex:regexLiteral(search),$options:'i'}},
    {moderationSnapshot:{$exists:false},discoverable:true,name:{$regex:regexLiteral(search),$options:'i'}}]}]:[]),
    ...(status==='CLEAR'?[{moderationState:{$nin:['HIDDEN','BLOCKED']}}]:['HIDDEN','BLOCKED'].includes(status)?[{moderationState:status}]:status==='REVIEW_REQUESTED'?[{reviewRequestedAt:{$ne:null}}]:[])]};
  const rows=await SignCollection.aggregate<{items:CollectionRow[];count:{total:number}[]}>([
    {$match:filter},
    ...(status==='REPORTED'?[
      {$lookup:{from:CollectionReport.collection.name,localField:'_id',foreignField:'collectionId',pipeline:[{$match:{status:'OPEN'}},{$limit:1},{$project:{_id:1}}],as:'openReport'}},
      {$match:{'openReport.0':{$exists:true}}},
    ]:[]),
    {$sort:{updatedAt:-1,_id:1}},
    {$facet:{items:[{$skip:(page-1)*10},{$limit:10},{$project:{name:1,description:1,avatarImage:1,entryIds:1,discoverable:1,shareToken:1,moderationSnapshot:1,moderationState:1,moderationVersion:1,moderationReason:1,moderatedAt:1,reviewRequestedAt:1}}],count:[{$count:'total'}]}},
  ]);
  const items=rows[0]?.items || [];
  const reports=await CollectionReport.aggregate<{_id:Types.ObjectId;count:number}>([
    {$match:{collectionId:{$in:items.map(row=>row._id)},status:'OPEN'}},{$group:{_id:'$collectionId',count:{$sum:1}}},
  ]);
  const counts=new Map(reports.map(row=>[String(row._id),row.count]));
  const active=await activeCategoryIds();
  const ids=[...new Set(items.flatMap(row=>snapshot(row).entryIds.map(String)))].map(id=>new Types.ObjectId(id));
  const available=await DictionaryEntry.find({_id:{$in:ids},status:'PUBLISHED',categoryId:{$in:active}}).select('_id').lean();
  const valid=new Set(available.map(row=>String(row._id)));
  return {items:items.map(row=>({...dto(row),wordCount:snapshot(row).entryIds.filter(id=>valid.has(String(id))).length,openReports:counts.get(String(row._id)) || 0})),pagination:pagination(page,rows[0]?.count[0]?.total || 0)};
}
async function moderationRow(id:Types.ObjectId) {
  const row=await SignCollection.findOne({_id:id,...scope}).select('+shareToken').lean() as unknown as CollectionRow|null;
  if(!row)throw missing();return row;
}
export async function moderationDetail(id:Types.ObjectId,page:number) {
  const row=await moderationRow(id),publicCopy=snapshot(row);
  const result=await collectionContents({...row,...publicCopy},page,'');
  return {...result,collection:{...dto(row),wordCount:result.collection.wordCount}};
}
export async function moderateCollection(actorId:Types.ObjectId,actorRole:string,id:Types.ObjectId,state:string,reason:string,version:number) {
  return userTransaction(actorId,async session=>{
    const row=await SignCollection.findOne({_id:id,...scope}).select('+shareToken').session(session).lean() as unknown as CollectionRow|null;
    if(!row)throw missing();
    if((row.moderationVersion || 0)!==version)throw new AppError('Bộ đã thay đổi. Hãy tải lại và kiểm tra trước khi xử lý.',409,'COLLECTION_MODERATION_CONFLICT');
    if(stateOf(row)===state)throw new AppError('Bộ đã ở trạng thái này. Hãy tải lại.',409,'COLLECTION_MODERATION_CONFLICT');
    if((state==='CLEAR' || stateOf(row)==='BLOCKED' && state==='HIDDEN') && (row.discoverable || row.shareToken)) {
      const publicCopy=snapshot(row);
      if(publicCopy.name!==row.name || publicCopy.description!==row.description || (publicCopy.avatarImage || '')!==(row.avatarImage || '') ||
        JSON.stringify(publicCopy.entryIds.map(String))!==JSON.stringify(row.entryIds.map(String))) {
        throw new AppError('Chủ bộ đã chỉnh sửa sau bản đang kiểm tra. Chủ bộ cần gửi lại trước khi khôi phục.',409,'COLLECTION_REVIEW_STALE');
      }
    }
    const actor=await User.findById(actorId).select('displayName').session(session).lean();
    const saved=await SignCollection.findOneAndUpdate({_id:id},{$set:{moderationState:state,moderationReason:reason,moderatedAt:new Date(),moderationSnapshot:snapshot(row)},$unset:{reviewRequestedAt:1},$inc:{moderationVersion:1}},{new:true,session}).select('+shareToken').lean();
    await AuditLog.create([{userId:actorId,actorRole,action:AuditAction.COLLECTION_MODERATION,resourceType:'SignCollection',resourceId:id,
      details:{actorName:actor?.displayName || 'Nhân viên',from:stateOf(row),to:state,reason},success:true}],{session});
    return dto(saved as unknown as CollectionRow);
  });
}
export async function reportCollection(userId:Types.ObjectId,code:string,category:string,details:string) {
  return userTransaction(userId,async session=>{
    const row=await SignCollection.findOne({shareToken:code,moderationState:{$ne:'BLOCKED'}}).session(session).lean() as unknown as CollectionRow|null;
    if(!row)throw missing();
    if(row.userId.equals(userId))throw new AppError('Bạn có thể chỉnh sửa hoặc ngừng chia sẻ bộ của mình.',400,'COLLECTION_REPORT_OWN');
    const existing=await CollectionReport.findOne({collectionId:row._id,userId,status:'OPEN'}).session(session).lean();
    if(existing)return {received:true,alreadyReported:true};
    await CollectionReport.create([{collectionId:row._id,userId,category,details}],{session});
    // The report grants access to this shared snapshot only, never to private owner fields.
    await SignCollection.updateOne({_id:row._id},{$set:{moderationSnapshot:snapshotOf(row)},$inc:{moderationVersion:1}},{session,timestamps:false});
    return {received:true,alreadyReported:false};
  });
}
export async function collectionReports(id:Types.ObjectId,page:number,status:string) {
  await moderationRow(id);
  const filter={collectionId:id,...(status==='ALL'?{}:{status})};
  const [items,total]=await Promise.all([
    CollectionReport.find(filter).select('_id category details status resolution resolvedAt createdAt').sort({createdAt:-1,_id:1}).skip((page-1)*10).limit(10).lean(),
    CollectionReport.countDocuments(filter),
  ]);
  return {items,pagination:pagination(page,total)};
}
export async function resolveCollectionReport(actorId:Types.ObjectId,actorRole:string,id:Types.ObjectId,reportId:Types.ObjectId,status:string,reason:string) {
  return userTransaction(actorId,async session=>{
    const row=await SignCollection.findOne({_id:id,...scope}).session(session).lean();
    if(!row)throw missing();
    const saved=await CollectionReport.findOneAndUpdate({_id:reportId,collectionId:id,status:'OPEN'},{$set:{status,resolution:reason,resolvedAt:new Date()}},{new:true,session}).lean();
    if(!saved)throw new AppError('Báo cáo đã được xử lý hoặc không còn khả dụng. Hãy tải lại.',409,'COLLECTION_REPORT_CONFLICT');
    await SignCollection.updateOne({_id:id},{$inc:{__v:1}},{session,timestamps:false});
    const actor=await User.findById(actorId).select('displayName').session(session).lean();
    await AuditLog.create([{userId:actorId,actorRole,action:AuditAction.COLLECTION_REPORT_RESOLVE,resourceType:'SignCollection',resourceId:id,
      details:{actorName:actor?.displayName || 'Nhân viên',reportId:String(reportId),to:status,reason},success:true}],{session});
    return {resolved:true};
  });
}
export async function collectionHistory(id:Types.ObjectId,page:number) {
  await moderationRow(id);
  const filter={resourceType:'SignCollection',resourceId:id,action:{$in:[AuditAction.COLLECTION_MODERATION,AuditAction.COLLECTION_REPORT_RESOLVE,AuditAction.COLLECTION_REVIEW_REQUEST]}};
  const [rows,total]=await Promise.all([
    AuditLog.find(filter).select('action actorRole details timestamp').sort({timestamp:-1,_id:1}).skip((page-1)*10).limit(10).lean(),AuditLog.countDocuments(filter),
  ]);
  return {items:rows.map(row=>({_id:String(row._id),action:row.action,actorName:row.details?.actorName || 'Tài khoản đã xóa',actorRole:row.actorRole,
    from:row.details?.from,to:row.details?.to,reason:row.details?.reason,createdAt:row.timestamp})),pagination:pagination(page,total)};
}
export async function requestCollectionReview(userId:Types.ObjectId,id:Types.ObjectId) {
  return userTransaction(userId,async session=>{
    const row=await ownedCollection(userId,id,session);
    if(stateOf(row)==='CLEAR')throw new AppError('Bộ hiện không cần gửi lại kiểm duyệt.',409,'COLLECTION_REVIEW_NOT_NEEDED');
    if(row.reviewRequestedAt)throw new AppError('Bộ đã được gửi kiểm tra. Hãy chờ phản hồi.',409,'COLLECTION_REVIEW_PENDING');
    const saved=await SignCollection.findByIdAndUpdate(id,{$set:{moderationSnapshot:snapshotOf(row),reviewRequestedAt:new Date()},$inc:{moderationVersion:1}},{new:true,session}).lean();
    await AuditLog.create([{userId,actorRole:'OWNER',action:AuditAction.COLLECTION_REVIEW_REQUEST,resourceType:'SignCollection',resourceId:id,
      details:{actorName:'Chủ bộ',reason:'Chủ bộ gửi lại nội dung để kiểm tra.'},success:true}],{session});
    return {requested:true,reviewRequestedAt:saved!.reviewRequestedAt};
  });
}
