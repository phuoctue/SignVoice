import express, { Application } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import path from 'path';
import { existsSync } from 'fs';
import { env } from './config/env';
import { errorHandler, notFoundHandler } from './common/middlewares/errorHandler';
import { requestLogger, addRequestId } from './common/middlewares/requestLogger';
import { isDatabaseReady, getDatabaseInfo } from './config/database';
import { setupSwagger } from './config/swagger';
import { attachAiPublicProxy } from './ai-public-proxy';
import { serveDetectorAssets } from './detector-assets';

/**
 * Create and configure Express application
 */
export async function createApp(): Promise<Application> {
  const app = express();
  // Inference runs in its own process. This only permits the browser connection.
  const aiOrigin = new URL(process.env.AI_SERVICE_URL || 'http://localhost:8001').origin;
  const aiSocketOrigin = aiOrigin.replace(/^http/, 'ws');
  const publicSocketOrigin = env.PUBLIC_ORIGIN ? new URL(env.PUBLIC_ORIGIN).origin.replace(/^http/, 'ws') : '';

  // Security middleware with Swagger UI and Flutter Web exception
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
        scriptSrc: ["'self'", "'unsafe-inline'", ...(env.SERVE_WEB ? ["'wasm-unsafe-eval'", 'https://cdn.jsdelivr.net'] : [])],
        imgSrc: ["'self'", "data:", "blob:", "https:"],
        connectSrc: ["'self'", aiOrigin, aiSocketOrigin, publicSocketOrigin, 'http://127.0.0.1:8001', 'ws://127.0.0.1:8001', "blob:", "data:", "https:", 'https://fonts.googleapis.com', 'https://fonts.gstatic.com'].filter(Boolean),
        workerSrc: ["'self'", "blob:"],
        fontSrc: ["'self'", "data:", 'https://fonts.gstatic.com'],
        mediaSrc: ["'self'", "blob:", "data:", "https:", ...(!env.isProduction ? ['http:'] : [])],
        upgradeInsecureRequests: env.isProduction ? [] : null,
      },
    },
    crossOriginResourcePolicy: { policy: "cross-origin" },
  }));

  if (process.env.AI_PUBLIC_PROXY === 'true') {
    const proxy = attachAiPublicProxy(app, {
      target: process.env.AI_PROXY_TARGET || 'http://127.0.0.1:8001',
      publicOrigin: env.PUBLIC_ORIGIN,
      port: env.PORT,
    });
    app.locals.attachAiUpgrade = proxy.attach;
  }

  // CORS configuration
  app.use(cors({
    origin: (origin, callback) => {
      // Allow requests with no origin (mobile apps, Postman)
      if (!origin) return callback(null, true);
      
      if (env.CORS_ALLOWED_ORIGINS.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error('Not allowed by CORS'));
      }
    },
    credentials: true, // Allow cookies
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  }));

  // Body parsing middleware (allow up to 50mb for high-res camera pictures)
  app.use(express.json({ limit: '50mb' }));
  app.use(express.urlencoded({ extended: true, limit: '50mb' }));
  app.use(cookieParser());

  // Request tracking
  app.use(addRequestId);
  app.use(requestLogger);

  // Swagger API Documentation (development only by default)
  setupSwagger(app);

  // Health check endpoints
  app.get('/health/live', (_req, res) => {
    res.status(200).json({
      success: true,
      data: {
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
      },
    });
  });

  app.get('/health/ready', (_req, res) => {
    const dbReady = isDatabaseReady();
    const dbInfo = getDatabaseInfo();

    if (!dbReady) {
      return res.status(503).json({
        success: false,
        error: {
          code: 'SERVICE_UNAVAILABLE',
          message: 'Database not ready',
        },
        data: {
          database: dbInfo,
        },
      });
    }

    return res.status(200).json({
      success: true,
      data: {
        status: 'ready',
        timestamp: new Date().toISOString(),
        database: {
          connected: dbInfo.connected,
          name: dbInfo.name,
        },
      },
    });
  });

  // API routes
  app.use('/api/v1/auth', (await import('./routes/auth.routes')).default);
  app.use('/api/v1/dictionary', (await import('./routes/dictionary.routes')).default);
  app.use('/api/v1/sign-sequence', (await import('./routes/sign-sequence.routes')).default);
  app.use('/sign-media', (await import('./routes/sign-media.routes')).default);
  app.use('/api/v1/categories', (await import('./routes/category.routes')).default);
  app.use('/api/v1/favorites', (await import('./routes/favorites.routes')).default);
  app.use('/api/v1/history', (await import('./routes/history.routes')).default);
  app.use('/api/v1/users', (await import('./routes/user.routes')).default);
  app.use('/api/v1/staff', (await import('./routes/staff.routes')).default);
  app.use('/api/v1/admin', (await import('./routes/admin.routes')).default);

  // Share one origin for Flutter and API so JWT cookies also work over a tunnel.
  if (env.SERVE_WEB) {
    const webRoot = env.WEB_BUILD_DIR
      ? path.resolve(env.WEB_BUILD_DIR)
      : path.resolve(__dirname, '../../build/web');
    if (!existsSync(path.join(webRoot, 'index.html'))) {
      throw new Error('Flutter web build is missing. Run flutter build web first.');
    }
    serveDetectorAssets(app, webRoot);
    app.use(express.static(webRoot, {
      setHeaders: (res, filePath) => {
        if (/\.(html|js|json)$/.test(filePath)) res.setHeader('Cache-Control', 'no-cache');
      },
    }));
    app.get(/^\/(?!api(?:\/|$)|health(?:\/|$)|api-docs(?:\/|$))[^.]*$/, (_req, res) => {
      res.sendFile(path.join(webRoot, 'index.html'));
    });
  }

  // 404 handler
  app.use(notFoundHandler);

  // Global error handler (must be last)
  app.use(errorHandler);

  return app;
}
