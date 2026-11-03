import dotenv from 'dotenv';

// Load environment variables
dotenv.config({ path: process.env.SIGNVOICE_ENV_FILE || '.env' });

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

  // SMTP credentials stay on the server; never include them in Flutter builds.
  SMTP_HOST: process.env.SMTP_HOST || 'smtp.gmail.com',
  SMTP_PORT: parseInt(process.env.SMTP_PORT || '465', 10),
  SMTP_SECURE: process.env.SMTP_SECURE !== 'false',
  SMTP_USER: process.env.SMTP_USER || '',
  SMTP_PASS: process.env.SMTP_PASS || '',
  SMTP_FROM: process.env.SMTP_FROM || process.env.SMTP_USER || '',
  PASSWORD_RESET_ORIGIN: process.env.PASSWORD_RESET_ORIGIN || process.env.PUBLIC_ORIGIN || process.env.WEB_ORIGIN || 'http://localhost:8080',

  // Database
  MONGODB_URI: process.env.MONGODB_URI || 'mongodb://signvoice:dev_password@localhost:27017/signvoice?authSource=admin',

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
  ADMIN_PASSWORD: process.env.ADMIN_PASSWORD || 'admin123456',
};

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
    if (env.NODE_ENV !== 'production') {
      console.warn('⚠️  NODE_ENV should be "production" in production environment');
    }
    if (env.MONGODB_URI.includes('localhost')) {
      console.warn('⚠️  Using localhost MongoDB in production is not recommended');
    }
  }
}
