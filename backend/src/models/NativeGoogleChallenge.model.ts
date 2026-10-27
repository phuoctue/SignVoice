import {Schema,model} from 'mongoose';
const schema=new Schema({
  challengeHash:{type:String,required:true,unique:true},
  nonce:{type:String,required:true},
  clientId:{type:String,required:true},
  expiresAt:{type:Date,required:true},
});
schema.index({expiresAt:1},{expireAfterSeconds:0});
export const NativeGoogleChallenge=model('NativeGoogleChallenge',schema);
