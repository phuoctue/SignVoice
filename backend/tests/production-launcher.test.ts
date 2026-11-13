import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { spawnSync } from 'node:child_process';

const scripts = path.resolve(__dirname, '../../scripts');
const preflight = readFileSync(path.join(scripts, 'public-server-config.cjs'), 'utf8');

function probe(overrides: Record<string, unknown> = {}, effective: Record<string, unknown> = {}, invalid = false) {
  const root = path.resolve('dummy-backend');
  const file = path.join(root, '.env.production.local');
  const processEnv = { NODE_ENV: 'production', SIGNVOICE_ENV_FILE: file, PUBLIC_ORIGIN: 'https://signvoice.example', ...overrides };
  const imports: string[] = [];
  let validations = 0;
  let errors = '';
  const processStub = { argv: ['node', 'probe', root, file], env: processEnv, exitCode: 0,
    stderr: { write: (message: string) => { errors += message; } } };
  vm.runInNewContext(preflight, {
    process: processStub,
    require: (name: string) => {
      imports.push(name);
      if (name === 'node:path') return path;
      if (name !== path.join(root, 'dist/config/env.js')) throw new Error('Forbidden server/file/DB import');
      return { env: { NODE_ENV: 'production', isProduction: true, LISTEN_HOST: '127.0.0.1',
        PUBLIC_ORIGIN: 'https://signvoice.example', ...effective },
      validateEnv: () => { validations++; if (invalid) throw new Error('private-config-value'); } };
    },
  });
  return { status: processStub.exitCode, errors, imports, validations };
}

describe('staged production launcher config-only validation', () => {
  it('accepts explicit production on loopback without importing the server', () => {
    const result = probe();
    expect(result.status).toBe(0);
    expect(result.validations).toBe(1);
    expect(result.imports).toHaveLength(2);
    expect(result.errors).toBe('');
  });

  it.each([
    { NODE_ENV: 'development' }, { NODE_ENV: 'test' }, { NODE_ENV: undefined },
    { SIGNVOICE_ENV_FILE: '.env' }, { SIGNVOICE_ENV_FILE: undefined },
  ])('refuses the wrong process selection %j before loading config', overrides => {
    const result = probe(overrides);
    expect(result.status).toBe(1);
    expect(result.validations).toBe(0);
    expect(result.imports).toEqual(['node:path']);
  });

  it.each([
    { NODE_ENV: 'development' }, { isProduction: false }, { LISTEN_HOST: '0.0.0.0' },
    { PUBLIC_ORIGIN: 'https://stale.example' },
  ])('refuses unsafe effective configuration %j', effective => {
    expect(probe({}, effective).status).toBe(1);
  });

  it('refuses invalid config without leaking its error or values', () => {
    const result = probe({}, {}, true);
    expect(result.status).toBe(1);
    expect(result.validations).toBe(1);
    expect(result.errors).toBe('Production configuration preflight refused.\n');
  });

  it('runs PowerShell parse and behavioral checks with only virtual env/process fixtures', () => {
    const parse = spawnSync('powershell.exe', ['-NoProfile', '-Command',
      `$ErrorActionPreference='Stop'; Get-ChildItem -LiteralPath '${scripts.replace(/'/g, "''")}' -Filter '*public-server*.ps1' | ForEach-Object { $t=$null; $e=$null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$t,[ref]$e) | Out-Null; if($e.Count) { throw ($e | Out-String) } }`],
    { encoding: 'utf8', timeout: 15000 });
    expect(parse.status, parse.stdout + parse.stderr).toBe(0);
    const checks = spawnSync('powershell.exe', ['-NoProfile', '-File', path.join(scripts, 'test-public-server-launcher.ps1')],
      { encoding: 'utf8', timeout: 30000 });
    expect(checks.status, checks.stdout + checks.stderr).toBe(0);
    expect(checks.stdout).toContain('27 launcher checks passed');
  });
});
