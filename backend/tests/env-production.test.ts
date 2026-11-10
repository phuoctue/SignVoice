import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const ORIGINAL_ENV = { ...process.env };
const STRONG_ACCESS = 'a'.repeat(48);
const STRONG_REFRESH = 'b'.repeat(48);

async function loadEnv(overrides: Record<string, string | undefined>) {
  vi.resetModules();
  process.env = { ...ORIGINAL_ENV, SIGNVOICE_ENV_FILE: '__missing_env_file__' };
  for (const key of ['MONGODB_URI', 'ADMIN_PASSWORD', 'SWAGGER_ENABLED', 'CORS_ALLOWED_ORIGINS', 'PUBLIC_ORIGIN']) {
    delete process.env[key];
  }
  Object.assign(process.env, {
    NODE_ENV: 'production',
    JWT_ACCESS_SECRET: STRONG_ACCESS,
    JWT_REFRESH_SECRET: STRONG_REFRESH,
    MONGODB_URI: 'mongodb://prod-user:s3cret@db.internal:27017/signvoice',
    CORS_ALLOWED_ORIGINS: 'https://signvoice.example',
  });
  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  return import('../src/config/env');
}

describe('production environment validation (fail closed)', () => {
  beforeEach(() => vi.spyOn(console, 'warn').mockImplementation(() => undefined));
  afterEach(() => {
    process.env = { ...ORIGINAL_ENV };
    vi.restoreAllMocks();
    vi.resetModules();
  });

  it('accepts an explicit, safe production configuration', async () => {
    const { env, validateEnv } = await loadEnv({});
    expect(env.LISTEN_HOST).toBe('127.0.0.1');
    expect(() => validateEnv()).not.toThrow();
  });

  it.each(['development', 'test'])('keeps %s reachable by local mobile clients', async nodeEnv => {
    const {env} = await loadEnv({NODE_ENV: nodeEnv});
    expect(env.LISTEN_HOST).toBe('0.0.0.0');
  });

  it('rejects a missing MONGODB_URI instead of using the dev credential', async () => {
    const { env, validateEnv } = await loadEnv({ MONGODB_URI: undefined });
    expect(env.MONGODB_URI).toBe('');
    expect(() => validateEnv()).toThrow(/MONGODB_URI/);
  });

  it('rejects the development database credential', async () => {
    const { validateEnv } = await loadEnv({
      MONGODB_URI: 'mongodb://signvoice:dev_password@localhost:27017/signvoice?authSource=admin',
    });
    expect(() => validateEnv()).toThrow(/development credential/);
  });

  it('has no usable default admin password and rejects weak ones', async () => {
    const unset = await loadEnv({});
    expect(unset.env.ADMIN_PASSWORD).toBe('');
    const weak = await loadEnv({ ADMIN_PASSWORD: 'admin123456' });
    expect(() => weak.validateEnv()).toThrow(/ADMIN_PASSWORD/);
  });

  it('rejects SWAGGER_ENABLED=true in production', async () => {
    const { validateEnv } = await loadEnv({ SWAGGER_ENABLED: 'true' });
    expect(() => validateEnv()).toThrow(/SWAGGER_ENABLED/);
  });

  it.each([
    ['*', /wildcard/],
    ['https://*.example.com', /wildcard/],
    ['not a url', /malformed/],
    ['http://signvoice.example', /https/],
    ['https://signvoice.example/app', /bare origin/],
  ])('rejects unsafe CORS origin %s', async (origin, message) => {
    const { validateEnv } = await loadEnv({ CORS_ALLOWED_ORIGINS: origin });
    expect(() => validateEnv()).toThrow(message);
  });

  it('allows loopback http origins for local production builds', async () => {
    const { validateEnv } = await loadEnv({ CORS_ALLOWED_ORIGINS: 'http://localhost:3002,https://signvoice.example' });
    expect(() => validateEnv()).not.toThrow();
  });
});

describe('swagger exposure', () => {
  afterEach(() => {
    process.env = { ...ORIGINAL_ENV };
    vi.restoreAllMocks();
    vi.resetModules();
  });

  async function swaggerEnabledFor(nodeEnv: string | undefined, flag?: string) {
    vi.resetModules();
    process.env = { ...ORIGINAL_ENV, SIGNVOICE_ENV_FILE: '__missing_env_file__' };
    if (nodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = nodeEnv;
    if (flag === undefined) delete process.env.SWAGGER_ENABLED;
    else process.env.SWAGGER_ENABLED = flag;
    vi.spyOn(console, 'log').mockImplementation(() => undefined);
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const { setupSwagger } = await import('../src/config/swagger');
    const use = vi.fn();
    const get = vi.fn();
    setupSwagger({ use, get } as never);
    return use.mock.calls.length + get.mock.calls.length > 0;
  }

  it('is disabled when NODE_ENV is unset', async () => {
    expect(await swaggerEnabledFor(undefined)).toBe(false);
  });

  it('is disabled in production even if SWAGGER_ENABLED=true', async () => {
    expect(await swaggerEnabledFor('production', 'true')).toBe(false);
  });

  it('is enabled with explicit NODE_ENV=development', async () => {
    expect(await swaggerEnabledFor('development')).toBe(true);
  });
});
