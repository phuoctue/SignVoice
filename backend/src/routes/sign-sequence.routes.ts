import { Router } from 'express';
import { DictionaryEntry, EntryStatus } from '../models/DictionaryEntry.model';
import { composeSignSequence } from '../services/sign-sequence';
import {requireAuth} from '../common/middlewares/auth.middleware';
import {requireActiveTrial} from '../common/middlewares/guest-trial.middleware';

const router = Router();
router.post('/', requireAuth, requireActiveTrial, async (req, res, next) => {
  try {
    const text = req.body?.text;
    if (typeof text !== 'string' || !text.trim() || text.length > 2000) {
      res.status(400).json({ success: false, error: { code: 'INVALID_TEXT', message: 'Văn bản phải có từ 1 đến 2.000 ký tự.' } });
      return;
    }
    const entries = await DictionaryEntry.find({ status: EntryStatus.PUBLISHED })
      .select('_id word aliases videoUrl thumbnailUrl imageUrls notes').sort({ _id: 1 }).limit(10001).lean();
    if (entries.length > 10000) {
      res.status(503).json({ success: false, error: { code: 'CATALOG_TOO_LARGE', message: 'Kho ký hiệu cần được lập chỉ mục lại.' } });
      return;
    }
    res.setHeader('Cache-Control', 'no-store');
    res.json({ success: true, data: composeSignSequence(text, entries) });
  } catch (error) { next(error); }
});
export default router;
