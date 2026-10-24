import mongoose, { ClientSession } from 'mongoose';
import { User } from '../models/User.model';
import { Role } from '../models/Role.model';
import { AppError } from '../common/errors/AppError';

async function activeAdministrators(session: ClientSession) {
  const roles = await Role.find({permissions: 'admin:access'}).distinct('_id').session(session);
  return User.countDocuments({status: 'ACTIVE', $or: [
    {customRoleId: {$in: roles}}, {role: 'ADMIN', customRoleId: null},
  ]}).session(session);
}
/** Shared by self deletion and administrative role/account mutations. */
export async function administratorTransaction<T>(operation: (session: ClientSession) => Promise<T>): Promise<T> {
  const locks = mongoose.connection.db!.collection<{_id: string; version: number}>('account_operation_locks');
  try { await locks.updateOne({_id: 'administrators'}, {$setOnInsert: {version: 0}}, {upsert: true}); }
  catch (error: any) { if (error.code !== 11000) throw error; }
  return mongoose.connection.transaction(async session => {
    await locks.updateOne({_id: 'administrators'}, {$inc: {version: 1}}, {session});
    const before = await activeAdministrators(session);
    const result = await operation(session);
    if (before > 0 && await activeAdministrators(session) === 0) {
      throw new AppError('Không thể xóa, khóa hoặc hạ quyền quản trị viên hoạt động cuối cùng.', 409, 'LAST_ADMIN_REQUIRED');
    }
    return result;
  });
}
