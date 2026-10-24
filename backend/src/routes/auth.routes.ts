import { Router } from 'express';
import * as authController from '../controllers/auth.controller';
import * as oauthController from '../controllers/oauth.controller';
import { validate } from '../common/middlewares/validate.middleware';
import { requireAuth } from '../common/middlewares/auth.middleware';
import { rateLimit } from 'express-rate-limit';
import {
  registerSchema,
  loginSchema,
  refreshTokenSchema,
  convertGuestSchema,
  forgotPasswordSchema,
  resetPasswordSchema,
  changePasswordSchema,
  guestSchema,
} from '../validation/auth.validation';

const router = Router();
const oauthLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 60,
  standardHeaders: 'draft-8', legacyHeaders: false, validate: { xForwardedForHeader: false },
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Vui lòng thử lại sau.' } } });
router.get('/oauth/providers', oauthController.providers);
router.get('/oauth/:provider/start', oauthLimiter, oauthController.start);
router.get('/oauth/:provider/callback', oauthLimiter, oauthController.callback);
router.post('/oauth/complete', oauthLimiter, oauthController.complete);

const passwordResetLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 30,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  // Conveyor connects through a local proxy. Do not trust arbitrary forwarded IPs.
  validate: { xForwardedForHeader: false },
  message: { success: false, error: { code: 'TOO_MANY_REQUESTS', message: 'Bạn đã gửi quá nhiều yêu cầu. Vui lòng thử lại sau.' } },
});
router.post('/forgot-password', passwordResetLimiter, validate(forgotPasswordSchema), authController.forgotPassword);
router.post('/reset-password', passwordResetLimiter, validate(resetPasswordSchema), authController.resetPassword);
router.post('/change-password', passwordResetLimiter, requireAuth, validate(changePasswordSchema), authController.changePassword);

/**
 * @route POST /api/v1/auth/register
 * @desc Register new user
 * @access Public
 */
router.post('/register', validate(registerSchema), authController.register);

/**
 * @route POST /api/v1/auth/login
 * @desc Login user
 * @access Public
 */
router.post('/login', validate(loginSchema), authController.login);

/**
 * @route POST /api/v1/auth/guest
 * @desc Create guest account
 * @access Public
 */
router.post('/guest', validate(guestSchema), authController.createGuest);

/**
 * @route POST /api/v1/auth/convert-guest
 * @desc Convert guest account to permanent
 * @access Private (Guest only)
 */
router.post(
  '/convert-guest',
  requireAuth,
  validate(convertGuestSchema),
  authController.convertGuest
);

/**
 * @route POST /api/v1/auth/refresh
 * @desc Refresh access token
 * @access Public
 */
router.post('/refresh', validate(refreshTokenSchema), authController.refresh);

/**
 * @route POST /api/v1/auth/logout
 * @desc Logout (revoke current session)
 * @access Private
 */
router.post('/logout', requireAuth, authController.logout);

/**
 * @route POST /api/v1/auth/logout-all
 * @desc Logout from all devices
 * @access Private
 */
router.post('/logout-all', requireAuth, authController.logoutAll);

/**
 * @route GET /api/v1/auth/me
 * @desc Get current user
 * @access Private
 */
router.get('/me', requireAuth, authController.getCurrentUser);

export default router;
