import { IncomingMessage, Server, ServerResponse } from 'node:http';
import { Socket } from 'node:net';
import { Application } from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import {env} from './config/env';
import {requireAuth} from './common/middlewares/auth.middleware';
import {assertTrialActive, authorizeAiTicket} from './services/guest-trial.service';

/** Transport only: model inference remains in the separate loopback AI service. */
export function attachAiPublicProxy(
  app: Application,
  options: { target: string; publicOrigin: string; port: number },
): { attach: (server: Server) => void } {
  const target = new URL(options.target);
  if (target.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(target.hostname) ||
      target.pathname !== '/' || target.search || target.hash || target.username || target.password) {
    throw new Error('AI proxy target must be a fixed loopback HTTP service origin');
  }
  const allowed = new Set([
    options.publicOrigin, ...env.CORS_ALLOWED_ORIGINS,
    `http://localhost:${options.port}`, `http://127.0.0.1:${options.port}`,
  ].filter(Boolean));
  const originAllowed = (req: IncomingMessage): boolean =>
    !req.headers.origin || allowed.has(req.headers.origin);
  const routeAllowed = (req: IncomingMessage, prefix = ''): boolean => {
    const path = (req.url || '').split('?')[0];
    return (req.method === 'GET' && path === `${prefix}/health`) ||
      (req.method === 'POST' && path === `${prefix}/v1/compose`);
  };
  const proxy = createProxyMiddleware<IncomingMessage, ServerResponse>({
    target: target.origin,
    changeOrigin: true,
    // Upgrade is attached explicitly below, including before any HTTP request.
    ws: false,
    pathRewrite: { '^/sign-ai(?=/)': '' },
    proxyTimeout: 60000,
    on: {
      // The edge validates browser origins. The upstream is a server-to-server
      // loopback connection, so it does not need the public browser Origin.
      proxyReq: (req) => req.removeHeader('origin'),
      proxyReqWs: (outgoing, _incoming, socket) => {
        outgoing.removeHeader('origin');
        outgoing.once('upgrade', (_response, upstream) => {
          // Abrupt downstream expiry must also release the AI worker upstream.
          socket.once('close', () => upstream.destroy());
          if (socket.destroyed) upstream.destroy();
        });
      },
    },
  });
  // Register before JSON parsers: POST bodies must be streamed, not consumed.
  app.use('/sign-ai', async (req, res, next) => {
    try {
      if (!originAllowed(req)) { res.status(403).json({ error: 'AI origin is not allowed' }); return; }
      // Conveyor may forward absolute-form request targets. Keep only their path;
      // the upstream host remains the fixed loopback target above.
      const url = new URL(req.url, 'http://localhost');
      req.url = url.pathname + url.search;
      if (!routeAllowed(req)) { res.status(404).json({ error: 'Unknown AI endpoint' }); return; }
      if (req.method === 'POST') {
        await new Promise<void>((resolve, reject) => {
          void requireAuth(req, res, error => error ? reject(error) : resolve());
        });
        await assertTrialActive(req.user!.id);
      }
      void proxy(req, res, next);
    } catch (error) { next(error); }
  });
  return {
    attach(server) {
      server.on('upgrade', async (req, socket, head) => {
        try {
          const url = new URL(req.url || '/', 'http://localhost');
          req.url = url.pathname;
          if (req.method !== 'GET' || req.url !== '/sign-ai/v1/stream' || !originAllowed(req)) {
            socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
            return;
          }
          const lease = await authorizeAiTicket(url.searchParams.get('ticket') || '');
          if (lease.expiresAt) {
            const remaining = lease.expiresAt.getTime() - Date.now();
            if (remaining <= 0) throw new Error('Trial expired');
            const expiry = setTimeout(() => socket.destroy(), remaining);
            expiry.unref();
            socket.once('close', () => clearTimeout(expiry));
          }
          await proxy.upgrade(req, socket as Socket, head);
        } catch {
          socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
        }
      });
    },
  };
}
