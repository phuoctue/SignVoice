import { Router } from 'express';
import * as staffController from '../controllers/staff.controller';
import { requireAuth, requireStaff, requirePermission } from '../common/middlewares/auth.middleware';
import * as management from '../controllers/admin-management.controller';
import { validate } from '../common/middlewares/validate.middleware';
import { adminUpdateDictionarySchema, adminIdSchema } from '../validation/admin.validation';
import { z } from 'zod';
import { objectId } from '../validation/user-data.validation';
const listSchema = z.object({query: z.object({
  page: z.string().regex(/^\d+$/).transform(Number).pipe(z.number().int().min(1).max(100000)).default('1'),
  limit: z.string().regex(/^\d+$/).transform(Number).pipe(z.number().int().min(1).max(100)).default('20'),
  search: z.string().max(100).optional(), status: z.enum(['DRAFT','PUBLISHED','ARCHIVED','ACTIVE','SUSPENDED','DELETED']).optional(),
  category: objectId.optional(), role: z.enum(['USER','STAFF','ADMIN']).optional(),
  sortBy: z.enum(['createdAt','updatedAt','word']).optional(), order: z.enum(['asc','desc']).optional(),
}).strict()});

const router = Router();

// All routes require STAFF or ADMIN role
router.use(requireAuth, requireStaff);

/**
 * GET /api/v1/staff/content
 * @desc Get content items for moderation with filters
 * @access Private (STAFF/ADMIN)
 */
router.get('/content', requirePermission('dictionary:read'), validate(listSchema), staffController.getContentForModeration);

/**
 * GET /api/v1/staff/content/:id
 * @desc Get single content item details
 * @access Private (STAFF/ADMIN)
 */
router.get('/content/:id', requirePermission('dictionary:read'), validate(adminIdSchema), staffController.getContentById);

/**
 * PATCH /api/v1/staff/content/:id
 * @desc Update content item
 * @access Private (STAFF/ADMIN)
 */
router.patch('/content/:id', requirePermission('dictionary:write'), validate(adminUpdateDictionarySchema), management.updateDictionary);

/**
 * POST /api/v1/staff/content/:id/approve
 * @desc Approve content item
 * @access Private (STAFF/ADMIN)
 */
router.post('/content/:id/approve', requirePermission('content:publish'), validate(adminIdSchema), staffController.approveContent);

/**
 * POST /api/v1/staff/content/:id/reject
 * @desc Reject content item with reason
 * @access Private (STAFF/ADMIN)
 */
router.post('/content/:id/reject', requirePermission('dictionary:write'), validate(adminIdSchema), staffController.rejectContent);

/**
 * GET /api/v1/staff/users
 * @desc Get users with basic filtering (for support)
 * @access Private (STAFF/ADMIN)
 */
router.get('/users', requirePermission('users:read'), validate(listSchema), staffController.getUsers);

/**
 * GET /api/v1/staff/users/:id
 * @desc Get user details (for support)
 * @access Private (STAFF/ADMIN)
 */
router.get('/users/:id', requirePermission('users:read'), validate(adminIdSchema), staffController.getUserDetails);

/**
 * GET /api/v1/staff/reports
 * @desc Get user reports/issues
 * @access Private (STAFF/ADMIN)
 */
router.get('/reports', staffController.getReports);

/**
 * PATCH /api/v1/staff/reports/:id
 * @desc Update report status
 * @access Private (STAFF/ADMIN)
 */
router.patch('/reports/:id', staffController.updateReport);

/**
 * GET /api/v1/staff/stats
 * @desc Get staff dashboard statistics
 * @access Private (STAFF/ADMIN)
 */
router.get('/stats', staffController.getStaffStats);

export default router;
