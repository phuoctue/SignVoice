import { Router } from 'express';
import { z } from 'zod';
import { Favorite } from '../models/Favorite.model';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { Category } from '../models/Category.model';
import { requireAuth, requirePermanentAccount } from '../common/middlewares/auth.middleware';
import { validate } from '../common/middlewares/validate.middleware';
import { objectId, offsetQuery } from '../validation/user-data.validation';
import { userTransaction, missing } from '../services/user-data.service';

const router = Router();
router.use(requireAuth);
router.use((req, res, next) => ['POST', 'PATCH'].includes(req.method) ? requirePermanentAccount(req, res, next) : next());
router.get('/', validate(z.object({query: offsetQuery})), async (req, res, next) => {
  try {
    const {limit, skip} = req.query as unknown as z.infer<typeof offsetQuery>;
    const categories = await Category.find({status: 'ACTIVE'}).distinct('_id');
    const entries = await DictionaryEntry.find({status: 'PUBLISHED', categoryId: {$in: categories}}).distinct('_id');
    const filter = {userId: req.user!.id, entryId: {$in: entries}};
    const [items, total] = await Promise.all([
      Favorite.find(filter).sort({createdAt: -1}).skip(skip).limit(limit).populate({path: 'entryId', populate: {path: 'categoryId', select: 'name slug'}}),
      Favorite.countDocuments(filter),
    ]);
    res.json({success: true, data: items.map(item => {
      const entry = item.entryId as any;
      return {_id: item.id, id: item.id, userId: String(item.userId), entryId: String(entry._id), entry, notes: item.notes, createdAt: item.createdAt};
    }), pagination: {total, limit, skip}});
  } catch (error) { next(error); }
});
router.post('/', validate(z.object({body: z.object({entryId: objectId, notes: z.string().max(1000).optional()}).strict()})), async (req, res, next) => {
  try {
    const favorite = await userTransaction(req.user!.id, async session => {
      const entry = await DictionaryEntry.findOne({_id: req.body.entryId, status: 'PUBLISHED'}).session(session);
      if (!entry || !await Category.exists({_id: entry.categoryId, status: 'ACTIVE'}).session(session)) throw missing();
      let item = await Favorite.findOne({userId: req.user!.id, entryId: entry._id}).session(session);
      if (!item) {
        [item] = await Favorite.create([{userId: req.user!.id, entryId: entry._id, notes: req.body.notes}], {session});
      }
      const favoriteCount = await Favorite.countDocuments({entryId: entry._id}).session(session);
      await DictionaryEntry.updateOne({_id: entry._id}, {$set: {favoriteCount}}, {session});
      return item;
    });
    res.status(201).json({success: true, data: {...favorite.toObject(), id: favorite.id, entryId: String(favorite.entryId), userId: String(favorite.userId)}});
  } catch (error) { next(error); }
});
router.delete('/:entryId', validate(z.object({params: z.object({entryId: objectId})})), async (req, res, next) => {
  try {
    await userTransaction(req.user!.id, async session => {
      await Favorite.deleteOne({userId: req.user!.id, entryId: req.params.entryId}, {session});
      const favoriteCount = await Favorite.countDocuments({entryId: req.params.entryId}).session(session);
      await DictionaryEntry.updateOne({_id: req.params.entryId}, {$set: {favoriteCount}}, {session});
    });
    res.json({success: true, data: {message: 'Đã bỏ yêu thích.'}});
  } catch (error) { next(error); }
});
export default router;
