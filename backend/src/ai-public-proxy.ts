import { IncomingMessage, Server, ServerResponse } from 'node:http';
import { Socket } from 'node:net';
import { Application } from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';

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
    options.publicOrigin,
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
      proxyReqWs: (req) => req.removeHeader('origin'),
    },
  });
  // Register before JSON parsers: POST bodies must be streamed, not consumed.
  app.use('/sign-ai', (req, res, next) => {
    if (!originAllowed(req)) { res.status(403).json({ error: 'AI origin is not allowed' }); return; }
    // Conveyor may forward absolute-form request targets. Keep only their path;
    // the upstream host remains the fixed loopback target above.
    const url = new URL(req.url, 'http://localhost');
    req.url = url.pathname + url.search;
    if (!routeAllowed(req)) { res.status(404).json({ error: 'Unknown AI endpoint' }); return; }
    void proxy(req, res, next);
  });
  return {
    attach(server) {
      server.on('upgrade', (req, socket, head) => {
        const url = new URL(req.url || '/', 'http://localhost');
        req.url = url.pathname + url.search;
        if (req.method !== 'GET' || req.url !== '/sign-ai/v1/stream' || !originAllowed(req)) {
          socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
          return;
        }
        proxy.upgrade(req, socket as Socket, head);
      });
    },
  };
}
