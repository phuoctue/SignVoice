import type { Request, RequestHandler } from 'express';
import { ipKeyGenerator, rateLimit } from 'express-rate-limit';
import { env } from '../../config/env';
import { createHash } from 'node:crypto';

/**
 * Rate limits for public authentication endpoints (brute force / account abuse).
 *
 * Client IPs come from `req.ip`, which only honours X-Forwarded-For when
 * TRUST_PROXY is configured for the real proxy chain. Without it, spoofed
 * forwarded headers are ignored.
 */
const WINDOW_15_MIN = 15 * 60 * 1000;
const WINDOW_1_HOUR = 60 * 60 * 1000;

// Test suites register/login many accounts from one address; keep limits out of the
// way there unless a test explicitly opts in to enforcement.
const relaxForTests = env.isTest && process.env.AUTH_RATE_LIMIT_ENFORCE_IN_TEST !== 'true';
const limitFor = (production: number) => (relaxForTests ? 100_000 : production);

const tooManyRequests = {
  success: false,
  error: { code: 'TOO_MANY_REQUESTS', message: 'Bạn đã thử quá nhiều lần. Vui lòng thử lại sau.' },
};

const clientIp = (req: Request) => ipKeyGenerator(req.ip || req.socket.remoteAddress || 'unknown');

// A configured local tunnel must supply a real client IP. Do not silently count
// all public visitors against the same loopback budget if the edge omits XFF.
export const requireProxyClientIp: RequestHandler = (req, res, next) => {
  const ip = req.ip || '';
  if (env.isProduction && env.TRUST_PROXY !== false &&
      (ip === '::1' || /^(?:::ffff:)?127\./.test(ip))) {
    res.status(503).json({success: false, error: {
      code: 'PROXY_CLIENT_IP_UNAVAILABLE', message: 'Authentication temporarily unavailable',
    }});
    return;
  }
  next();
};

function createLimiter(
  windowMs: number,
  limit: number,
  keyGenerator: (req: Request) => string = clientIp,
  skipSuccessfulRequests = false,
) {
  return rateLimit({
    windowMs,
    limit: limitFor(limit),
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    keyGenerator,
    skipSuccessfulRequests,
    // Keep express-rate-limit's X-Forwarded-For validation on: it warns when a proxy
    // forwards client IPs but TRUST_PROXY is not configured.
    message: tooManyRequests,
  });
}

/**
 * Login: failed attempts per IP + email, so one shared NAT/proxy address does not
 * lock out every account and successful logins do not consume the budget.
 */
export const loginLimiter = createLimiter(WINDOW_15_MIN, 10, req => {
  const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
  return `${clientIp(req)}|${createHash('sha256').update(email).digest('hex')}`;
}, true);

/** Login: overall per-IP cap to slow credential stuffing across many emails. */
export const loginIpLimiter = createLimiter(WINDOW_15_MIN, 100);
export const registerLimiter = createLimiter(WINDOW_1_HOUR, 20);
export const guestLimiter = createLimiter(WINDOW_1_HOUR, 30);
export const refreshLimiter = createLimiter(WINDOW_15_MIN, 120);
