import dotenv from 'dotenv';
import { isIP } from 'node:net';

// Load environment variables
dotenv.config({ path: process.env.SIGNVOICE_ENV_FILE || '.env' });

const DEV_MONGODB_URI = 'mongodb://signvoice:dev_password@localhost:27017/signvoice?authSource=admin';
const WEAK_ADMIN_PASSWORDS = new Set(['admin123456', 'admin', 'password', 'changeme']);

export function parseTrustProxy(raw: string | undefined): false | number | string {
  const value = raw?.trim() || 'false';
  if (value === 'false') return false;
  if (/^[1-9]\d*$/.test(value) && Number(value) <= 16) return Number(value);
  const entries = value.split(',').map(part => part.trim());
  if (entries.every(entry => {
    if (['loopback', 'linklocal', 'uniquelocal'].includes(entry)) return true;
    const [ip, bits, extra] = entry.split('/');
    const version = isIP(ip);
    return !!version && extra === undefined && (bits === undefined ||
      /^\d+$/.test(bits) && Number(bits) > 0 && Number(bits) <= (version === 4 ? 32 : 128));
  })) return entries.join(',');
  throw new Error('Invalid or unsafe TRUST_PROXY; use false, 1..16, or explicit proxy IP/subnet names');
}

/**
 * Environment configuration
 * All required environment variables with validation
 */
export const env = {
  // Environment
  NODE_ENV: process.env.NODE_ENV || 'development',
  isDevelopment: process.env.NODE_ENV === 'development',
  isProduction: process.env.NODE_ENV === 'production',
  isTest: process.env.NODE_ENV === 'test',

  // Server
  PORT: parseInt(process.env.PORT || '3000', 10),
  SERVE_WEB: process.env.SERVE_WEB === 'true',
  WEB_BUILD_DIR: process.env.WEB_BUILD_DIR || '',
  PUBLIC_ORIGIN: process.env.PUBLIC_ORIGIN || '',
  TRUST_PROXY: parseTrustProxy(process.env.TRUST_PROXY),

  // SMTP credentials stay on the server; never include them in Flutter builds.
  SMTP_HOST: process.env.SMTP_HOST || 'smtp.gmail.com',
  SMTP_PORT: parseInt(process.env.SMTP_PORT || '465', 10),
  SMTP_SECURE: process.env.SMTP_SECURE !== 'false',
  SMTP_USER: process.env.SMTP_USER || '',
  SMTP_PASS: process.env.SMTP_PASS || '',
  SMTP_FROM: process.env.SMTP_FROM || process.env.SMTP_USER || '',
  PASSWORD_RESET_ORIGIN: process.env.PASSWORD_RESET_ORIGIN || process.env.PUBLIC_ORIGIN || process.env.WEB_ORIGIN || 'http://localhost:8080',

  // Database (the local credential fallback is never used in production)
  MONGODB_URI: process.env.MONGODB_URI || (process.env.NODE_ENV === 'production' ? '' : DEV_MONGODB_URI),

  // JWT
  JWT_ACCESS_SECRET: process.env.JWT_ACCESS_SECRET || '',
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || '',
  JWT_ACCESS_EXPIRES_IN: process.env.JWT_ACCESS_EXPIRES_IN || '15m',
  JWT_REFRESH_EXPIRES_IN: process.env.JWT_REFRESH_EXPIRES_IN || '7d',

  // CORS
  WEB_ORIGIN: process.env.WEB_ORIGIN || 'http://localhost:8080',
  CORS_ALLOWED_ORIGINS: [
    ...(process.env.CORS_ALLOWED_ORIGINS || 'http://localhost:8080,http://localhost:3000').split(','),
    process.env.PUBLIC_ORIGIN || '',
  ].map(origin => origin.trim()).filter(Boolean),

  // OAuth (optional for now)
  GOOGLE_CLIENT_ID: process.env.GOOGLE_CLIENT_ID || '',
  GOOGLE_CLIENT_SECRET: process.env.GOOGLE_CLIENT_SECRET || '',
  FACEBOOK_APP_ID: process.env.FACEBOOK_APP_ID || '',
  FACEBOOK_APP_SECRET: process.env.FACEBOOK_APP_SECRET || '',
  OAUTH_BACKEND_ORIGIN: process.env.OAUTH_BACKEND_ORIGIN || '',
  OAUTH_FRONTEND_ORIGIN: process.env.OAUTH_FRONTEND_ORIGIN || '',
  GOOGLE_CALLBACK_URL: process.env.GOOGLE_CALLBACK_URL || '',
  FACEBOOK_CALLBACK_URL: process.env.FACEBOOK_CALLBACK_URL || '',
  FACEBOOK_GRAPH_API_VERSION: process.env.FACEBOOK_GRAPH_API_VERSION || '',
  OAUTH_STATE_TTL_SECONDS: Number(process.env.OAUTH_STATE_TTL_SECONDS || '600'),

  // Logging
  LOG_LEVEL: process.env.LOG_LEVEL || 'info',

  // Development
  ADMIN_EMAIL: process.env.ADMIN_EMAIL || 'admin@signvoice.local',
  // No usable default: an admin password must be supplied explicitly.
  ADMIN_PASSWORD: process.env.ADMIN_PASSWORD || '',
  SWAGGER_ENABLED: process.env.SWAGGER_ENABLED === 'true',
};

