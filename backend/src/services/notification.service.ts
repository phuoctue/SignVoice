import {GoogleAuth} from 'google-auth-library';
import {Types} from 'mongoose';
import {User} from '../models/User.model';
import {UserSettings} from '../models/UserSettings.model';
import {Category} from '../models/Category.model';
import {DictionaryEntry} from '../models/DictionaryEntry.model';
import {WordProgress} from '../models/Learning.model';
import {NotificationDevice, UserNotification} from '../models/Notification.model';
import {AuthSession} from '../models/AuthSession.model';
import {userTransaction} from './user-data.service';
import {dueStudyReminder} from './study-reminder-notice';

const day = 86400000;
export const pushConfigured = () => !!process.env.GOOGLE_APPLICATION_CREDENTIALS && !!process.env.FIREBASE_PROJECT_ID;
export async function refreshNotifications(userId: Types.ObjectId) {
  const [user, settings] = await Promise.all([User.findById(userId).lean(), UserSettings.findOne({userId}).lean()]);
  if (!user || user.status !== 'ACTIVE' || user.isGuest) return;
  const due = dueStudyReminder(settings?.studyReminder, new Date(), settings?.studyReminderConfiguredAt);
  if (due) {
    await userTransaction(userId, async session => UserNotification.updateOne({userId, key: due.key}, {$setOnInsert: {
      userId, key: due.key, kind: 'STUDY_REMINDER', title: 'Đến giờ học rồi!',
      body: `Đã đến lịch học ${due.time}. Cùng học thêm ký hiệu và ôn lại các từ đã nhớ nhé.`,
      route: '/learn?tab=1', read: false, expiresAt: new Date(Date.now() + 30 * day),
    }}, {upsert: true, session}).exec());
  }
  if (settings?.notificationsEnabled === false) return;
  const now = new Date(), date = now.toISOString().slice(0, 10);
  const categories = await Category.find({status: 'ACTIVE'}).select('_id').lean();
  const categoryIds = categories.map(item => item._id);
  const write = async (kind: string, title: string, body: string, route: string) => {
    const key = `${kind}:${date}`;
    await userTransaction(userId, async session => UserNotification.updateOne({userId, key}, {$setOnInsert: {
      userId, key, kind, title, body, route, read: false, expiresAt: new Date(+now + 30 * day),
    }}, {upsert: true, session}).exec());
  };
  if (settings?.notificationPreferences?.newWords !== false) {
    const since = new Date(Math.max(+new Date(user.createdAt), +now - day));
    const count = await DictionaryEntry.countDocuments({status: 'PUBLISHED', categoryId: {$in: categoryIds}, publishedAt: {$gte: since, $lte: now}});
    if (count) await write('NEW_WORDS', 'Có ký hiệu mới', `${count} từ mới trong từ điển đang chờ bạn khám phá.`, '/learn');
  }
  if (settings?.notificationPreferences?.favorites !== false) {
    const due = await WordProgress.find({userId, topicId: {$in: categoryIds}, $or: [
      {stage: 'REVIEW'}, {stage: 'REMEMBERED', nextReviewAt: {$ne: null, $lte: now}},
    ]}).select('entryId').lean();
    const count = due.length ? await DictionaryEntry.countDocuments({_id: {$in: due.map(item => item.entryId)}, status: 'PUBLISHED'}) : 0;
    if (count) await write('REVIEW', 'Đến lúc ôn lại', `Bạn có ${count} từ cần ôn tập. Cùng củng cố ký hiệu đã học nhé.`, '/learn?tab=1');
  }
}

let googleAuth: GoogleAuth | undefined;
async function sendPush(token: string, notice: any) {
  googleAuth ??= new GoogleAuth({keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging']});
  const client = await googleAuth.getClient();
  await client.request({url: `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(process.env.FIREBASE_PROJECT_ID!)}/messages:send`, method: 'POST',
    data: {message: {token, data: {userId: String(notice.userId), title: notice.title, body: notice.body,
      route: notice.route, notificationId: String(notice._id), expiresAt: String(+new Date(notice.expiresAt))},
      android: {priority: 'high', ttl: '86400s'}}}, timeout: 15000});
}

/** One bounded batch, leased per installation so overlapping server processes do not double-send. */
export async function deliverNotificationBatch(send = sendPush, onlyUser?: Types.ObjectId) {
  if (!pushConfigured()) return;
  const startedAt = new Date();
  for (let i = 0; i < 20; i++) {
    const now = new Date();
    const device = await NotificationDevice.findOneAndUpdate({...(onlyUser ? {userId: onlyUser} : {}), expiresAt: {$gt: now}, leaseUntil: {$lte: now}, checkedAt: {$lt: onlyUser ? startedAt : new Date(+now - 60000)}},
      {$set: {leaseUntil: new Date(+now + 120000), checkedAt: now}}, {new: true, sort: {checkedAt: 1}});
    if (!device) break;
    try {
      const user = await User.findOne({_id: device.userId, status: 'ACTIVE', isGuest: false});
      if (!user) {await NotificationDevice.deleteOne({_id: device._id}); continue;}
      const activeSession = await AuthSession.exists({userId: device.userId, sessionFamily: device.sessionFamily, sessionType: 'REFRESH', status: 'ACTIVE', expiresAt: {$gt: now}, passwordVersion: user.passwordVersion});
      // Token refresh temporarily revokes the old family before transferring
      // the device. Preserve registration across that handoff window.
      if (!activeSession) continue;
      const settings = await UserSettings.findOne({userId: device.userId}).lean();
      if (settings?.notificationsEnabled === false) continue;
      await refreshNotifications(device.userId);
      const notices = await UserNotification.find({userId: device.userId, createdAt: {$gt: device.deliveredAt}, expiresAt: {$gt: now}}).sort({createdAt: 1}).limit(10);
      for (const notice of notices) {
        // Android already schedules this reminder locally, including while offline.
        const enabled = notice.kind !== 'STUDY_REMINDER' && (notice.kind === 'TEST' || (notice.kind === 'NEW_WORDS' ? settings?.notificationPreferences?.newWords !== false : settings?.notificationPreferences?.favorites !== false));
        // Re-check ownership immediately before delivery after a token transfer/logout.
        if (!await NotificationDevice.exists({_id: device._id, userId: device.userId})) break;
        if (enabled && !notice.read) await send(device.token, notice);
        await NotificationDevice.updateOne({_id: device._id, userId: device.userId}, {$set: {deliveredAt: notice.createdAt}});
      }
    } catch (error: any) {
      const code = error?.response?.data?.error?.details?.find((item: any) => item.errorCode)?.errorCode;
      if (code === 'UNREGISTERED') await NotificationDevice.deleteOne({_id: device._id, userId: device.userId});
      else console.warn('Push delivery deferred:', code || error?.code || 'FCM_ERROR');
    } finally {
      await NotificationDevice.updateOne({_id: device._id, userId: device.userId}, {$set: {leaseUntil: new Date(0)}});
    }
  }
}

export function startNotificationDelivery() {
  let running = false;
  const tick = async () => {if (running) return; running = true; try {await deliverNotificationBatch();} catch {console.warn('Notification batch deferred.');} finally {running = false;}};
  const timer = setInterval(() => {void tick();}, 60000);
  timer.unref();
  void tick();
  return () => clearInterval(timer);
}
