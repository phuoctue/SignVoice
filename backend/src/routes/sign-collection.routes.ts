import {Router,Request,Response,NextFunction} from 'express';
import {z} from 'zod';
import {rateLimit} from 'express-rate-limit';
import {requireAuth,requirePermanentAccount} from '../common/middlewares/auth.middleware';
import {AppError} from '../common/errors/AppError';
import {objectId} from '../services/learning.service';
import * as collections from '../services/sign-collection.service';
import {startCollectionQuiz} from '../services/review-quiz.service';
import {personalWordSchema} from '../validation/personal-word.validation';
import {reportCollection,requestCollectionReview} from '../services/collection-moderation.service';

const router=Router();
const wrap=(fn:(req:Request,res:Response)=>Promise<unknown>)=>(req:Request,res:Response,next:NextFunction)=>{void fn(req,res).catch(next);};
function parse<T extends z.ZodTypeAny>(schema:T,input:unknown):z.output<T> {
  const value=schema.safeParse(input);if(!value.success)throw new AppError('Kiểm tra lại nội dung đã nhập.',400,'INVALID_COLLECTION_INPUT');return value.data;
}
const query=z.object({page:z.coerce.number().int().min(1).max(10000).default(1),search:z.string().trim().max(80).default('')}).strict();
const metadata=z.object({name:z.string().trim().min(1).max(80),description:z.string().trim().max(500).default(''),avatarImage:z.string().max(100000).optional()}).strict();
const empty=z.object({}).strict();
const code=z.string().regex(/^[a-f0-9]{32}$/);
const entry=z.string().regex(/^[a-f0-9]{24}$/i);
router.use(requireAuth,requirePermanentAccount,(_req,res,next)=>{res.setHeader('Cache-Control','no-store');next();});
router.get('/',wrap(async(req,res)=>{const input=parse(query,req.query);return res.json({success:true,data:await collections.listCollections(req.user!.id,input.page,input.search)});}));
router.post('/',wrap(async(req,res)=>res.status(201).json({success:true,data:await collections.createCollection(req.user!.id,parse(metadata,req.body))})));
router.post('/import',rateLimit({windowMs:60000,limit:20}),wrap(async(req,res)=>{
  const input=parse(z.object({code}).strict(),req.body);return res.json({success:true,data:await collections.importCollection(req.user!.id,input.code)});
}));
router.get('/:id',wrap(async(req,res)=>{const input=parse(query,req.query);return res.json({success:true,data:await collections.getCollection(req.user!.id,objectId(req.params.id),input.page,input.search)});}));
router.patch('/:id',wrap(async(req,res)=>res.json({success:true,data:await collections.updateCollection(req.user!.id,objectId(req.params.id),parse(metadata,req.body))})));
router.delete('/:id',wrap(async(req,res)=>{parse(empty,req.body || {});return res.json({success:true,data:await collections.deleteCollection(req.user!.id,objectId(req.params.id))});}));
router.get('/:id/candidates',wrap(async(req,res)=>{const input=parse(query,req.query);return res.json({success:true,data:await collections.collectionCandidates(req.user!.id,objectId(req.params.id),input.page,input.search)});}));
router.post('/:id/moderation-review',requirePermanentAccount,wrap(async(req,res)=>{
  parse(empty,req.body || {});return res.json({success:true,data:await requestCollectionReview(req.user!.id,objectId(req.params.id))});
}));
router.get('/:id/personal-words/available',wrap(async(req,res)=>{const input=parse(query,req.query);return res.json({success:true,data:await collections.availablePersonalWords(req.user!.id,objectId(req.params.id),input.page,input.search)});}));
router.post('/:id/personal-words/attach',wrap(async(req,res)=>{
  const input=parse(z.object({wordIds:z.array(entry).min(1).max(200)}).strict(),req.body);
  return res.json({success:true,data:await collections.attachPersonalWords(req.user!.id,objectId(req.params.id),input.wordIds.map(objectId))});
}));
router.post('/:id/personal-words',wrap(async(req,res)=>res.status(201).json({success:true,data:await collections.savePersonalWord(req.user!.id,objectId(req.params.id),parse(personalWordSchema,req.body))})));
router.get('/:id/personal-words/:wordId',wrap(async(req,res)=>res.json({success:true,data:await collections.collectionPersonalWord(req.user!.id,objectId(req.params.id),objectId(req.params.wordId))})));
router.patch('/:id/personal-words/:wordId',wrap(async(req,res)=>res.json({success:true,data:await collections.savePersonalWord(req.user!.id,objectId(req.params.id),parse(personalWordSchema,req.body),objectId(req.params.wordId))})));
router.delete('/:id/personal-words/:wordId',wrap(async(req,res)=>res.json({success:true,data:await collections.deletePersonalWord(req.user!.id,objectId(req.params.id),objectId(req.params.wordId))})));
router.post('/:id/entries',wrap(async(req,res)=>{
  const input=parse(z.object({entryIds:z.array(entry).min(1).max(200)}).strict(),req.body);
  return res.json({success:true,data:await collections.addCollectionEntries(req.user!.id,objectId(req.params.id),input.entryIds.map(objectId))});
}));
router.delete('/:id/entries/:entryId',wrap(async(req,res)=>{parse(empty,req.body || {});return res.json({success:true,data:await collections.removeCollectionEntry(req.user!.id,objectId(req.params.id),objectId(req.params.entryId))});}));
router.post('/:id/quiz',rateLimit({windowMs:60000,limit:15}),wrap(async(req,res)=>{
  const {format}=parse(z.object({format:z.enum(['VIDEO_RECALL','VIDEO_MATCH']).default('VIDEO_RECALL')}).strict(),req.body || {});
  return res.json({success:true,data:await startCollectionQuiz(req.user!.id,objectId(req.params.id),format)});
}));
router.post('/:id/share',wrap(async(req,res)=>{
  const input=parse(z.object({enabled:z.boolean()}).strict(),req.body);
  return res.json({success:true,data:await collections.shareCollection(req.user!.id,objectId(req.params.id),input.enabled)});
}));
router.post('/:id/discovery',requirePermanentAccount,rateLimit({windowMs:60000,limit:20}),wrap(async(req,res)=>{
  const input=parse(z.object({enabled:z.boolean()}).strict(),req.body);
  return res.json({success:true,data:await collections.publishCollection(req.user!.id,objectId(req.params.id),input.enabled)});
}));
export default router;

