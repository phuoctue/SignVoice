import {Router} from 'express';
import {randomUUID} from 'node:crypto';
import {z} from 'zod';
import {requireAuth} from '../common/middlewares/auth.middleware';
import {validate} from '../common/middlewares/validate.middleware';
import {idParams} from '../validation/user-data.validation';
import {NotificationDevice, UserNotification} from '../models/Notification.model';
import {pushConfigured, refreshNotifications, deliverNotificationBatch} from '../services/notification.service';
import {UserSettings} from '../models/UserSettings.model';
import {missing, userTransaction} from '../services/user-data.service';
import {AppError} from '../common/errors/AppError';
import {AuthSession} from '../models/AuthSession.model';

const router = Router();
router.use(requireAuth, (_req, res, next) => {res.setHeader('Cache-Control', 'no-store'); next();});
router.get('/notifications', async (req, res, next) => {
  try {
    await refreshNotifications(req.user!.id);
    const items = await UserNotification.find({userId: req.user!.id, expiresAt: {$gt: new Date()}}).sort({createdAt: -1, _id: -1}).limit(50).lean();
    res.json({success: true, data: {items, unread: items.filter(item => !item.read).length, pushConfigured: pushConfigured()}});
  } catch (error) {next(error);}
});
router.post('/notifications/test', validate(z.object({body: z.object({}).strict()})), async (req, res, next) => {
  try {
    if (req.user!.isGuest) throw new AppError('Đăng nhập để thử thông báo.', 403, 'GUEST_RESTRICTED');
    const settings = await UserSettings.findOne({userId: req.user!.id});
    if (settings?.notificationsEnabled === false || !await NotificationDevice.exists({userId: req.user!.id, expiresAt: {$gt: new Date()}})) {
      throw new AppError('Bật thông báo và đăng ký thiết bị Android trước khi thử push.', 409, 'PUSH_DEVICE_REQUIRED');
    }
    if (!pushConfigured()) throw new AppError('Máy chủ chưa cấu hình Firebase.', 503, 'PUSH_NOT_CONFIGURED');
    const notice = await userTransaction(req.user!.id, async session => {
      if (await UserNotification.exists({userId: req.user!.id, kind: 'TEST', createdAt: {$gt: new Date(Date.now() - 10000)}}).session(session)) {
        throw new AppError('Chờ 10 giây trước khi thử lại.', 429, 'PUSH_TEST_RATE_LIMIT');
      }
      return (await UserNotification.create([{userId: req.user!.id, key: `TEST:${randomUUID()}`, kind: 'TEST',
        title: 'Kiểm tra thông báo SignVoice', body: 'Đây là thông báo kiểm tra. Bạn có thể xem lại trong mục chuông.', route: '/notifications',
        expiresAt: new Date(Date.now() + 30 * 86400000)}], {session}))[0];
    });
    await deliverNotificationBatch(undefined, req.user!.id);
    const sent = !!await NotificationDevice.exists({userId: req.user!.id, deliveredAt: {$gte: notice.createdAt}});
    res.status(201).json({success: true, data: {notification: notice, sent}});
  } catch (error) {next(error);}
});
router.patch('/notifications/:id', validate(z.object({params: idParams, body: z.object({read: z.literal(true)}).strict()})), async (req, res, next) => {
  try {
    const item = await UserNotification.findOneAndUpdate({_id: req.params.id, userId: req.user!.id}, {$set: {read: true}}, {new: true});
    if (!item) throw missing();
    res.json({success: true, data: item});
  } catch (error) {next(error);}
});
const token = z.string().min(20).max(4096).regex(/^[A-Za-z0-9_:\-.]+$/);
router.post('/notification-devices', validate(z.object({body: z.object({token, platform: z.enum(['android', 'ios'])}).strict()})), async (req, res, next) => {
  try {
    if (req.user!.isGuest) throw new AppError('Đăng nhập để nhận thông báo.', 403, 'GUEST_RESTRICTED');
    await userTransaction(req.user!.id, async session => {
      const authSession = await AuthSession.findById(req.sessionId).session(session);
      if (!authSession?.sessionFamily) throw missing();
      const existing = await NotificationDevice.findOne({token: req.body.token}).session(session);
      const now = new Date();
      await NotificationDevice.updateOne({token: req.body.token}, {$set: {userId: req.user!.id, platform: req.body.platform, sessionFamily: authSession.sessionFamily,
        expiresAt: new Date(+now + 90 * 86400000), ...(String(existing?.userId) !== String(req.user!.id) ? {deliveredAt: now, leaseUntil: new Date(0)} : {})}}, {upsert: true, session});
    });
    res.json({success: true, data: {registered: true, pushConfigured: pushConfigured()}});
  } catch (error) {next(error);}
});
router.delete('/notification-devices', validate(z.object({body: z.object({token}).strict()})), async (req, res, next) => {
  try {
    await NotificationDevice.deleteOne({token: req.body.token, userId: req.user!.id});
    res.json({success: true, data: {removed: true}});
  } catch (error) {next(error);}
});
export default router;
