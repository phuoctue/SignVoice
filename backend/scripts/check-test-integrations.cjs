const fs = require('node:fs');
const path = require('node:path');
const dotenv = require('dotenv');
const envPath = path.resolve(__dirname, '../.env.test');
const config = dotenv.parse(fs.readFileSync(envPath));
if (new URL(config.MONGODB_URI).pathname !== '/signvoice_test') throw Error('Expected signvoice_test');
Object.assign(process.env, config, {SIGNVOICE_ENV_FILE: envPath, NODE_ENV: 'test'});
require('tsx/cjs');
(async () => {
  const {createMailTransport} = require('../src/services/mail.service.ts');
  const transport = createMailTransport();
  try {
    await transport.verify();
    console.log('PASS SMTP connection and authentication');
    if (process.argv.includes('--send-self')) {
      const sent = await transport.sendMail({from: config.SMTP_FROM || config.SMTP_USER, to: config.SMTP_USER,
        subject: '[SignVoice TEST] Kiểm tra SMTP',
        text: 'Email kiểm tra từ môi trường signvoice_test. Mở http://localhost:3003/#/login để thử khôi phục mật khẩu. Đây không phải email đặt lại mật khẩu.'});
      console.log('SMTP self-test accepted recipients: ' + sent.accepted.length);
    }
  } finally { transport.close(); }
  console.log('Google Web callback: ' + config.GOOGLE_CALLBACK_URL);
  console.log('Google credentials present: ' + Boolean(config.GOOGLE_CLIENT_ID && config.GOOGLE_CLIENT_SECRET));
  console.log('Firebase credential file exists: ' + Boolean(config.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(config.GOOGLE_APPLICATION_CREDENTIALS)));
})().catch(error => {console.error('Integration check failed: ' + (error.code || error.name));process.exitCode = 1;});
