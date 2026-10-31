import {randomBytes} from 'node:crypto';
import {Types,PipelineStage} from 'mongoose';
import {SignCollection,SignNote,CollectionReport} from '../models/SignCollection.model';
import {DictionaryEntry} from '../models/DictionaryEntry.model';
import {Category} from '../models/Category.model';
import {User} from '../models/User.model';
import {WordProgress,PersonalWord} from '../models/Learning.model';
import {ReviewQuiz} from '../models/ReviewQuiz.model';
import {AppError} from '../common/errors/AppError';
import {userTransaction} from './user-data.service';
import {addInlineThumbnails} from './sign-media-preview.service';
import {pagination,regexLiteral,withAvailableMedia} from './learning.service';
import {avatarImage as validateImage} from './avatar-media.service';

export const COLLECTION_LIMIT=100, COLLECTION_WORD_LIMIT=200;
export type PublicCollectionSnapshot={name:string;description:string;avatarImage?:string;entryIds:Types.ObjectId[];capturedAt:Date};
export type CollectionRow={_id:Types.ObjectId;userId:Types.ObjectId;name:string;description:string;
  entryIds:Types.ObjectId[];avatarImage?:string;shareToken?:string;discoverable?:boolean;publishedAt?:Date|null;createdAt:Date;updatedAt:Date;
  moderationState?:string;moderationVersion?:number;moderationReason?:string;moderatedAt?:Date;moderationSnapshot?:PublicCollectionSnapshot;reviewRequestedAt?:Date};
export function snapshotOf(row:Pick<CollectionRow,'name'|'description'|'avatarImage'|'entryIds'>):PublicCollectionSnapshot {
  return {name:row.name,description:row.description,avatarImage:row.avatarImage || '',entryIds:row.entryIds,capturedAt:new Date()};
}
const notFound=()=>new AppError('Không tìm thấy bộ sưu tập của bạn.',404,'COLLECTION_NOT_FOUND');
export async function ownedCollection(userId:Types.ObjectId,id:Types.ObjectId,session?:import('mongoose').ClientSession) {
  const query=SignCollection.findOne({_id:id,userId}).select('+shareToken');
  if(session)query.session(session);
  const row=await query.lean() as unknown as CollectionRow|null;
  if(!row)throw notFound();return row;
}
export async function activeCategoryIds() {return (await Category.find({status:'ACTIVE'}).select('_id').lean()).map(row=>row._id);}
export function collectionDto(row:CollectionRow,owner=true) {
  return {_id:String(row._id),name:row.name,description:row.description,avatarImage:row.avatarImage || '',wordCount:row.entryIds.length,
    ...(owner?{shared:!!row.shareToken && row.moderationState!=='BLOCKED',shareCode:row.shareToken || '',discoverable:row.discoverable===true && (!row.moderationState || row.moderationState==='CLEAR'),discoveryRequested:row.discoverable===true,
      moderationState:row.moderationState || 'CLEAR',moderationVersion:row.moderationVersion || 0,moderationReason:row.moderationReason || '',reviewRequestedAt:row.reviewRequestedAt || null,updatedAt:row.updatedAt}: {})};
}
function due(progress:{stage?:string;nextReviewAt?:Date|null}|undefined) {
  return progress?.stage==='REVIEW' || progress?.stage==='REMEMBERED' && !!progress.nextReviewAt && progress.nextReviewAt<=new Date();
}

