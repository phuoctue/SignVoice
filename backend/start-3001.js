const path = require('node:path');
const { existsSync } = require('node:fs');
const envFile = path.join(__dirname, '.env.production.local');
if (!existsSync(envFile)) throw new Error('Missing backend/.env.production.local; production startup refused');
process.env.SIGNVOICE_ENV_FILE = envFile;
process.env.PORT = '3001';
process.env.SERVE_WEB = 'true';
process.env.NODE_ENV = 'production';
// Supply PUBLIC_ORIGIN from your own tunnel; never reuse another machine's URL.
process.env.PUBLIC_ORIGIN ||= 'http://localhost:3001';

require('./dist/config/env.js').validateEnv();
const { startServer } = require('./dist/server.js');
startServer();
