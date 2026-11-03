import {Express} from 'express';
import {env} from './config/env';

export function servePasswordResetLinks(app: Express) {
  app.get('/.well-known/assetlinks.json', (_req, res) => {
    const fingerprints = (process.env.ANDROID_APP_LINK_SHA256 || '').split(',').map(x => x.trim()).filter(Boolean);
    const packageName = process.env.ANDROID_APP_LINK_PACKAGE || 'com.example.sign_voice';
    if (!fingerprints.length || fingerprints.some(x => !/^(?:[A-Fa-f0-9]{2}:){31}[A-Fa-f0-9]{2}$/.test(x)) || !/^[a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)+$/.test(packageName)) {
      return res.status(404).json({error: 'App Links not configured'});
    }
    return res.json([{relation: ['delegate_permission/common.handle_all_urls'], target: {
      namespace: 'android_app', package_name: packageName, sha256_cert_fingerprints: fingerprints,
    }}]);
  });
  app.get('/auth/reset-password', (_req, res) => {
    // The token stays in the fragment and is never sent to this HTTP endpoint.
    const origin = JSON.stringify(new URL(env.PASSWORD_RESET_ORIGIN).origin).replace(/</g, '\\u003c');
    res.set({'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer'}).type('html').send(`<!doctype html>
<html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Đặt lại mật khẩu SignVoice</title>
<style>body{font:18px/1.6 system-ui;max-width:560px;margin:10vh auto;padding:24px;color:#0f172a}a{display:block;padding:16px;margin:16px 0;border:2px solid #2563eb;border-radius:16px;text-align:center;color:#1d4ed8}a:focus-visible{outline:3px solid #0f172a;outline-offset:4px}</style>
<h1>Đặt lại mật khẩu SignVoice</h1><p id="message">Chọn mở ứng dụng Android hoặc tiếp tục bằng trình duyệt.</p>
<a id="app" hidden>Mở trong ứng dụng SignVoice</a><a id="web" hidden>Tiếp tục trên trình duyệt</a>
<noscript>Bật JavaScript để mở liên kết đặt lại mật khẩu.</noscript>
<script>
const match=/^#token=([a-f0-9]{64})$/.exec(location.hash);
if(match){const token=match[1],web=${origin}+'/#/reset-password?token='+token;
const a=document.getElementById('app'),w=document.getElementById('web');
a.href='intent://reset-password?token='+token+'#Intent;scheme=signvoice;package=com.example.sign_voice;S.browser_fallback_url='+encodeURIComponent(web)+';end';
w.href=web;a.hidden=false;w.hidden=false;
if(!/Android/i.test(navigator.userAgent))location.replace(web);
}else{document.getElementById('message').textContent='Liên kết không hợp lệ. Vui lòng yêu cầu email mới.';}
</script></html>`);
  });
}
