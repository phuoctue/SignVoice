import { Types } from 'mongoose';
import { User, IUser } from '../models/User.model';
import { IAuthSession } from '../models/AuthSession.model';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';

export function sessionEpoch(value: unknown): number {
  if (value === undefined) return 0;
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new Error('Invalid session revocation epoch');
  }
  return value;
}

export function userEpochFilter(epoch: number) {
  return epoch === 0
    ? { $or: [{ sessionRevocationEpoch: 0 }, { sessionRevocationEpoch: { $exists: false } }] }
    : { sessionRevocationEpoch: epoch };
}

/** Fresh primary confirmation is required after an acknowledged logout-all, including failover. */
export function loadSessionUser(userId: Types.ObjectId | string) {
  return User.findById(userId).select('+sessionRevocationEpoch')
    .read('primary').readConcern('linearizable').maxTimeMS(5000);
}

export function assertSessionEpoch(session: Pick<IAuthSession, 'userEpoch'>, user: Pick<IUser, 'sessionRevocationEpoch'>): void {
  if (sessionEpoch(session.userEpoch) !== sessionEpoch(user.sessionRevocationEpoch)) {
    throw new AppError('Session not found or expired', 401, ErrorCodes.AUTH_SESSION_INVALID);
  }
}
