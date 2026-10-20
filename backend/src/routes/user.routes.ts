import { Router, Request, Response, NextFunction } from 'express';
import { User } from '../models/User.model';
import { UserSettings } from '../models/UserSettings.model';
import { requireAuth } from '../common/middlewares/auth.middleware';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';
import { deleteOwnAccount } from '../services/account-deletion.service';

const router = Router();

// All user routes require authentication
router.use(requireAuth);

router.delete('/account', async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.user) throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    await deleteOwnAccount(req.user.id);
    res.clearCookie('signvoice_refresh', { path: '/api/v1/auth' });
    res.setHeader('Cache-Control', 'no-store');
    res.json({ success: true, data: { message: 'Đã xóa tài khoản và dữ liệu cá nhân trên hệ thống đang hoạt động.' } });
  } catch (error) { next(error); }
});

/**
 * @route GET /api/v1/users/profile
 * @desc Get current user profile
 * @access Private
 */
router.get('/profile', async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    const user = await User.findById(req.user.id).select('-passwordHash').exec();
    
    if (!user) {
      throw new AppError('User not found', 404, ErrorCodes.USER_NOT_FOUND);
    }
    
    res.status(200).json({
      success: true,
      data: user,
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route PATCH /api/v1/users/profile
 * @desc Update user profile
 * @access Private
 */
router.patch('/profile', async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    const { displayName, avatarUrl } = req.body;
    const allowedUpdates: any = {};
    
    if (displayName) allowedUpdates.displayName = displayName;
    if (avatarUrl !== undefined) allowedUpdates.avatarUrl = avatarUrl;
    
    const user = await User.findByIdAndUpdate(
      req.user.id,
      { $set: allowedUpdates },
      { new: true, runValidators: true }
    ).select('-passwordHash');
    
    if (!user) {
      throw new AppError('User not found', 404, ErrorCodes.USER_NOT_FOUND);
    }
    
    res.status(200).json({
      success: true,
      data: user,
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route GET /api/v1/users/settings
 * @desc Get user settings
 * @access Private
 */
router.get('/settings', async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    let settings = await UserSettings.findOne({ userId: req.user.id }).exec();
    
    if (!settings) {
      settings = await UserSettings.create({ userId: req.user.id });
    }
    
    res.status(200).json({
      success: true,
      data: settings,
    });
  } catch (error) {
    next(error);
  }
});

/**
 * @route PATCH /api/v1/users/settings
 * @desc Update user settings
 * @access Private
 */
router.patch('/settings', async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.user) {
      throw new AppError('Authentication required', 401, ErrorCodes.AUTH_REQUIRED);
    }
    
    const settings = await UserSettings.findOneAndUpdate(
      { userId: req.user.id },
      { $set: req.body },
      { new: true, runValidators: true, upsert: true }
    );
    
    res.status(200).json({
      success: true,
      data: settings,
    });
  } catch (error) {
    next(error);
  }
});

export default router;
