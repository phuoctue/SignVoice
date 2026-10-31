import { beforeAll, afterAll, describe, expect, it } from 'vitest';
import request from 'supertest';
import { Application } from 'express';
import { randomUUID } from 'crypto';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { User, UserRole } from '../src/models/User.model';
import { Role } from '../src/models/Role.model';
import { Category } from '../src/models/Category.model';
import { DictionaryEntry } from '../src/models/DictionaryEntry.model';
import { AuthSession } from '../src/models/AuthSession.model';
import { UserSettings } from '../src/models/UserSettings.model';
import { AuditLog } from '../src/models/AuditLog.model';

let app: Application;
const ids: string[] = [], roles: string[] = [], categories: string[] = [], entries: string[] = [];
const password='AdminTests123!';
let admin: string, reader: string, adminId: string, readerId: string, customId: string;
const prefix=randomUUID().replace(/-/g,'').slice(0,12);
const auth=(token=admin)=>({Authorization:`Bearer ${token}`});

beforeAll(async()=>{
  await connectDatabase(); app=await createApp();
  for(const isAdmin of [true,false]) {
    const email=`management-${prefix}-${isAdmin}@example.com`;
    const created=await request(app).post('/api/v1/auth/register').send({email,password,displayName:'Management Test'}).expect(201);
    const id=created.body.data.user.id; ids.push(id);
    if(isAdmin) {
      adminId=id; await User.findByIdAndUpdate(id,{role:UserRole.ADMIN});
      admin=(await request(app).post('/api/v1/auth/login').send({email,password}).expect(200)).body.data.tokens.accessToken;
    } else { readerId=id; reader=created.body.data.tokens.accessToken; }
  }
});
afterAll(async()=>{
  await Promise.all([
    User.deleteMany({_id:{$in:ids}}), UserSettings.deleteMany({userId:{$in:ids}}),
    AuthSession.deleteMany({userId:{$in:ids}}), AuditLog.deleteMany({userId:{$in:ids}}),
    Role.deleteMany({_id:{$in:roles}}), DictionaryEntry.deleteMany({_id:{$in:entries}}), Category.deleteMany({_id:{$in:categories}}),
  ]); await disconnectDatabase();
});