export const sharedCollectionRouter=Router();
sharedCollectionRouter.use(rateLimit({windowMs:60000,limit:60}),(_req,res,next)=>{res.setHeader('Cache-Control','no-store');next();});
sharedCollectionRouter.get('/',wrap(async(req,res)=>{
  const input=parse(query,req.query);return res.json({success:true,data:await collections.discoverCollections(input.page,input.search)});
}));
sharedCollectionRouter.get('/:code',wrap(async(req,res)=>{
  const value=parse(code,req.params.code),input=parse(query,req.query);
  return res.json({success:true,data:await collections.collectionContents(await collections.sharedCollection(value),input.page,input.search)});
}));
sharedCollectionRouter.post('/:code/reports',requireAuth,requirePermanentAccount,rateLimit({windowMs:3600000,limit:10,keyGenerator:req=>String(req.user!.id)}),wrap(async(req,res)=>{
  const value=parse(code,req.params.code);
  const input=parse(z.object({category:z.enum(['INAPPROPRIATE','MISLEADING','SPAM','COPYRIGHT','OTHER']),details:z.string().trim().max(1000).default('')}).strict().refine(value=>value.category!=='OTHER' || value.details.length>=5),req.body);
  return res.json({success:true,data:await reportCollection(req.user!.id,value,input.category,input.details)});
}));
export const signNoteRouter=Router();
signNoteRouter.use(requireAuth,requirePermanentAccount,(_req,res,next)=>{res.setHeader('Cache-Control','no-store');next();});
signNoteRouter.get('/:id',wrap(async(req,res)=>res.json({success:true,data:await collections.getSignNote(req.user!.id,objectId(req.params.id))})));
signNoteRouter.put('/:id',wrap(async(req,res)=>{
  const input=parse(z.object({text:z.string().trim().max(2000)}).strict(),req.body);
  return res.json({success:true,data:await collections.saveSignNote(req.user!.id,objectId(req.params.id),input.text)});
}));
