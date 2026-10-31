import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {Types} from 'mongoose';
import * as authentication from '../src/common/middlewares/auth.middleware';
import * as trials from '../src/services/guest-trial.service';
import {UserRole} from '../src/models/User.model';
import {AppError} from '../src/common/errors/AppError';
import express from 'express';
import { createServer, Server } from 'node:http';
import { AddressInfo } from 'node:net';
import { once } from 'node:events';
import WebSocket, { WebSocketServer } from 'ws';
import { attachAiPublicProxy } from '../src/ai-public-proxy';

const servers: Server[] = [];
const sockets: WebSocket[] = [];
beforeEach(() => {
  vi.spyOn(authentication, 'requireAuth').mockImplementation(async (req, _res, next) => {
    req.user = {id: new Types.ObjectId(), isGuest: false, role: UserRole.USER, permissions: []}; next();
  });
  vi.spyOn(trials, 'assertTrialActive').mockResolvedValue(undefined);
  vi.spyOn(trials, 'authorizeAiTicket').mockResolvedValue({expiresAt: undefined});
});
async function listen(server: Server): Promise<string> {
  servers.push(server); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}
afterEach(async () => {
  vi.restoreAllMocks();
  sockets.splice(0).forEach(s => s.terminate());
  await Promise.all(servers.splice(0).map(s => new Promise<void>(resolve => {
    s.closeAllConnections(); s.close(() => resolve());
  })));
});
async function stack() {
  const requests: { url: string; origin?: string; body: string }[] = [];
  const upstream = createServer((req, res) => {
    let body = ''; req.on('data', chunk => { body += chunk; });
    req.on('end', () => { requests.push({ url: req.url!, origin: req.headers.origin, body }); res.setHeader('content-type', 'application/json'); res.end(JSON.stringify({ ready: true })); });
  });
  const target = await listen(upstream);
  const ws = new WebSocketServer({ server: upstream, path: '/v1/stream' });
  ws.on('connection', (socket, req) => {
    sockets.push(socket);
    requests.push({ url: req.url!, origin: req.headers.origin, body: '' });
    socket.on('message', (data, binary) => socket.send(data, { binary }));
  });
  const app = express();
  const proxy = attachAiPublicProxy(app, { target, publicOrigin: 'https://phone.conveyor.cloud', port: 3001 });
  const server = createServer(app); proxy.attach(server);
  return { url: await listen(server), requests };
}
describe('Public AI transport proxy', () => {
  it('cuts off an already-open guest socket at its server deadline', async () => {
    vi.spyOn(trials, 'authorizeAiTicket').mockImplementation(async () => ({expiresAt: new Date(Date.now() + 1000)}));
    const {url} = await stack();
    const socket = new WebSocket(url.replace('http:', 'ws:') + '/sign-ai/v1/stream?ticket=test');
    sockets.push(socket); await once(socket, 'open');
    const upstream = sockets.find(item => item !== socket)!;
    await Promise.all([once(socket, 'close'), once(upstream, 'close')]);
    expect(socket.readyState).toBe(WebSocket.CLOSED);
  });
  it('rejects inference without an authenticated session or valid stream ticket', async () => {
    vi.spyOn(authentication, 'requireAuth').mockImplementation(async (_req, _res, next) => next(new AppError('Auth required', 401)));
    vi.spyOn(trials, 'authorizeAiTicket').mockRejectedValue(new Error('Bad ticket'));
    const {url} = await stack();
    expect((await fetch(url + '/sign-ai/v1/compose', {method: 'POST', body: '{}'})).status).toBe(401);
    const socket = new WebSocket(url.replace('http:', 'ws:') + '/sign-ai/v1/stream');
    socket.on('error', () => {}); sockets.push(socket);
    const [, response] = await once(socket, 'unexpected-response');
    expect(response.statusCode).toBe(403);
  });
  it('routes health and streams POST JSON without consuming its body', async () => {
    const { url, requests } = await stack();
    expect((await fetch(`${url}/sign-ai/health`)).status).toBe(200);
    const body = JSON.stringify({ words: ['xin chào', 'rau'] });
    const response = await fetch(`${url}/sign-ai/v1/compose`, { method: 'POST', body, headers: { 'content-type': 'application/json', origin: 'https://phone.conveyor.cloud' } });
    expect(response.status).toBe(200);
    expect(requests[1]).toEqual({ url: '/v1/compose', body, origin: undefined });
    expect((await fetch(`${url}/sign-ai/docs`)).status).toBe(404);
    expect((await fetch(`${url}/sign-ai/health`, { headers: { origin: 'https://other.example' } })).status).toBe(403);
  });
  it('upgrades WebSocket before HTTP use and preserves text and binary frames', async () => {
    const { url, requests } = await stack();
    const socket = new WebSocket(url.replace('http:', 'ws:') + '/sign-ai/v1/stream', { origin: 'https://phone.conveyor.cloud' });
    sockets.push(socket); await once(socket, 'open');
    let received = once(socket, 'message'); socket.send('{"mode":"words"}');
    expect((await received)[0].toString()).toBe('{"mode":"words"}');
    const bytes = Buffer.from([0, 255, 2, 128]);
    received = once(socket, 'message'); socket.send(bytes);
    const [data, binary] = await received;
    expect(binary).toBe(true); expect(data).toEqual(bytes);
    expect(requests[0].url).toBe('/v1/stream'); expect(requests[0].origin).toBeUndefined();
  });
  it('rejects an unexpected browser origin on the raw upgrade path', async () => {
    const { url } = await stack();
    const socket = new WebSocket(url.replace('http:', 'ws:') + '/sign-ai/v1/stream', { origin: 'https://other.example' });
    socket.on('error', () => { /* Expected when the rejected handshake is disposed. */ });
    sockets.push(socket);
    const response = once(socket, 'unexpected-response');
    const [, result] = await response;
    expect(result.statusCode).toBe(403);
  });
  it('does not accept a request-controlled or remote upstream target', () => {
    expect(() => attachAiPublicProxy(express(), { target: 'http://other.example', publicOrigin: '', port: 3001 })).toThrow('loopback');
  });
  it('accepts Conveyor absolute-form HTTP and WebSocket request paths', async () => {
    const { url } = await stack();
    const { request } = await import('node:http');
    const status = await new Promise<number>(resolve => {
      const req = request(url, { path: `${url}/sign-ai/health` }, res => { res.resume(); resolve(res.statusCode!); });
      req.end();
    });
    expect(status).toBe(200);
    const socket = new WebSocket(url.replace('http:', 'ws:') + '/sign-ai/v1/stream', {
      origin: 'https://phone.conveyor.cloud',
      finishRequest: req => { req.path = `${url}/sign-ai/v1/stream`; req.end(); },
    });
    sockets.push(socket); await once(socket, 'open');
    const received = once(socket, 'message'); socket.send('hello');
    expect((await received)[0].toString()).toBe('hello');
  });
});
