import { Schema, model } from 'mongoose';

export const permissions = [
  'admin:access', 'staff:access', 'users:read', 'users:write',
  'roles:read', 'roles:write', 'dictionary:read', 'dictionary:write',
  'content:publish', 'categories:read', 'categories:write', 'sessions:read', 'sessions:write',
  'collections:read', 'collections:moderate',
] as const;
export type Permission = typeof permissions[number];

const RoleSchema = new Schema({
  name: {type:String,required:true,trim:true,maxlength:50},
  key: {type:String,required:true,unique:true,trim:true,uppercase:true,match:/^[A-Z][A-Z0-9_]{1,39}$/},
  description: {type:String,trim:true,maxlength:500,default:''},
  permissions: {type:[String],enum:permissions,default:[]},
}, {timestamps:true,collection:'roles'});
export const Role = model('Role',RoleSchema);
