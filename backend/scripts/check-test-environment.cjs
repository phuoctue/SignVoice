const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const origin = 'http://localhost:3003';
async function api(route, {token, body, method} = {}) {
  const response = await fetch(origin + '/api/v1' + route, {
    method: method || (body ? 'POST' : 'GET'),
    headers: {'Content-Type': 'application/json', ...(token ? {Authorization: 'Bearer ' + token} : {})},
    body: body ? JSON.stringify(body) : undefined,
  });
  return {status: response.status, body: await response.json()};
}
(async () => {
  const ready = await (await fetch(origin + '/health/ready')).json();
  assert.equal(ready.data.database.name, 'signvoice_test');
  console.log('PASS isolated test database');
  const served = Buffer.from(await (await fetch(origin + '/main.dart.js')).arrayBuffer());
  const digest = value => crypto.createHash('sha256').update(value).digest('hex');
  assert.equal(digest(served), digest(fs.readFileSync(path.join(root, 'build/web/main.dart.js'))));
  console.log('PASS current Web build');
  const dictionary = await api('/dictionary?limit=1');
  assert.equal(dictionary.status, 200);
  assert.equal((await api('/shared-collections')).status, 200);
  console.log('PASS public dictionary and collections');
  const accounts = JSON.parse(fs.readFileSync(path.join(root, '.runtime/testing/accounts.json'), 'utf8'));
  for (const account of accounts) {
    const login = await api('/auth/login', {body: {email: account.email, password: account.password}});
    assert.equal(login.status, 200, account.role + ' login');
    assert.equal(login.body.data.user.role, account.role);
    assert.equal((await api('/auth/logout', {token: login.body.data.tokens.accessToken, method: 'POST'})).status, 200);
    console.log('PASS ' + account.role + ' login/logout');
  }
  const deviceKey = crypto.randomBytes(32).toString('hex');
  for (let index = 0; index < 2; index++) {
    const guest = await api('/auth/guest', {body: {deviceKey, newGuest: true}});
    assert.equal(guest.status, 201);
    const token = guest.body.data.tokens.accessToken;
    const status = await api('/guest-trial/status', {token});
    assert.ok(status.body.data.remainingSeconds > 580);
    assert.equal((await api('/auth/logout', {token, method: 'POST'})).status, 200);
    assert.equal((await api('/auth/me', {token})).status, 401);
  }
  console.log('PASS fresh guest allowance and revoked access after logout');
  assert.equal((await (await fetch(origin + '/sign-ai/health')).json()).ready, true);
  console.log('PASS AI proxy');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