/** Bounded, batched reads: query count does not increase with the page's cards. */
export async function listCollections(userId:Types.ObjectId,page:number,search:string) {
  const [rows,active]=await Promise.all([
    SignCollection.aggregate< {items:CollectionRow[];count:{total:number}[]} >([
      {$match:{userId,...(search?{name:{$regex:regexLiteral(search),$options:'i'}}:{})}},
      {$sort:{updatedAt:-1,_id:1}},{$facet:{items:[{$skip:(page-1)*10},{$limit:10}],count:[{$count:'total'}]}},
    ]),activeCategoryIds(),
  ]);
  const collections=rows[0]?.items || [], ids=[...new Set(collections.flatMap(row=>row.entryIds.map(String)))].map(id=>new Types.ObjectId(id));
  const [entries,progress,privateCounts]=await Promise.all([
    DictionaryEntry.find({_id:{$in:ids},status:'PUBLISHED',categoryId:{$in:active}}).select('thumbnailUrl').lean(),
    WordProgress.find({userId,entryId:{$in:ids}}).select('entryId stage nextReviewAt').lean(),
    PersonalWord.aggregate< { _id:Types.ObjectId;count:number} >([{$match:{userId,collectionId:{$in:collections.map(row=>row._id)}}},{$group:{_id:'$collectionId',count:{$sum:1}}}]),
  ]);
  const published=new Map(entries.map(row=>[String(row._id),row]));
  const states=new Map(progress.map(row=>[String(row.entryId),row]));
  const counts=new Map(privateCounts.map(row=>[String(row._id),row.count]));
  const items=collections.map(row=>{
    const valid=row.entryIds.map(String).filter(id=>published.has(id));
    const reviewCount=valid.filter(id=>due(states.get(id))).length;
    const rememberedCount=valid.filter(id=>states.get(id)?.stage==='REMEMBERED' && !due(states.get(id))).length;
    const thumbnailUrl=String(published.get(valid[0])?.thumbnailUrl || '');
    const personalWordCount=counts.get(String(row._id)) || 0;
    return {...collectionDto(row),wordCount:valid.length+personalWordCount,libraryWordCount:valid.length,personalWordCount,unavailableCount:row.entryIds.length-valid.length,reviewCount,rememberedCount,thumbnailUrl};
  });
  return {items:await addInlineThumbnails(items),pagination:pagination(page,rows[0]?.count[0]?.total || 0)};
}

function validatedCollection(input:{name:string;description:string;avatarImage?:string}) {
  if(input.avatarImage) {
    const image=validateImage(input.avatarImage);
    if(image.bytes.length>72*1024)throw new AppError('Ảnh bộ sưu tập cần nhỏ hơn 72 KB.',400,'INVALID_COLLECTION_AVATAR');
  }
  return input;
}
export async function createCollection(userId:Types.ObjectId,input:{name:string;description:string;avatarImage?:string}) {
  validatedCollection(input);
  return userTransaction(userId,async session=>{
    if(await SignCollection.countDocuments({userId}).session(session)>=COLLECTION_LIMIT)throw new AppError('Bạn đã có 100 bộ. Hãy gộp hoặc xóa bớt bộ trước.',409,'COLLECTION_LIMIT');
    const [row]=await SignCollection.create([{userId,...input,entryIds:[]}],{session});
    return collectionDto(row.toObject() as unknown as CollectionRow);
  });
}
export async function updateCollection(userId:Types.ObjectId,id:Types.ObjectId,input:{name:string;description:string;avatarImage?:string}) {
  validatedCollection(input);
  return userTransaction(userId,async session=>{
    const current=await ownedCollection(userId,id,session);
    const snapshot=current.discoverable && (!current.moderationState || current.moderationState==='CLEAR')?{moderationSnapshot:snapshotOf({...current,...input})}:{};
    const row=await SignCollection.findOneAndUpdate({_id:id,userId},{$set:{...input,...snapshot},$unset:{reviewRequestedAt:1},$inc:{moderationVersion:1}},{new:true,runValidators:true,session}).select('+shareToken').lean();
    return collectionDto(row as unknown as CollectionRow);
  });
}
export async function deleteCollection(userId:Types.ObjectId,id:Types.ObjectId) {
  return userTransaction(userId,async session=>{
    await ownedCollection(userId,id,session);
    await ReviewQuiz.updateMany({userId,collectionId:id,status:'DRAFT'},{$set:{status:'ABANDONED'}},{session});
    await PersonalWord.updateMany({userId,collectionId:id},{$unset:{collectionId:1}},{session});
    await CollectionReport.deleteMany({collectionId:id},{session});
    await SignCollection.deleteOne({_id:id,userId},{session});
    return {deleted:true};
  });
}

