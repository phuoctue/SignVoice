import {createHash, randomBytes} from 'node:crypto';
import {Types} from 'mongoose';
import jwt from 'jsonwebtoken';
import {GuestTrial} from '../models/GuestTrial.model';
import {User} from '../models/User.model';
import {AuthSession} from '../models/AuthSession.model';
import {AppError} from '../common/errors/AppError';
import {env} from '../config/env';

export const GUEST_TRIAL_SECONDS = 10 * 60;
const hash = (value: string) => createHash('sha256').update(value).digest('hex');
export async function trialForDevice(key: string) {
  await GuestTrial.init();
  const deviceHash = hash(key);
  try {
    return await GuestTrial.findOneAndUpdate({deviceHash}, {$setOnInsert: {deviceHash}},
      {upsert: true, new: true, setDefaultsOnInsert: true});
  } catch (error) {
    if ((error as {code?: number}).code !== 11000) throw error;
    return (await GuestTrial.findOne({deviceHash}))!;
  }
}
async function trialForUser(userId: Types.ObjectId) {
  const user = await User.findById(userId).select('isGuest status +guestTrialId');
  if (!user || !user.isActive()) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_USER_NOT_FOUND');
  if (!user.isGuest) return null;
  if (!user.guestTrialId) {
    const trial = await trialForDevice('legacy-user:' + userId);
    await User.updateOne({_id: userId, guestTrialId: {$exists: false}}, {$set: {guestTrialId: trial._id}});
    const current = await User.findById(userId).select('+guestTrialId');
    user.guestTrialId = current!.guestTrialId;
  }
  const trial = await GuestTrial.findById(user.guestTrialId);
  if (!trial) throw new AppError('Không tải được phiên dùng thử.', 503, 'TRIAL_UNAVAILABLE');
  if (!!trial.startedAt !== !!trial.expiresAt) throw new AppError('Trạng thái phiên dùng thử không hợp lệ.', 503, 'TRIAL_UNAVAILABLE');
  return trial;
}
export async function guestTrialStatus(userId: Types.ObjectId, start = false) {
  let trial = await trialForUser(userId);
  const now = new Date();
  if (!trial) return {state: 'unlimited', serverNow: now, durationSeconds: GUEST_TRIAL_SECONDS, remainingSeconds: null, expiresAt: undefined, startedAt: undefined};
  if (start && !trial.startedAt) {
    trial = (await GuestTrial.findOneAndUpdate({_id: trial._id, startedAt: {$exists: false}},
      {$set: {startedAt: now, expiresAt: new Date(now.getTime() + GUEST_TRIAL_SECONDS * 1000)}}, {new: true}))
      || await GuestTrial.findById(trial._id);
  }
  if (!trial) throw new AppError('Không tải được phiên dùng thử.', 503, 'TRIAL_UNAVAILABLE');
  const remainingSeconds = trial.expiresAt ? Math.max(0, Math.ceil((trial.expiresAt.getTime() - now.getTime()) / 1000)) : GUEST_TRIAL_SECONDS;
  return {state: !trial.startedAt ? 'available' : remainingSeconds > 0 ? 'active' : 'expired',
    serverNow: now, startedAt: trial.startedAt, expiresAt: trial.expiresAt,
    durationSeconds: GUEST_TRIAL_SECONDS, remainingSeconds};
}
export async function assertTrialActive(userId: Types.ObjectId) {
  const status = await guestTrialStatus(userId);
  if (status.state === 'available') throw new AppError('Hãy bắt đầu phiên dùng thử 10 phút.', 403, 'GUEST_TRIAL_NOT_STARTED');
  if (status.state === 'expired') throw new AppError('Đã hết 10 phút dùng thử. Vui lòng đăng nhập hoặc tạo tài khoản để tiếp tục.', 403, 'GUEST_TRIAL_EXPIRED');
  return status.expiresAt;
}
export async function createAiTicket(userId: Types.ObjectId, sessionId: Types.ObjectId) {
  await assertTrialActive(userId);
  const session = await AuthSession.findById(sessionId);
  if (!session?.isValid() || !session.userId.equals(userId)) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_SESSION_INVALID');
  return jwt.sign({purpose: 'ai_stream', userId: String(userId), family: session.sessionFamily}, env.JWT_ACCESS_SECRET,
    {expiresIn: '30s', jwtid: randomBytes(16).toString('hex'), algorithm: 'HS256'});
}
export async function authorizeAiTicket(ticket: string) {
  let payload;
  try {
    payload = jwt.verify(ticket, env.JWT_ACCESS_SECRET, {algorithms: ['HS256']}) as jwt.JwtPayload;
    if (payload.purpose !== 'ai_stream' || !Types.ObjectId.isValid(payload.userId) || typeof payload.family !== 'string') throw new Error();
  } catch { throw new AppError('Kết nối AI cần phiên hợp lệ.', 401, 'AI_TICKET_INVALID'); }
  const userId = new Types.ObjectId(payload.userId);
  const session = await AuthSession.findOne({userId, sessionFamily: payload.family, status: 'ACTIVE', expiresAt: {$gt: new Date()}});
  if (!session) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_SESSION_INVALID');
  const user = await User.findById(userId);
  if (!user || !user.isActive() || session.passwordVersion !== user.passwordVersion) throw new AppError('Phiên không còn hợp lệ.', 401, 'AUTH_SESSION_INVALID');
  return {expiresAt: await assertTrialActive(userId)};
}
