import { Router, Request, Response, NextFunction } from 'express';
import { Category } from '../models/Category.model';
import { requireAuth, requirePermission } from '../common/middlewares/auth.middleware';

const router = Router();

/**
 * @route GET /api/v1/categories
 * @desc Get active categories
 * @access Public
 */
router.get('/', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const categories = await Category.find({ status: 'ACTIVE' })
      .sort({ sortOrder: 1, name: 1 })
      .select('name slug description icon sortOrder wordCount parentId status createdAt updatedAt')
      .exec();
    
    res.status(200).json({
      success: true,
      data: categories,
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/categories/:slug
 * @desc Get category by slug
 * @access Public
 */
router.get('/:slug', async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    const category = await Category.findOne({
      slug: req.params.slug,
      status: 'ACTIVE',
    }).exec();
    
    if (!category) {
      res.status(404).json({
        success: false,
        error: {
          code: 'CATEGORY_NOT_FOUND',
          message: 'Category not found',
        },
      });
      return;
    }
    
    res.status(200).json({
      success: true,
      data: category,
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route POST /api/v1/categories
 * @desc Create category (ADMIN only)
 * @access Private (ADMIN)
 */
router.post('/', requireAuth, requirePermission('categories:write'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const category = await Category.create(req.body);
    
    res.status(201).json({
      success: true,
      data: category,
    });
  } catch (error) {
    next(error);
  }
});

export default router;
