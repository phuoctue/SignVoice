import { createHmac } from 'crypto';
import { OAuth2Client } from 'google-auth-library';
import { oauthConfig, OAuthProvider } from '../config/oauth';
import { AppError } from '../common/errors/AppError';

export interface ProviderIdentity { subject: string; email?: string; displayName: string }
type Config = ReturnType<typeof oauthConfig>;
async function json(url: string, init: RequestInit = {}): Promise<any> {
  const response = await fetch(url, { ...init, signal: AbortSignal.timeout(15000), redirect: 'error' });
  if (!response.ok) throw new Error('Provider refused request');
  const body: any = await response.json();
  if (!body || typeof body !== 'object' || body.error) throw new Error('Invalid provider response');
  return body;
}
function validEmail(value: unknown): value is string {
  return typeof value === 'string' && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}
// Exported only to allow tests to replace external cryptographic/network boundaries.
export const googleVerifier = new OAuth2Client();
export async function verifyGoogleIdentity(idToken: string, clientId: string, nonce: string): Promise<ProviderIdentity> {
  try {
    const ticket = await googleVerifier.verifyIdToken({idToken, audience: clientId});
    const p = ticket.getPayload();
    if (!p || p.aud !== clientId || !['accounts.google.com', 'https://accounts.google.com'].includes(p.iss) ||
        !Number.isFinite(p.exp) || p.exp <= Date.now()/1000 || typeof p.sub !== 'string' || !p.sub || p.sub.length > 255 ||
        (p as typeof p & {nonce?: string}).nonce !== nonce || p.email_verified !== true || !validEmail(p.email)) throw new Error('Invalid identity');
    return {subject:p.sub,email:p.email.toLowerCase(),displayName:typeof p.name === 'string' ? p.name : 'Google User'};
  } catch {
    throw new AppError('Không xác minh được tài khoản Google. Vui lòng thử lại.',401,'OAUTH_IDENTITY_INVALID');
  }
}
export async function exchangeIdentity(provider: OAuthProvider, config: Config, code: string,
  nonce: string, verifier: string): Promise<ProviderIdentity> {
  try {
    if (provider === 'google') {
      const token = await json('https://oauth2.googleapis.com/token', { method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ code, client_id: config.clientId, client_secret: config.clientSecret,
          redirect_uri: config.callback, grant_type: 'authorization_code', code_verifier: verifier }) });
      if (typeof token.id_token !== 'string') throw new Error('Missing ID token');
      return await verifyGoogleIdentity(token.id_token, config.clientId, nonce);
    }
    const graph = `https://graph.facebook.com/${config.graphVersion}`;
    const token = await json(`${graph}/oauth/access_token`, { method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ code, client_id: config.clientId, client_secret: config.clientSecret, redirect_uri: config.callback }) });
    if (typeof token.access_token !== 'string' || token.token_type?.toLowerCase() !== 'bearer') throw new Error('Missing access token');
    const debugUrl = new URL(`${graph}/debug_token`);
    debugUrl.searchParams.set('input_token', token.access_token);
    const debug = await json(debugUrl.href, { headers: { Authorization: `Bearer ${config.clientId}|${config.clientSecret}` } });
    const p = debug.data;
    if (!p || p.is_valid !== true || p.app_id !== config.clientId || typeof p.user_id !== 'string' || !p.user_id ||
        !Number.isFinite(p.expires_at) || p.expires_at <= Date.now() / 1000 ||
        !Number.isFinite(p.data_access_expires_at) || p.data_access_expires_at <= Date.now() / 1000 ||
        p.type !== 'USER') throw new Error('Invalid access token');
    const profileUrl = new URL(`${graph}/me`);
    profileUrl.searchParams.set('fields', 'id,name,email');
    profileUrl.searchParams.set('appsecret_proof', createHmac('sha256', config.clientSecret).update(token.access_token).digest('hex'));
    const profile = await json(profileUrl.href, { headers: { Authorization: `Bearer ${token.access_token}` } });
    if (profile.id !== p.user_id || p.user_id.length > 255) throw new Error('User identity mismatch');
    return { subject: p.user_id, email: validEmail(profile.email) ? profile.email.toLowerCase() : undefined,
      displayName: typeof profile.name === 'string' ? profile.name : 'Facebook User' };
  } catch {
    // Never expose provider responses, codes, tokens or secrets through application errors/logging.
    throw new AppError('Không xác minh được danh tính OAuth. Vui lòng đăng nhập lại.', 401, 'OAUTH_IDENTITY_INVALID');
  }
}