export async function addCollectionEntries(userId:Types.ObjectId,id:Types.ObjectId,entryIds:Types.ObjectId[]) {
  return userTransaction(userId,async session=>{
    const row=await ownedCollection(userId,id,session);
    const active=(await Category.find({status:'ACTIVE'}).select('_id').session(session).lean()).map(item=>item._id);
    const allowed=await DictionaryEntry.find({_id:{$in:entryIds},status:'PUBLISHED',categoryId:{$in:active}}).select('_id').session(session).lean();
    if(allowed.length!==new Set(entryIds.map(String)).size)throw new AppError('Một số từ không còn công khai. Hãy tải lại danh sách.',409,'COLLECTION_ENTRY_UNAVAILABLE');
    const combined=[...new Set([...row.entryIds.map(String),...allowed.map(item=>String(item._id))])];
    const privateCount=await PersonalWord.countDocuments({userId,collectionId:id}).session(session);
    if(combined.length+privateCount>COLLECTION_WORD_LIMIT)throw new AppError('Mỗi bộ tối đa 200 từ. Hãy tạo thêm bộ khác.',409,'COLLECTION_WORD_LIMIT');
    const ids=combined.map(value=>new Types.ObjectId(value));
    await SignCollection.updateOne({_id:id,userId},{$set:{entryIds:ids,...(row.discoverable && (!row.moderationState || row.moderationState==='CLEAR')?{moderationSnapshot:snapshotOf({...row,entryIds:ids})}:{})},$unset:{reviewRequestedAt:1},$inc:{moderationVersion:1}},{session});
    return {...collectionDto({...row,entryIds:ids}),added:combined.length-row.entryIds.length};
  });
}
export async function removeCollectionEntry(userId:Types.ObjectId,id:Types.ObjectId,entryId:Types.ObjectId) {
  return userTransaction(userId,async session=>{
    const row=await ownedCollection(userId,id,session);
    const remaining=row.entryIds.filter(value=>!value.equals(entryId));
    await SignCollection.updateOne({_id:id,userId},{$pull:{entryIds:entryId},$set:{...(!remaining.length?{discoverable:false,publishedAt:null}:{}),...(row.discoverable && (!row.moderationState || row.moderationState==='CLEAR')?{moderationSnapshot:snapshotOf({...row,entryIds:remaining})}:{})},$unset:{reviewRequestedAt:1},$inc:{moderationVersion:1}},{session});
    return collectionDto({...row,entryIds:remaining,...(!remaining.length?{discoverable:false,publishedAt:null}:{})});
  });
}

