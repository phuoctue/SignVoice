const {randomUUID, randomBytes} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const local = 'http://127.0.0.1:3001/api/v1';
const origin = process.env.STARTUP_PUBLIC_ORIGIN || 'https://differentshinyleaf12.conveyor.cloud';
const password = `Startup!${randomBytes(20).toString('hex')}`;
let token;
async function request(base, endpoint, method = 'GET', body) {
  const start = performance.now();
  const response = await fetch(base + endpoint, {method, headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(30000)});
  const text = await response.text();
  if (!response.ok) throw new Error(`${method} ${endpoint}: ${response.status}`);
  return {ms: +(performance.now() - start).toFixed(1), bytes: Buffer.byteLength(text), json: JSON.parse(text)};
}
async function main() {
  try {
    const account = await request(local, '/auth/register', 'POST', {email: `qa-startup-${randomUUID()}@example.test`, password, displayName: 'Kiểm thử khởi động'});
    token = account.json.data.tokens.accessToken;
    const report = {origin, measuredAt: new Date().toISOString(), legacy: [], bootstrap: []};
    for (let i = 0; i < 3; i++) {
      for (const mode of i % 2 ? ['bootstrap', 'legacy'] : ['legacy', 'bootstrap']) {
        const start = performance.now();
        await request(origin + '/api/v1', '/auth/me');
        if (mode === 'legacy') {
          await Promise.all(['/users/profile', '/users/settings', '/conversations', '/favorites?limit=100&skip=0'].map(endpoint => request(origin + '/api/v1', endpoint)));
        } else await request(origin + '/api/v1', '/users/bootstrap');
        report[mode].push(+(performance.now() - start).toFixed(1));
      }
    }
    report.requestsUntilAccountReady = {legacy: 5, bootstrap: 2};
    report.medianMs = Object.fromEntries(['legacy', 'bootstrap'].map(mode => [mode, [...report[mode]].sort((a, b) => a - b)[1]]));
    fs.writeFileSync(path.resolve(__dirname, '../../.runtime/startup-api-comparison.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  } finally {
    if (token) {await request(local, '/users/account', 'DELETE', {confirm: true, currentPassword: password}); console.log('Temporary startup account removed.');}
  }
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
