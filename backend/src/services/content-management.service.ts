import mongoose, { ClientSession, Types } from 'mongoose';
import { DictionaryEntry, EntryStatus } from '../models/DictionaryEntry.model';
import { Category } from '../models/Category.model';
import { Favorite } from '../models/Favorite.model';
import { SearchHistory } from '../models/SearchHistory.model';
import { AuditLog, AuditAction } from '../models/AuditLog.model';
import { AppError } from '../common/errors/AppError';
type Actor = {id: Types.ObjectId; role: string; permissions: readonly string[]};
const missing = () => new AppError('Không tìm thấy nội dung.', 404, 'NOT_FOUND');
async function categories(session: ClientSession, ids: string[], requiredActive?: string) {
  for (const id of [...new Set(ids)].sort()) {
    const item = await Category.findOneAndUpdate({_id: id}, {$inc: {mutationVersion: 1}}, {session, new: true});
    if (!item || (id === requiredActive && item.status !== 'ACTIVE')) throw new AppError('Cần chọn danh mục đang hoạt động.', 400, 'CATEGORY_NOT_FOUND');
  }
}
async function counts(session: ClientSession, ids: string[]) {
  for (const id of [...new Set(ids)]) {
    const wordCount = await DictionaryEntry.countDocuments({categoryId: id, status: 'PUBLISHED'}).session(session);
    await Category.updateOne({_id: id}, {$set: {wordCount}}, {session});
  }
}
async function audit(session: ClientSession, actor: Actor, id: Types.ObjectId, action: AuditAction) {
  await AuditLog.create([{userId: actor.id, actorRole: actor.role, action, resourceType: 'DictionaryEntry', resourceId: id}], {session});
}
export async function writeContent(actor: Actor, body: Record<string, any>, id?: string) {
  return mongoose.connection.transaction(async session => {
    const existing = id ? await DictionaryEntry.findById(id).session(session) : null;
    if (id && !existing) throw missing();
    const publishes = actor.permissions.includes('content:publish');
    if (existing && !publishes && !actor.permissions.includes('admin:access') &&
        (String(existing.createdBy) !== String(actor.id) || existing.status !== 'DRAFT')) {
      throw new AppError('Bạn chỉ được sửa bản nháp do mình tạo.', 403, 'AUTH_FORBIDDEN');
    }
    const status = body.status ?? existing?.status ?? EntryStatus.DRAFT;
    if (!publishes && (status === EntryStatus.PUBLISHED || existing?.status === EntryStatus.PUBLISHED)) {
      throw new AppError('Bạn không có quyền quản lý nội dung đã xuất bản.', 403, 'AUTH_FORBIDDEN');
    }
    const oldCategory = existing ? String(existing.categoryId) : undefined;
    const category = String(body.categoryId ?? existing?.categoryId);
    const ids = oldCategory ? [oldCategory, category] : [category];
    await categories(session, ids, category);
    let result;
    if (existing) {
      const previousStatus = existing.status;
      Object.assign(existing, body, {lastModifiedBy: actor.id});
      if (status === EntryStatus.PUBLISHED && previousStatus !== status) existing.publishedAt = new Date();
      result = await existing.save({session});
    } else {
      [result] = await DictionaryEntry.create([{...body, status, createdBy: actor.id, lastModifiedBy: actor.id}], {session});
    }
    await counts(session, ids);
    await audit(session, actor, result._id, id ? AuditAction.ENTRY_UPDATE : AuditAction.ENTRY_CREATE);
    return result;
  });
}
export async function removeContent(actor: Actor, id: string) {
  await mongoose.connection.transaction(async session => {
    const entry = await DictionaryEntry.findById(id).session(session);
    if (!entry) throw missing();
    if (!actor.permissions.includes('content:publish') &&
        (entry.status === EntryStatus.PUBLISHED || (!actor.permissions.includes('admin:access') && String(entry.createdBy) !== String(actor.id)))) {
      throw new AppError('Bạn không có quyền xóa nội dung này.', 403, 'AUTH_FORBIDDEN');
    }
    const category = String(entry.categoryId);
    await categories(session, [category]);
    await DictionaryEntry.deleteOne({_id: id}, {session});
    await Favorite.deleteMany({entryId: id}, {session});
    await SearchHistory.deleteMany({entryId: id}, {session});
    await DictionaryEntry.updateMany({'relatedWords.entryId': id}, {$pull: {relatedWords: {entryId: entry._id}}}, {session});
    await counts(session, [category]);
    await audit(session, actor, entry._id, AuditAction.ENTRY_DELETE);
  });
}
export async function removeCategory(id: string) {
  await mongoose.connection.transaction(async session => {
    await categories(session, [id]);
    if (await DictionaryEntry.exists({categoryId: id}).session(session) || await Category.exists({parentId: id}).session(session)) {
      throw new AppError('Danh mục đang được sử dụng.', 409, 'CATEGORY_IN_USE');
    }
    await Category.deleteOne({_id: id}, {session});
  });
}
