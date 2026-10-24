import { administratorTransaction } from './administrator-transaction.service';
import { Types } from 'mongoose';
import { User, AuthSession, AuditLog } from '../models';
import { AppError } from '../common/errors/AppError';
import { clearOwnedData, provePassword } from './user-data.service';

/** Delete only the authenticated account. All changes commit or roll back together. */
export async function deleteOwnAccount(userId: Types.ObjectId, currentPassword?: string): Promise<void> {
  await administratorTransaction(async session => {
    await User.updateOne({_id: userId}, {$inc: {dataVersion: 1}}, {session});
    const user = await User.findById(userId).select('+passwordHash').session(session);
    if (!user) throw new AppError('Không tìm thấy tài khoản.', 404, 'NOT_FOUND');
    await provePassword(user, currentPassword);
    await clearOwnedData(userId, session);
    // Removing the account also makes any outstanding bearer/refresh tokens unusable.
    await User.deleteOne({ _id: userId }, { session });
    for (const model of [AuthSession]) {
      await model.collection.deleteMany({ userId }, { session });
    }
    await AuditLog.deleteMany({ $or: [{ userId }, { resourceType: 'User', resourceId: userId }] }, { session });
  });
}