describe('Admin custom roles and resource management',()=>{
  it('blocks unauthenticated and regular users for every management module',async()=>{
    for(const module of ['users','roles','dictionary','categories','sessions']) {
      await request(app).get(`/api/v1/admin/${module}`).expect(401);
      await request(app).get(`/api/v1/admin/${module}`).set(auth(reader)).expect(403);
    }
  });
  it('creates a custom role and validates immutable built-in keys and permission names',async()=>{
    const created=await request(app).post('/api/v1/admin/roles').set(auth()).send({name:'Content reader',key:`READER_${prefix}`,permissions:['admin:access','dictionary:read']}).expect(201);
    customId=created.body.data._id; roles.push(customId);
    await request(app).post('/api/v1/admin/roles').set(auth()).send({name:'Invalid',key:'ADMIN',permissions:[]}).expect(400);
    await request(app).patch(`/api/v1/admin/roles/${customId}`).set(auth()).send({permissions:['anything:write']}).expect(400);
    const listed=await request(app).get('/api/v1/admin/roles').set(auth()).expect(200);
    expect(listed.body.data.some((r:any)=>r._id===customId && !r.system)).toBe(true);
    expect(listed.body.data.filter((r:any)=>r.system)).toHaveLength(3);
  });
  it('assigns a role dynamically without replacing existing tokens; denies unrelated modules',async()=>{
    await request(app).patch(`/api/v1/admin/users/${readerId}`).set(auth()).send({customRoleId:customId}).expect(200);
    const me=await request(app).get('/api/v1/auth/me').set(auth(reader)).expect(200);
    expect(me.body.data.customRoleId).toBe(customId);
    expect(me.body.data.permissions).toEqual(['admin:access','dictionary:read']);
    await request(app).get('/api/v1/admin/dictionary').set(auth(reader)).expect(200);
    for(const module of ['users','roles','categories','sessions']) await request(app).get(`/api/v1/admin/${module}`).set(auth(reader)).expect(403);
    await request(app).post('/api/v1/admin/dictionary').set(auth(reader)).send({}).expect(403);
    await request(app).delete(`/api/v1/admin/roles/${customId}`).set(auth()).expect(409);
  });
  it('changes role permissions immediately and prevents privilege escalation by custom writers',async()=>{
    await request(app).patch(`/api/v1/admin/roles/${customId}`).set(auth()).send({permissions:['admin:access','staff:access','dictionary:read','dictionary:write','roles:read','roles:write','users:read','users:write']}).expect(200);
    await request(app).get('/api/v1/admin/users').set(auth(reader)).expect(200);
    await request(app).patch(`/api/v1/admin/roles/${customId}`).set(auth(reader)).send({permissions:['admin:access','content:publish']}).expect(403);
    await request(app).patch(`/api/v1/admin/roles/${customId}`).set(auth(reader)).send({permissions:['dictionary:read']}).expect(400);
    await request(app).post('/api/v1/admin/users').set(auth(reader)).send({email:`escalate-${prefix}@example.com`,password,displayName:'Attempt',role:'ADMIN'}).expect(403);
    await request(app).patch(`/api/v1/admin/users/${adminId}`).set(auth(reader)).send({displayName:'Hijack'}).expect(403);
    const options=await request(app).get('/api/v1/admin/users/role-options').set(auth(reader)).expect(200);
    expect(options.body.data.some((r:any)=>r.key==='ADMIN')).toBe(false);
    await request(app).patch(`/api/v1/admin/users/${adminId}`).set(auth()).send({role:'USER'}).expect(400);
    await request(app).patch(`/api/v1/admin/users/${readerId}`).set(auth()).send({$set:{role:'ADMIN'}}).expect(400);
  });
  it('creates, updates, assigns roles and disables users',async()=>{
    const created=await request(app).post('/api/v1/admin/users').set(auth()).send({email:`created-${prefix}@example.com`,password,displayName:'New Account',customRoleId:customId}).expect(201);
    const id=created.body.data._id; ids.push(id);
    expect(created.body.data.passwordHash).toBeUndefined();
    await request(app).patch(`/api/v1/admin/users/${id}`).set(auth()).send({displayName:'Updated',role:'USER'}).expect(200);
    expect((await User.findById(id))!.customRoleId).toBeNull();
    await request(app).delete(`/api/v1/admin/users/${id}`).set(auth()).expect(200);
    expect((await User.findById(id))!.status).toBe('DELETED');
  });
  it('manages category and dictionary lifecycle, publishing permissions and public visibility',async()=>{
    const category=await request(app).post('/api/v1/admin/categories').set(auth()).send({name:'Test Topic',slug:`test-${prefix}`}).expect(201);
    const categoryId=category.body.data._id; categories.push(categoryId);
    await request(app).patch(`/api/v1/admin/categories/${categoryId}`).set(auth()).send({description:'Updated category'}).expect(200);
    const entry=await request(app).post('/api/v1/admin/dictionary').set(auth(reader)).send({word:`Word ${prefix}`,definition:'A test dictionary definition',videoUrl:'https://example.com/sign.mp4',categoryId}).expect(201);
    const id=entry.body.data._id; entries.push(id);
    await request(app).get(`/api/v1/dictionary/${id}`).expect(404);
    await request(app).patch(`/api/v1/admin/dictionary/${id}`).set(auth(reader)).send({status:'PUBLISHED'}).expect(403);
    // Legacy write routes must not bypass publishing permission.
    await request(app).patch(`/api/v1/dictionary/${id}`).set(auth(reader)).send({status:'PUBLISHED'}).expect(400);
    await request(app).patch(`/api/v1/admin/dictionary/${id}`).set(auth()).send({status:'PUBLISHED'}).expect(200);
    await request(app).get(`/api/v1/dictionary/${id}`).expect(200);
    expect((await Category.findById(categoryId))!.wordCount).toBe(1);
    await request(app).patch(`/api/v1/admin/dictionary/${id}`).set(auth(reader)).send({definition:'Forbidden public edit'}).expect(403);
    await request(app).delete(`/api/v1/admin/dictionary/${id}`).set(auth(reader)).expect(403);
    await request(app).get('/api/v1/staff/content').set(auth(reader)).expect(200);
    await request(app).get(`/api/v1/staff/content/${id}`).set(auth(reader)).expect(200);
    await request(app).post(`/api/v1/staff/content/${id}/approve`).set(auth(reader)).expect(403);
    await request(app).post(`/api/v1/staff/content/${id}/reject`).set(auth(reader)).send({reason:'Unauthorized rejection'}).expect(403);
    await request(app).patch(`/api/v1/staff/content/${id}`).set(auth(reader)).send({status:'DRAFT'}).expect(403);
    await request(app).post(`/api/v1/staff/content/${id}/reject`).set(auth()).send({reason:'Needs revision'}).expect(200);
    expect((await Category.findById(categoryId))!.wordCount).toBe(0);
    await request(app).post(`/api/v1/staff/content/${id}/approve`).set(auth()).expect(200);
    expect((await Category.findById(categoryId))!.wordCount).toBe(1);
    await request(app).delete(`/api/v1/admin/categories/${categoryId}`).set(auth()).expect(409);
    await request(app).patch(`/api/v1/admin/dictionary/${id}`).set(auth()).send({status:'ARCHIVED'}).expect(200);
    expect((await Category.findById(categoryId))!.wordCount).toBe(0);
    await request(app).get(`/api/v1/dictionary/${id}`).expect(404);
    await request(app).delete(`/api/v1/admin/dictionary/${id}`).set(auth()).expect(200);
    await request(app).delete(`/api/v1/admin/categories/${categoryId}`).set(auth()).expect(200);
  });
  it('removes custom roles after all users are reassigned, and rejects former access',async()=>{
    await request(app).patch(`/api/v1/admin/users/${readerId}`).set(auth()).send({role:'USER'}).expect(200);
    await request(app).delete(`/api/v1/admin/roles/${customId}`).set(auth()).expect(200);
    await request(app).get('/api/v1/admin/dictionary').set(auth(reader)).expect(403);
  });

  it('shares content administration with STAFF while protecting accounts, roles and sessions', async()=>{
    const email=`staff-dashboard-${prefix}@example.com`;
    const registered=await request(app).post('/api/v1/auth/register').send({email,password,displayName:'Staff editor'}).expect(201);
    const id=registered.body.data.user.id, token=registered.body.data.tokens.accessToken;
    ids.push(id);
    await request(app).patch(`/api/v1/admin/users/${id}`).set(auth()).send({role:'STAFF'}).expect(200);
    const me=await request(app).get('/api/v1/auth/me').set(auth(token)).expect(200);
    expect(me.body.data.role).toBe('STAFF');
    expect(me.body.data.permissions).toContain('content:publish');
    expect(me.body.data.permissions).not.toContain('admin:access');
    expect(me.body.data.permissions).not.toContain('users:read');
    const stats=await request(app).get('/api/v1/admin/stats').set(auth(token)).expect(200);
    expect(stats.body.data.content).toBeDefined();
    expect(stats.body.data.users).toBeUndefined();
    expect(stats.body.data.sessions).toBeUndefined();
    const legacyStats=await request(app).get('/api/v1/staff/stats').set(auth(token)).expect(200);
    expect(legacyStats.body.data.users).toBeUndefined();
    for(const resource of ['users','roles','sessions']) {
      await request(app).get(`/api/v1/admin/${resource}`).set(auth(token)).expect(403);
      await request(app).get(`/api/v1/admin/${resource}`).set(auth()).expect(200);
    }
    for(const path of ['/api/v1/staff/users',`/api/v1/staff/users/${adminId}`]) {
      await request(app).get(path).set(auth(token)).expect(403);
    }
    for(const path of ['/api/v1/admin/users','/api/v1/admin/roles',`/api/v1/admin/users/${adminId}/password`,`/api/v1/admin/users/${adminId}/suspend`]) {
      await request(app).post(path).set(auth(token)).send({}).expect(403);
    }
    await request(app).patch(`/api/v1/admin/users/${adminId}`).set(auth(token)).send({role:'USER'}).expect(403);
    const session=await AuthSession.findOne({userId:adminId});
    await request(app).delete(`/api/v1/admin/sessions/${session!._id}`).set(auth(token)).expect(403);

    const category=await request(app).post('/api/v1/admin/categories').set(auth(token)).send({name:'Staff topic',slug:`staff-${prefix}`}).expect(201);
    const categoryId=category.body.data._id; categories.push(categoryId);
    await request(app).patch(`/api/v1/admin/categories/${categoryId}`).set(auth(token)).send({description:'Edited by STAFF'}).expect(200);
    const body={word:`Staff word ${prefix}`,definition:'Staff managed content',videoUrl:'https://example.com/staff.mp4',categoryId};
    const created=await request(app).post('/api/v1/admin/dictionary').set(auth(token)).send({...body,status:'PUBLISHED'}).expect(201);
    const entryId=created.body.data._id; entries.push(entryId);
    const other=await request(app).post('/api/v1/admin/dictionary').set(auth()).send({...body,word:`Admin draft ${prefix}`}).expect(201);
    const otherId=other.body.data._id; entries.push(otherId);
    await request(app).patch(`/api/v1/admin/dictionary/${otherId}`).set(auth(token)).send({status:'PUBLISHED'}).expect(200);
    await request(app).get(`/api/v1/dictionary/${otherId}`).expect(200);
    await request(app).get('/api/v1/admin/content/pending').set(auth(token)).expect(200);
    await request(app).delete(`/api/v1/admin/dictionary/${entryId}`).set(auth(token)).expect(200);
    await request(app).delete(`/api/v1/admin/dictionary/${otherId}`).set(auth(token)).expect(200);
    await request(app).delete(`/api/v1/admin/categories/${categoryId}`).set(auth(token)).expect(200);
    await request(app).patch(`/api/v1/admin/users/${id}`).set(auth()).send({role:'USER'}).expect(200);
    await request(app).get('/api/v1/admin/dictionary').set(auth(token)).expect(403);
  });

  it('cannot use custom STAFF permission flags to bypass ADMIN-only modules', async()=>{
    const custom=await request(app).post('/api/v1/admin/roles').set(auth()).send({name:'Staff with extra flags',key:`STAFF_${prefix}`,permissions:['staff:access','users:read','users:write','roles:read','roles:write','sessions:read','sessions:write']}).expect(201);
    roles.push(custom.body.data._id);
    await request(app).patch(`/api/v1/admin/users/${readerId}`).set(auth()).send({customRoleId:custom.body.data._id}).expect(200);
    for(const path of ['/api/v1/admin/users','/api/v1/admin/roles','/api/v1/admin/sessions','/api/v1/staff/users']) {
      await request(app).get(path).set(auth(reader)).expect(403);
    }
    await request(app).post('/api/v1/admin/users').set(auth(reader)).send({}).expect(403);
    await request(app).post('/api/v1/admin/roles').set(auth(reader)).send({}).expect(403);
    const stats=await request(app).get('/api/v1/admin/stats').set(auth(reader)).expect(200);
    expect(stats.body.data.users).toBeUndefined();
    expect(stats.body.data.sessions).toBeUndefined();
    await request(app).patch(`/api/v1/admin/users/${readerId}`).set(auth()).send({role:'USER'}).expect(200);
  });
});
