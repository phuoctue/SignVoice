import { Request, Response, NextFunction, CookieOptions } from 'express';
import * as authService from '../services/auth.service';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';
import { env } from '../config/env';
import { ITokenPair } from '../utils/jwt.util';
import * as passwordResetService from '../services/password-reset.service';
import { authorizationFor } from '../services/authorization.service';
import {trialForDevice} from '../services/guest-trial.service';
import {guestDeviceKey} from '../services/guest-device.service';

export async function forgotPassword(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    await passwordResetService.requestPasswordReset(req.body.email);
    res.status(200).json({ success: true, data: { message: 'Nếu email này có tài khoản, bạn sẽ nhận được liên kết đặt lại mật khẩu.' } });
  } catch (error) { next(error); }
}

export async function resetPassword(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    await passwordResetService.resetPassword(req.body.token, req.body.newPassword);
    res.clearCookie(refreshCookie, cookieOptions);
    res.status(200).json({ success: true, data: { message: 'Đã đổi mật khẩu. Vui lòng đăng nhập lại.' } });
  } catch (error) { next(error); }
}

const refreshCookie = 'signvoice_refresh';
const cookieOptions: CookieOptions = {
  httpOnly: true, secure: env.isProduction || env.OAUTH_BACKEND_ORIGIN.startsWith('https://') || env.PUBLIC_ORIGIN.startsWith('https://'), sameSite: 'strict', path: '/api/v1/auth',
};

export function setRefreshCookie(res: Response, tokens: ITokenPair, secure = cookieOptions.secure): void {
  res.cookie(refreshCookie, tokens.refreshToken, {
    ...cookieOptions, secure, expires: tokens.refreshTokenExpiresAt,
  });
}

export async function changePassword(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    if (!req.user) throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    await authService.changePassword(req.user.id, req.body.currentPassword, req.body.newPassword);
    res.clearCookie(refreshCookie, cookieOptions);
    res.json({ success: true, data: { message: 'Đã đổi mật khẩu. Vui lòng đăng nhập lại trên các thiết bị.' } });
  } catch (error) { next(error); }
}

/**
 * Extract request metadata
 */
function getRequestMeta(req: Request) {
  return {
    ipAddress: (req.headers['x-forwarded-for'] as string) || req.socket.remoteAddress || undefined,
    userAgent: req.headers['user-agent'] || undefined,
  };
}

/**
 * Register new user
 * POST /api/v1/auth/register
 */
export async function register(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const { email, password, displayName } = req.body;
    
    const result = await authService.registerUser(
      { email, password, displayName },
      getRequestMeta(req)
    );
    
    setRefreshCookie(res, result.tokens);
    res.status(201).json({
      success: true,
      data: result,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Login user
 * POST /api/v1/auth/login
 */
export async function login(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const { email, password } = req.body;
    
    const result = await authService.loginUser(
      { email, password },
      getRequestMeta(req)
    );
    
    setRefreshCookie(res, result.tokens);
    res.status(200).json({
      success: true,
      data: result,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Create guest account
 * POST /api/v1/auth/guest
 */
export async function createGuest(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const trial = await trialForDevice(guestDeviceKey(req, res));
    const result = await authService.createGuestAccount(getRequestMeta(req), trial._id);
    setRefreshCookie(res, result.tokens);
    
    res.status(201).json({
      success: true,
      data: result,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Convert guest to permanent account
 * POST /api/v1/auth/convert-guest
 */
export async function convertGuest(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    if (!req.user.isGuest) {
      throw new AppError('Only guest accounts can be converted', 400, ErrorCodes.BAD_REQUEST);
    }
    
    const { email, password, displayName } = req.body;
    
    const result = await authService.convertGuestToPermanent(
      req.user.id,
      { email, password, displayName },
      getRequestMeta(req)
    );
    setRefreshCookie(res, result.tokens);
    
    res.status(200).json({
      success: true,
      data: result,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Refresh access token
 * POST /api/v1/auth/refresh
 */
export async function refresh(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const refreshToken = req.body?.refreshToken || req.cookies?.[refreshCookie];
    if (!req.body?.refreshToken && req.cookies?.[refreshCookie]) {
      const origin = req.get('origin');
      if (!origin || !env.CORS_ALLOWED_ORIGINS.includes(origin)) {
        throw new AppError('Untrusted refresh origin', 403, ErrorCodes.AUTH_FORBIDDEN);
      }
    }
    
    if (!refreshToken) {
      throw new AppError('Refresh token required', 400, ErrorCodes.AUTH_TOKEN_MISSING);
    }
    
    const tokens = await authService.refreshTokens(refreshToken, getRequestMeta(req));
    setRefreshCookie(res, tokens);
    
    res.status(200).json({
      success: true,
      data: tokens,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Logout (revoke current session)
 * POST /api/v1/auth/logout
 */
export async function logout(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    if (!req.user || !req.sessionId) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    await authService.logoutUser(req.user.id, req.sessionId, getRequestMeta(req));
    res.clearCookie(refreshCookie, cookieOptions);
    
    res.status(200).json({
      success: true,
      data: { message: 'Logged out successfully' },
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Logout from all devices
 * POST /api/v1/auth/logout-all
 */
export async function logoutAll(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    const count = await authService.logoutAllDevices(req.user.id, getRequestMeta(req));
    res.clearCookie(refreshCookie, cookieOptions);
    
    res.status(200).json({
      success: true,
      data: {
        message: 'Logged out from all devices',
        sessionsRevoked: count,
      },
    });
  } catch (error) {
    next(error);
  }
}

/**
 * Get current user
 * GET /api/v1/auth/me
 */
export async function getCurrentUser(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    const { User } = await import('../models/User.model');
    const user = await User.findById(req.user.id).select('-passwordHash');
    
    if (!user) {
      throw new AppError('User not found', 404, ErrorCodes.USER_NOT_FOUND);
    }
    
    res.status(200).json({
      success: true,
      data: {
        id: user._id.toString(),
        email: user.email,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        accountType: user.accountType,
        isGuest: user.isGuest,
        status: user.status,
        createdAt: user.createdAt,
        updatedAt: user.updatedAt,
        ...await authorizationFor(user),
      },
    });
  } catch (error) {
    next(error);
  }
}
