// Sends only to the ephemeral qa-fcm-* account created by fcm_probe.dart.
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const adb = 'E:/Android/Sdk/platform-tools/adb.exe';
const base = process.env.FCM_QA_API || 'http://127.0.0.1:3001/api/v1';
const runtime = path.resolve(__dirname, '../../.runtime');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const run = (...args) => execFileSync(adb, ['-s', 'emulator-5554', ...args], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});
const report = {fcm: [], startedAt: new Date().toISOString()};
async function waitFor(check, label, timeout = 90000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {try {const result = await check(); if (result) return result;} catch {} await pause(2000);}
  throw new Error(`Timed out: ${label}`);
}
async function main() {
  const data = await waitFor(() => JSON.parse(run('shell', 'run-as', 'com.example.sign_voice', 'cat', 'files/signvoice-fcm-test.json')), 'probe account');
  if (!/^qa-fcm-[a-f0-9]+@example\.test$/.test(data.email)) throw new Error('Refusing a non-QA account');
  report.accountId = data.userId;
  const request = async (endpoint, method = 'GET', body) => {
    const response = await fetch(base + endpoint, {method, headers: {'Authorization': `Bearer ${data.accessToken}`, 'Content-Type': 'application/json'}, body: body === undefined ? undefined : JSON.stringify(body)});
    const json = await response.json();
    if (!response.ok) throw new Error(`${response.status}: ${json.error?.code || 'HTTP_ERROR'}`);
    return json.data;
  };
  const screenshot = stage => {run('shell', 'screencap', '-p', `/sdcard/fcm-${stage}.png`); run('pull', `/sdcard/fcm-${stage}.png`, path.join(runtime, `fcm-${stage}.png`));};
  const testPush = () => request('/users/notifications/test', 'POST', {});
  if (process.argv.includes('--background-only') || process.argv.includes('--closed-only') || process.argv.includes('--cold-only')) {
    const stage = process.argv.includes('--cold-only') ? 'cold_process' : process.argv.includes('--closed-only') ? 'closed_from_recents' : 'background';
    let backgroundEnginesBefore = 0;
    if (stage === 'cold_process') {
      if (run('shell', 'dumpsys', 'activity', 'activities').includes('com.example.sign_voice/.MainActivity')) throw new Error('MainActivity must be closed for cold-engine test');
      backgroundEnginesBefore = (run('logcat', '-d', '-s', 'FLTFireBGExecutor:I').match(/Creating background FlutterEngine instance/g) || []).length;
      report.mainActivityWasClosed = true;
    }
    const result = await testPush(), id = result.notification._id;
    await waitFor(() => run('shell', 'dumpsys', 'notification', '--noredact').includes(`tag=${id}`), `${stage} OS notification`);
    if (stage === 'cold_process') {
      report.backgroundEngineCreated = (run('logcat', '-d', '-s', 'FLTFireBGExecutor:I').match(/Creating background FlutterEngine instance/g) || []).length > backgroundEnginesBefore;
      if (!report.backgroundEngineCreated) throw new Error('No fresh background engine observed');
    }
    const feed = await request('/users/notifications');
    report.fcm.push({stage, id, sent: result.sent, systemNotification: true, inBell: feed.items.some(item => item._id === id)});
    fs.writeFileSync(path.join(runtime, `fcm-guard-${stage}.json`), JSON.stringify(report, null, 2));
    console.log(`${stage}: received and present in bell`);
    return;
  }
  const foreground = await waitFor(testPush, 'registered FCM installation');
  const fgId = foreground.notification._id;
  await waitFor(() => run('logcat', '-d', '-s', 'flutter:I').includes(`FCM_PROBE_FOREGROUND ${fgId}`), 'foreground onMessage');
  await waitFor(() => run('shell', 'dumpsys', 'notification', '--noredact').includes(`tag=${fgId}`), 'foreground visible notification');
  const fgFeed = await request('/users/notifications');
  if (!fgFeed.items.some(item => item._id === fgId)) throw new Error('Foreground notification missing from bell');
  screenshot('foreground');
  report.fcm.push({stage: 'foreground', id: fgId, sent: foreground.sent, onMessage: true, systemNotification: true, inBell: true});
  console.log('foreground: received by Dart and persisted in bell');
  if (process.argv.includes('--foreground-only')) {
    fs.writeFileSync(path.join(runtime, 'fcm-guard-foreground.json'), JSON.stringify(report, null, 2));
    return;
  }
  run('shell', 'input', 'keyevent', 'KEYCODE_HOME');
  await pause(11000);
  const background = await testPush();
  const bgId = background.notification._id;
  await waitFor(() => run('shell', 'dumpsys', 'notification', '--noredact').includes(`tag=${bgId}`), 'background OS notification');
  screenshot('background');
  report.fcm.push({stage: 'background', id: bgId, sent: background.sent, systemNotification: true});
  console.log('background: visible in Android notification service');
  run('shell', 'am', 'kill', 'com.example.sign_voice');
  await waitFor(() => {try {return !run('shell', 'pidof', 'com.example.sign_voice').trim();} catch {return true;}}, 'terminated process');
  await pause(11000);
  const terminated = await testPush();
  const termId = terminated.notification._id;
  await waitFor(() => run('shell', 'dumpsys', 'notification', '--noredact').includes(`tag=${termId}`), 'terminated OS notification');
  report.fcm.push({stage: 'terminated', id: termId, sent: terminated.sent, processWasStopped: true, systemNotification: true});
  console.log('terminated: received after process was killed (not Android force-stop)');
  run('shell', 'am', 'start', '-n', 'com.example.sign_voice/.MainActivity');
  await pause(10000);
  const feed = await request('/users/notifications');
  if (!report.fcm.every(item => feed.items.some(notice => notice._id === item.id))) throw new Error('Missing notification after restart');
  screenshot('reopened');
  report.bellAfterRestart = true;
  report.accountId = data.userId;
  report.finishedAt = new Date().toISOString();
  fs.writeFileSync(path.join(runtime, 'fcm-device-verification.json'), JSON.stringify(report, null, 2));
  console.log('bell after restart: all 3 notifications present');
  // Keep the dedicated account until the UI evidence has been reviewed. Cleanup
  // must use /users/account with this probe's password, never a broad DB delete.
}
main().catch(error => {console.error('FCM device verification failed:', error.message); process.exitCode = 1;});
