import {beforeAll, afterAll, it, expect} from 'vitest';
import request from 'supertest';
import {randomUUID} from 'crypto';
import {Application} from 'express';
import {createApp} from '../src/app';
import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {AuthSession, SessionStatus} from '../src/models/AuthSession.model';

let app: Application;
beforeAll(async () => { await connectDatabase(); app = await createApp(); });
afterAll(disconnectDatabase);
const account = () => ({email:`register-${randomUUID()}@example.com`, password:'RegisterTest123', displayName:'New learner'});

it('registration creates no active session or refresh cookie, and login is required', async () => {
  const data = account();
  const agent = request.agent(app);
  const result = await agent.post('/api/v1/auth/register').send({...data,requireLogin:true}).expect(201);
  expect(result.body.data.loginRequired).toBe(true);
  expect(result.body.data.tokens).toBeUndefined();
  expect(await AuthSession.countDocuments({userId:result.body.data.user.id,status:SessionStatus.ACTIVE})).toBe(0);
  expect((result.headers['set-cookie'] as unknown as string[]).join(';')).toContain('Expires=Thu, 01 Jan 1970');
  await agent.get('/api/v1/auth/me').expect(401);
  await agent.post('/api/v1/auth/refresh').send({}).expect(400);
  const login = await agent.post('/api/v1/auth/login').send({email:data.email,password:data.password}).expect(200);
  await agent.get('/api/v1/auth/me').set('Authorization',`Bearer ${login.body.data.tokens.accessToken}`).expect(200);
});

it('guest conversion retains the account ID and revokes guest sessions until a new login', async () => {
  const guest = await request(app).post('/api/v1/auth/guest').send({}).expect(201);
  const data = account();
  const result = await request(app).post('/api/v1/auth/convert-guest')
    .set('Authorization',`Bearer ${guest.body.data.tokens.accessToken}`).send({...data,requireLogin:true}).expect(200);
  expect(result.body.data.user.id).toBe(guest.body.data.user.id);
  expect(result.body.data.tokens).toBeUndefined();
  expect(result.body.data.loginRequired).toBe(true);
  expect(await AuthSession.countDocuments({userId:result.body.data.user.id,status:SessionStatus.ACTIVE})).toBe(0);
  await request(app).get('/api/v1/auth/me').set('Authorization',`Bearer ${guest.body.data.tokens.accessToken}`).expect(401);
  const login = await request(app).post('/api/v1/auth/login').send({email:data.email,password:data.password}).expect(200);
  expect(login.body.data.user.id).toBe(guest.body.data.user.id);
});
