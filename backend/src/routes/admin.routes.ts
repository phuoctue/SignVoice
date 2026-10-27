import { Router } from 'express';
import * as adminController from '../controllers/admin.controller';
import { requireAuth, requireAdmin, requireManagement, requirePermission } from '../common/middlewares/auth.middleware';
import * as management from '../controllers/admin-management.controller';
import { validate } from '../common/middlewares/validate.middleware';
import { adminListSchema, adminCreateUserSchema, adminUpdateUserSchema, adminIdSchema, adminSessionIdSchema,
  adminCreateDictionarySchema, adminUpdateDictionarySchema, adminCreateCategorySchema, adminUpdateCategorySchema, adminCreateRoleSchema, adminUpdateRoleSchema, adminResetPasswordSchema } from '../validation/admin.validation';

const router = Router();

// Shared dashboard/content tools. Account, role and session administration stays ADMIN-only.
router.use(requireAuth, requireManagement);
router.use(['/users', '/roles', '/sessions'], requireAdmin);
router.get('/roles', requirePermission('roles:read'), management.listRoles);
router.post('/roles', requirePermission('roles:write'), validate(adminCreateRoleSchema), management.createRole);
router.patch('/roles/:id', requirePermission('roles:write'), validate(adminUpdateRoleSchema), management.updateRole);
router.delete('/roles/:id', requirePermission('roles:write'), validate(adminIdSchema), management.deleteRole);
router.get('/dictionary', requirePermission('dictionary:read'), validate(adminListSchema), management.listDictionary);
router.post('/dictionary', requirePermission('dictionary:write'), validate(adminCreateDictionarySchema), management.createDictionary);
router.patch('/dictionary/:id', requirePermission('dictionary:write'), validate(adminUpdateDictionarySchema), management.updateDictionary);
router.delete('/dictionary/:id', requirePermission('dictionary:write'), validate(adminIdSchema), management.deleteDictionary);
router.get('/categories', requirePermission('categories:read'), management.listCategories);
router.post('/categories', requirePermission('categories:write'), validate(adminCreateCategorySchema), management.createCategory);
router.patch('/categories/:id', requirePermission('categories:write'), validate(adminUpdateCategorySchema), management.updateCategory);
router.delete('/categories/:id', requirePermission('categories:write'), validate(adminIdSchema), management.deleteCategory);
router.post('/users', requirePermission('users:write'), validate(adminCreateUserSchema), management.createUser);
router.get('/users/role-options', requirePermission('users:write'), management.userRoleOptions);

/**
 * GET /api/v1/admin/users
 * @desc Get all users with pagination and filtering
 * @access Private (ADMIN)
 */
router.get('/users', requirePermission('users:read'), validate(adminListSchema), adminController.getUsers);

/**
 * GET /api/v1/admin/users/:id
 * @desc Get single user by ID
 * @access Private (ADMIN)
 */
router.get('/users/:id', requirePermission('users:read'), validate(adminIdSchema), adminController.getUserById);

/**
 * PATCH /api/v1/admin/users/:id
 * @desc Update user (role, status, etc.)
 * @access Private (ADMIN)
 */
router.patch('/users/:id', requirePermission('users:write'), validate(adminUpdateUserSchema), adminController.updateUser);
router.post('/users/:id/password', requirePermission('users:write'), validate(adminResetPasswordSchema), management.resetUserPassword);

/**
 * DELETE /api/v1/admin/users/:id
 * @desc Soft delete user account
 * @access Private (ADMIN)
 */
router.delete('/users/:id', requirePermission('users:write'), validate(adminIdSchema), adminController.deleteUser);

/**
 * POST /api/v1/admin/users/:id/suspend
 * @desc Suspend user account
 * @access Private (ADMIN)
 */
router.post('/users/:id/suspend', requirePermission('users:write'), validate(adminIdSchema), adminController.suspendUser);

/**
 * POST /api/v1/admin/users/:id/activate
 * @desc Activate suspended user account
 * @access Private (ADMIN)
 */
router.post('/users/:id/activate', requirePermission('users:write'), validate(adminIdSchema), adminController.activateUser);

/**
 * GET /api/v1/admin/stats
 * @desc Get system statistics and analytics
 * @access Private (ADMIN)
 */
router.get('/stats', adminController.getSystemStats);

/**
 * GET /api/v1/admin/content/pending
 * @desc Get pending content for review
 * @access Private (ADMIN)
 */
router.get('/content/pending', requirePermission('dictionary:read'), validate(adminListSchema), adminController.getPendingContent);

/**
 * GET /api/v1/admin/sessions
 * @desc Get active sessions with pagination
 * @access Private (ADMIN)
 */
router.get('/sessions', requirePermission('sessions:read'), validate(adminListSchema), adminController.getActiveSessions);

/**
 * DELETE /api/v1/admin/sessions/:sessionId
 * @desc Terminate a specific session
 * @access Private (ADMIN)
 */
router.delete('/sessions/:sessionId', requirePermission('sessions:write'), validate(adminSessionIdSchema), adminController.terminateSession);

export default router;
