import {guestGrantBody} from './guest-fixture';
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app';
import { connectDatabase, disconnectDatabase } from '../src/config/database';
import { Application } from 'express';

let app: Application;

beforeAll(async () => {
  await connectDatabase();
  app = await createApp();
});

afterAll(async () => {
  await disconnectDatabase();
});

describe('Authentication', () => {
  const testUser = {
    email: `test${Date.now()}@example.com`,
    password: 'Test1234',
    displayName: 'Test User',
  };
  
  let accessToken: string;
  let refreshToken: string;
  
  describe('POST /api/v1/auth/register', () => {
    it('should register a new user', async () => {
      const response = await request(app)
        .post('/api/v1/auth/register')
        .send(testUser)
        .expect(201);
      
      expect(response.body.success).toBe(true);
      expect(response.body.data.user).toBeDefined();
      expect(response.body.data.user.email).toBe(testUser.email);
      expect(response.body.data.tokens).toBeDefined();
      
      accessToken = response.body.data.tokens.accessToken;
      refreshToken = response.body.data.tokens.refreshToken;
    });
    
    it('should reject duplicate email', async () => {
      await request(app)
        .post('/api/v1/auth/register')
        .send(testUser)
        .expect(409);
    });
    
    it('should reject weak password', async () => {
      await request(app)
        .post('/api/v1/auth/register')
        .send({
          email: 'weak@example.com',
          password: 'weak',
          displayName: 'Weak',
        })
        .expect(400);
    });
  });
  
  describe('POST /api/v1/auth/login', () => {
    it('should login with valid credentials', async () => {
      const response = await request(app)
        .post('/api/v1/auth/login')
        .send({
          email: testUser.email,
          password: testUser.password,
        })
        .expect(200);
      
      expect(response.body.success).toBe(true);
      expect(response.body.data.tokens).toBeDefined();
    });
    
    it('should reject invalid credentials', async () => {
      await request(app)
        .post('/api/v1/auth/login')
        .send({
          email: testUser.email,
          password: 'WrongPassword123',
        })
        .expect(401);
    });
  });
  
  describe('GET /api/v1/auth/me', () => {
    it('should get current user with valid token', async () => {
      const response = await request(app)
        .get('/api/v1/auth/me')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(200);
      
      expect(response.body.success).toBe(true);
      expect(response.body.data.email).toBe(testUser.email);
    });
    
    it('should reject without token', async () => {
      await request(app)
        .get('/api/v1/auth/me')
        .expect(401);
    });
  });
  
  describe('POST /api/v1/auth/refresh', () => {
    it('should refresh tokens', async () => {
      const response = await request(app)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken })
        .expect(200);
      
      expect(response.body.success).toBe(true);
      expect(response.body.data.accessToken).toBeDefined();
      expect(response.body.data.refreshToken).toBeDefined();
    });
  });
  
  describe('POST /api/v1/auth/guest', () => {
    it('should create guest account', async () => {
      const response = await request(app)
        .post('/api/v1/auth/guest').send(guestGrantBody())
        .expect(201);
      
      expect(response.body.success).toBe(true);
      expect(response.body.data.user.isGuest).toBe(true);
      expect(response.body.data.tokens).toBeDefined();
    });
  });
});
