import { Application } from 'express';
import swaggerUi from 'swagger-ui-express';
import * as yaml from 'yaml';
import * as fs from 'fs';
import * as path from 'path';
import { env } from './env';

/**
 * Setup Swagger UI for API documentation
 */
export function setupSwagger(app: Application): void {
  // Check if Swagger should be enabled
  const swaggerEnabled = env.NODE_ENV === 'development' || process.env.SWAGGER_ENABLED === 'true';

  if (!swaggerEnabled) {
    console.log('📖 Swagger UI disabled in production mode');
    return;
  }

  try {
    // Load OpenAPI specification
    const openApiPath = path.join(__dirname, '../../docs/openapi.yaml');
    
    if (!fs.existsSync(openApiPath)) {
      console.error('⚠️  OpenAPI specification file not found:', openApiPath);
      return;
    }

    const openApiFile = fs.readFileSync(openApiPath, 'utf8');
    const swaggerDocument = yaml.parse(openApiFile);
    if (env.isTest) {
      swaggerDocument.servers = [{ url: '/api/v1', description: 'Testing (same origin)' }];
    }

    // Swagger UI options
    const swaggerOptions: swaggerUi.SwaggerUiOptions = {
      explorer: true,
      swaggerOptions: {
        persistAuthorization: false, // Don't persist JWT in browser storage for security
        displayRequestDuration: true,
        filter: true,
        tryItOutEnabled: true,
        requestSnippetsEnabled: true,
        syntaxHighlight: {
          activate: true,
          theme: 'monokai'
        }
      },
      customCss: `
        .swagger-ui .topbar { display: none }
        .swagger-ui .info { margin: 20px 0; }
        .swagger-ui .scheme-container { margin: 20px 0; padding: 20px; background: #fafafa; border-radius: 4px; }
      `,
      customSiteTitle: 'SignVoice API Documentation'
    };

    // Serve Swagger UI at /api-docs
    app.use('/api-docs', swaggerUi.serve);
    app.get('/api-docs', swaggerUi.setup(swaggerDocument, swaggerOptions));

    // Serve OpenAPI JSON at /api-docs/openapi.json
    app.get('/api-docs/openapi.json', (_req, res) => {
      res.setHeader('Content-Type', 'application/json');
      res.send(swaggerDocument);
    });

    console.log('📖 Swagger UI enabled at /api-docs');
    console.log('📄 OpenAPI JSON available at /api-docs/openapi.json');
  } catch (error) {
    console.error('❌ Failed to setup Swagger UI:', error);
  }
}

/**
 * Validate OpenAPI specification
 * Can be used in tests or build scripts
 */
export function validateOpenApiSpec(): boolean {
  try {
    const openApiPath = path.join(__dirname, '../../docs/openapi.yaml');
    const openApiFile = fs.readFileSync(openApiPath, 'utf8');
    const spec = yaml.parse(openApiFile);

    // Basic validation
    if (!spec.openapi || !spec.info || !spec.paths) {
      console.error('❌ Invalid OpenAPI specification: missing required fields');
      return false;
    }

    if (!spec.openapi.startsWith('3.0')) {
      console.error('❌ Invalid OpenAPI version:', spec.openapi);
      return false;
    }

    console.log('✅ OpenAPI specification is valid');
    console.log(`   Title: ${spec.info.title}`);
    console.log(`   Version: ${spec.info.version}`);
    console.log(`   Paths: ${Object.keys(spec.paths).length}`);

    return true;
  } catch (error) {
    console.error('❌ OpenAPI validation failed:', error);
    return false;
  }
}
