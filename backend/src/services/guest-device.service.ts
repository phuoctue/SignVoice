import {randomBytes} from 'node:crypto';
import {Request, Response} from 'express';
import {env} from '../config/env';
import {AppError} from '../common/errors/AppError';

export function guestDeviceKey(req: Request) {
  const supplied = req.method === 'GET' ? req.query.deviceKey : req.body?.deviceKey;
  if (supplied !== undefined && (typeof supplied !== 'string' || !/^[a-f0-9]{64}$/.test(supplied))) {
    throw new AppError('Mã phiên dùng thử không hợp lệ.', 400, 'INVALID_GUEST_DEVICE');
  }
  const cookie = req.cookies?.signvoice_guest_device;
  const key = typeof cookie === 'string' && /^[a-f0-9]{64}$/.test(cookie)
    ? cookie : supplied as string || randomBytes(32).toString('hex');
  return key;
}
export function setGuestDeviceCookie(res: Response, key: string) {
  res.cookie('signvoice_guest_device', key, {httpOnly: true, sameSite: 'strict', path: '/api/v1',
    secure: env.isProduction || env.OAUTH_BACKEND_ORIGIN.startsWith('https://') || env.PUBLIC_ORIGIN.startsWith('https://'),
    maxAge: 365 * 24 * 60 * 60 * 1000});
}
