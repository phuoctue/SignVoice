import 'dotenv/config';
import {GoogleAuth} from 'google-auth-library';

async function main() {
  if (!process.env.FIREBASE_PROJECT_ID || !process.env.GOOGLE_APPLICATION_CREDENTIALS) throw new Error('Missing Firebase server configuration');
  const auth = new GoogleAuth({keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging']});
  const client = await auth.getClient();
  await client.request({url: `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(process.env.FIREBASE_PROJECT_ID)}/messages:send`, method: 'POST',
    data: {validate_only: true, message: {topic: 'signvoice-configuration-check', notification: {title: 'Configuration check', body: 'Validation only'}}}, timeout: 20000});
  console.log(`Firebase ${process.env.FIREBASE_PROJECT_ID}: FCM HTTP v1 validation passed; no notification sent.`);
}
main().catch((error: any) => {
  // Never print the GoogleAuth request object: it can contain an access token.
  console.error('Firebase validation failed:', error?.response?.data?.error?.status || error?.code || 'CONFIGURATION_ERROR');
  console.error(error?.response?.data?.error?.message || 'Check credentials and network.');
  process.exitCode = 1;
});
