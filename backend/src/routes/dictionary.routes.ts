import { Router } from 'express';
import * as dictionaryController from '../controllers/dictionary.controller';
import { authenticate, requireAuth, requirePermission } from '../common/middlewares/auth.middleware';
import { validate } from '../common/middlewares/validate.middleware';
import { staffCreateDictionarySchema, staffUpdateDictionarySchema } from '../validation/admin.validation';
import { z } from 'zod';
import { offsetQuery, objectId } from '../validation/user-data.validation';
const publicQuery = z.object({query: offsetQuery.extend({
  categoryId: objectId.optional(), search: z.string().trim().max(200).optional(), difficulty: z.enum(['BEGINNER','INTERMEDIATE','ADVANCED']).optional(),
  sort: z.enum(['word_asc', 'word_desc']).optional(),
})});

const router = Router();

/**
 * @route GET /api/v1/dictionary/popular
 * @desc Get popular entries
 * @access Public
 */
router.get('/popular', validate(z.object({query: offsetQuery.pick({limit:true})})), dictionaryController.getPopularEntries);

/**
 * @route GET /api/v1/dictionary
 * @desc Get published dictionary entries with filters
 * @access Public (with optional auth for history tracking)
 */
router.get('/', authenticate, validate(publicQuery), dictionaryController.getEntries);

/**
 * @route GET /api/v1/dictionary/:id
 * @desc Get dictionary entry by ID
 * @access Public (with optional auth for history tracking)
 */
router.get('/:id', authenticate, dictionaryController.getEntryById);

/**
 * @route POST /api/v1/dictionary
 * @desc Create draft entry
 * @access Private (STAFF/ADMIN)
 */
router.post('/', requireAuth, requirePermission('dictionary:write'), validate(staffCreateDictionarySchema), dictionaryController.createEntry);

/**
 * @route PATCH /api/v1/dictionary/:id
 * @desc Update draft entry
 * @access Private (STAFF/ADMIN)
 */
router.patch('/:id', requireAuth, requirePermission('dictionary:write'), validate(staffUpdateDictionarySchema), dictionaryController.updateEntry);

/**
 * @route POST /api/v1/dictionary/:id/publish
 * @desc Publish entry
 * @access Private (ADMIN)
 */
router.post('/:id/publish', requireAuth, requirePermission('content:publish'), dictionaryController.publishEntry);

/**
 * @route POST /api/v1/dictionary/:id/archive
 * @desc Archive entry
 * @access Private (ADMIN)
 */
router.post('/:id/archive', requireAuth, requirePermission('content:publish'), dictionaryController.archiveEntry);

export default router;