const entryFields={word:1,aliases:1,definition:1,usageExample:1,categoryId:1,videoUrl:1,thumbnailUrl:1,imageUrls:1};
export async function collectionContents(row:CollectionRow,page:number,search:string,userId?:Types.ObjectId) {
  const active=await activeCategoryIds();
  const filter={_id:{$in:row.entryIds},status:'PUBLISHED',categoryId:{$in:active}};
  const searchFilter=search?{$or:[{word:{$regex:regexLiteral(search),$options:'i'}},{aliases:{$regex:regexLiteral(search),$options:'i'}}]}:{};
  const personal:PipelineStage[] = userId ? [
    {$lookup:{from:WordProgress.collection.name,let:{entry:'$_id'},pipeline:[{$match:{userId,$expr:{$eq:['$entryId','$$entry']}}},{$project:{stage:1,nextReviewAt:1}}],as:'progress'}},
    {$set:{progress:{$first:'$progress'}}},
    {$set:{stage:{$cond:[{$or:[{$eq:['$progress.stage','REVIEW']},{$and:[{$eq:['$progress.stage','REMEMBERED']},{$ne:[{$ifNull:['$progress.nextReviewAt',null]},null]},{$lte:['$progress.nextReviewAt',new Date()]}]}]},'REVIEW',{$ifNull:['$progress.stage','LEARNING']}]}}},
  ] : [];
  const notes:PipelineStage.FacetPipelineStage[] = userId ? [
    {$lookup:{from:SignNote.collection.name,let:{entry:'$_id'},pipeline:[{$match:{userId,$expr:{$eq:['$entryId','$$entry']}}},{$project:{_id:0,text:1}}],as:'note'}},
    {$set:{personalNote:{$ifNull:[{$first:'$note.text'},'']}}},{$unset:'note'},
  ] : [];
  const rows=await DictionaryEntry.aggregate([
    {$match:filter},{$project:entryFields},{$set:{isPersonal:false}},...personal,
    ...(userId?[{$unionWith:{coll:PersonalWord.collection.name,pipeline:[
      {$match:{userId,collectionId:row._id}},
      {$set:{imageDeferred:{$gt:[{$strLenBytes:{$ifNull:['$imageUrl','']}},100000]}}},
      {$project:{word:1,definition:1,usageExample:1,notes:1,videoUrl:1,imageDeferred:1,imageUrl:{$cond:['$imageDeferred','','$imageUrl']},thumbnailUrl:{$cond:['$imageDeferred','','$imageUrl']},imageUrls:{$cond:[{$or:['$imageDeferred',{$eq:['$imageUrl','']}]},[],['$imageUrl']]},isPersonal:{$literal:true},stage:{$literal:'PRIVATE'}}},
    ]}}]:[]),
    {$facet:{items:[{$match:searchFilter},{$sort:{word:1,_id:1}},{$skip:(page-1)*10},{$limit:10},...notes,{$unset:['progress','aliases']}],
      count:[{$match:searchFilter},{$count:'total'}],summary:userId?[{$group:{_id:'$stage',count:{$sum:1}}}]:[{$count:'total'}]}},
  ]);
  const summary={learning:0,remembered:0,review:0,personal:0,total:0};
  if(userId)for(const item of rows[0].summary || []) {summary.total+=item.count;if(item._id==='PRIVATE')summary.personal+=item.count;else if(item._id==='REMEMBERED')summary.remembered+=item.count;else if(item._id==='REVIEW')summary.review+=item.count;else summary.learning+=item.count;}
  return {collection:{...collectionDto(row,!!userId),wordCount:userId?summary.total:(rows[0].summary[0]?.total || 0),...(userId?{personalWordCount:summary.personal,libraryWordCount:summary.total-summary.personal}:{})},...(userId?{summary}:{}),
    items:await addInlineThumbnails(rows[0].items.map(withAvailableMedia)),pagination:pagination(page,rows[0].count[0]?.total || 0)};
}
export async function getCollection(userId:Types.ObjectId,id:Types.ObjectId,page:number,search:string) {
  return collectionContents(await ownedCollection(userId,id),page,search,userId);
}
export async function collectionCandidates(userId:Types.ObjectId,id:Types.ObjectId,page:number,search:string) {
  const [row,active]=await Promise.all([ownedCollection(userId,id),activeCategoryIds()]);
  const rows=await DictionaryEntry.aggregate([
    {$match:{status:'PUBLISHED',categoryId:{$in:active},...(search?{$or:[{word:{$regex:regexLiteral(search),$options:'i'}},{aliases:{$regex:regexLiteral(search),$options:'i'}}]}:{})}},
    {$sort:{word:1,_id:1}},{$facet:{items:[{$skip:(page-1)*10},{$limit:10},{$project:entryFields}],count:[{$count:'total'}]}},
  ]);
  const saved=new Set(row.entryIds.map(String));
  return {collection:collectionDto(row),items:await addInlineThumbnails(rows[0].items.map((entry:Record<string,unknown>)=>({...withAvailableMedia(entry),inCollection:saved.has(String(entry._id))}))),pagination:pagination(page,rows[0].count[0]?.total || 0)};
}

