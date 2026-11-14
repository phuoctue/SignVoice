import mongoose, { Types, ClientSession } from 'mongoose';
import { User, IUser, AccountType, AccountStatus, UserRole } from '../models/User.model';
import { AuthSession, SessionType, SessionStatus } from '../models/AuthSession.model';
import { UserSettings } from '../models/UserSettings.model';
import { AuditLog, AuditAction, AuditSeverity } from '../models/AuditLog.model';
import { hashPassword, verifyPassword } from '../utils/password.util';
import { generateTokenPair, hashToken, verifyAccessToken, verifyRefreshToken, ITokenPair } from '../utils/jwt.util';
import {NotificationDevice} from '../models/Notification.model';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';
import { authorizationFor } from './authorization.service';
import { assertSessionEpoch, loadSessionUser, sessionEpoch, userEpochFilter } from './session-fence.service';
import { assertChainDeadline, assertSessionChain, chainWriteConcern, createFreshChain, loadChainTransition, revokeSessionChain, tombstoneChain } from './session-chain.service';
import { SessionChain } from '../models/SessionChain.model';
import { authClock } from './auth-clock';
import {GuestTrial} from '../models/GuestTrial.model';
import {assertGuestDataRetained, concurrentGrantConflict, grantTrial, GuestGrantInput} from './guest-trial.service';
import {appendGuestEvent, ensureGuestOutbox} from './guest-lifecycle-outbox.service';
import {discardGuestInTransaction, guestDataVersionFilter, GuestAuthority} from './guest-data.service';
import {retryGuestMediaCleanup} from './guest-media-cleanup.service';

/**
 * Registration data
 */
export interface IRegisterData {
  email: string;
  password: string;
  displayName: string;
}

/**
 * Login data
 */
export interface ILoginData {
  email: string;
  password: string;
}

/**
 * Auth response
 */
export interface IAuthResponse {
  user: {
    id: string;
    email?: string;
    displayName: string;
    avatarUrl?: string;
    role: UserRole;
    isGuest: boolean;
    accountType: AccountType;
    status: AccountStatus;
    createdAt: Date;
    updatedAt: Date;
    permissions: readonly string[];
    customRoleId?: string;
    customRoleName?: string;
  };
  tokens: ITokenPair;
}

/**
 * Request metadata
 */
interface IRequestMeta {
  ipAddress?: string;
  userAgent?: string;
}

/**
 * Register new user with email/password
 */
