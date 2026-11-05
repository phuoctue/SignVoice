// Merge only integration configuration. Database, JWT and test accounts stay isolated.
const fs = require('node:fs');
const path = require('node:path');
const dotenv = require('dotenv');
const root = path.resolve(__dirname, '../..');
const target = path.join(root, 'backend/.env.test');
const current = fs.readFileSync(target, 'utf8');
const test = dotenv.parse(current);
if (new URL(test.MONGODB_URI).pathname !== '/signvoice_test') throw Error('Expected signvoice_test');
const source = dotenv.parse(fs.readFileSync(path.join(root, 'backend/.env'), 'utf8'));
const updates = {};
for (const key of ['SMTP_HOST', 'SMTP_PORT', 'SMTP_SECURE', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM', 'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET']) {
  if (!test[key] && source[key]) updates[key] = source[key];
}
Object.assign(updates, {
  OAUTH_BACKEND_ORIGIN: 'http://localhost:3003', OAUTH_FRONTEND_ORIGIN: 'http://localhost:3003',
  GOOGLE_CALLBACK_URL: 'http://localhost:3003/api/v1/auth/oauth/google/callback',
  PASSWORD_RESET_ORIGIN: 'http://localhost:3003',
});
const testCredential = path.join(root, '.runtime/testing/firebase-service-account.json');
const credential = fs.existsSync(testCredential) ? testCredential : source.GOOGLE_APPLICATION_CREDENTIALS;
if (credential && fs.existsSync(credential)) {
  const account = JSON.parse(fs.readFileSync(credential, 'utf8'));
  const android = JSON.parse(fs.readFileSync(path.join(root, 'android/app/google-services.json'), 'utf8'));
  if (account.type !== 'service_account' || account.project_id !== android.project_info.project_id) throw Error('Firebase project mismatch with Android app');
  if (!test.GOOGLE_APPLICATION_CREDENTIALS) updates.GOOGLE_APPLICATION_CREDENTIALS = path.resolve(credential);
  if (!test.FIREBASE_PROJECT_ID) updates.FIREBASE_PROJECT_ID = account.project_id;
}
let next = current;
for (const [key, value] of Object.entries(updates)) {
  const line = key + '=' + JSON.stringify(value);
  const pattern = new RegExp('^' + key + '=.*$', 'm');
  next = pattern.test(next) ? next.replace(pattern, () => line) : next.trimEnd() + '\n' + line + '\n';
}
if (!process.argv.includes('--apply')) {
  console.log('Ready to configure test integrations: ' + Object.keys(updates).join(', '));
  console.log('Use --apply. No secrets printed.');
} else {
  fs.mkdirSync(path.join(root, '.runtime/testing'), {recursive: true});
  const backup = path.join(root, '.runtime/testing/env-before-integrations-' + Date.now() + '.bak');
  fs.writeFileSync(backup, current);
  fs.writeFileSync(target, next);
  console.log('Test integration configuration updated; previous configuration backed up locally.');
  console.log('Firebase service account: ' + (credential && fs.existsSync(credential) ? 'found' : 'missing; not enabled'));
}
