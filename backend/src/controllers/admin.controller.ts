import { administratorTransaction } from '../services/administrator-transaction.service';
import { Request, Response, NextFunction } from 'express';
import { User, UserRole, AccountStatus } from '../models/User.model';
import { AuthSession, SessionStatus } from '../models/AuthSession.model';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';
import { Role } from '../models/Role.model';
import { roleForPermissions, authorizationFor, assertCanGrant, builtInPermissions } from '../services/authorization.service';

/**
 * GET /api/v1/admin/users
 * Get all users with pagination and filtering
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
      accountType,
      sortBy = 'createdAt',
      order = 'desc',
    } = req.query;

    const query: any = {};

    if (search && typeof search === 'string') {
      query.$or = [
        { displayName: { $regex: search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), $options: 'i' } },
        { email: { $regex: search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), $options: 'i' } },
      ];
    }

    if (role) {
      query.role = role;
    }

    if (status) {
      query.status = status;
    }

    if (accountType) {
      query.accountType = accountType;
    }

    const skip = (Number(page) - 1) * Number(limit);
    const sortOrder = order === 'desc' ? -1 : 1;

    const [users, total] = await Promise.all([
      User.find(query)
        .select('-passwordHash')
        .sort({ [String(sortBy)]: sortOrder })
        .skip(skip)
        .limit(Number(limit)),
      User.countDocuments(query),
    ]);

    res.status(200).json({
      success: true,
      data: {
        users,
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
 * GET /api/v1/admin/users/:id
 * Get single user by ID
 */
export async function getUserById(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const { id } = req.params;

    const user = await User.findById(id).select('-passwordHash');

    if (!user) {
      throw new AppError('User not found', 404, ErrorCodes.NOT_FOUND);
    }

    // Get additional user stats
    const [sessionCount, favoriteCount] = await Promise.all([
      AuthSession.countDocuments({ userId: user._id, expiresAt: { $gt: new Date() } }),
      // If you have a Favorite model:
      // Favorite.countDocuments({ userId: user._id })
      Promise.resolve(0), // Placeholder
    ]);

    res.status(200).json({
      success: true,
      data: {
        user,
        stats: {
          activeSessions: sessionCount,
          favorites: favoriteCount,
        },
      },
    });
  } catch (error) {
    next(error);
  }
}

/**
 * PATCH /api/v1/admin/users/:id
 * Update user (role, status, etc.)
 */
export async function updateUser(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const user = await administratorTransaction(async session => {
    const { id } = req.params;
    const updates = req.body;
    if (req.user!.id.toString() === id && (updates.role || updates.customRoleId !== undefined)) {
      throw new AppError('Không thể tự thay đổi role của tài khoản đang dùng.',400,ErrorCodes.VALIDATION_ERROR);
    }
    const existing = await User.findById(id).session(session);
    if (!existing) throw new AppError('User not found',404,ErrorCodes.NOT_FOUND);
    assertCanGrant(req.user!.permissions,(await authorizationFor(existing)).permissions);
    if (existing.isGuest && (updates.role || updates.customRoleId)) throw new AppError('Không thể gán quyền quản lý cho tài khoản dùng thử.',400,ErrorCodes.VALIDATION_ERROR);
    if (updates.customRoleId) {
      const custom = await Role.findById(updates.customRoleId).session(session);
      if (!custom) throw new AppError('Role không tồn tại.',400,ErrorCodes.BAD_REQUEST);
      assertCanGrant(req.user!.permissions,custom.permissions);
      updates.role = roleForPermissions(custom.permissions);
    } else if (updates.role || updates.customRoleId === null) {
      assertCanGrant(req.user!.permissions,builtInPermissions[(updates.role || existing.role) as UserRole]);
      updates.customRoleId = null;
    }
    if (req.user!.id.toString() === id &&
        ((updates.role && updates.role !== UserRole.ADMIN) || (updates.status && updates.status !== AccountStatus.ACTIVE))) {
      throw new AppError('Không thể tự hạ quyền hoặc khóa tài khoản quản trị đang dùng.',400,ErrorCodes.VALIDATION_ERROR);
    }

    // Prevent updating sensitive fields
    delete updates.passwordHash;
    delete updates.googleProvider;
    delete updates.facebookProvider;
    delete updates.createdAt;

    // Validate role if being updated
    if (updates.role && !Object.values(UserRole).includes(updates.role)) {
      throw new AppError('Invalid role', 400, ErrorCodes.VALIDATION_ERROR);
    }

    // Validate status if being updated
    if (updates.status && !Object.values(AccountStatus).includes(updates.status)) {
      throw new AppError('Invalid status', 400, ErrorCodes.VALIDATION_ERROR);
    }

    const user = await User.findByIdAndUpdate(
      id,
      updates,
      { new: true, runValidators: true, session }
    ).select('-passwordHash');

    if (!user) {
      throw new AppError('User not found', 404, ErrorCodes.NOT_FOUND);
    }

    if (updates.status && updates.status !== AccountStatus.ACTIVE) await AuthSession.updateMany({userId:user._id}, {$set:{status:'REVOKED',revokedAt:new Date()}}, {session});

      return user;
    });

    res.status(200).json({
      success: true,
      data: user,
      message: 'User updated successfully',
    });
  } catch (error) {
    next(error);
  }
}

