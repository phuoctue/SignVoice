import { Router } from 'express';
import { z } from 'zod';
import { Conversation } from '../models/Conversation.model';
import { requireAuth, requirePermanentAccount } from '../common/middlewares/auth.middleware';
import { validate } from '../common/middlewares/validate.middleware';
import { conversationBody, conversationPatch, conversationQuery, idParams, literalSearch } from '../validation/user-data.validation';
import { conversationDto, missing, userTransaction } from '../services/user-data.service';

const router = Router();
router.use(requireAuth);
router.use((req, res, next) => ['POST', 'PATCH'].includes(req.method) ? requirePermanentAccount(req, res, next) : next());
router.get('/', validate(z.object({query: conversationQuery})), async (req, res, next) => {
  try {
    const query = req.query as unknown as z.infer<typeof conversationQuery>;
    const filter: any = {userId: req.user!.id};
    if (query.search) filter.content = {$regex: literalSearch(query.search), $options: 'i'};
    if (query.direction) filter.direction = query.direction;
    if (query.favorite !== undefined) filter.favorite = query.favorite;
    const [items, total] = await Promise.all([
      Conversation.find(filter).sort({createdAt: -1, _id: -1}).skip((query.page - 1) * query.limit).limit(query.limit),
      Conversation.countDocuments(filter),
    ]);
    res.json({success: true, data: {items: items.map(conversationDto), total, page: query.page, pages: Math.ceil(total / query.limit)}});
  } catch (error) { next(error); }
});
router.get('/:id', validate(z.object({params: idParams})), async (req, res, next) => {
  try {
    const item = await Conversation.findOne({_id: req.params.id, userId: req.user!.id});
    if (!item) throw missing();
    res.json({success: true, data: conversationDto(item)});
  } catch (error) { next(error); }
});
router.post('/', validate(z.object({body: conversationBody})), async (req, res, next) => {
  try {
    const item = await userTransaction(req.user!.id, async session => {
      const [created] = await Conversation.create([{...req.body, userId: req.user!.id}], {session});
      return created;
    });
    res.status(201).json({success: true, data: conversationDto(item)});
  } catch (error) { next(error); }
});
router.patch('/:id', validate(z.object({params: idParams, body: conversationPatch})), async (req, res, next) => {
  try {
    const item = await userTransaction(req.user!.id, async session => {
      const updated = await Conversation.findOneAndUpdate({_id: req.params.id, userId: req.user!.id}, {$set: req.body}, {session, new: true, runValidators: true});
      if (!updated) throw missing();
      return updated;
    });
    res.json({success: true, data: conversationDto(item)});
  } catch (error) { next(error); }
});
router.delete('/:id', validate(z.object({params: idParams})), async (req, res, next) => {
  try {
    await userTransaction(req.user!.id, async session => {
      const result = await Conversation.deleteOne({_id: req.params.id, userId: req.user!.id}, {session});
      if (!result.deletedCount) throw missing();
    });
    res.json({success: true, data: {deletedCount: 1}});
  } catch (error) { next(error); }
});
router.delete('/', async (req, res, next) => {
  try {
    const result = await userTransaction(req.user!.id, session => Conversation.deleteMany({userId: req.user!.id}, {session}).exec());
    res.json({success: true, data: {deletedCount: result.deletedCount}});
  } catch (error) { next(error); }
});
export default router;
