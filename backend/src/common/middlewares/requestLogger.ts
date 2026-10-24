import { Request, Response, NextFunction } from 'express';
import { env } from '../../config/env';

/**
 * Request logging middleware
 * Logs incoming requests and their responses
 */
export function requestLogger(req: Request, res: Response, next: NextFunction): void {
  const start = Date.now();

  // Generate request ID if not present
  if (!req.id) {
    req.id = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  // Log request
  if (env.LOG_LEVEL === 'debug') {
    console.log(`→ ${req.method} ${req.path}`, {
      requestId: req.id,
      ip: req.ip,
      userAgent: req.get('user-agent'),
      query: req.path.includes('/auth/oauth/') ? '[OAuth query redacted]' : sanitizeBody(req.query),
      body: /\/sign-sequence|\/conversations|\/learning\/(?:my-words|quizzes)/.test(req.path) ? '[Private content redacted]' : sanitizeBody(req.body),
    });
  } else {
    console.log(`→ ${req.method} ${req.path} [${req.id}]`);
  }

  // Log response
  res.on('finish', () => {
    const duration = Date.now() - start;
    const logLevel = res.statusCode >= 400 ? 'error' : 'info';
    
    if (logLevel === 'error') {
      console.error(`← ${req.method} ${req.path} ${res.statusCode} (${duration}ms) [${req.id}]`);
    } else if (env.LOG_LEVEL === 'debug' || res.statusCode >= 300) {
      console.log(`← ${req.method} ${req.path} ${res.statusCode} (${duration}ms) [${req.id}]`);
    }
  });

  next();
}

/**
 * Sanitize request body for logging
 * Remove sensitive fields like passwords, tokens
 */
function sanitizeBody(body: any): any {
  if (!body || typeof body !== 'object') return body;

  const sensitiveFields = ['deviceKey', 'ticket', 'password', 'newPassword', 'currentPassword', 'passwordHash', 'token', 'refreshToken', 'secret', 'code', 'state', 'client_secret', 'access_token', 'id_token', 'input_token', 'code_verifier'];
  const sanitized = { ...body };

  for (const field of sensitiveFields) {
    if (field in sanitized) {
      sanitized[field] = '***REDACTED***';
    }
  }

  return sanitized;
}

/**
 * Add request ID to all requests
 */
export function addRequestId(req: Request, res: Response, next: NextFunction): void {
  req.id = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  res.setHeader('X-Request-ID', req.id);
  next();
}

// Extend Express Request type to include id
declare global {
  namespace Express {
    interface Request {
      id: string;
    }
  }
}
