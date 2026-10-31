import {connectDatabase, disconnectDatabase} from '../src/config/database';
import {User, AuthSession, AuditLog} from '../src/models';
import {clearOwnedData, userTransaction} from '../src/services/user-data.service';

async function main() {
  await connectDatabase();
  try {
    const ids = process.argv.slice(2).filter(value => /^[a-f0-9]{24}$/.test(value));
    const filter = {email: /^qa-fcm-[a-f0-9]+@example\.test$/, displayName: 'Kiểm thử thông báo', role: 'USER',
      isGuest: false, createdAt: {$gte: new Date(Date.now() - 2 * 3600000)}, ...(ids.length ? {_id: {$in: ids}} : {})};
    const users = await User.find(filter).select('_id email createdAt').lean();
    console.log(JSON.stringify(users, null, 2));
    if (!process.argv.includes('--apply')) return;
    if (!ids.length || ids.length > 10 || users.length !== ids.length) throw new Error('Explicit matching QA IDs required; no accounts were removed.');
    for (const user of users) {
      await userTransaction(user._id, async session => {
        if (!await User.exists({...filter, _id: user._id}).session(session)) throw new Error('QA identity changed; aborting cleanup.');
        await clearOwnedData(user._id, session);
        await AuthSession.deleteMany({userId: user._id}, {session});
        await AuditLog.deleteMany({userId: user._id}, {session});
        await User.deleteOne({_id: user._id}, {session});
      });
    }
    console.log(`Removed ${users.length} scoped FCM probe accounts.`);
  } finally {await disconnectDatabase();}
}
main().catch(error => {console.error('QA cleanup failed:', error.message); process.exitCode = 1;});
