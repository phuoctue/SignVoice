import {User} from '../models/User.model';
import {DictionaryEntry} from '../models/DictionaryEntry.model';

/** Fresh request-scoped counts: one database round-trip per collection. */
export async function accountStats(now: Date) {
  const nonGuest = {$eq: ['$isGuest', false]};
  const [stats] = await User.aggregate([{$group: {
    _id: null,
    total: {$sum: {$cond: [nonGuest, 1, 0]}},
    active: {$sum: {$cond: [{$and: [nonGuest, {$eq: ['$status', 'ACTIVE']}]}, 1, 0]}},
    guest: {$sum: {$cond: [{$eq: ['$isGuest', true]}, 1, 0]}},
    staff: {$sum: {$cond: [{$eq: ['$role', 'STAFF']}, 1, 0]}},
    admin: {$sum: {$cond: [{$eq: ['$role', 'ADMIN']}, 1, 0]}},
    newThisMonth: {$sum: {$cond: [{$and: [nonGuest, {$gte: ['$createdAt', new Date(now.getTime()-30*86400000)]}]}, 1, 0]}},
    newThisWeek: {$sum: {$cond: [{$and: [nonGuest, {$gte: ['$createdAt', new Date(now.getTime()-7*86400000)]}]}, 1, 0]}},
  }}, {$project: {_id: 0}}]);
  return stats ?? {total: 0, active: 0, guest: 0, staff: 0, admin: 0, newThisMonth: 0, newThisWeek: 0};
}

export async function contentStats() {
  const [stats] = await DictionaryEntry.aggregate([{$group: {
    _id: null, total: {$sum: 1},
    published: {$sum: {$cond: [{$eq: ['$status', 'PUBLISHED']}, 1, 0]}},
    pending: {$sum: {$cond: [{$eq: ['$status', 'DRAFT']}, 1, 0]}},
  }}, {$project: {_id: 0}}]);
  return stats ?? {total: 0, published: 0, pending: 0};
}
