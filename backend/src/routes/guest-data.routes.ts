import {Router} from 'express';
import {z} from 'zod';
import {requireAuth} from '../common/middlewares/auth.middleware';
import {validate} from '../common/middlewares/validate.middleware';
import {discardGuest} from '../services/guest-data.service';
const router = Router();
router.post('/discard', requireAuth, validate(z.object({body: z.object({
  expectedDataVersion: z.number().int().nonnegative().safe(), confirmDiscard: z.literal(true),
}).strict()})), async (req, res, next) => {
  try {
    await discardGuest(req.user!.id, req.sessionId!, req.body.expectedDataVersion);
    res.json({success: true, data: {discarded: true}});
  } catch (error) {next(error);}
});
export default router;
