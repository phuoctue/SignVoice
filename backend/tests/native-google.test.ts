import {afterAll,afterEach,beforeAll,beforeEach,describe,expect,it,vi} from 'vitest';
import request from 'supertest';
import {randomUUID} from 'crypto';
import {createApp} from '../src/app';
import {connectDatabase,disconnectDatabase} from '../src/config/database';
import {env} from '../src/config/env';
import {User} from '../src/models/User.model';
import {UserSettings} from '../src/models/UserSettings.model';
import {AuthSession} from '../src/models/AuthSession.model';
import {AuditLog} from '../src/models/AuditLog.model';
import {NativeGoogleChallenge} from '../src/models/NativeGoogleChallenge.model';
import {googleVerifier} from '../src/services/oauth-provider.service';
import {digest} from '../src/services/oauth.service';

let app:Awaited<ReturnType<typeof createApp>>;
const original={...env},prefix=`native-${randomUUID()}`;
const ids:string[]=[],challenges:string[]=[];
beforeAll(async()=>{await connectDatabase(); await User.init(); await NativeGoogleChallenge.init(); app=await createApp();});
beforeEach(()=>{env.GOOGLE_CLIENT_ID='test-native.apps.googleusercontent.com';env.NODE_ENV='test';});
afterEach(()=>{vi.restoreAllMocks();Object.assign(env,original);});
afterAll(async()=>{
  const users=await User.find({$or:[{displayName:prefix},{_id:{$in:ids}}]});const userIds=users.map(u=>u._id);
  await Promise.all([User.deleteMany({_id:{$in:userIds}}),UserSettings.deleteMany({userId:{$in:userIds}}),
    AuthSession.deleteMany({userId:{$in:userIds}}),AuditLog.deleteMany({userId:{$in:userIds}}),
    NativeGoogleChallenge.deleteMany({challengeHash:{$in:challenges.map(digest)}})]);
  await disconnectDatabase();
});
async function proof(overrides:Record<string,unknown>={}) {
  const response=await request(app).post('/api/v1/auth/google/native/challenge').expect(200);
  expect(response.headers['cache-control']).toContain('no-store');
  expect(response.body.data.clientId).toBe(env.GOOGLE_CLIENT_ID);
  expect(response.body.data).not.toHaveProperty('clientSecret');
  const {challenge,nonce}=response.body.data;challenges.push(challenge);
  vi.spyOn(googleVerifier,'verifyIdToken').mockResolvedValue({getPayload:()=>({
    sub:`${prefix}-${randomUUID()}`,aud:env.GOOGLE_CLIENT_ID,iss:'https://accounts.google.com',
    exp:Math.floor(Date.now()/1000)+300,nonce,email:`${prefix}-${randomUUID()}@example.com`,
    email_verified:true,name:prefix,...overrides,
  })} as any);
  return {challenge,idToken:'signed-by-google-test-boundary'};
}
async function local() {
  const email=`${prefix}-${randomUUID()}@example.com`;
  const response=await request(app).post('/api/v1/auth/register').send({email,password:'NativeGoogle123',displayName:prefix}).expect(201);
  ids.push(response.body.data.user.id);
  return {email,id:response.body.data.user.id,authorization:`Bearer ${response.body.data.tokens.accessToken}`};
}
describe('Android Google authentication',()=>{
  it('creates persisted sessions and consumes proof once, including concurrent requests',async()=>{
    const body=await proof();
    const responses=await Promise.all([request(app).post('/api/v1/auth/google/native/login').send(body),
      request(app).post('/api/v1/auth/google/native/login').send(body)]);
    expect(responses.map(r=>r.status).sort()).toEqual([200,400]);
    const result=responses.find(r=>r.status===200)!.body.data;ids.push(result.user.id);
    expect(result.user.role).toBe('USER');expect(result.user.googleLinked).toBe(true);
    expect(await AuthSession.countDocuments({userId:result.user.id})).toBe(2);
    const me=await request(app).get('/api/v1/auth/me').set('Authorization',`Bearer ${result.tokens.accessToken}`).expect(200);
    expect(me.body.data.id).toBe(result.user.id);expect(me.body.data.googleLinked).toBe(true);
    expect(JSON.stringify(result)).not.toContain('providerId');
  });
  it.each([{nonce:'wrong'},{aud:'wrong'},{iss:'wrong'},{exp:1},{email_verified:false}])('rejects invalid claims %j',async claims=>{
    const body=await proof(claims);
    const result=await request(app).post('/api/v1/auth/google/native/login').send(body).expect(401);
    expect(result.body.error.code).toBe('OAUTH_IDENTITY_INVALID');
    expect(JSON.stringify(result.body)).not.toContain(body.idToken);
  });
  it('rejects expired challenges and does not trust signature failures',async()=>{
    let body=await proof();
    await NativeGoogleChallenge.updateOne({challengeHash:digest(body.challenge)},{$set:{expiresAt:new Date(0)}});
    await request(app).post('/api/v1/auth/google/native/login').send(body).expect(400);
    vi.restoreAllMocks();body=await proof();vi.mocked(googleVerifier.verifyIdToken).mockRejectedValue(new Error('bad signature'));
    await request(app).post('/api/v1/auth/google/native/login').send(body).expect(401);
  });
  it('never silently merges a matching email',async()=>{
    const account=await local(),body=await proof({email:account.email});
    const result=await request(app).post('/api/v1/auth/google/native/login').send(body).expect(409);
    expect(result.body.error.code).toBe('OAUTH_ACCOUNT_COLLISION');
    expect((await User.findById(account.id))!.googleProvider?.providerId).toBeUndefined();
  });
  it('links a verified same-email Google identity while preserving LOCAL identity, STAFF and password',async()=>{
    const account=await local(),subject=`${prefix}-linked`;
    await User.updateOne({_id:account.id},{$set:{role:'STAFF'}});
    const before=(await User.findById(account.id).select('+passwordHash'))!;
    let body=await proof({email:account.email,sub:subject});
    const linked=await request(app).post('/api/v1/auth/google/native/link').set('Authorization',account.authorization).send(body).expect(200);
    expect(linked.body.data.user).toMatchObject({id:account.id,role:'STAFF',accountType:'LOCAL',googleLinked:true});
    const after=(await User.findById(account.id).select('+passwordHash'))!;
    expect(after.passwordHash).toBe(before.passwordHash);expect(after.passwordVersion).toBe(before.passwordVersion);
    vi.restoreAllMocks();body=await proof({email:account.email,sub:subject});
    const login=await request(app).post('/api/v1/auth/google/native/login').send(body).expect(200);
    expect(login.body.data.user).toMatchObject({id:account.id,role:'STAFF',accountType:'LOCAL'});
    await User.updateOne({_id:account.id},{$set:{role:'USER'}});
    const me=await request(app).get('/api/v1/auth/me').set('Authorization',`Bearer ${login.body.data.tokens.accessToken}`).expect(200);
    expect(me.body.data.role).toBe('USER');
  });
  it('requires local authentication, same email and valid proof without expiring a valid session',async()=>{
    const account=await local();let body=await proof();
    await request(app).post('/api/v1/auth/google/native/link').send(body).expect(401);
    await request(app).post('/api/v1/auth/google/native/link').set('Authorization',account.authorization).send(body).expect(400);
    vi.restoreAllMocks();body=await proof({nonce:'wrong',email:account.email});
    await request(app).post('/api/v1/auth/google/native/link').set('Authorization',account.authorization).send(body).expect(400);
    await request(app).get('/api/v1/auth/me').set('Authorization',account.authorization).expect(200);
    expect((await User.findById(account.id))!.googleProvider?.providerId).toBeUndefined();
  });
});
