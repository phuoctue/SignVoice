import { Request, Response, NextFunction } from 'express';
import { Types } from 'mongoose';
import { UserRole, IUser } from '../../models/User.model';
import { AuthSession, SessionType } from '../../models/AuthSession.model';
import { verifyAccessToken, hashToken } from '../../utils/jwt.util';
import { AppError } from '../errors/AppError';
import { ErrorCodes } from '../errors/errorCodes';
import { authorizationFor } from '../../services/authorization.service';
import { Permission } from '../../models/Role.model';
import { assertSessionEpoch, loadSessionUser } from '../../services/session-fence.service';
import { assertSessionChain } from '../../services/session-chain.service';
import { authClock } from '../../services/auth-clock';
import {enforceGuestAccess} from './guest-trial.middleware';

/**
 * Extend Express Request with user info
 */
declare module 'express-serve-static-core' {
  interface Request {
    user?: {
      id: Types.ObjectId;
      role: UserRole;
      isGuest: boolean;
      permissions: readonly string[];
      customRoleId?: string;
      customRoleName?: string;
    };
    authenticatedUser?: IUser;
    sessionId?: Types.ObjectId;
    legacyGuestSessionCutoffAt?: string;
  }
}

/**
 * Extract Bearer token from Authorization header
 */
function extractBearerToken(req: Request): string | null {
  const authHeader = req.headers.authorization;
  
  if (!authHeader) {
    return null;
  }
  
  const match = /^Bearer\s+(\S+)$/i.exec(authHeader);
  if (!match) {
    throw new AppError('Invalid Authorization header', 401, ErrorCodes.AUTH_TOKEN_INVALID);
  }
  return match[1];
}

/**
 * Authenticate request - verify JWT and load user
 * Optional: allows unauthenticated requests to pass through
 */
export async function authenticate(req: Request, res: Response, next: NextFunction): Promise<void> {
  return authenticateRequest(req, res, next, false);
}

async function authenticateRequest(req: Request, _res: Response, next: NextFunction, enforceGuestPolicy: boolean): Promise<void> {
  try {
    const token = extractBearerToken(req);
    
    if (!token) {
      // No token provided - allow through for optional auth
      return next();
    }
    
    // Verify token
    let payload;
    try {
      payload = verifyAccessToken(token);
    } catch (error) {
      // Invalid or expired token
      const message = error instanceof Error ? error.message : 'TOKEN_INVALID';
      throw new AppError(
        message === 'TOKEN_EXPIRED' ? 'Access token expired' : 'Invalid access token',
        401,
        message === 'TOKEN_EXPIRED' ? ErrorCodes.AUTH_TOKEN_EXPIRED : ErrorCodes.AUTH_TOKEN_INVALID
      );
    }
    
    // Check if session exists and is valid
    const tokenHash = hashToken(token);
    const [session, user] = await Promise.all([AuthSession.findOne({
      tokenHash, userId: payload.userId, sessionType: SessionType.ACCESS,
      sessionFamily: payload.sid,
    }), loadSessionUser(payload.userId)]);
    
    if (!session || !session.isValid()) {
      throw new AppError(
        'Session not found or expired',
        401,
        ErrorCodes.AUTH_SESSION_INVALID
      );
    }
    
    // Load user
    
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
    const {chain, transition} = await assertSessionChain(session);
    if (user.isGuest && chain?.legacyDerived) {
      if (transition && +authClock.now() >= +transition.cutoverAt) {
        req.legacyGuestSessionCutoffAt = new Date(+transition.sunsetAt - 2 * transition.clockBudgetMs).toISOString();
      }
    }

    // Attach user info to request
    const authorization = await authorizationFor(user);
    req.user = {
      id: user._id,
      isGuest: user.isGuest,
      ...authorization,
    };
    req.authenticatedUser = user;
    req.sessionId = session._id;
    if (enforceGuestPolicy) await enforceGuestAccess(req);
    // Rejected private requests must not touch even session metadata.
    await AuthSession.updateOne({ _id: session._id }, { $set: { lastUsedAt: new Date() } });
    next();
  } catch (error) {
    next(error);
  }
}

/**
 * Require authentication - must be logged in
 */
export async function requireAuth(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    res.setHeader('Cache-Control', 'no-store');
    // First run authenticate
    await new Promise<void>((resolve, reject) => {
      void authenticateRequest(req, res, err => err ? reject(err) : resolve(), true);
    });
    if (!req.user) throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    next();
  } catch (error) {
    next(error);
  }
}

/**
 * Require specific role(s)
 */
export function requireRole(...allowedRoles: UserRole[]) {
  return async (req: Request, _res: Response, next: NextFunction): Promise<void> => {
    try {
      if (!req.user) {
        throw new AppError(
          'Authentication required',
          401,
          ErrorCodes.AUTH_REQUIRED
        );
      }
      
      if (!allowedRoles.includes(req.user.role)) {
        throw new AppError(
          'Insufficient permissions',
          403,
          ErrorCodes.AUTH_FORBIDDEN
        );
      }
      
      next();
    } catch (error) {
      next(error);
    }
  };
}

/**
 * Require non-guest account
 */
export function requirePermanentAccount(req: Request, _res: Response, next: NextFunction): void {
  try {
    if (!req.user) {
      throw new AppError(
        'Authentication required',
        401,
        ErrorCodes.AUTH_REQUIRED
      );
    }
    
    if (req.user.isGuest) {
      throw new AppError(
        'Vui lòng đăng nhập hoặc tạo tài khoản để lưu và đồng bộ dữ liệu.',
        403,
        ErrorCodes.AUTH_GUEST_RESTRICTED
      );
    }
    
    next();
  } catch (error) {
    next(error);
  }
}

/**
 * Staff or Admin only
 */
export const requireStaff = requirePermission('staff:access');

/**
 * Admin only
 */
export const requireAdmin = requirePermission('admin:access');

/** Shared management dashboard; individual modules still enforce permissions. */
export function requireManagement(req: Request, _res: Response, next: NextFunction): void {
  if (!req.user) return next(new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED));
  if (!req.user.permissions.some(permission => permission === 'admin:access' || permission === 'staff:access')) {
    return next(new AppError('Bạn không có quyền truy cập khu vực quản trị.', 403, ErrorCodes.AUTH_FORBIDDEN));
  }
  next();
}

export function requirePermission(permission: Permission) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if(!req.user) return next(new AppError('Authentication required',401,ErrorCodes.AUTH_REQUIRED));
    if(!req.user.permissions.includes(permission)) return next(new AppError('Bạn không có quyền thực hiện thao tác này.',403,ErrorCodes.AUTH_FORBIDDEN));
    next();
  };
}
