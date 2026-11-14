import {Request, Response, NextFunction} from 'express';
import {assertGuestDataRetained, assertTrialActive} from '../../services/guest-trial.service';
import {AppError} from '../errors/AppError';

/** Applied by requireAuth so new private route groups cannot omit the guest fence. */
export async function enforceGuestAccess(req: Request): Promise<void> {
  if (!req.user?.isGuest) return;
  const path = (req.baseUrl + req.path).toLowerCase().replace(/\/+$/, '');
  const operation = req.method + ' ' + path;
  if (req.method === 'DELETE' && ['/api/v1/users/account', '/api/v1/users/data'].includes(path)) {
    throw new AppError('Hãy dùng thao tác xóa dữ liệu khách có xác nhận.', 403, 'GUEST_USE_DISCARD');
  }
  // RS2: installed clients still POST start; it is the same read-only status operation.
  if (['GET /api/v1/guest-trial/status', 'POST /api/v1/guest-trial/start',
    'GET /api/v1/auth/me', 'POST /api/v1/auth/refresh', 'POST /api/v1/auth/logout',
    'POST /api/v1/guest-data/discard'].includes(operation)) return;
  if (operation === 'POST /api/v1/auth/convert-guest') {
    await assertGuestDataRetained(req.user.id);
    return;
  }
  await assertTrialActive(req.user.id);
}
export async function requireActiveTrial(req: Request, _res: Response, next: NextFunction) {
  try { await assertTrialActive(req.user!.id); next(); } catch (error) { next(error); }
}
