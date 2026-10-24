import { Router } from 'express';
import { z } from 'zod';
import { User, AccountType } from '../models/User.model';
import { UserSettings } from '../models/UserSettings.model';
import { AuthSession, SessionStatus, SessionType } from '../models/AuthSession.model';
import { Favorite } from '../models/Favorite.model';
import { Conversation } from '../models/Conversation.model';
import { SearchHistory } from '../models/SearchHistory.model';
import { requireAuth } from '../common/middlewares/auth.middleware';
import { validate } from '../common/middlewares/validate.middleware';
import { AppError } from '../common/errors/AppError';
import { deleteOwnAccount } from '../services/account-deletion.service';
import { clearOwnedData, conversationDto, missing, provePassword, safeUser, userTransaction } from '../services/user-data.service';
import { deleteAccountBody, idParams, profileBody, settingsBody } from '../validation/user-data.validation';

const router = Router();
router.use(requireAuth);
router.use((_req, res, next) => { res.setHeader('Cache-Control', 'no-store'); next(); });
router.get('/profile', async (req, res, next) => {
  try {
    const user = await User.findById(req.user!.id);
    if (!user) throw missing();
    res.json({success: true, data: await safeUser(user)});
  } catch (error) { next(error); }
});
router.patch('/profile', validate(z.object({body: profileBody})), async (req, res, next) => {
  try {
    const user = await userTransaction(req.user!.id, async session => {
      const current = await User.findById(req.user!.id).select('+passwordHash').session(session);
      if (!current) throw missing();
      const {email, displayName, avatarUrl, currentPassword} = req.body;
      if (email !== undefined && email !== current.email) {
        if (current.accountType !== AccountType.LOCAL) throw new AppError('Không thể đổi email của tài khoản liên kết hoặc dùng thử.', 400, 'EMAIL_CHANGE_NOT_ALLOWED');
        await provePassword(current, currentPassword);
        if (await User.exists({email, _id: {$ne: current._id}}).session(session)) throw new AppError('Email đã được sử dụng.', 409, 'AUTH_EMAIL_ALREADY_EXISTS');
        current.email = email;
      }
      if (displayName !== undefined) current.displayName = displayName;
      if (avatarUrl !== undefined) current.avatarUrl = avatarUrl || undefined;
      await current.save({session});
      return current;
    });
    res.json({success: true, data: await safeUser(user)});
  } catch (error) { next(error); }
});
router.get('/settings', async (req, res, next) => {
  try {
    const settings = await userTransaction(req.user!.id, session => UserSettings.findOneAndUpdate(
      {userId: req.user!.id}, {$setOnInsert: {userId: req.user!.id}}, {session, upsert: true, new: true, setDefaultsOnInsert: true}).exec());
    res.json({success: true, data: settings});
  } catch (error) { next(error); }
});
router.patch('/settings', validate(z.object({body: settingsBody})), async (req, res, next) => {
  try {
    const changes: Record<string, unknown> = {...req.body};
    if (req.body.notificationPreferences) {
      delete changes.notificationPreferences;
      for (const [key, value] of Object.entries(req.body.notificationPreferences)) changes[`notificationPreferences.${key}`] = value;
    }
    const settings = await userTransaction(req.user!.id, session => UserSettings.findOneAndUpdate(
      {userId: req.user!.id}, {$set: changes}, {session, upsert: true, new: true, runValidators: true, setDefaultsOnInsert: true}).exec());
    res.json({success: true, data: settings});
  } catch (error) { next(error); }
});
router.get('/data/export', async (req, res, next) => {
  try {
    const data = await userTransaction(req.user!.id, async session => {
      const userId = req.user!.id;
      const user = await User.findById(userId).session(session);
      if (!user) throw missing();
      const settings = await UserSettings.findOne({userId}).session(session);
      const favorites = await Favorite.find({userId}).select('entryId notes createdAt updatedAt').session(session);
      const conversations = await Conversation.find({userId}).sort({createdAt: -1}).session(session);
      const searchHistory = await SearchHistory.find({userId}).select('entryId viewedAt').session(session);
      return {profile: await safeUser(user), settings, favorites, conversations: conversations.map(conversationDto), searchHistory, exportedAt: new Date().toISOString()};
    });
    res.json({success: true, data});
  } catch (error) { next(error); }
});
router.delete('/data', validate(z.object({body: z.object({confirm: z.literal(true)}).strict()})), async (req, res, next) => {
  try {
    const counts = await userTransaction(req.user!.id, session => clearOwnedData(req.user!.id, session));
    res.json({success: true, data: {deleted: counts}});
  } catch (error) { next(error); }
});
router.get('/sessions', async (req, res, next) => {
  try {
    const current = await AuthSession.findById(req.sessionId);
    const sessions = await AuthSession.find({userId: req.user!.id, sessionType: SessionType.REFRESH, status: SessionStatus.ACTIVE, expiresAt: {$gt: new Date()}})
      .select('_id sessionFamily deviceInfo ipAddress createdAt lastUsedAt expiresAt').sort({lastUsedAt: -1});
    res.json({success: true, data: sessions.map(item => ({_id: item.id, deviceInfo: item.deviceInfo, ipAddress: item.ipAddress,
      createdAt: item.createdAt, lastUsedAt: item.lastUsedAt, expiresAt: item.expiresAt, current: item.sessionFamily === current?.sessionFamily}))});
  } catch (error) { next(error); }
});
router.delete('/sessions/:id', validate(z.object({params: idParams})), async (req, res, next) => {
  try {
    const revokedCurrent = await userTransaction(req.user!.id, async session => {
      const target = await AuthSession.findOne({_id: req.params.id, userId: req.user!.id}).session(session);
      if (!target) throw missing();
      const current = await AuthSession.findById(req.sessionId).session(session);
      const filter = target.sessionFamily ? {userId: req.user!.id, sessionFamily: target.sessionFamily} : {_id: target._id, userId: req.user!.id};
      await AuthSession.updateMany(filter, {$set: {status: SessionStatus.REVOKED, revokedAt: new Date()}}, {session});
      return !!current && (target.sessionFamily ? target.sessionFamily === current.sessionFamily : target.id === current.id);
    });
    if (revokedCurrent) res.clearCookie('signvoice_refresh', {path: '/api/v1/auth'});
    res.json({success: true, data: {revokedCurrent}});
  } catch (error) { next(error); }
});
router.delete('/account', validate(z.object({body: deleteAccountBody})), async (req, res, next) => {
  try {
    await deleteOwnAccount(req.user!.id, req.body.currentPassword);
    res.clearCookie('signvoice_refresh', {path: '/api/v1/auth'});
    res.json({success: true, data: {message: 'Đã xóa tài khoản và dữ liệu cá nhân.'}});
  } catch (error) { next(error); }
});
export default router;