function isLoopbackHost(hostname: string): boolean {
  return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '[::1]';
}

/**
 * Production-only checks: fail closed instead of running with
 * development defaults or permissive debug settings.
 */
function validateProductionEnv(): void {
  const errors: string[] = [];

  if (env.MONGODB_URI === DEV_MONGODB_URI || env.MONGODB_URI.includes('dev_password')) {
    errors.push('MONGODB_URI must not use the development credential in production');
  }
  if (env.ADMIN_PASSWORD && (env.ADMIN_PASSWORD.length < 12 || WEAK_ADMIN_PASSWORDS.has(env.ADMIN_PASSWORD.toLowerCase()))) {
    errors.push('ADMIN_PASSWORD must not be a default/weak value in production');
  }
  if (env.SWAGGER_ENABLED) {
    errors.push('SWAGGER_ENABLED=true is not allowed in production');
  }

  for (const origin of env.CORS_ALLOWED_ORIGINS) {
    if (origin.includes('*')) {
      errors.push(`CORS origin must not contain a wildcard: ${origin}`);
      continue;
    }
    let url: URL;
    try {
      url = new URL(origin);
    } catch {
      errors.push(`CORS origin is malformed: ${origin}`);
      continue;
    }
    if (url.origin !== origin.replace(/\/$/, '')) {
      errors.push(`CORS origin must be a bare origin without path/credentials: ${origin}`);
    } else if (url.protocol !== 'https:' && !(url.protocol === 'http:' && isLoopbackHost(url.hostname))) {
      errors.push(`CORS origin must use https in production: ${origin}`);
    }
  }

  if (errors.length > 0) {
    throw new Error(`Invalid production configuration:\n${errors.join('\n')}`);
  }
}

/**
 * Validate required environment variables
 * Throws error if critical variables are missing
 */
export function validateEnv(): void {
  const required: (keyof typeof env)[] = [
    'MONGODB_URI',
    'JWT_ACCESS_SECRET',
    'JWT_REFRESH_SECRET',
  ];

  const missing = required.filter(key => !env[key]);

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables:\n${missing.join('\n')}\n\n` +
      'Please copy .env.example to .env and configure the variables.'
    );
  }

  // Validate JWT secrets are strong enough
  if (!env.isTest) {
    if (env.JWT_ACCESS_SECRET.length < 32) {
      throw new Error('JWT_ACCESS_SECRET must be at least 32 characters long');
    }
    if (env.JWT_REFRESH_SECRET.length < 32) {
      throw new Error('JWT_REFRESH_SECRET must be at least 32 characters long');
    }
    if (env.JWT_ACCESS_SECRET === env.JWT_REFRESH_SECRET) {
      throw new Error('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be different');
    }
  }

  // Warn about production-only checks
  if (env.isProduction) {
    validateProductionEnv();
    if (env.NODE_ENV !== 'production') {
      console.warn('⚠️  NODE_ENV should be "production" in production environment');
    }
    if (env.MONGODB_URI.includes('localhost')) {
      console.warn('⚠️  Using localhost MongoDB in production is not recommended');
    }
  }
}
