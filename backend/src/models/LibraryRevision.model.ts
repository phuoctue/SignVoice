import {Schema,model} from 'mongoose';
export const LibraryRevision=model('LibraryRevision',new Schema({
  _id:{type:String,default:'dictionary'},revision:{type:String,required:true},
},{timestamps:true,collection:'dictionary_revision'}));
