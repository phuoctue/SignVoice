// A config-only preflight: no server imports, DNS lookups or DB connections.
const path = require('node:path');

try {
  const [backendRoot, expectedFile] = process.argv.slice(2);
  const productionFile = path.join(backendRoot, '.env.production.local');
  if (process.env.NODE_ENV !== 'production' || !path.isAbsolute(expectedFile) ||
      path.resolve(expectedFile) !== path.resolve(productionFile) ||
      process.env.SIGNVOICE_ENV_FILE !== expectedFile) throw new Error();
  const { env, validateEnv } = require(path.join(backendRoot, 'dist/config/env.js'));
  // Process overrides are intentional; validate the effective values, not just the file.
  if (env.NODE_ENV !== 'production' || !env.isProduction || env.LISTEN_HOST !== '127.0.0.1' ||
      env.PUBLIC_ORIGIN !== process.env.PUBLIC_ORIGIN) throw new Error();
  validateEnv();
} catch {
  // Never emit a config value or a parser error that could contain credentials.
  process.stderr.write('Production configuration preflight refused.\n');
  process.exitCode = 1;
}
