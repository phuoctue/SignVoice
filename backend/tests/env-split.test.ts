import { afterAll, afterEach, describe, expect, it, vi } from 'vitest';
import dotenv from 'dotenv';
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { spawnSync } from 'node:child_process';

const originalEnv = { ...process.env };
const backendRoot = path.resolve(__dirname, '..');
const scratch = mkdtempSync(path.join(tmpdir(), 'signvoice-env-unit-'));
const configFile = path.join(scratch, 'dummy-config');
const emptyConfig = path.join(scratch, 'empty-config');
writeFileSync(configFile, 'NODE_ENV=production\nMONGODB_URI=mongodb://localhost/file_database\n');
writeFileSync(emptyConfig, '');

async function load(overrides: Record<string, string | undefined> = {}) {
  vi.resetModules();
  process.env = { ...originalEnv, SIGNVOICE_ENV_FILE: configFile, NODE_ENV: 'test',
    MONGODB_URI: 'mongodb://127.0.0.1/signvoice_test_unit', ...overrides };
  for (const [key, value] of Object.entries(overrides)) if (value === undefined) delete process.env[key];
  return import('../src/config/env');
}

afterEach(() => {
  process.env = { ...originalEnv };
  vi.restoreAllMocks();
  vi.resetModules();
});
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

describe('nonproduction MongoDB boundary (configuration only)', () => {
  it.each([
    ['localhost', 'mongodb://localhost/signvoice_test_unit'],
    ['127/8', 'mongodb://127.98.76.54:27018/signvoice_test_unit'],
    ['IPv6', 'mongodb://[::1]:27017/signvoice_test_unit'],
    ['expanded IPv6', 'mongodb://[0:0:0:0:0:0:0:1]/signvoice_test_unit'],
    ['credentials and query', 'mongodb://user:p%40ss@localhost:27017/signvoice_test_unit?authSource=admin'],
    ['multiple loopbacks', 'mongodb://localhost:27017,127.1.2.3:27018,[::1]:27019/signvoice_test_unit?replicaSet=local'],
  ])('accepts %s without connecting', async (_name, uri) => {
    const { env, validateEnv } = await load({ MONGODB_URI: uri });
    expect(env.MONGODB_URI).toBe(uri);
    expect(() => validateEnv()).not.toThrow();
  });

  it.each([
    ['Atlas', 'mongodb://user:private-pass@cluster.example.net/database'],
    ['SRV', 'mongodb+srv://user:private-pass@cluster.example.net/database'],
    ['loopback SRV', 'mongodb+srv://localhost/database'],
    ['mixed hosts', 'mongodb://localhost:27017,remote.example:27017/database'],
    ['mixed IPv6', 'mongodb://[::1]:27017,[2001:db8::1]:27017/database'],
    ['invalid scheme', 'https://localhost/database'],
    ['malformed', 'not a URI'],
    ['no host', 'mongodb:///database'],
    ['empty list host', 'mongodb://localhost,,127.0.0.1/database'],
    ['trailing empty host', 'mongodb://localhost,/database'],
    ['IPv4 lookalike', 'mongodb://127.0.0.1.evil.com/database'],
    ['localhost lookalike', 'mongodb://localhost.evil/database'],
    ['invalid port', 'mongodb://localhost:99999/database'],
    ['invalid credential escape', 'mongodb://user:%ZZ@localhost/database'],
    ['remote SOCKS proxy', 'mongodb://localhost/database?proxyHost=remote.example'],
    ['loopback SOCKS proxy', 'mongodb://localhost/database?proxyHost=127.0.0.1'],
  ])('rejects %s without leaking input', async (_name, uri) => {
    await expect(load({ MONGODB_URI: uri })).rejects.toThrow(/MONGODB_URI.*loopback/);
    try { await load({ MONGODB_URI: uri }); } catch (error) {
      expect(String(error)).not.toContain(uri);
      expect(String(error)).not.toContain('private-pass');
    }
  });

  it.each(['development', 'test', undefined])('blocks remote hosts with NODE_ENV=%s', async nodeEnv => {
    await expect(load({ NODE_ENV: nodeEnv, SIGNVOICE_ENV_FILE: emptyConfig, MONGODB_URI: 'mongodb://remote.example/database' }))
      .rejects.toThrow(/MONGODB_URI.*loopback/);
  });

  it('leaves production URI validation unchanged', async () => {
    const { env } = await load({ NODE_ENV: 'production', MONGODB_URI: 'mongodb+srv://cluster.example.net/database' });
    expect(env.isProduction).toBe(true);
  });
});

