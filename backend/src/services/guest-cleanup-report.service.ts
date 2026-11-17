import mongoose, {Types} from 'mongoose';
import {User} from '../models/User.model';
import {UserSettings} from '../models/UserSettings.model';
import {Favorite} from '../models/Favorite.model';
import {Conversation} from '../models/Conversation.model';
import {SearchHistory} from '../models/SearchHistory.model';
import {TopicEnrollment, WordProgress, PersonalWord} from '../models/Learning.model';
import {ReviewQuiz} from '../models/ReviewQuiz.model';
import {LearningEvent} from '../models/LearningEvent.model';
import {NotificationDevice, UserNotification} from '../models/Notification.model';
import {SignCollection, SignNote, CollectionReport} from '../models/SignCollection.model';
import {AuditLog} from '../models/AuditLog.model';
import {AuthSession} from '../models/AuthSession.model';
import {SessionChain} from '../models/SessionChain.model';
import {GuestTrial} from '../models/GuestTrial.model';
import {GuestMediaCleanup} from '../models/GuestMediaCleanup.model';
import {cleanupClassification} from './guest-cleanup-candidates.service';

/** No writes, initialization, indexes, outbox barriers or media calls, even on an empty DB. */
export async function guestCleanupDryRun(now: Date) {
  if (!(now instanceof Date) || !Number.isFinite(+now)) throw new Error('Explicit report time required');
  const session = await mongoose.startSession();
  try {
    return await session.withTransaction(async () => {
      const counts = {ordinary_expired: 0, legacy_unknown: 0, synthetic_exempt: 0, converted_permanent_skipped: 0, not_due: 0};
      const list: {userId: string; deadline: string | null; category: keyof typeof counts}[] = [];
      const ids: Types.ObjectId[] = [];
      const cursor = User.find().select('_id').sort({_id: 1}).session(session).lean().cursor();
      try {
        for await (const row of cursor) {
          const {category, deadline} = await cleanupClassification(row._id, now, session);
          counts[category]++;
          list.push({userId: String(row._id), deadline: deadline?.toISOString() ?? null, category});
          if (category === 'ordinary_expired' || category === 'legacy_unknown') ids.push(row._id);
        }
      } finally {await cursor.close();}
      const owned = {userId: {$in: ids}}, documents: Record<string, number> = {};
      documents[User.collection.name] = ids.length;
      for (const model of [UserSettings, Favorite, Conversation, SearchHistory, TopicEnrollment, WordProgress, PersonalWord,
        ReviewQuiz, LearningEvent, NotificationDevice, UserNotification, SignCollection, SignNote]) {
        documents[model.collection.name] = await model.collection.countDocuments(owned, {session});
      }
      const collections = await SignCollection.find(owned).select('_id').session(session).lean();
      documents[CollectionReport.collection.name] = await CollectionReport.countDocuments({$or: [owned, {collectionId: {$in: collections.map(c => c._id)}}]}).session(session);
      documents[AuditLog.collection.name] = await AuditLog.countDocuments({$or: [owned, {resourceType: 'User', resourceId: {$in: ids}}]}).session(session);
      // Revocation fences and cooldowns are retained; they are not deletion totals.
      for (const model of [AuthSession, SessionChain, GuestTrial]) documents[model.collection.name] = 0;
      return {asOf: now.toISOString(), counts, list, documents,
        sessionsToRevoke: await AuthSession.countDocuments({...owned, status: 'ACTIVE'}).session(session),
        pendingMediaJobs: await GuestMediaCleanup.countDocuments().session(session)};
    }, {readConcern: {level: 'snapshot'}, timeoutMS: 120000});
  } finally {await session.endSession();}
}
