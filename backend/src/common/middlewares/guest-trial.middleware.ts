import {Request, Response, NextFunction} from 'express';
import {assertTrialActive} from '../../services/guest-trial.service';
export async function requireActiveTrial(req: Request, _res: Response, next: NextFunction) {
  try { await assertTrialActive(req.user!.id); next(); } catch (error) { next(error); }
}