export async function availablePersonalWords(userId:Types.ObjectId,id:Types.ObjectId,page:number,search:string) {
  await ownedCollection(userId,id);
  const filter={userId,collectionId:{$exists:false},...(search?{word:{$regex:regexLiteral(search),$options:'i'}}:{})};
  const [items,total]=await Promise.all([
    PersonalWord.find(filter).select('word definition usageExample').sort({word:1,_id:1}).skip((page-1)*10).limit(10).lean(),
    PersonalWord.countDocuments(filter),
  ]);
  return {items,pagination:pagination(page,total)};
}
async function personalRoom(userId:Types.ObjectId,id:Types.ObjectId,entries:number,session:import('mongoose').ClientSession) {
  if(entries+await PersonalWord.countDocuments({userId,collectionId:id}).session(session)>=COLLECTION_WORD_LIMIT) {
    throw new AppError('Mỗi bộ tối đa 200 từ. Hãy tạo thêm bộ khác.',409,'COLLECTION_WORD_LIMIT');
  }
}
export async function savePersonalWord(userId:Types.ObjectId,id:Types.ObjectId,input:Record<string,unknown>,wordId?:Types.ObjectId) {
  return userTransaction(userId,async session=>{
    const collection=await ownedCollection(userId,id,session);
    if(wordId) {
      const updated=await PersonalWord.findOneAndUpdate({_id:wordId,userId,collectionId:id},{$set:input},{new:true,runValidators:true,session}).lean();
      if(!updated)throw new AppError('Không tìm thấy từ riêng trong bộ của bạn.',404,'PERSONAL_WORD_NOT_FOUND');
      await SignCollection.updateOne({_id:id,userId},{$set:{updatedAt:new Date()}},{session});
      return updated;
    }
    await personalRoom(userId,id,collection.entryIds.length,session);
    const [created]=await PersonalWord.create([{...input,userId,collectionId:id}],{session});
    await SignCollection.updateOne({_id:id,userId},{$set:{updatedAt:new Date()}},{session});
    return created.toObject();
  });
}
export async function attachPersonalWords(userId:Types.ObjectId,id:Types.ObjectId,wordIds:Types.ObjectId[]) {
  return userTransaction(userId,async session=>{
    const collection=await ownedCollection(userId,id,session);
    const words=await PersonalWord.find({_id:{$in:wordIds},userId}).select('collectionId').session(session).lean();
    if(words.length!==new Set(wordIds.map(String)).size || words.some(word=>word.collectionId && !word.collectionId.equals(id)))throw new AppError('Một số từ riêng không còn trong danh sách chưa xếp bộ.',404,'PERSONAL_WORD_NOT_FOUND');
    const additions=words.filter(word=>!word.collectionId).length;
    if(collection.entryIds.length+await PersonalWord.countDocuments({userId,collectionId:id}).session(session)+additions>COLLECTION_WORD_LIMIT)throw new AppError('Mỗi bộ tối đa 200 từ. Hãy tạo thêm bộ khác.',409,'COLLECTION_WORD_LIMIT');
    await PersonalWord.updateMany({_id:{$in:wordIds},userId},{$set:{collectionId:id}},{session});
    await SignCollection.updateOne({_id:id,userId},{$set:{updatedAt:new Date()}},{session});
    return {attached:true};
  });
}
export async function collectionPersonalWord(userId:Types.ObjectId,id:Types.ObjectId,wordId:Types.ObjectId) {
  await ownedCollection(userId,id);
  const word=await PersonalWord.findOne({_id:wordId,userId,collectionId:id}).select('-userId -__v').lean();
  if(!word)throw new AppError('Không tìm thấy từ riêng trong bộ của bạn.',404,'PERSONAL_WORD_NOT_FOUND');
  return word;
}
export async function deletePersonalWord(userId:Types.ObjectId,id:Types.ObjectId,wordId:Types.ObjectId) {
  return userTransaction(userId,async session=>{
    await ownedCollection(userId,id,session);
    const result=await PersonalWord.deleteOne({_id:wordId,userId,collectionId:id},{session});
    if(!result.deletedCount)throw new AppError('Không tìm thấy từ riêng trong bộ của bạn.',404,'PERSONAL_WORD_NOT_FOUND');
    await SignCollection.updateOne({_id:id,userId},{$set:{updatedAt:new Date()}},{session});
    return {deleted:true};
  });
}

