import { z } from 'zod';
import { UserRole, AccountStatus } from '../models/User.model';
import { CategoryStatus } from '../models/Category.model';
import { DifficultyLevel, EntryStatus } from '../models/DictionaryEntry.model';
import { permissions } from '../models/Role.model';
import { httpUrl } from './user-data.validation';

const objectId = z.string().regex(/^[a-f0-9]{24}$/i, 'Invalid ID');
const email = z.string().trim().toLowerCase().email();
const displayName = z.string().trim().min(2).max(50);
export const adminListSchema = z.object({ query: z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().trim().max(100).optional(),
  role: z.nativeEnum(UserRole).optional(),
  status: z.string().max(20).optional(),
}).passthrough() });
export const adminCreateUserSchema = z.object({body:z.object({
  email, displayName,
  password: z.string().min(8).max(128).regex(/[a-zA-Z]/).regex(/[0-9]/),
  role: z.nativeEnum(UserRole).default(UserRole.USER),
  customRoleId:objectId.optional(),
}).strict()});
export const adminUpdateUserSchema = z.object({params:z.object({id:objectId}),body:z.object({
  email, displayName, role:z.nativeEnum(UserRole), status:z.nativeEnum(AccountStatus),
  customRoleId:objectId.nullable(),
}).partial().strict().refine(body=>Object.keys(body).length>0,'No changes provided')});
export const adminIdSchema = z.object({params:z.object({id:objectId})});
export const adminSessionIdSchema = z.object({params:z.object({sessionId:objectId})});
const roleFields=z.object({
  name:z.string().trim().min(2).max(50),
  key:z.string().trim().toUpperCase().regex(/^[A-Z][A-Z0-9_]{1,39}$/).refine(key=>!['ADMIN','STAFF','USER'].includes(key),'Reserved role key'),
  description:z.string().trim().max(500).optional(),
  permissions:z.array(z.enum(permissions)).max(permissions.length).transform(value=>[...new Set(value)]),
});
export const adminCreateRoleSchema=z.object({body:roleFields.strict()});
export const adminUpdateRoleSchema=z.object({params:z.object({id:objectId}),body:roleFields.partial().strict().refine(body=>Object.keys(body).length>0,'No changes provided')});

const dictionaryFields = z.object({
  word:z.string().trim().min(1).max(200),
  definition:z.string().trim().min(5).max(2000),
  videoUrl:z.string().url().regex(/^https?:\/\//),
  categoryId:objectId,
  thumbnailUrl:z.union([httpUrl,z.literal('')]).optional(),
  imageUrls:z.array(httpUrl).max(10).optional(),
  difficulty:z.nativeEnum(DifficultyLevel).optional(),
  tags:z.array(z.string().trim().min(1).max(50)).max(20).optional(),
  usageExample:z.string().trim().max(1000).optional(),
  notes:z.string().trim().max(1000).optional(),
  status:z.nativeEnum(EntryStatus).optional(),
});
export const adminCreateDictionarySchema = z.object({body:dictionaryFields.strict()});
export const staffCreateDictionarySchema = z.object({body:dictionaryFields.omit({status:true}).strict()});
export const staffUpdateDictionarySchema = z.object({params:z.object({id:objectId}),body:dictionaryFields.omit({status:true}).partial().strict()});
export const adminUpdateDictionarySchema = z.object({params:z.object({id:objectId}),body:dictionaryFields.partial().strict().refine(body=>Object.keys(body).length>0,'No changes provided')});
const categoryFields = z.object({
  name:z.string().trim().min(2).max(50),
  slug:z.string().trim().min(1).max(80).regex(/^[a-z0-9-]+$/),
  description:z.string().trim().max(500).optional(),
  icon:z.string().trim().max(50).optional(),
  sortOrder:z.number().int().min(0).max(10000).optional(),
  status:z.nativeEnum(CategoryStatus).optional(),
});
export const adminCreateCategorySchema = z.object({body:categoryFields.strict()});
export const adminUpdateCategorySchema = z.object({params:z.object({id:objectId}),body:categoryFields.partial().strict().refine(body=>Object.keys(body).length>0,'No changes provided')});
