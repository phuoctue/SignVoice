import { createHmac, timingSafeEqual } from 'node:crypto';
import { env } from '../config/env';
import { AppError } from '../common/errors/AppError';

export const personalVideoPattern = /^\/personal-videos\/([a-f0-9]{24})\/([a-f0-9]{64}\.mp4)$/;
function signature(path: string, expires: string) {
  return createHmac('sha256', env.JWT_ACCESS_SECRET).update(`personal-video\n${path}\n${expires}`).digest('hex');
}
export function ownedPersonalVideo(value: string, userId: string): string {
  const path = new URL(value, 'http://localhost').pathname;
  if (!path.startsWith('/personal-videos/')) return value;
  const match = personalVideoPattern.exec(path);
  if (!match || match[1] !== userId) throw new AppError('Video không thuộc tài khoản của bạn.', 403, 'PERSONAL_VIDEO_FORBIDDEN');
  return path;
}
export function signPersonalVideo(value: string): string {
  if (!personalVideoPattern.test(value)) return value;
  const expires = `${Math.floor(Date.now() / 1000) + 3600}`;
  return `${value}?expires=${expires}&signature=${signature(value, expires)}`;
}
export function validPersonalVideoSignature(path: string, expires: unknown, token: unknown): boolean {
  if (!personalVideoPattern.test(path) || typeof expires !== 'string' || !/^\d+$/.test(expires) ||
      Number(expires) <= Date.now() / 1000 || typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) return false;
  return timingSafeEqual(Buffer.from(token, 'hex'), Buffer.from(signature(path, expires), 'hex'));
}