export async function saveSignNote(userId:Types.ObjectId,entryId:Types.ObjectId,text:string) {
  return userTransaction(userId,async session=>{
    const entry=await DictionaryEntry.findOne({_id:entryId,status:'PUBLISHED'}).select('categoryId').session(session).lean();
    if(!entry || !await Category.exists({_id:entry.categoryId,status:'ACTIVE'}).session(session))throw new AppError('Từ không còn khả dụng.',404,'WORD_NOT_FOUND');
    if(text)await SignNote.updateOne({userId,entryId},{$set:{text}},{upsert:true,runValidators:true,session});
    else await SignNote.deleteOne({userId,entryId},{session});
    return {entryId:String(entryId),text};
  });
}
export async function getSignNote(userId:Types.ObjectId,entryId:Types.ObjectId) {
  const row=await SignNote.findOne({userId,entryId}).select('text').lean();
  return {entryId:String(entryId),text:row?.text || ''};
}

export async function shareCollection(userId:Types.ObjectId,id:Types.ObjectId,enabled:boolean) {
  return userTransaction(userId,async session=>{
    const row=await ownedCollection(userId,id,session);
    if(enabled && row.moderationState==='BLOCKED')throw new AppError('Bộ đang bị chặn chia sẻ. Hãy xem lý do và gửi lại để kiểm tra.',409,'COLLECTION_MODERATION_BLOCKED');
    const token=enabled?(row.shareToken || randomBytes(16).toString('hex')):undefined;
    const snapshot=row.discoverable && !row.moderationSnapshot?{moderationSnapshot:snapshotOf(row)}:{};
    await SignCollection.updateOne({_id:id,userId},token?{$set:{shareToken:token,...snapshot},$inc:{moderationVersion:1}}:{$unset:{shareToken:1},$set:{discoverable:false,publishedAt:null,...snapshot},$inc:{moderationVersion:1}},{session});
    return {shared:!!token,shareCode:token || '',discoverable:enabled && row.discoverable===true && (!row.moderationState || row.moderationState==='CLEAR'),discoveryRequested:enabled && row.discoverable===true};
  });
}
/** Listing is a separate, explicit opt-in. A private link never implies discovery. */
export async function publishCollection(userId:Types.ObjectId,id:Types.ObjectId,enabled:boolean) {
  return userTransaction(userId,async session=>{
    const row=await ownedCollection(userId,id,session);
    if(enabled && row.moderationState && row.moderationState!=='CLEAR')throw new AppError('Bộ đang được kiểm duyệt. Hãy chỉnh sửa và gửi lại để kiểm tra.',409,'COLLECTION_MODERATION_BLOCKED');
    if(enabled) {
      const active=(await Category.find({status:'ACTIVE'}).select('_id').session(session).lean()).map(item=>item._id);
      if(!await DictionaryEntry.exists({_id:{$in:row.entryIds},status:'PUBLISHED',categoryId:{$in:active}}).session(session)) {
        throw new AppError('Thêm ít nhất một ký hiệu công khai trước khi đăng bộ.',409,'COLLECTION_EMPTY');
      }
    }
    const token=enabled?(row.shareToken || randomBytes(16).toString('hex')):row.shareToken;
    const update={discoverable:enabled,publishedAt:enabled?(row.publishedAt || new Date()):null,...(token?{shareToken:token}:{}),...(enabled || row.discoverable && !row.moderationSnapshot?{moderationSnapshot:snapshotOf(row)}:{})};
    const saved=await SignCollection.findOneAndUpdate({_id:id,userId},{$set:update,$inc:{moderationVersion:1}},{new:true,session}).select('+shareToken').lean();
    return collectionDto(saved as unknown as CollectionRow);
  });
}

