import {Router} from 'express';
import {requireAuth} from '../common/middlewares/auth.middleware';
import {guestTrialStatus, createAiTicket} from '../services/guest-trial.service';
import {bindExistingGuestDevice} from '../services/guest-device.service';
import {z} from 'zod';
import {validate} from '../common/middlewares/validate.middleware';
import {guestDeviceFields, guestSchema} from '../validation/auth.validation';
const router = Router();
router.use(requireAuth);
router.get('/status', validate(z.object({query: guestDeviceFields})), async (req, res, next) => {
  try {await bindExistingGuestDevice(req, res); res.setHeader('Cache-Control', 'no-store'); res.json({success: true, data: await guestTrialStatus(req.user!.id)});}
  catch (error) {next(error);}
});
router.post('/start', validate(guestSchema), async (req, res, next) => {
  try {await bindExistingGuestDevice(req, res); res.setHeader('Cache-Control', 'no-store'); res.json({success: true, data: await guestTrialStatus(req.user!.id, true)});}
  catch (error) {next(error);}
});
router.post('/ai-ticket', validate(z.object({body: z.object({}).strict().default({})})), async (req, res, next) => {
  try {res.setHeader('Cache-Control', 'no-store'); res.json({success: true, data: {ticket: await createAiTicket(req.user!.id, req.sessionId!)}});}
  catch (error) {next(error);}
});
export default router;
