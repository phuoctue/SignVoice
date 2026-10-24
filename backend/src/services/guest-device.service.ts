import {randomBytes} from 'node:crypto';
import {Request, Response} from 'express';
import {User} from '../models/User.model';
import {env} from '../config/env';
import {AppError} from '../common/errors/AppError';
import {trialForDevice} from './guest-trial.service';

export function guestDeviceKey(req: Request, res: Response) {
  const supplied = req.method === 'GET' ? req.query.deviceKey : req.body?.deviceKey;
  if (supplied !== undefined && (typeof supplied !== 'string' || !/^[a-f0-9]{64}$/.test(supplied))) {
    throw new AppError('Mã phiên dùng thử không hợp lệ.', 400, 'INVALID_GUEST_DEVICE');
  }
  const cookie = req.cookies?.signvoice_guest_device;
  const key = typeof cookie === 'string' && /^[a-f0-9]{64}$/.test(cookie)
    ? cookie : supplied as string || randomBytes(32).toString('hex');
  res.cookie('signvoice_guest_device', key, {httpOnly: true, sameSite: 'strict', path: '/api/v1',
    secure: env.isProduction || env.OAUTH_BACKEND_ORIGIN.startsWith('https://') || env.PUBLIC_ORIGIN.startsWith('https://'),
    maxAge: 365 * 24 * 60 * 60 * 1000});
  return key;
}
export async function bindExistingGuestDevice(req: Request, res: Response) {
  if (!req.user!.isGuest) return;
  const user = await User.findById(req.user!.id).select('+guestTrialId');
  if (!user?.guestTrialId) {
    const trial = await trialForDevice(guestDeviceKey(req, res));
    await User.updateOne({_id: req.user!.id, guestTrialId: {$exists: false}}, {$set: {guestTrialId: trial._id}});
  }
}
