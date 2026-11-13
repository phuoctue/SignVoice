import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { Types } from 'mongoose';
import { env } from '../config/env';
import { SessionType } from '../models/AuthSession.model';
import { UserRole } from '../models/User.model';
import { authClock } from '../services/auth-clock';

/**
 * JWT payload interface
 */
export interface IJwtPayload {
  userId: string;
  sessionType: SessionType;
  role: string;
  sid: string;
  jti?: string;
  iat?: number;
  exp?: number;
}

/**
 * Token generation result
 */
export interface ITokenPair {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresAt: Date;
  refreshTokenExpiresAt: Date;
}

/**
 * Generate SHA-256 hash of a token (for storage)
 */
export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Generate access token (short-lived, 15 minutes)
 */
export function generateAccessToken(userId: Types.ObjectId, role: string, sid = crypto.randomUUID()): string {
  const payload: IJwtPayload = {
    userId: userId.toString(),
    sessionType: SessionType.ACCESS,
    iat: Math.floor(+authClock.now() / 1000),
    role,
    sid,
  };
  
  return jwt.sign(payload, env.JWT_ACCESS_SECRET, {
    expiresIn: env.JWT_ACCESS_EXPIRES_IN as jwt.SignOptions['expiresIn'],
    algorithm: 'HS256',
    jwtid: crypto.randomUUID(),
    issuer: 'signvoice-api',
    audience: 'signvoice-app',
  });
}

/**
 * Generate refresh token (long-lived, 7 days)
 */
export function generateRefreshToken(userId: Types.ObjectId, role: string, sid = crypto.randomUUID()): string {
  const payload: IJwtPayload = {
    userId: userId.toString(),
    sessionType: SessionType.REFRESH,
    iat: Math.floor(+authClock.now() / 1000),
    role,
    sid,
  };
  
  return jwt.sign(payload, env.JWT_REFRESH_SECRET, {
    expiresIn: env.JWT_REFRESH_EXPIRES_IN as jwt.SignOptions['expiresIn'],
    algorithm: 'HS256',
    jwtid: crypto.randomUUID(),
    issuer: 'signvoice-api',
    audience: 'signvoice-app',
  });
}

/**
 * Generate token pair (access + refresh)
 */
export function generateTokenPair(userId: Types.ObjectId, role: string): ITokenPair {
  const sid = crypto.randomUUID();
  const accessToken = generateAccessToken(userId, role, sid);
  const refreshToken = generateRefreshToken(userId, role, sid);
  
  return {
    accessToken,
    refreshToken,
    accessTokenExpiresAt: getTokenExpiration(accessToken)!,
    refreshTokenExpiresAt: getTokenExpiration(refreshToken)!,
  };
}

/**
 * Verify and decode access token
 */
export function verifyAccessToken(token: string): IJwtPayload {
  try {
    const payload = jwt.verify(token, env.JWT_ACCESS_SECRET, {
      clockTimestamp: Math.floor(+authClock.now() / 1000),
      issuer: 'signvoice-api',
      audience: 'signvoice-app',
      algorithms: ['HS256'],
    }) as IJwtPayload;
    
    if (payload.sessionType !== SessionType.ACCESS || !validPayload(payload)) {
      throw new Error('Invalid token type');
    }
    
    return payload;
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      throw new Error('TOKEN_EXPIRED');
    } else if (error instanceof jwt.JsonWebTokenError) {
      throw new Error('TOKEN_INVALID');
    } else {
      throw new Error('TOKEN_VERIFICATION_FAILED');
    }
  }
}

/**
 * Verify and decode refresh token
 */
export function verifyRefreshToken(token: string): IJwtPayload {
  try {
    const payload = jwt.verify(token, env.JWT_REFRESH_SECRET, {
      clockTimestamp: Math.floor(+authClock.now() / 1000),
      issuer: 'signvoice-api',
      audience: 'signvoice-app',
      algorithms: ['HS256'],
    }) as IJwtPayload;
    
    if (payload.sessionType !== SessionType.REFRESH || !validPayload(payload)) {
      throw new Error('Invalid token type');
    }
    
    return payload;
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      throw new Error('TOKEN_EXPIRED');
    } else if (error instanceof jwt.JsonWebTokenError) {
      throw new Error('TOKEN_INVALID');
    } else {
      throw new Error('TOKEN_VERIFICATION_FAILED');
    }
  }
}

/**
 * Decode token without verification (for debugging)
 */
export function decodeToken(token: string): IJwtPayload | null {
  try {
    return jwt.decode(token) as IJwtPayload;
  } catch {
    return null;
  }
}

function validPayload(payload: IJwtPayload): boolean {
  return typeof payload === 'object' && payload !== null &&
    typeof payload.userId === 'string' && /^[a-f\d]{24}$/i.test(payload.userId) &&
    Object.values(UserRole).includes(payload.role as UserRole) &&
    typeof payload.sid === 'string' && payload.sid.length > 0 &&
    typeof payload.jti === 'string' && payload.jti.length > 0 &&
    typeof payload.exp === 'number';
}

/**
 * Get token expiration date
 */
export function getTokenExpiration(token: string): Date | null {
  const decoded = decodeToken(token);
  if (!decoded || !decoded.exp) {
    return null;
  }
  return new Date(decoded.exp * 1000);
}

/**
 * Check if token is expired (without verification)
 */
export function isTokenExpired(token: string): boolean {
  const expiration = getTokenExpiration(token);
  if (!expiration) {
    return true;
  }
  return expiration < new Date();
}
