import { Request, Response, NextFunction } from 'express';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { User } from '../models/User.model';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';
import { updateDictionary } from './admin-management.controller';
import { literalSearch } from '../validation/user-data.validation';
import { safeUser } from '../services/user-data.service';

/**
 * GET /api/v1/staff/content
 * Get content items for moderation with filters
 */
export async function getContentForModeration(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const {
      status,
      category,
      sortBy = 'createdAt',
      order = 'desc',
      page = 1,
      limit = 20,
      search,
    } = req.query;

    const query: any = {};

    // Filter by status
    if (status) {
      query.status = status;
    }

    // Filter by category
    if (category) {
      query.categoryId = category;
    }

    // Search filter
    if (search && typeof search === 'string') {
      query.$or = [
        { word: { $regex: literalSearch(search), $options: 'i' } },
        { definition: { $regex: literalSearch(search), $options: 'i' } },
      ];
    }

    const skip = (Number(page) - 1) * Number(limit);
    const sortOrder = order === 'desc' ? -1 : 1;

    const [items, total] = await Promise.all([
      DictionaryEntry.find(query)
        .populate('categoryId', 'name slug')
        .populate('createdBy', 'displayName email')
        .sort({ [String(sortBy)]: sortOrder })
        .skip(skip)
        .limit(Number(limit)),
      DictionaryEntry.countDocuments(query),
    ]);

    res.status(200).json({
      success: true,
      data: {
        items,
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total,
          pages: Math.ceil(total / Number(limit)),
        },
      },
    });
  } catch (error) {
    next(error);
  }
}

/**
 * GET /api/v1/staff/content/:id
 * Get single content item details
 */
export async function getContentById(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const { id } = req.params;

    const item = await DictionaryEntry.findById(id)
      .populate('categoryId', 'name slug')
      .populate('createdBy', 'displayName email')
      .populate('lastModifiedBy', 'displayName email');

    if (!item) {
      throw new AppError('Content not found', 404, ErrorCodes.DICT_ENTRY_NOT_FOUND);
    }

    res.status(200).json({
      success: true,
      data: item,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * PATCH /api/v1/staff/content/:id
 * Update content item
 */
export async function updateContent(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const { id } = req.params;
    const updates = req.body;

    const item = await DictionaryEntry.findByIdAndUpdate(
      id,
      {
        ...updates,
        updatedBy: req.user!.id,
      },
      { new: true, runValidators: true }
    );

    if (!item) {
      throw new AppError('Content not found', 404, ErrorCodes.DICT_ENTRY_NOT_FOUND);
    }

    res.status(200).json({
      success: true,
      data: item,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * POST /api/v1/staff/content/:id/approve
 * Approve content item
 */
export async function approveContent(req: Request, res: Response, next: NextFunction): Promise<void> {
  req.body={status:'PUBLISHED'};
  await updateDictionary(req,res,next);
}

/** Reject content and keep the category count consistent. */
export async function rejectContent(req: Request, res: Response, next: NextFunction): Promise<void> {
  const reason=req.body.reason;
  if(typeof reason!=='string' || !reason.trim() || reason.length>1000) {
    next(new AppError('C?n nh?p l? do t? ch?i, t?i ?a 1000 k? t?.',400,ErrorCodes.VALIDATION_ERROR));
    return;
  }
  req.body={status:'DRAFT',notes:reason.trim()};
  await updateDictionary(req,res,next);
}

/**
 * GET /api/v1/staff/users
 * Get users with basic filtering (for support)
 */
export async function getUsers(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const {
      page = 1,
      limit = 20,
      search,
      role,
      status,
    } = req.query;

    const query: any = {};

    if (search && typeof search === 'string') {
      query.$or = [
        { displayName: { $regex: literalSearch(search), $options: 'i' } },
        { email: { $regex: literalSearch(search), $options: 'i' } },
      ];
    }

    if (role) {
      query.role = role;
    }

    if (status) {
      query.status = status;
    }

    const skip = (Number(page) - 1) * Number(limit);

    const [users, total] = await Promise.all([
      User.find(query)
        .select('-passwordHash')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(Number(limit)),
      User.countDocuments(query),
    ]);

    res.status(200).json({
      success: true,
      data: {
        users: await Promise.all(users.map(safeUser)),
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total,
          pages: Math.ceil(total / Number(limit)),
        },
      },
    });
  } catch (error) {
    next(error);
  }
}

/**
 * GET /api/v1/staff/users/:id
 * Get user details (for support)
 */
export async function getUserDetails(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const { id } = req.params;

    const user = await User.findById(id).select('-passwordHash');

    if (!user) {
      throw new AppError('User not found', 404, ErrorCodes.USER_NOT_FOUND);
    }

    res.status(200).json({
      success: true,
      data: await safeUser(user),
    });
  } catch (error) {
    next(error);
  }
}

/**
 * GET /api/v1/staff/reports
 * Get user reports/issues (placeholder - implement based on your reporting model)
 */
export async function getReports(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    res.status(501).json({success: false, error: {code: 'FEATURE_UNAVAILABLE', message: 'Chức năng báo cáo chưa được triển khai.'}});
  } catch (error) {
    next(error);
  }
}

/**
 * PATCH /api/v1/staff/reports/:id
 * Update report status (placeholder)
 */
export async function updateReport(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    res.status(501).json({success: false, error: {code: 'FEATURE_UNAVAILABLE', message: 'Chức năng báo cáo chưa được triển khai.'}});
  } catch (error) {
    next(error);
  }
}

/**
 * GET /api/v1/staff/stats
 * Get staff dashboard statistics
 */
export async function getStaffStats(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const [
      pendingContent,
      publishedContent,
      totalUsers,
      recentUsers,
    ] = await Promise.all([
      DictionaryEntry.countDocuments({ status: 'DRAFT' }),
      DictionaryEntry.countDocuments({ status: 'PUBLISHED' }),
      User.countDocuments({ isGuest: false }),
      User.countDocuments({
        isGuest: false,
        createdAt: { $gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
      }),
    ]);

    res.status(200).json({
      success: true,
      data: {
        content: {
          pending: pendingContent,
          published: publishedContent,
        },
        users: {
          total: totalUsers,
          recentWeek: recentUsers,
        },
      },
    });
  } catch (error) {
    next(error);
  }
}
