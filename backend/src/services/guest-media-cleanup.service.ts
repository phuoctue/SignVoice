import {GuestMediaCleanup} from '../models/GuestMediaCleanup.model';
import {User} from '../models/User.model';
import {ownedAvatarPath, removeOwnedAvatars} from './avatar-media.service';
import {authClock} from './auth-clock';

/** A later cleanup pass can retry durable jobs after a crash or filesystem outage. */
export async function retryGuestMediaCleanup(userId?: string, budget?: {check: () => Promise<void>}) {
  try {
    const jobs = await GuestMediaCleanup.find(userId ? {_id: userId} : {}).sort({lastAttemptAt: 1, createdAt: 1, _id: 1}).limit(25).lean();
    for (const job of jobs) {
      await budget?.check();
      let attempts = 0, removed = false;
      for (; attempts < 3; attempts++) {
        await budget?.check();
        try {
          if (job.paths.length !== 1 || job.paths[0] !== ownedAvatarPath(job._id) || await User.exists({_id: job._id})) {
            throw new Error('Media cleanup ownership changed');
          }
          await removeOwnedAvatars(job._id);
          removed = true; break;
        } catch { /* bounded retries; the durable job survives exhaustion */ }
      }
      await budget?.check();
      if (removed) await GuestMediaCleanup.deleteOne({_id: job._id});
      else {
        await GuestMediaCleanup.updateOne({_id: job._id}, {$inc: {attempts}, $set: {lastAttemptAt: authClock.now()}});
        console.warn('Guest media cleanup ALERT after 3 failed attempts; durable job retained for cleanup retry');
      }
    }
  } catch {console.warn('Guest media cleanup unavailable; committed discard is unchanged and durable jobs remain retryable');}
}