export async function registerUser(
  data: IRegisterData,
  meta: IRequestMeta = {},
  issueSession = true
): Promise<IAuthResponse> {
  await loadChainTransition();
  // Check if email already exists
  const existing = await User.findOne({ email: data.email.toLowerCase() });

  if (existing) {
    throw new AppError(
      'Email already registered',
      409,
      ErrorCodes.AUTH_EMAIL_ALREADY_EXISTS
    );
  }

  // Hash password
  const passwordHash = await hashPassword(data.password);

  // Create user
  const user = await User.create({
    email: data.email.toLowerCase(),
    displayName: data.displayName,
    accountType: AccountType.LOCAL,
    passwordHash,
    sessionRevocationEpoch: 0,
    role: UserRole.USER,
    isGuest: false,
    lastLoginAt: issueSession ? new Date() : undefined,
    lastLoginIp: issueSession ? meta.ipAddress : undefined,
  });

  // Create default settings
  await UserSettings.create({ userId: user._id });

  // Generate tokens
  const tokens = generateTokenPair(user._id, user.role);

  // Create auth session
  if (issueSession) {
    await persistFreshPair(user, tokens, meta);
  }

  // Audit log
  await AuditLog.log({
    userId: user._id,
    actorRole: user.role,
    action: AuditAction.USER_REGISTER,
    severity: AuditSeverity.INFO,
    resourceType: 'User',
    resourceId: user._id,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  return {
    user: {
      id: user._id.toString(),
      email: user.email,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      isGuest: user.isGuest,
      accountType: user.accountType,
      status: user.status,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      ...await authorizationFor(user),
    },
    tokens,
  };
}

/**
 * Login user with email/password
 */
export async function loginUser(
  data: ILoginData,
  meta: IRequestMeta = {}
): Promise<IAuthResponse> {
  await loadChainTransition();
  // Find user (include passwordHash)
  const user = await User.findOne({ email: data.email.toLowerCase() }).select('+passwordHash +sessionRevocationEpoch');

  if (!user) {
    // Audit failed login attempt
    await AuditLog.log({
      action: AuditAction.USER_LOGIN,
      severity: AuditSeverity.WARNING,
      success: false,
      errorMessage: `Login failed for email: ${data.email}`,
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    throw new AppError(
      'Invalid credentials',
      401,
      ErrorCodes.AUTH_INVALID_CREDENTIALS
    );
  }

  // Check if account is active
  if (!user.isActive()) {
    throw new AppError(
      'Account is suspended or deleted',
      403,
      ErrorCodes.USER_DISABLED
    );
  }

  // Verify password
  if (!user.passwordHash) {
    throw new AppError(
      'Password not set for this account',
      400,
      ErrorCodes.BAD_REQUEST
    );
  }

  const isValidPassword = await verifyPassword(user.passwordHash, data.password);

  if (!isValidPassword) {
    // Audit failed login
    await AuditLog.log({
      userId: user._id,
      actorRole: user.role,
      action: AuditAction.USER_LOGIN,
      severity: AuditSeverity.WARNING,
      success: false,
      errorMessage: 'Invalid password',
      ipAddress: meta.ipAddress,
      userAgent: meta.userAgent,
    });

    throw new AppError(
      'Invalid credentials',
      401,
      ErrorCodes.AUTH_INVALID_CREDENTIALS
    );
  }

  // Update last login
  user.lastLoginAt = new Date();
  user.lastLoginIp = meta.ipAddress;
  await User.updateOne({ _id: user._id }, {
    $set: { lastLoginAt: user.lastLoginAt, lastLoginIp: user.lastLoginIp },
    ...(user.lastLoginIp === undefined ? { $unset: { lastLoginIp: 1 } } : {}),
  });
  user.updatedAt = new Date();

  // Generate tokens
  const tokens = generateTokenPair(user._id, user.role);

  // Create auth sessions
  await persistFreshPair(user, tokens, meta);

  // Audit successful login
  await AuditLog.log({
    userId: user._id,
    actorRole: user.role,
    action: AuditAction.USER_LOGIN,
    severity: AuditSeverity.INFO,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  return {
    user: {
      id: user._id.toString(),
      email: user.email,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      isGuest: user.isGuest,
      accountType: user.accountType,
      status: user.status,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      ...await authorizationFor(user),
    },
    tokens,
  };
}

/**
 * Create guest account
 */
export async function grantGuestAccount(meta: IRequestMeta, input: GuestGrantInput,
  replacement?: {authority: GuestAuthority; expectedDataVersion: number}): Promise<IAuthResponse> {
  await GuestTrial.init();
  await ensureGuestOutbox();
  try {
    const result = await mongoose.connection.transaction(async transaction => {
      const finalDiscardFence = replacement ? await discardGuestInTransaction(replacement.authority, replacement.expectedDataVersion, transaction, true) : undefined;
      const trial = await grantTrial(input, transaction);
      const result = await createGuestAccount(meta, trial._id, transaction, trial.startedAt);
      await appendGuestEvent('GRANTED', {deviceHash: trial.deviceHash, lastGrantedAt: trial.startedAt!.toISOString(),
        guestUserId: result.user.id, requestHash: trial.lastGrantRequestHash!}, transaction);
      await finalDiscardFence?.();
      return result;
    }, {writeConcern: chainWriteConcern});
    if (replacement) await retryGuestMediaCleanup(String(replacement.authority.userId));
    return result;
  } catch (error) {
    // Concurrent first inserts can hit the unique device index before Mongo retries.
    if ((error as {code?: number; keyPattern?: {deviceHash?: number}}).code === 11000 &&
        (error as {keyPattern?: {deviceHash?: number}}).keyPattern?.deviceHash) return concurrentGrantConflict(input);
    throw error;
  }
}
export async function createGuestAccount(meta: IRequestMeta = {}, guestTrialId?: Types.ObjectId,
  transaction?: ClientSession, guestGrantedAt?: Date): Promise<IAuthResponse> {
  await loadChainTransition();
  // Generate random display name
  const displayName = `Guest_${Date.now().toString(36)}`;

  // Create guest user
  const [user] = await User.create([{
    displayName,
    accountType: AccountType.GUEST,
    sessionRevocationEpoch: 0,
    guestTrialId,
    guestGrantedAt,
    role: UserRole.USER,
    isGuest: true,
    lastLoginAt: new Date(),
    lastLoginIp: meta.ipAddress,
  }], {session: transaction});

  // Create default settings
  await UserSettings.create([{ userId: user._id }], {session: transaction});

  // Generate tokens
  const tokens = generateTokenPair(user._id, user.role);

  // Create auth sessions
  await persistFreshPair(user, tokens, meta, transaction);

  // Audit log
  await AuditLog.create([{
    userId: user._id,
    actorRole: user.role,
    action: AuditAction.USER_REGISTER,
    severity: AuditSeverity.INFO,
    resourceType: 'User',
    resourceId: user._id,
    details: { accountType: 'GUEST' },
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  }], {session: transaction});

  return {
    user: {
      id: user._id.toString(),
      displayName: user.displayName,
      isGuest: true,
      accountType: user.accountType,
      status: user.status,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      ...await authorizationFor(user),
    },
    tokens,
  };
}

/**
 * Convert guest account to permanent account
 */
export async function convertGuestToPermanent(
  userId: Types.ObjectId,
  data: IRegisterData,
  meta: IRequestMeta = {},
  issueSession = true,
  callerSessionId?: Types.ObjectId
): Promise<IAuthResponse> {
  // Find guest user
  const user = await User.findById(userId).select('+sessionRevocationEpoch +dataVersion');
  await assertGuestDataRetained(userId);

  if (!user) {
    throw new AppError('User not found', 404, ErrorCodes.USER_NOT_FOUND);
  }
  const expectedDataVersion = user.dataVersion;

  if (!user.canConvertFromGuest()) {
    throw new AppError(
      'Account cannot be converted',
      400,
      ErrorCodes.BAD_REQUEST
    );
  }

  // Check if email already exists
  const existing = await User.findOne({ email: data.email.toLowerCase() });

  if (existing) {
    throw new AppError(
      'Email already registered',
      409,
      ErrorCodes.AUTH_EMAIL_ALREADY_EXISTS
    );
  }

  // Hash password
  const passwordHash = await hashPassword(data.password);
  if (!callerSessionId) throw new AppError('Current session required', 401, ErrorCodes.AUTH_SESSION_INVALID);
  const caller = await AuthSession.findOne({_id: callerSessionId, userId});
  if (!caller?.isValid()) throw new AppError('Session not found or expired', 401, ErrorCodes.AUTH_SESSION_INVALID);
  const epoch = sessionEpoch(caller.userEpoch);
  if (epoch === Number.MAX_SAFE_INTEGER) throw new Error('Session revocation epoch exhausted');
  // Pin authority before transaction retries; never adopt a later epoch as authority.
  assertSessionEpoch(caller, user);
  await ensureGuestOutbox();
  let tokens = generateTokenPair(user._id, user.role);
  user.email = data.email.toLowerCase();
  user.displayName = data.displayName;
  user.passwordHash = passwordHash;
  user.accountType = AccountType.LOCAL;
  user.isGuest = false;
  user.guestConvertedAt = authClock.now();
  try { await mongoose.connection.transaction(async transaction => {
    const current = await User.findById(userId).select('+sessionRevocationEpoch +dataVersion').session(transaction);
    const row = await AuthSession.findOne({_id: callerSessionId, userId}).session(transaction);
    if (!current?.isActive() || !current.canConvertFromGuest() || !row?.isValid() ||
        row.passwordVersion !== current.passwordVersion || sessionEpoch(row.userEpoch) !== epoch ||
        row.chainId !== caller.chainId) throw new AppError('Session changed', 401, ErrorCodes.AUTH_SESSION_INVALID);
    assertSessionEpoch(caller, current);
    if (current.dataVersion !== expectedDataVersion) throw new AppError('Guest data changed.', 409, 'GUEST_DATA_CHANGED');
    const {chain: callerChain} = await assertSessionChain(row, transaction);
    const dataState = await assertGuestDataRetained(userId, transaction);
    const guard = await AuthSession.updateOne({_id: row._id, status: SessionStatus.ACTIVE,
      chainId: row.chainId === undefined ? {$exists: false} : row.chainId,
      userEpoch: row.userEpoch === undefined ? {$exists: false} : row.userEpoch},
    {$set: {lastUsedAt: new Date(Math.max(+authClock.now(), +row.lastUsedAt + 1))}}, {session: transaction});
    if (!guard.matchedCount) throw new AppError('Session changed', 401, ErrorCodes.AUTH_SESSION_INVALID);
    const enrolled = await User.updateOne({_id: userId, isGuest: true, status: AccountStatus.ACTIVE,
      guestConvertedAt: {$exists: false}, ...guestDataVersionFilter(expectedDataVersion),
      passwordVersion: caller.passwordVersion, ...userEpochFilter(epoch)}, {$set: {
      email: user.email, displayName: user.displayName, passwordHash: user.passwordHash,
      accountType: user.accountType, isGuest: false, guestConvertedAt: user.guestConvertedAt,
    }, $inc: {sessionRevocationEpoch: 1, dataVersion: 1}}, {session: transaction, runValidators: true});
    if (!enrolled.matchedCount) throw new AppError('Session changed', 401, ErrorCodes.AUTH_SESSION_INVALID);
    const roots = await SessionChain.find({userId, legacyDerived: true}).session(transaction);
    for (const root of roots) await tombstoneChain(userId, root.chainId, transaction);
    await AuthSession.updateMany({userId, status: SessionStatus.ACTIVE,
      $or: [{userEpoch: {$exists: false}}, {userEpoch: {$lt: epoch + 1}}]},
    {$set: {status: SessionStatus.REVOKED, revokedAt: authClock.now()}}, {session: transaction});
    user.sessionRevocationEpoch = epoch + 1;
    if (issueSession) {
      tokens = generateTokenPair(user._id, user.role);
      await persistFreshPair(user, tokens, meta, transaction);
    }
    await appendGuestEvent('CONVERTED', {sameUserId: String(userId), guestGrantedAt: dataState.startedAt?.toISOString() ?? null,
      newEpoch: epoch + 1, convertedAt: user.guestConvertedAt!.toISOString()}, transaction);
    // A separate singleton reread and the final time checkpoint are not snapshot reads.
    const transition = await loadChainTransition();
    if (callerChain) assertChainDeadline(callerChain, transition);
    else if (transition) throw new AppError('Session changed', 401, ErrorCodes.AUTH_SESSION_INVALID);
    // The committed conversion must still be within the original guest data deadline.
    await assertGuestDataRetained(userId);
    if (!row.isValid()) throw new AppError('Session expired', 401, ErrorCodes.AUTH_SESSION_INVALID);
  }, {writeConcern: chainWriteConcern}); }
  catch (error) {
    if ((error as {code?: number; keyPattern?: {email?: number}}).code === 11000 && (error as {keyPattern?: {email?: number}}).keyPattern?.email) {
      throw new AppError('Email already registered', 409, ErrorCodes.AUTH_EMAIL_ALREADY_EXISTS);
    }
    throw error;
  }
  user.updatedAt = authClock.now();

  // Audit log
  await AuditLog.log({
    userId: user._id,
    actorRole: user.role,
    action: AuditAction.GUEST_CONVERT,
    severity: AuditSeverity.INFO,
    resourceType: 'User',
    resourceId: user._id,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  return {
    user: {
      id: user._id.toString(),
      email: user.email,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      isGuest: false,
      accountType: user.accountType,
      status: user.status,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      ...await authorizationFor(user),
    },
    tokens,
  };
}

/**
 * Refresh access token using refresh token
 */
export async function refreshTokens(
  refreshToken: string,
  meta: IRequestMeta = {}
): Promise<ITokenPair> {
  // Verify refresh token
  let payload;
  try {
    payload = verifyRefreshToken(refreshToken);
  } catch (error) {
    throw new AppError(
      'Invalid or expired refresh token',
      401,
      ErrorCodes.AUTH_REFRESH_TOKEN_INVALID
    );
  }

  // Check if session exists
  const tokenHash = hashToken(refreshToken);
  const session = await AuthSession.findOne({
    tokenHash, sessionType: SessionType.REFRESH,
    userId: payload.userId, sessionFamily: payload.sid,
  });

  if (!session || !session.isValid()) {
    throw new AppError(
      'Refresh session not found or expired',
      401,
      ErrorCodes.AUTH_SESSION_INVALID
    );
  }

  // Load user
  const user = await loadSessionUser(payload.userId);

  if (!user || !user.isActive()) {
    throw new AppError(
      'User not found or inactive',
      401,
      ErrorCodes.AUTH_USER_NOT_FOUND
    );
  }
  if (session.passwordVersion !== user.passwordVersion) {
    throw new AppError('Password changed; sign in again', 401, ErrorCodes.AUTH_SESSION_INVALID);
  }
  assertSessionEpoch(session, user);
  await assertSessionChain(session);

  // Claim the refresh token once, including when requests arrive concurrently.
  const claimed = await AuthSession.findOneAndUpdate({
    _id: session._id, status: SessionStatus.ACTIVE, expiresAt: { $gt: authClock.now() },
    userEpoch: session.userEpoch === undefined ? { $exists: false } : session.userEpoch,
    chainId: session.chainId === undefined ? { $exists: false } : session.chainId,
  }, { $set: { status: SessionStatus.REVOKED, revokedAt: new Date() } });
  if (!claimed) {
    throw new AppError('Refresh token already used', 401, ErrorCodes.AUTH_SESSION_INVALID);
  }
  await AuthSession.updateMany({ userId: user._id, sessionFamily: payload.sid }, {
    $set: { status: SessionStatus.REVOKED, revokedAt: new Date() },
  });

  // Generate new tokens
  const tokens = generateTokenPair(user._id, user.role);

  // Create new sessions
  const authenticatedAt = session.authenticatedAt || new Date(0);
  const userEpoch = sessionEpoch(session.userEpoch);
  await createAuthSession(user._id, tokens.accessToken, tokens.accessTokenExpiresAt, meta, session.passwordVersion, authenticatedAt, userEpoch, session.chainId);
  await createAuthSession(user._id, tokens.refreshToken, tokens.refreshTokenExpiresAt, meta, session.passwordVersion, authenticatedAt, userEpoch, session.chainId);
  const currentUser = await loadSessionUser(user._id);
  if (!currentUser?.isActive()) throw new AppError('User not found or inactive', 401, ErrorCodes.AUTH_USER_NOT_FOUND);
  assertSessionEpoch(session, currentUser);
  if (currentUser.passwordVersion !== session.passwordVersion) throw new AppError('Session changed', 401, ErrorCodes.AUTH_SESSION_INVALID);
  await assertSessionChain(session);

  // Audit log
  await AuditLog.log({
    userId: user._id,
    actorRole: user.role,
    action: AuditAction.TOKEN_REFRESH,
    severity: AuditSeverity.INFO,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  await NotificationDevice.updateMany({userId: user._id, sessionFamily: payload.sid}, {$set: {sessionFamily: verifyAccessToken(tokens.accessToken).sid}});

  return tokens;
}

/**
 * Logout user (revoke current session)
 */
export async function logoutUser(
  userId: Types.ObjectId,
  sessionId: Types.ObjectId,
  meta: IRequestMeta = {}
): Promise<void> {
  const session = await AuthSession.findById(sessionId);

  if (session && session.userId.equals(userId)) {
    await revokeSessionChain(session);
  }

  // Audit log
  await AuditLog.log({
    userId,
    action: AuditAction.USER_LOGOUT,
    severity: AuditSeverity.INFO,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });
}

/**
 * Logout from all devices (revoke all sessions)
 */
export async function logoutAllDevices(
  userId: Types.ObjectId,
  sessionId: Types.ObjectId,
  meta: IRequestMeta = {}
): Promise<number> {
  const caller = await AuthSession.findOne({ _id: sessionId, userId });
  if (!caller) throw new AppError('Session not found or expired', 401, ErrorCodes.AUTH_SESSION_INVALID);
  const epoch = sessionEpoch(caller.userEpoch);
  if (epoch === Number.MAX_SAFE_INTEGER) throw new Error('Session revocation epoch exhausted');
  const fence = await User.updateOne({ _id: userId, ...userEpochFilter(epoch) },
    { $inc: { sessionRevocationEpoch: 1 } }, { writeConcern: { w: 'majority', j: true } });
  if (!fence.matchedCount) throw new AppError('Session not found or expired', 401, ErrorCodes.AUTH_SESSION_INVALID);
  const count = await AuthSession.revokeAllForUser(userId, undefined, epoch + 1);

  // Audit log
  await AuditLog.log({
    userId,
    action: AuditAction.SESSION_REVOKE,
    severity: AuditSeverity.INFO,
    details: { revokedCount: count },
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });

  return count;
}

/**
 * Helper: Create auth session
 */
export async function createAuthSession(
  userId: Types.ObjectId,
  token: string,
  expiresAt: Date,
  meta: IRequestMeta,
  passwordVersion = 0,
  authenticatedAt = authClock.now(),
  userEpoch = 0,
  chainId?: string,
  transaction?: ClientSession
): Promise<void> {
  const tokenHash = hashToken(token);
  // Both token types have similar lengths; derive the type from verified claims.
  let payload;
  try {
    payload = verifyAccessToken(token);
  } catch {
    payload = verifyRefreshToken(token);
  }
  const sessionType = payload.sessionType;

  const row = {
    userId,
    authenticatedAt,
    sessionFamily: payload.sid,
    ...(chainId === undefined ? {} : {chainId}),
    passwordVersion,
    userEpoch: sessionEpoch(userEpoch),
    sessionType,
    tokenHash,
    deviceInfo: meta.userAgent,
    ipAddress: meta.ipAddress,
    expiresAt,
    lastUsedAt: authClock.now(),
  };
  if (transaction) await AuthSession.create([row], {session: transaction});
  else await AuthSession.create(row);
}

async function persistFreshPair(user: IUser, tokens: ITokenPair, meta: IRequestMeta, transaction?: ClientSession): Promise<void> {
  const chainId = await createFreshChain(user._id, transaction);
  const epoch = sessionEpoch(user.sessionRevocationEpoch);
  await createAuthSession(user._id, tokens.accessToken, tokens.accessTokenExpiresAt, meta, user.passwordVersion, undefined, epoch, chainId, transaction);
  await createAuthSession(user._id, tokens.refreshToken, tokens.refreshTokenExpiresAt, meta, user.passwordVersion, undefined, epoch, chainId, transaction);
  const current = transaction ? await User.findById(user._id).select('+sessionRevocationEpoch').session(transaction) : await loadSessionUser(user._id);
  if (!current?.isActive() || current.passwordVersion !== user.passwordVersion) throw new AppError('Session changed', 401, ErrorCodes.AUTH_SESSION_INVALID);
  await assertSessionChain({userId: user._id, chainId}, transaction);
}

/** Issue OAuth sessions through the same persisted token/session model as password login. */
export async function loginOAuthUser(user: IUser, meta: IRequestMeta = {}): Promise<IAuthResponse> {
  await loadChainTransition();
  if (!user.isActive()) throw new AppError('Account is suspended or deleted', 403, ErrorCodes.USER_DISABLED);
  await UserSettings.updateOne({ userId: user._id }, { $setOnInsert: { userId: user._id } }, { upsert: true });
  user.lastLoginAt = new Date();
  user.lastLoginIp = meta.ipAddress;
  await User.updateOne({ _id: user._id }, {
    $set: { lastLoginAt: user.lastLoginAt, lastLoginIp: user.lastLoginIp },
    ...(user.lastLoginIp === undefined ? { $unset: { lastLoginIp: 1 } } : {}),
  });
  user.updatedAt = new Date();
  const tokens = generateTokenPair(user._id, user.role);
  await persistFreshPair(user, tokens, meta);
  await AuditLog.log({ userId: user._id, actorRole: user.role, action: AuditAction.USER_LOGIN,
    severity: AuditSeverity.INFO, ipAddress: meta.ipAddress, userAgent: meta.userAgent });
  return { user: { id: user._id.toString(), email: user.email, displayName: user.displayName,
    avatarUrl: user.avatarUrl, isGuest: user.isGuest, accountType: user.accountType,
    status: user.status, createdAt: user.createdAt, updatedAt: user.updatedAt, ...await authorizationFor(user) }, tokens };
}

export async function changePassword(userId: Types.ObjectId, currentPassword: string, newPassword: string): Promise<void> {
  const user = await User.findById(userId).select('+passwordHash');
  if (!user || !user.isActive()) throw new AppError('Account unavailable', 403, ErrorCodes.USER_DISABLED);
  if (user.accountType !== AccountType.LOCAL || !user.passwordHash)
    throw new AppError('Chỉ tài khoản email có thể đổi mật khẩu tại đây.', 400, 'AUTH_PASSWORD_NOT_SUPPORTED');
  if (!await verifyPassword(user.passwordHash, currentPassword))
    // The bearer session is still valid. Failed password proof is form validation,
    // not an expired/invalid session: clients must preserve auth so users can retry.
    throw new AppError('Mật khẩu hiện tại không đúng.', 400, ErrorCodes.VALIDATION_ERROR);
  if (currentPassword === newPassword) throw new AppError('Mật khẩu mới phải khác mật khẩu hiện tại.', 422, ErrorCodes.VALIDATION_ERROR);
  const passwordHash = await hashPassword(newPassword);
  const claimed = await User.findOneAndUpdate({ _id: user._id, passwordVersion: user.passwordVersion,
    status: AccountStatus.ACTIVE }, { $set: { passwordHash }, $inc: { passwordVersion: 1 },
    $unset: { passwordResetTokenHash: 1, passwordResetExpiresAt: 1, passwordResetRequestedAt: 1 } });
  if (!claimed) throw new AppError('Tài khoản vừa thay đổi. Vui lòng đăng nhập lại.', 409, 'AUTH_SESSION_INVALID');
  await AuthSession.revokeAllForUser(user._id);
}

export async function setGooglePassword(userId: Types.ObjectId, sessionId: Types.ObjectId, newPassword: string): Promise<void> {
  const user = await User.findById(userId).select('+passwordHash');
  if (!user || !user.isActive()) throw new AppError('Account unavailable', 403, ErrorCodes.USER_DISABLED);
  if (user.isGuest || user.accountType !== AccountType.GOOGLE || user.passwordHash || !user.email || !user.googleProvider?.providerId) {
    throw new AppError('Chức năng này chỉ dành cho tài khoản Google chưa có mật khẩu.', 400, 'AUTH_PASSWORD_NOT_SUPPORTED');
  }
  const session = await AuthSession.findOne({_id: sessionId, userId});
  const authenticatedAt = session?.authenticatedAt;
  if (!session?.isValid() || !authenticatedAt || authenticatedAt.getTime() < Date.now() - 10 * 60 * 1000) {
    throw new AppError('Vui lòng đăng xuất và đăng nhập lại bằng Google trước khi tạo mật khẩu (trong vòng 10 phút).', 403, 'AUTH_REAUTHENTICATION_REQUIRED');
  }
  const passwordHash = await hashPassword(newPassword);
  const claimed = await User.findOneAndUpdate({_id: userId, accountType: AccountType.GOOGLE,
    status: AccountStatus.ACTIVE, passwordVersion: user.passwordVersion, passwordHash: {$exists: false}},
    {$set: {passwordHash, accountType: AccountType.LOCAL}, $inc: {passwordVersion: 1},
      $unset: {passwordResetTokenHash: 1, passwordResetExpiresAt: 1, passwordResetRequestedAt: 1}});
  if (!claimed) throw new AppError('Tài khoản vừa thay đổi. Vui lòng đăng nhập lại.', 409, 'AUTH_SESSION_INVALID');
  // Keep the Google provider subject, account ID, roles and learning data intact.
  await AuthSession.revokeAllForUser(userId);
}
