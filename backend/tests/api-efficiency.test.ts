import {beforeAll,afterAll,it,expect,vi} from 'vitest';
import request from 'supertest';
import {randomUUID} from 'node:crypto';
import {createApp} from '../src/app';
import {connectDatabase,disconnectDatabase} from '../src/config/database';
import {User,UserRole} from '../src/models/User.model';
import {UserSettings} from '../src/models/UserSettings.model';
import {AuthSession} from '../src/models/AuthSession.model';
import {AuditLog} from '../src/models/AuditLog.model';
import {Category} from '../src/models/Category.model';
import {DictionaryEntry} from '../src/models/DictionaryEntry.model';
import {accountStats,contentStats} from '../src/services/dashboard-stats.service';

const ids:string[]=[],categories:string[]=[],entries:string[]=[];
const prefix=randomUUID();
beforeAll(connectDatabase);
afterAll(async()=>{vi.restoreAllMocks();await Promise.all([
  User.deleteMany({_id:{$in:ids}}),UserSettings.deleteMany({userId:{$in:ids}}),
  AuthSession.deleteMany({userId:{$in:ids}}),AuditLog.deleteMany({userId:{$in:ids}}),
  DictionaryEntry.deleteMany({_id:{$in:entries}}),Category.deleteMany({_id:{$in:categories}}),
]);await disconnectDatabase();});

it('combined dashboard queries preserve original counters including guest and date boundaries',async()=>{
  const now=new Date();
  for(const [index,role] of [UserRole.USER,UserRole.STAFF,UserRole.ADMIN].entries()){
    const user=await User.create({email:`efficiency-${index}-${prefix}@example.com`,displayName:'Efficiency fixture',
      passwordHash:'isolated-test-hash',role,isGuest:index===0,status:index===2?'SUSPENDED':'ACTIVE',
      createdAt:new Date(now.getTime()-index*20*86400000)});
    ids.push(user.id);
  }
  const category=await Category.create({name:'Efficiency topic',slug:`efficiency-${prefix}`});categories.push(category.id);
  for(const status of ['DRAFT','PUBLISHED','ARCHIVED']){
    const entry=await DictionaryEntry.create({word:`efficiency-${status}`,definition:'Isolated test content',
      categoryId:category._id,createdBy:ids[0],videoUrl:'https://example.com/test.mp4',status});entries.push(entry.id);
  }
  const [users,content]=await Promise.all([accountStats(now),contentStats()]);
  const old=await Promise.all([
    User.countDocuments({isGuest:false}),User.countDocuments({isGuest:false,status:'ACTIVE'}),
    User.countDocuments({isGuest:true}),User.countDocuments({role:'STAFF'}),User.countDocuments({role:'ADMIN'}),
    User.countDocuments({isGuest:false,createdAt:{$gte:new Date(now.getTime()-30*86400000)}}),
    User.countDocuments({isGuest:false,createdAt:{$gte:new Date(now.getTime()-7*86400000)}}),
    DictionaryEntry.countDocuments(),DictionaryEntry.countDocuments({status:'PUBLISHED'}),DictionaryEntry.countDocuments({status:'DRAFT'}),
  ]);
  expect(users).toEqual({total:old[0],active:old[1],guest:old[2],staff:old[3],admin:old[4],newThisMonth:old[5],newThisWeek:old[6]});
  expect(content).toEqual({total:old[7],published:old[8],pending:old[9]});
});

it('auth/me reuses the request authentication snapshot and stays non-cacheable',async()=>{
  const app=await createApp();
  const created=await request(app).post('/api/v1/auth/register').send({email:`auth-efficiency-${prefix}@example.com`,password:'EfficiencyTest123!',displayName:'Auth efficiency'}).expect(201);
  ids.push(created.body.data.user.id);
  const read=vi.spyOn(User,'findById');
  try{
    const me=await request(app).get('/api/v1/auth/me').set('Authorization',`Bearer ${created.body.data.tokens.accessToken}`).expect(200);
    expect(read).toHaveBeenCalledTimes(1);
    expect(me.body.data.role).toBe('USER');expect(me.body.data.permissions).toEqual([]);
    expect(me.body.data.passwordHash).toBeUndefined();expect(me.headers['cache-control']).toBe('no-store');
  }finally{read.mockRestore();}
});
