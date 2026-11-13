import { randomBytes, createHash } from 'crypto';
import { OAuthState } from '../models/OAuthState.model';
import { oauthConfig, OAuthProvider } from '../config/oauth';
import { AppError } from '../common/errors/AppError';
import { User, IUser, AccountType } from '../models/User.model';
import { ProviderIdentity } from './oauth-provider.service';

const random = () => randomBytes(32).toString('base64url');
export const digest = (value: string) => createHash('sha256').update(value).digest('hex');
export async function beginOAuth(provider: OAuthProvider, config: ReturnType<typeof oauthConfig>) {
  const state = random(), browser = random(), nonce = random(), verifier = random();
  await OAuthState.create({ stateHash: digest(state), browserHash: digest(browser), provider,
    callback: config.callback, completion: config.completion, nonce, verifier,
    expiresAt: new Date(Date.now() + config.ttl * 1000) });
  const url = new URL(provider === 'google' ? 'https://accounts.google.com/o/oauth2/v2/auth' :
    `https://www.facebook.com/${config.graphVersion}/dialog/oauth`);
  for (const [key, value] of Object.entries({ client_id: config.clientId, redirect_uri: config.callback,
    response_type: 'code', scope: provider === 'google' ? 'openid email profile' : 'public_profile,email', state })) url.searchParams.set(key, value);
  if (provider === 'google') {
    url.searchParams.set('nonce', nonce);
    url.searchParams.set('code_challenge', createHash('sha256').update(verifier).digest('base64url'));
    url.searchParams.set('code_challenge_method', 'S256');
  }
  return { state, browser, url: url.href };
}
export async function consumeState(provider: OAuthProvider, config: ReturnType<typeof oauthConfig>, state: unknown, browser: unknown) {
  if (typeof state !== 'string' || !/^[\w-]{43}$/.test(state) || typeof browser !== 'string' || !/^[\w-]{43}$/.test(browser))
    throw new AppError('Phiên OAuth không hợp lệ hoặc đã hết hạn.', 400, 'OAUTH_STATE_INVALID');
  const record = await OAuthState.findOneAndDelete({ stateHash: digest(state), browserHash: digest(browser), provider,
    callback: config.callback, completion: config.completion, expiresAt: { $gt: new Date() } });
  if (!record) throw new AppError('Phiên OAuth không hợp lệ hoặc đã hết hạn.', 400, 'OAUTH_STATE_INVALID');
  return record;
}
export async function resolveOAuthUser(provider: OAuthProvider, identity: ProviderIdentity) {
  // Refuse OAuth writes until unique identity/email indexes have actually been created.
  await User.init();
  const field = provider === 'google' ? 'googleProvider' : 'facebookProvider';
  let user = await User.findOne<IUser>({ [`${field}.providerId`]: identity.subject }).select('+sessionRevocationEpoch');
  if (user) return user;
  if (identity.email && await User.exists({ email: identity.email }))
    throw new AppError('Email đã có tài khoản. Hãy đăng nhập bằng phương thức đã đăng ký; liên kết tài khoản cần xác minh riêng.', 409, 'OAUTH_ACCOUNT_COLLISION');
  try {
    const name = identity.displayName.trim().slice(0, 50);
    user = await User.create({ email: identity.email, displayName: name.length >= 2 ? name : `${provider} User`,
      accountType: provider === 'google' ? AccountType.GOOGLE : AccountType.FACEBOOK,
      isGuest: false, sessionRevocationEpoch: 0, [field]: { providerId: identity.subject } });
  } catch (error) {
    if ((error as { code?: number }).code !== 11000) throw error;
    // Concurrent first login: only the unique provider subject may identify the winner.
    user = await User.findOne<IUser>({ [`${field}.providerId`]: identity.subject }).select('+sessionRevocationEpoch');
    if (!user) throw new AppError('Email đã có tài khoản.', 409, 'OAUTH_ACCOUNT_COLLISION');
  }
  return user;
}
