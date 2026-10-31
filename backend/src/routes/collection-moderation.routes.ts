import {Router,Request,Response,NextFunction} from 'express';
import {z} from 'zod';
import {requireAuth,requireManagement,requirePermission} from '../common/middlewares/auth.middleware';
import {AppError} from '../common/errors/AppError';
import {objectId} from '../services/learning.service';
import * as service from '../services/collection-moderation.service';

const router=Router();
const wrap=(fn:(req:Request,res:Response)=>Promise<unknown>)=>(req:Request,res:Response,next:NextFunction)=>{void fn(req,res).catch(next);};
function parse<T extends z.ZodTypeAny>(schema:T,input:unknown):z.output<T> {
  const value=schema.safeParse(input);if(!value.success)throw new AppError('Kiểm tra lại nội dung đã nhập.',400,'INVALID_COLLECTION_INPUT');return value.data;
}
const page=z.coerce.number().int().min(1).max(10000).default(1);
const reason=z.string().trim().min(5).max(1000);
router.use(requireAuth,requireManagement,requirePermission('collections:read'),(_req,res,next)=>{res.setHeader('Cache-Control','no-store');next();});
router.get('/',wrap(async(req,res)=>{
  const input=parse(z.object({page,search:z.string().trim().max(80).default(''),status:z.enum(['ALL','CLEAR','HIDDEN','BLOCKED','REPORTED','REVIEW_REQUESTED']).default('ALL')}).strict(),req.query);
  return res.json({success:true,data:await service.moderationList(input.page,input.search,input.status)});
}));
router.get('/:id',wrap(async(req,res)=>{
  const input=parse(z.object({page}).strict(),req.query);
  return res.json({success:true,data:await service.moderationDetail(objectId(req.params.id),input.page)});
}));
router.get('/:id/reports',wrap(async(req,res)=>{
  const input=parse(z.object({page,status:z.enum(['ALL','OPEN','RESOLVED','DISMISSED']).default('OPEN')}).strict(),req.query);
  return res.json({success:true,data:await service.collectionReports(objectId(req.params.id),input.page,input.status)});
}));
router.get('/:id/history',wrap(async(req,res)=>{
  const input=parse(z.object({page}).strict(),req.query);
  return res.json({success:true,data:await service.collectionHistory(objectId(req.params.id),input.page)});
}));
router.post('/:id/moderation',requirePermission('collections:moderate'),wrap(async(req,res)=>{
  const input=parse(z.object({state:z.enum(['CLEAR','HIDDEN','BLOCKED']),reason,version:z.number().int().min(0)}).strict(),req.body);
  return res.json({success:true,data:await service.moderateCollection(req.user!.id,req.user!.role,objectId(req.params.id),input.state,input.reason,input.version)});
}));
router.post('/:id/reports/:reportId/resolve',requirePermission('collections:moderate'),wrap(async(req,res)=>{
  const input=parse(z.object({status:z.enum(['RESOLVED','DISMISSED']),reason}).strict(),req.body);
  return res.json({success:true,data:await service.resolveCollectionReport(req.user!.id,req.user!.role,objectId(req.params.id),objectId(req.params.reportId),input.status,input.reason)});
}));
export default router;
