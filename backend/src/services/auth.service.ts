import { Types } from 'mongoose';
import { User, IUser, AccountType, AccountStatus, UserRole } from '../models/User.model';
import { AuthSession, SessionType, SessionStatus } from '../models/AuthSession.model';
import { UserSettings } from '../models/UserSettings.model';
import { AuditLog, AuditAction, AuditSeverity } from '../models/AuditLog.model';
import { hashPassword, verifyPassword } from '../utils/password.util';
import { generateTokenPair, hashToken, verifyAccessToken, verifyRefreshToken, ITokenPair } from '../utils/jwt.util';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';
import { authorizationFor } from './authorization.service';

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
  meta: IRequestMeta = {}
): Promise<IAuthResponse> {
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
    role: UserRole.USER,
    isGuest: false,
    lastLoginAt: new Date(),
    lastLoginIp: meta.ipAddress,
  });
  
  // Create default settings
  await UserSettings.create({ userId: user._id });
  
  // Generate tokens
  const tokens = generateTokenPair(user._id, user.role);
  
  // Create auth session
  await createAuthSession(user._id, tokens.accessToken, tokens.accessTokenExpiresAt, meta, user.passwordVersion);
  await createAuthSession(user._id, tokens.refreshToken, tokens.refreshTokenExpiresAt, meta, user.passwordVersion);
  
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
      avatarUrl: user.avatarUrl,      isGuest: user.isGuest,
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
  // Find user (include passwordHash)
  const user = await User.findOne({ email: data.email.toLowerCase() }).select('+passwordHash');
  
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
  await user.save();
  
  // Generate tokens
  const tokens = generateTokenPair(user._id, user.role);
  
  // Create auth sessions
  await createAuthSession(user._id, tokens.accessToken, tokens.accessTokenExpiresAt, meta, user.passwordVersion);
  await createAuthSession(user._id, tokens.refreshToken, tokens.refreshTokenExpiresAt, meta, user.passwordVersion);
  
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
      avatarUrl: user.avatarUrl,      isGuest: user.isGuest,
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
export async function createGuestAccount(meta: IRequestMeta = {}): Promise<IAuthResponse> {
  // Generate random display name
  const displayName = `Guest_${Date.now().toString(36)}`;
  
  // Create guest user
  const user = await User.create({
    displayName,
    accountType: AccountType.GUEST,
    role: UserRole.USER,
    isGuest: true,
    lastLoginAt: new Date(),
    lastLoginIp: meta.ipAddress,
  });
  
  // Create default settings
  await UserSettings.create({ userId: user._id });
  
  // Generate tokens
  const tokens = generateTokenPair(user._id, user.role);
  
  // Create auth sessions
  await createAuthSession(user._id, tokens.accessToken, tokens.accessTokenExpiresAt, meta, user.passwordVersion);
  await createAuthSession(user._id, tokens.refreshToken, tokens.refreshTokenExpiresAt, meta, user.passwordVersion);
  
  // Audit log
  await AuditLog.log({
    userId: user._id,
    actorRole: user.role,
    action: AuditAction.USER_REGISTER,
    severity: AuditSeverity.INFO,
    resourceType: 'User',
    resourceId: user._id,
    details: { accountType: 'GUEST' },
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });
  
  return {
    user: {
      id: user._id.toString(),
      displayName: user.displayName,      isGuest: true,
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
  meta: IRequestMeta = {}
): Promise<IAuthResponse> {
  // Find guest user
  const user = await User.findById(userId);
  
  if (!user) {
    throw new AppError('User not found', 404, ErrorCodes.USER_NOT_FOUND);
  }
  
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
  
  // Update user
  user.email = data.email.toLowerCase();
  user.displayName = data.displayName;
  user.passwordHash = passwordHash;
  user.accountType = AccountType.LOCAL;
  user.isGuest = false;
  user.guestConvertedAt = new Date();
  await user.save();
  
  // Generate new tokens
  const tokens = generateTokenPair(user._id, user.role);
  
  // Revoke old sessions
  await AuthSession.revokeAllForUser(user._id);
  
  // Create new sessions
  await createAuthSession(user._id, tokens.accessToken, tokens.accessTokenExpiresAt, meta, user.passwordVersion);
  await createAuthSession(user._id, tokens.refreshToken, tokens.refreshTokenExpiresAt, meta, user.passwordVersion);
  
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
      avatarUrl: user.avatarUrl,      isGuest: false,
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
  const user = await User.findById(payload.userId);
  
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
  
  // Claim the refresh token once, including when requests arrive concurrently.
  const claimed = await AuthSession.findOneAndUpdate({
    _id: session._id, status: SessionStatus.ACTIVE, expiresAt: { $gt: new Date() },
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
  await createAuthSession(user._id, tokens.accessToken, tokens.accessTokenExpiresAt, meta, user.passwordVersion);
  await createAuthSession(user._id, tokens.refreshToken, tokens.refreshTokenExpiresAt, meta, user.passwordVersion);
  
  // Audit log
  await AuditLog.log({
    userId: user._id,
    actorRole: user.role,
    action: AuditAction.TOKEN_REFRESH,
    severity: AuditSeverity.INFO,
    ipAddress: meta.ipAddress,
    userAgent: meta.userAgent,
  });
  
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
    if (session.sessionFamily) {
      await AuthSession.updateMany({ userId, sessionFamily: session.sessionFamily }, {
        $set: { status: SessionStatus.REVOKED, revokedAt: new Date() },
      });
    } else {
      await session.revoke();
    }
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
  meta: IRequestMeta = {}
): Promise<number> {
  const count = await AuthSession.revokeAllForUser(userId);
  
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
  passwordVersion = 0
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
  
  await AuthSession.create({
    userId,
    sessionFamily: payload.sid,
    passwordVersion,
    sessionType,
    tokenHash,
    deviceInfo: meta.userAgent,
    ipAddress: meta.ipAddress,
    expiresAt,
    lastUsedAt: new Date(),
  });
}

/** Issue OAuth sessions through the same persisted token/session model as password login. */
export async function loginOAuthUser(user: IUser, meta: IRequestMeta = {}): Promise<IAuthResponse> {
  if (!user.isActive()) throw new AppError('Account is suspended or deleted', 403, ErrorCodes.USER_DISABLED);
  await UserSettings.updateOne({ userId: user._id }, { $setOnInsert: { userId: user._id } }, { upsert: true });
  user.lastLoginAt = new Date();
  user.lastLoginIp = meta.ipAddress;
  await user.save();
  const tokens = generateTokenPair(user._id, user.role);
  await createAuthSession(user._id, tokens.accessToken, tokens.accessTokenExpiresAt, meta, user.passwordVersion);
  await createAuthSession(user._id, tokens.refreshToken, tokens.refreshTokenExpiresAt, meta, user.passwordVersion);
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
