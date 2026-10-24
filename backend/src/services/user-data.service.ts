import mongoose, { ClientSession, Types } from 'mongoose';
import { User, IUser, AccountStatus, AccountType } from '../models/User.model';
import { UserSettings } from '../models/UserSettings.model';
import { Favorite } from '../models/Favorite.model';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { Conversation } from '../models/Conversation.model';
import { SearchHistory } from '../models/SearchHistory.model';
import { authorizationFor } from './authorization.service';
import { verifyPassword } from '../utils/password.util';
import { AppError } from '../common/errors/AppError';

export const missing = () => new AppError('Không tìm thấy dữ liệu.', 404, 'NOT_FOUND');
export async function safeUser(user: IUser) {
  return {
    _id: user.id, id: user.id, email: user.email, displayName: user.displayName,
    avatarUrl: user.avatarUrl, accountType: user.accountType, isGuest: user.isGuest,
    status: user.status, createdAt: user.createdAt, updatedAt: user.updatedAt,
    ...await authorizationFor(user),
  };
}
export async function provePassword(user: IUser, password?: string) {
  if (user.accountType !== AccountType.LOCAL) return;
  if (!password || !user.passwordHash || !await verifyPassword(user.passwordHash, password)) {
    throw new AppError('Mật khẩu hiện tại không đúng.', 400, 'PASSWORD_PROOF_INVALID');
  }
}
/** The account write makes concurrent save/reset/deletion conflict instead of leaving orphan data. */
export async function userTransaction<T>(userId: Types.ObjectId, operation: (session: ClientSession) => Promise<T>): Promise<T> {
  return mongoose.connection.transaction(async session => {
    const lock = await User.updateOne({_id: userId, status: AccountStatus.ACTIVE}, {$inc: {dataVersion: 1}}, {session});
    if (!lock.matchedCount) throw missing();
    return operation(session);
  });
}
export async function clearOwnedData(userId: Types.ObjectId, session: ClientSession) {
  const favorites = await Favorite.find({userId}).session(session);
  const removedFavorites = await Favorite.deleteMany({userId}, {session});
  for (const item of favorites) {
    const favoriteCount = await Favorite.countDocuments({entryId: item.entryId}).session(session);
    await DictionaryEntry.updateOne({_id: item.entryId}, {$set: {favoriteCount}}, {session});
  }
  const conversations = await Conversation.deleteMany({userId}, {session});
  const history = await SearchHistory.deleteMany({userId}, {session});
  await UserSettings.deleteOne({userId}, {session});
  return {favorites: removedFavorites.deletedCount, conversations: conversations.deletedCount, searchHistory: history.deletedCount};
}
export function conversationDto(item: any) {
  return {_id: String(item._id), content: item.content ?? item.messages.map((message: any) => message.content).join('\n'),
    direction: item.direction ?? 'TEXT', favorite: item.favorite ?? false, createdAt: item.createdAt, updatedAt: item.updatedAt};
}