/**
 * DELETE /api/v1/admin/users/:id
 * Soft delete user account
 */
export async function deleteUser(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const user = await administratorTransaction(async session => {
    const { id } = req.params;

    const existing = await User.findById(id).session(session);
    if (!existing) throw new AppError('User not found',404,ErrorCodes.NOT_FOUND);
    assertCanGrant(req.user!.permissions,(await authorizationFor(existing)).permissions);

    // Prevent self-deletion
    if (req.user!.id.toString() === id) {
      throw new AppError('Cannot delete your own account', 400, ErrorCodes.VALIDATION_ERROR);
    }

    const user = await User.findByIdAndUpdate(
      id,
      { status: AccountStatus.DELETED },
      { new: true, session }
    ).select('-passwordHash');

    if (!user) {
      throw new AppError('User not found', 404, ErrorCodes.NOT_FOUND);
    }

    // Invalidate all user sessions
    await AuthSession.deleteMany({ userId: user._id }, {session});

      return user;
    });

    res.status(200).json({
      success: true,
      data: user,
      message: 'User account deleted successfully',
    });
  } catch (error) {
    next(error);
  }
}

/**
 * POST /api/v1/admin/users/:id/suspend
 * Suspend user account
 */
export async function suspendUser(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const user = await administratorTransaction(async session => {
    const { id } = req.params;
    const existing = await User.findById(id).session(session);
    if (!existing) throw new AppError('User not found',404,ErrorCodes.NOT_FOUND);
    assertCanGrant(req.user!.permissions,(await authorizationFor(existing)).permissions);
    const { reason } = req.body;

    // Prevent self-suspension
    if (req.user!.id.toString() === id) {
      throw new AppError('Cannot suspend your own account', 400, ErrorCodes.VALIDATION_ERROR);
    }

    const user = await User.findByIdAndUpdate(
      id,
      {
        status: AccountStatus.SUSPENDED,
        suspensionReason: reason,
      },
      { new: true, session }
    ).select('-passwordHash');

    if (!user) {
      throw new AppError('User not found', 404, ErrorCodes.NOT_FOUND);
    }

    // Invalidate all user sessions
    await AuthSession.deleteMany({ userId: user._id }, {session});

      return user;
    });

    res.status(200).json({
      success: true,
      data: user,
      message: 'User account suspended',
    });
  } catch (error) {
    next(error);
  }
}

/**
 * POST /api/v1/admin/users/:id/activate
 * Activate suspended user account
 */
export async function activateUser(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const { id } = req.params;
    const existing = await User.findById(id);
    if (!existing) throw new AppError('User not found',404,ErrorCodes.NOT_FOUND);
    assertCanGrant(req.user!.permissions,(await authorizationFor(existing)).permissions);

    const user = await User.findByIdAndUpdate(
      id,
      {
        status: AccountStatus.ACTIVE,
        $unset: { suspensionReason: 1 },
      },
      { new: true }
    ).select('-passwordHash');

    if (!user) {
      throw new AppError('User not found', 404, ErrorCodes.NOT_FOUND);
    }

    res.status(200).json({
      success: true,
      data: user,
      message: 'User account activated',
    });
  } catch (error) {
    next(error);
  }
}