/** Page before loading media: at most ten collections, each bounded to 200 references. */
export async function discoverCollections(page:number,search:string) {
  const [rows,active]=await Promise.all([
    SignCollection.aggregate<{items:CollectionRow[];count:{total:number}[]}>([
      {$match:{discoverable:true,moderationState:{$nin:['HIDDEN','BLOCKED']},shareToken:{$type:'string'},'entryIds.0':{$exists:true},...(search?{name:{$regex:regexLiteral(search),$options:'i'}}:{})}},
      {$sort:{publishedAt:-1,_id:1}},
      {$lookup:{from:User.collection.name,localField:'userId',foreignField:'_id',pipeline:[{$match:{status:'ACTIVE',isGuest:false}},{$project:{_id:1}}],as:'author'}},
      {$match:{'author.0':{$exists:true}}},
      {$facet:{items:[{$skip:(page-1)*10},{$limit:10},{$unset:'author'}],count:[{$count:'total'}]}},
    ]),activeCategoryIds(),
  ]);
  const collections=rows[0]?.items || [],ids=[...new Set(collections.flatMap(row=>row.entryIds.map(String)))].map(id=>new Types.ObjectId(id));
  const entries=await DictionaryEntry.find({_id:{$in:ids},status:'PUBLISHED',categoryId:{$in:active}}).select('thumbnailUrl').lean();
  const published=new Map(entries.map(item=>[String(item._id),item]));
  const items=collections.map(row=>{
    const available=row.entryIds.map(String).filter(id=>published.has(id));
    return {...collectionDto(row,false),shareCode:row.shareToken,wordCount:available.length,
      thumbnailUrl:String(published.get(available[0])?.thumbnailUrl || '')};
  });
  return {items:await addInlineThumbnails(items),pagination:pagination(page,rows[0]?.count[0]?.total || 0)};
}
export async function sharedCollection(code:string) {
  const row=await SignCollection.findOne({shareToken:code,moderationState:{$ne:'BLOCKED'}}).lean() as unknown as CollectionRow|null;
  if(!row)throw new AppError('Mã chia sẻ không còn hiệu lực.',404,'COLLECTION_SHARE_NOT_FOUND');return row;
}
export async function importCollection(userId:Types.ObjectId,code:string) {
  return userTransaction(userId,async session=>{
    const source=await SignCollection.findOne({shareToken:code,moderationState:{$ne:'BLOCKED'}}).session(session).lean() as unknown as CollectionRow|null;
    if(!source)throw new AppError('Mã chia sẻ không còn hiệu lực.',404,'COLLECTION_SHARE_NOT_FOUND');
    // Conflict with a concurrent moderation/delete so an import cannot commit using a newly blocked source.
    await SignCollection.updateOne({_id:source._id},{$inc:{__v:1}},{session,timestamps:false});
    if(source.userId.equals(userId))return {...collectionDto(source),alreadySaved:true};
    const existing=await SignCollection.findOne({userId,importedFrom:source._id}).session(session).lean() as unknown as CollectionRow|null;
    if(existing)return {...collectionDto(existing),alreadySaved:true};
    if(await SignCollection.countDocuments({userId}).session(session)>=COLLECTION_LIMIT)throw new AppError('Bạn đã có 100 bộ. Hãy xóa bớt trước khi lưu thêm.',409,'COLLECTION_LIMIT');
    const active=(await Category.find({status:'ACTIVE'}).select('_id').session(session).lean()).map(row=>row._id);
    const entries=await DictionaryEntry.find({_id:{$in:source.entryIds},status:'PUBLISHED',categoryId:{$in:active}}).select('_id').session(session).lean();
    if(!entries.length)throw new AppError('Bộ chưa có ký hiệu khả dụng để lưu. Hãy quay lại sau.',409,'COLLECTION_EMPTY');
    const [created]=await SignCollection.create([{userId,name:source.name,description:source.description,avatarImage:source.avatarImage || '',entryIds:entries.map(row=>row._id),importedFrom:source._id}],{session});
    return {...collectionDto(created.toObject() as unknown as CollectionRow),alreadySaved:false};
  });
}
