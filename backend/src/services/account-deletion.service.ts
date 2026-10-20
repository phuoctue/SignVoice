import mongoose, { Types } from 'mongoose';
import { User, AuthSession, UserSettings, Conversation, Favorite, SearchHistory, AuditLog } from '../models';

/** Delete only the authenticated account. All changes commit or roll back together. */
export async function deleteOwnAccount(userId: Types.ObjectId): Promise<void> {
  await mongoose.connection.transaction(async session => {
    // Removing the account also makes any outstanding bearer/refresh tokens unusable.
    await User.deleteOne({ _id: userId }, { session });
    for (const model of [AuthSession, UserSettings, Conversation, Favorite, SearchHistory]) {
      await model.collection.deleteMany({ userId }, { session });
    }
    await AuditLog.deleteMany({ $or: [{ userId }, { resourceType: 'User', resourceId: userId }] }, { session });
  });
}