/**
 * GET /api/v1/admin/stats
 * Get system statistics and analytics
 */
export async function getSystemStats(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const now = new Date();
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    const [
      totalUsers,
      activeUsers,
      guestUsers,
      staffUsers,
      adminUsers,
      newUsersThisMonth,
      newUsersThisWeek,
      totalContent,
      publishedContent,
      pendingContent,
      activeSessions,
    ] = await Promise.all([
      User.countDocuments({ isGuest: false }),
      User.countDocuments({ status: AccountStatus.ACTIVE, isGuest: false }),
      User.countDocuments({ isGuest: true }),
      User.countDocuments({ role: UserRole.STAFF }),
      User.countDocuments({ role: UserRole.ADMIN }),
      User.countDocuments({ createdAt: { $gte: thirtyDaysAgo }, isGuest: false }),
      User.countDocuments({ createdAt: { $gte: sevenDaysAgo }, isGuest: false }),
      DictionaryEntry.countDocuments(),
      DictionaryEntry.countDocuments({ status: 'PUBLISHED' }),
      DictionaryEntry.countDocuments({ status: 'DRAFT' }),
      AuthSession.countDocuments({ status: SessionStatus.ACTIVE, expiresAt: { $gt: now } }),
    ]);

    res.status(200).json({
      success: true,
      data: {
        users: {
          total: totalUsers,
          active: activeUsers,
          guest: guestUsers,
          staff: staffUsers,
          admin: adminUsers,
          newThisMonth: newUsersThisMonth,
          newThisWeek: newUsersThisWeek,
        },
        content: {
          total: totalContent,
          published: publishedContent,
          pending: pendingContent,
        },
        sessions: {
          active: activeSessions,
        },
        timestamp: now.toISOString(),
      },
    });
  } catch (error) {
    next(error);
  }
}

/**
 * GET /api/v1/admin/content/pending
 * Get pending content for review
 */
export async function getPendingContent(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const { page = 1, limit = 20 } = req.query;
    const skip = (Number(page) - 1) * Number(limit);

    const [items, total] = await Promise.all([
      DictionaryEntry.find({ status: 'DRAFT' })
        .populate('categoryId', 'name slug')
        .populate('createdBy', 'displayName email')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(Number(limit)),
      DictionaryEntry.countDocuments({ status: 'DRAFT' }),
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
 * GET /api/v1/admin/sessions
 * Get active sessions with pagination
 */
export async function getActiveSessions(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const { page = 1, limit = 20 } = req.query;
    const skip = (Number(page) - 1) * Number(limit);

    const [sessions, total] = await Promise.all([
      AuthSession.find({ status: SessionStatus.ACTIVE, expiresAt: { $gt: new Date() } })
        .select('-tokenHash')
        .populate('userId', 'displayName email role')
        .sort({ lastUsedAt: -1 })
        .skip(skip)
        .limit(Number(limit)),
      AuthSession.countDocuments({ status: SessionStatus.ACTIVE, expiresAt: { $gt: new Date() } }),
    ]);

    res.status(200).json({
      success: true,
      data: {
        sessions,
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
 * DELETE /api/v1/admin/sessions/:sessionId
 * Terminate a specific session
 */
export async function terminateSession(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const { sessionId } = req.params;

    const session = await AuthSession.findById(sessionId);

    if (!session) {
      throw new AppError('Session not found', 404, ErrorCodes.NOT_FOUND);
    }
    if (session.sessionFamily) {
      await AuthSession.updateMany({ userId: session.userId, sessionFamily: session.sessionFamily }, {
        $set: { status: SessionStatus.REVOKED, revokedAt: new Date() },
      });
    } else {
      await session.revoke();
    }

    res.status(200).json({
      success: true,
      message: 'Session terminated successfully',
    });
  } catch (error) {
    next(error);
  }
}