describe('environment file resolution and precedence', () => {
  it('loads an absolute file from an unrelated cwd; process variables win', async () => {
    vi.spyOn(process, 'cwd').mockReturnValue(scratch);
    const { env } = await load();
    expect(env.NODE_ENV).toBe('test');
    expect(env.MONGODB_URI).toBe('mongodb://127.0.0.1/signvoice_test_unit');
  });

  it('resolves relative files against the backend root regardless of cwd', async () => {
    vi.spyOn(process, 'cwd').mockReturnValue(scratch);
    const { env } = await load({ SIGNVOICE_ENV_FILE: path.relative(backendRoot, configFile), MONGODB_URI: undefined });
    expect(env.MONGODB_URI).toBe('mongodb://localhost/file_database');
  });

  it('rejects a missing explicit file even with complete process configuration', async () => {
    await expect(load({ SIGNVOICE_ENV_FILE: path.join(scratch, 'missing-config') }))
      .rejects.toThrow(/SIGNVOICE_ENV_FILE/);
  });

  it.each(['', '   '])('rejects a blank explicit file selection %j without loading the default', async selection => {
    const loader = vi.spyOn(dotenv, 'config').mockReturnValue({});
    await expect(load({ SIGNVOICE_ENV_FILE: selection })).rejects.toThrow(/SIGNVOICE_ENV_FILE/);
    expect(loader).not.toHaveBeenCalled();
  });

  it('uses the backend default and tolerates its absence without reading a real env file', async () => {
    const loader = vi.spyOn(dotenv, 'config').mockReturnValue({ error: new Error('synthetic missing default') });
    vi.spyOn(process, 'cwd').mockReturnValue(scratch);
    const { env } = await load({ SIGNVOICE_ENV_FILE: undefined });
    expect(loader).toHaveBeenCalledWith({ path: path.join(backendRoot, '.env') });
    expect(env.NODE_ENV).toBe('test');
  });
});

describe('production launchers (no server execution)', () => {
  it.each([false, true])('Node launcher fails closed with missing file=%s', missing => {
    const code = readFileSync(path.join(backendRoot, 'start-3001.js'), 'utf8');
    const launchEnv: Record<string, string> = { NODE_ENV: 'development', SIGNVOICE_ENV_FILE: 'stale-file' };
    const expectedFile = path.join(scratch, '.env.production.local');
    const events: string[] = [];
    const run = () => vm.runInNewContext(code, {
      __dirname: scratch, process: { env: launchEnv },
      require: (id: string) => {
        if (id === 'node:path') return path;
        if (id === 'node:fs') return { existsSync: (file: string) =>
          file === path.join(scratch, '.env') || !missing && file === expectedFile };
        if (id === './dist/config/env.js') return { validateEnv: () => {
          expect(launchEnv.NODE_ENV).toBe('production');
          expect(launchEnv.SIGNVOICE_ENV_FILE).toBe(expectedFile);
          events.push('validate');
          throw new Error('synthetic invalid config');
        } };
        events.push('server import');
        throw new Error('server execution forbidden');
      },
    });
    expect(run).toThrow(missing ? /Missing.*production/ : /synthetic invalid config/);
    expect(events).toEqual(missing ? [] : ['validate']);
  });

  it.each([false, true])('PowerShell refuses a missing selected file despite a decoy, NoTunnel=%s', noTunnel => {
    const source = readFileSync(path.join(backendRoot, '../scripts/start-public-server.ps1'), 'utf8');
    const scripts = path.join(scratch, 'scripts');
    mkdirSync(scripts, { recursive: true });
    const script = path.join(scripts, 'start-public-server.ps1');
    writeFileSync(script, source);
    const expectedFile = path.join(scratch, 'backend', noTunnel ? '.env' : '.env.production.local');
    mkdirSync(path.dirname(expectedFile), { recursive: true });
    const decoyFile = path.join(scratch, 'backend', noTunnel ? '.env.production.local' : '.env');
    const probe = path.join(scratch, `launcher-probe-${noTunnel}.ps1`);
    // Virtual existence fixtures prove no fallback without opening any .env file.
    const quote = (value: string) => `'${value.replace(/'/g, "''")}'`;
    writeFileSync(probe, [
      "$ErrorActionPreference = 'Stop'",
      '$global:signvoiceProbeLookups = @()',
      'function Test-Path {',
      '  param([string]$LiteralPath, [string]$PathType)',
      '  $global:signvoiceProbeLookups += $LiteralPath',
      `  return $LiteralPath -eq ${quote(decoyFile)}`,
      '}',
      `try { & ${quote(script)} -TrustProxy loopback -SkipBuild -SkipAi${noTunnel ? ' -NoTunnel' : ''} }`,
      'catch {',
      '  Write-Output $_.Exception.Message',
      "  Write-Output ('LOOKUPS=' + (ConvertTo-Json -InputObject @($global:signvoiceProbeLookups) -Compress))",
      '  exit 1',
      '}',
    ].join('\n'));
    const result = spawnSync('powershell.exe', ['-NoProfile', '-File', probe],
      { cwd: scratch, encoding: 'utf8', timeout: 15000 });
    expect(result.status).toBe(1);
    expect(result.stdout + result.stderr).toMatch(noTunnel ? /Missing backend\/\.env\./ : /Missing.*production/);
    const lookups: string[] = JSON.parse(result.stdout.match(/^LOOKUPS=(.*)$/m)![1]);
    expect(lookups).toHaveLength(1);
    expect(path.basename(lookups[0])).toBe(path.basename(expectedFile));
    // Native realpath expands Windows 8.3 aliases on the existing parent, never the virtual file.
    expect(realpathSync.native(path.dirname(lookups[0])))
      .toBe(realpathSync.native(path.dirname(expectedFile)));
    expect(source).toMatch(/\$env:SIGNVOICE_ENV_FILE\s*=\s*\$envFile/);
    expect(source).toMatch(/\$env:NODE_ENV\s*=\s*if\s*\(\$NoTunnel\)\s*\{\s*'development'\s*\}\s*else\s*\{\s*'production'/);
    expect(source.indexOf("require('./dist/config/env.js').validateEnv()"))
      .toBeLessThan(source.indexOf('$serverProcess = Start-Process'));
  });
});
