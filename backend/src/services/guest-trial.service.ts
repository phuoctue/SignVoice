import {createHash, randomBytes} from 'node:crypto';
import {ClientSession, Types} from 'mongoose';
import jwt from 'jsonwebtoken';
import {GuestTrial} from '../models/GuestTrial.model';
import {AuthSession} from '../models/AuthSession.model';
import {AppError} from '../common/errors/AppError';
import {env} from '../config/env';
import {assertSessionEpoch, loadSessionUser} from './session-fence.service';
import {assertSessionChain} from './session-chain.service';
import {authClock} from './auth-clock';

import {guestTrialStatus, GUEST_TRIAL_SECONDS, GUEST_COOLDOWN_MS} from './guest-retention.service';
export {guestTrialStatus, GUEST_TRIAL_SECONDS, GUEST_COOLDOWN_MS} from './guest-retention.service';
const hash = (value: string) => createHash('sha256').update(value).digest('hex');
export class GuestGrantConflict extends AppError {
  readonly data: {serverNow: Date; nextTrialAvailableAt: Date | null};
  constructor(code: string, startedAt?: Date) {
    super('Lượt thử chưa thể được cấp. Vui lòng kiểm tra thời gian và xác nhận lại.', 409, code);
    Object.setPrototypeOf(this, GuestGrantConflict.prototype);
    this.data = {serverNow: authClock.now(), nextTrialAvailableAt: startedAt ? new Date(+startedAt + GUEST_COOLDOWN_MS) : null};
  }
}
export interface GuestGrantInput {deviceKey: string; requestKey: string; expectedLastGrantAt: string | null}
export async function grantTrial(input: GuestGrantInput, transaction: ClientSession) {
  if (env.GUEST_GRANTS_PAUSED) throw new AppError('Guest grants are temporarily paused for recovery.', 503, 'GUEST_GRANTS_PAUSED');
  const deviceHash = hash(input.deviceKey), now = authClock.now();
  const trial = await GuestTrial.findOne({deviceHash}).select('+lastGrantRequestHash').session(transaction);
  if (trial?.lastGrantRequestHash === hash(input.requestKey)) throw new GuestGrantConflict('GUEST_GRANT_ALREADY_COMMITTED', trial.startedAt);
  const observed = trial?.startedAt;
  if ((observed?.getTime() ?? null) !== (input.expectedLastGrantAt === null ? null : Date.parse(input.expectedLastGrantAt))) {
    throw new GuestGrantConflict('GUEST_GRANT_STALE', observed);
  }
  if (observed && +now < +observed + GUEST_COOLDOWN_MS) throw new GuestGrantConflict('GUEST_TRIAL_COOLDOWN', observed);
  const granted = await GuestTrial.findOneAndUpdate({deviceHash,
    startedAt: observed ?? {$exists: false},
    ...(observed ? {$and: [{startedAt: {$lte: new Date(+now - GUEST_COOLDOWN_MS)}}]} : {}),
  }, {$set: {startedAt: now, expiresAt: new Date(+now + GUEST_TRIAL_SECONDS * 1000), lastGrantRequestHash: hash(input.requestKey)}},
  {new: true, upsert: !trial, session: transaction}).select('+lastGrantRequestHash');
  if (!granted) throw new GuestGrantConflict('GUEST_GRANT_STALE', observed);
  return granted;
}
export async function concurrentGrantConflict(input: GuestGrantInput): Promise<never> {
  const trial = await GuestTrial.findOne({deviceHash: hash(input.deviceKey)}).select('+lastGrantRequestHash');
  if (!trial) throw new AppError('Không tải được phiên dùng thử.', 503, 'TRIAL_UNAVAILABLE');
  throw new GuestGrantConflict(trial.lastGrantRequestHash === hash(input.requestKey)
    ? 'GUEST_GRANT_ALREADY_COMMITTED' : 'GUEST_GRANT_STALE', trial.startedAt);
}
export async function assertGuestDataRetained(userId: Types.ObjectId, transaction?: ClientSession) {
  const status = await guestTrialStatus(userId, transaction);
  if (status.dataState === 'expired') throw new AppError('Đã hết thời hạn giữ dữ liệu khách.', 403, 'GUEST_DATA_EXPIRED');
  return status;
}
export async function assertTrialActive(userId: Types.ObjectId, transaction?: ClientSession) {
  const status = await guestTrialStatus(userId, transaction);
  if (status.state === 'expired') throw new AppError('Đã hết 10 phút dùng thử. Vui lòng đăng nhập hoặc tạo tài khoản để tiếp tục.', 403, 'GUEST_TRIAL_EXPIRED');
  return status.expiresAt;
}
export async function createAiTicket(userId: Types.ObjectId, sessionId: Types.ObjectId) {
  await assertTrialActive(userId);
  const session = await AuthSession.findById(sessionId);
  if (!session?.isValid() || !session.userId.equals(userId)) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_SESSION_INVALID');
  const user = await loadSessionUser(userId);
  if (!user?.isActive() || session.passwordVersion !== user.passwordVersion) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_SESSION_INVALID');
  assertSessionEpoch(session, user);
  await assertSessionChain(session);
  return jwt.sign({purpose: 'ai_stream', userId: String(userId), family: session.sessionFamily, iat: Math.floor(+authClock.now() / 1000)}, env.JWT_ACCESS_SECRET,
    {expiresIn: '30s', jwtid: randomBytes(16).toString('hex'), algorithm: 'HS256'});
}
export async function authorizeAiTicket(ticket: string) {
  let payload;
  try {
    payload = jwt.verify(ticket, env.JWT_ACCESS_SECRET, {algorithms: ['HS256'], clockTimestamp: Math.floor(+authClock.now() / 1000)}) as jwt.JwtPayload;
    if (payload.purpose !== 'ai_stream' || !Types.ObjectId.isValid(payload.userId) || typeof payload.family !== 'string') throw new Error();
  } catch { throw new AppError('Kết nối AI cần phiên hợp lệ.', 401, 'AI_TICKET_INVALID'); }
  const userId = new Types.ObjectId(payload.userId);
  const session = await AuthSession.findOne({userId, sessionFamily: payload.family, status: 'ACTIVE', expiresAt: {$gt: authClock.now()}});
  if (!session) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_SESSION_INVALID');
  const user = await loadSessionUser(userId);
  if (!user || !user.isActive() || session.passwordVersion !== user.passwordVersion) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_SESSION_INVALID');
  assertSessionEpoch(session, user);
  await assertSessionChain(session);
  return {expiresAt: await assertTrialActive(userId)};
}
