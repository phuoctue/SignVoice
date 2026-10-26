import {Types} from 'mongoose';
import {User} from '../models/User.model';
import {UserSettings} from '../models/UserSettings.model';
import {Conversation} from '../models/Conversation.model';
import {Favorite} from '../models/Favorite.model';
import {conversationDto, missing, safeUser, userTransaction} from './user-data.service';

export async function userBootstrap(userId: Types.ObjectId) {
  const [user, savedSettings, items, total, favorites] = await Promise.all([
    User.findById(userId),
    UserSettings.findOne({userId}),
    Conversation.find({userId}).sort({createdAt: -1, _id: -1}).limit(20),
    Conversation.countDocuments({userId}),
    Favorite.find({userId}).select('entryId').populate({path: 'entryId', match: {status: 'PUBLISHED'}, select: '_id categoryId',
      populate: {path: 'categoryId', match: {status: 'ACTIVE'}, select: '_id'}}).lean(),
  ]);
  if (!user) throw missing();
  const settings = savedSettings ?? await userTransaction(userId, session => UserSettings.findOneAndUpdate(
    {userId}, {$setOnInsert: {userId}}, {session, upsert: true, new: true, setDefaultsOnInsert: true}).exec());
  return {profile: await safeUser(user), settings,
    conversations: {items: items.map(conversationDto), total, page: 1, pages: Math.ceil(total / 20)},
    favorites: favorites.flatMap(item => {
      const entry = item.entryId as any;
      return entry?.categoryId?._id ? [{entryId: String(entry._id)}] : [];
    })};
}
