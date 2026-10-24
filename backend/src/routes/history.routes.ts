import { Router, Request, Response, NextFunction } from 'express';
import { SearchHistory } from '../models/SearchHistory.model';
import { requireAuth } from '../common/middlewares/auth.middleware';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';
import { z } from 'zod';
import { validate } from '../common/middlewares/validate.middleware';
import { offsetQuery } from '../validation/user-data.validation';

const router = Router();

// All history routes require authentication
router.use(requireAuth);

/**
 * @route GET /api/v1/history
 * @desc Get user's search history
 * @access Private
 */
router.get('/', validate(z.object({query: offsetQuery})), async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    const { limit, skip } = req.query;
    
    const history = await SearchHistory.find({ userId: req.user.id })
      .sort({ viewedAt: -1 })
      .limit(limit ? parseInt(limit as string) : 50)
      .skip(skip ? parseInt(skip as string) : 0)
      .populate({
        path: 'entryId',
        populate: {path: 'categoryId', select: 'name slug'},
        match: { status: 'PUBLISHED' },
      })
      .exec();
    
    res.status(200).json({
      success: true,
      data: history,
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route DELETE /api/v1/history
 * @desc Clear user's search history
 * @access Private
 */
router.delete('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    const result = await SearchHistory.deleteMany({ userId: req.user.id });
    
    res.status(200).json({
      success: true,
      data: {
        message: 'History cleared',
        deletedCount: result.deletedCount,
      },
    });
  } catch (error) {
    next(error);
  }
});

export default router;
