import {Schema,model} from 'mongoose';

const publicSnapshot=new Schema({
  name:{type:String,required:true,maxlength:80},description:{type:String,default:'',maxlength:500},
  avatarImage:{type:String,default:'',maxlength:100000},entryIds:{type:[Schema.Types.ObjectId],default:[]},
  capturedAt:{type:Date,required:true},
},{_id:false});

export const SignCollection=model('SignCollection',new Schema({
  userId:{type:Schema.Types.ObjectId,required:true},
  name:{type:String,required:true,trim:true,maxlength:80},
  description:{type:String,default:'',trim:true,maxlength:500},
  avatarImage:{type:String,default:'',maxlength:100000},
  entryIds:{type:[Schema.Types.ObjectId],default:[],validate:{validator:(ids:unknown[])=>ids.length<=200,message:'Tối đa 200 từ trong một bộ.'}},
  shareToken:{type:String,select:false},
  discoverable:{type:Boolean,default:false},
  publishedAt:{type:Date,default:null},
  importedFrom:{type:Schema.Types.ObjectId},
  moderationState:{type:String,enum:['CLEAR','HIDDEN','BLOCKED'],default:'CLEAR'},
  moderationVersion:{type:Number,default:0},
  moderationReason:{type:String,default:'',maxlength:1000},
  moderatedAt:{type:Date},
  moderationSnapshot:{type:publicSnapshot},
  reviewRequestedAt:{type:Date},
},{timestamps:true,collection:'learning_sign_collections'})
  .index({userId:1,updatedAt:-1,_id:1})
  .index({shareToken:1},{unique:true,sparse:true})
  .index({discoverable:1,publishedAt:-1,_id:1})
  .index({moderationState:1,updatedAt:-1,_id:1})
  .index({updatedAt:-1,_id:1},{name:'moderation_submitted_time',partialFilterExpression:{'moderationSnapshot.capturedAt':{$exists:true}}})
  .index({reviewRequestedAt:1,updatedAt:-1,_id:1})
  .index({userId:1,importedFrom:1},{unique:true,partialFilterExpression:{importedFrom:{$exists:true}}}));

export const SignNote=model('SignNote',new Schema({
  userId:{type:Schema.Types.ObjectId,required:true},
  entryId:{type:Schema.Types.ObjectId,required:true},
  text:{type:String,default:'',trim:true,maxlength:2000},
},{timestamps:true,collection:'learning_sign_notes'}).index({userId:1,entryId:1},{unique:true}));

export const CollectionReport=model('CollectionReport',new Schema({
  collectionId:{type:Schema.Types.ObjectId,required:true},
  userId:{type:Schema.Types.ObjectId,required:true},
  category:{type:String,enum:['INAPPROPRIATE','MISLEADING','SPAM','COPYRIGHT','OTHER'],required:true},
  details:{type:String,default:'',maxlength:1000},
  status:{type:String,enum:['OPEN','RESOLVED','DISMISSED'],default:'OPEN'},
  resolution:{type:String,default:'',maxlength:1000},
  resolvedAt:{type:Date},
},{timestamps:true,collection:'collection_reports'})
  .index({collectionId:1,status:1,createdAt:-1,_id:1})
  .index({collectionId:1,userId:1},{unique:true,partialFilterExpression:{status:'OPEN'}}));
