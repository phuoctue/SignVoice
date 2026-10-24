import { z } from 'zod';

export const objectId = z.string().regex(/^[a-f\d]{24}$/i, 'Invalid ID');
export const httpUrl = z.string().url().refine(value => /^https?:\/\//i.test(value), 'Only HTTP/HTTPS URLs are allowed');
const integer = (fallback: number, max: number, min = 0) =>
  z.string().regex(/^\d+$/).transform(Number).pipe(z.number().int().min(min).max(max)).default(String(fallback));
export const offsetQuery = z.object({ limit: integer(20, 100, 1), skip: integer(0, 100000) }).strict();
export const idParams = z.object({ id: objectId });
export const profileBody = z.object({
  displayName: z.string().trim().min(2).max(50).optional(),
  avatarUrl: z.union([httpUrl, z.literal('')]).optional(),
  email: z.string().trim().toLowerCase().email().optional(),
  currentPassword: z.string().min(1).max(128).optional(),
}).strict().refine(value => Object.keys(value).some(key => key !== 'currentPassword'), 'No changes provided');
export const settingsBody = z.object({
  theme: z.enum(['LIGHT', 'DARK', 'SYSTEM']).optional(),
  language: z.enum(['vi', 'en']).optional(),
  fontSize: z.number().min(12).max(24).optional(),
  highContrast: z.boolean().optional(),
  speechSpeed: z.number().min(0.5).max(2).optional(),
  speechPitch: z.number().min(0.5).max(2).optional(),
  autoSpeak: z.boolean().optional(),
  avatarColor: z.number().int().min(0).max(3).optional(),
  notificationsEnabled: z.boolean().optional(),
  notificationPreferences: z.object({newWords: z.boolean(), favorites: z.boolean(), updates: z.boolean()}).partial().strict().optional(),
  shareUsageData: z.boolean().optional(),
}).strict().refine(value => Object.keys(value).length > 0, 'No changes provided');
export const deleteAccountBody = z.object({ currentPassword: z.string().max(128).optional(), confirm: z.literal(true) }).strict();
export const conversationBody = z.object({
  content: z.string().trim().min(1).max(10000),
  direction: z.enum(['TEXT', 'SIGN_TO_SPEECH', 'SPEECH_TO_TEXT']).default('TEXT'),
  favorite: z.boolean().default(false),
}).strict();
export const conversationPatch = conversationBody.partial().strict().refine(value => Object.keys(value).length > 0, 'No changes provided');
export const conversationQuery = z.object({
  page: integer(1, 100000, 1), limit: integer(20, 100, 1),
  search: z.string().trim().max(200).optional(),
  direction: z.enum(['TEXT', 'SIGN_TO_SPEECH', 'SPEECH_TO_TEXT']).optional(),
  favorite: z.enum(['true', 'false']).transform(value => value === 'true').optional(),
}).strict();
export const literalSearch = (value: string) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
