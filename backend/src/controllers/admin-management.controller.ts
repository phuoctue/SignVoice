import { administratorTransaction } from '../services/administrator-transaction.service';
import { writeContent, removeContent, removeCategory } from '../services/content-management.service';
import { Request, Response, NextFunction } from 'express';
import { User, AccountType, UserRole } from '../models/User.model';
import { Role } from '../models/Role.model';
import { builtInPermissions, roleForPermissions, assertCanGrant } from '../services/authorization.service';
import { UserSettings } from '../models/UserSettings.model';
import { Category } from '../models/Category.model';
import { DictionaryEntry } from '../models/DictionaryEntry.model';
import { hashPassword } from '../utils/password.util';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';

function paging(req: Request) {
  const page = Number(req.query.page || 1), limit = Number(req.query.limit || 20);
  return {page,limit,skip:(page-1)*limit};
}
function literalSearch(value: unknown): string {
  return String(value || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
function notFound() { return new AppError('Không tìm thấy dữ liệu.',404,ErrorCodes.NOT_FOUND); }
export async function createUser(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const {email,password,displayName,role} = req.body;
    if(await User.exists({email})) throw new AppError('Email đã được sử dụng.',409,ErrorCodes.AUTH_EMAIL_ALREADY_EXISTS);
    const custom=req.body.customRoleId?await Role.findById(req.body.customRoleId):null;
    if(req.body.customRoleId && !custom) throw notFound();
    assertCanGrant(req.user!.permissions,custom?custom.permissions:builtInPermissions[role as UserRole]);
    const user = await User.create({email,displayName,role:custom?roleForPermissions(custom.permissions):role,customRoleId:custom?custom._id:undefined,passwordHash:await hashPassword(password),accountType:AccountType.LOCAL,isGuest:false});
    await UserSettings.create({userId:user._id});
    const safeUser = await User.findById(user._id);
    res.status(201).json({success:true,data:safeUser});
  } catch(error) {next(error);}
}

export async function listRoles(_req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const system=Object.values(UserRole).map(key=>({_id:key,key,name:key,description:'Vai trò hệ thống',permissions:builtInPermissions[key],system:true}));
    const custom=await Role.find().sort({name:1});
    res.json({success:true,data:[...system,...custom.map(role=>({...role.toObject(),system:false}))]});
  } catch(error) {next(error);}
}
export async function userRoleOptions(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const system=Object.values(UserRole).map(key=>({_id:key,key,name:key,permissions:builtInPermissions[key],system:true}));
    const custom=(await Role.find().sort({name:1})).map(role=>({...role.toObject(),system:false}));
    const options=[...system,...custom].filter(role=>role.permissions.every(permission=>req.user!.permissions.includes(permission)));
    res.json({success:true,data:options});
  } catch(error) {next(error);}
}
export async function createRole(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    assertCanGrant(req.user!.permissions,req.body.permissions);
    res.status(201).json({success:true,data:await Role.create(req.body)});
  } catch(error) {next(error);}
}
export async function updateRole(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const role = await administratorTransaction(async session => {
    const existing=await Role.findById(req.params.id).session(session);
    if(!existing) throw notFound();
    assertCanGrant(req.user!.permissions,existing.permissions);
    if(req.body.permissions) assertCanGrant(req.user!.permissions,req.body.permissions);
    if(req.user!.customRoleId===req.params.id && req.body.permissions &&
       ['admin:access','roles:write'].some(permission=>!req.body.permissions.includes(permission))) {
      throw new AppError('Không thể bỏ quyền truy cập/quản lý role của chính mình.',400,ErrorCodes.VALIDATION_ERROR);
    }
    const role=await Role.findByIdAndUpdate(req.params.id,{$set:req.body},{new:true,runValidators:true,session});
    if(!role) throw notFound();
      return role;
    });
    res.json({success:true,data:role});
  } catch(error) {next(error);}
}
export async function deleteRole(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const existing=await Role.findById(req.params.id);
    if(!existing) throw notFound();
    assertCanGrant(req.user!.permissions,existing.permissions);
    if(await User.exists({customRoleId:req.params.id})) throw new AppError('Role đang được gán cho tài khoản. Hãy đổi role của các tài khoản này trước.',409,ErrorCodes.CONFLICT);
    const role=await Role.findByIdAndDelete(req.params.id);
    if(!role) throw notFound();
    res.json({success:true,data:{message:'Đã xóa role.'}});
  } catch(error) {next(error);}
}

export async function listDictionary(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const {page,limit,skip}=paging(req);
    const filter: Record<string,unknown> = {};
    if(req.query.status) filter.status=req.query.status;
    if(req.query.search) filter.word={$regex:literalSearch(req.query.search),$options:'i'};
    const [items,total]=await Promise.all([
      DictionaryEntry.find(filter).populate('categoryId','name slug').sort({updatedAt:-1}).skip(skip).limit(limit),
      DictionaryEntry.countDocuments(filter),
    ]);
    res.json({success:true,data:{items,pagination:{page,limit,total,pages:Math.ceil(total/limit)}}});
  } catch(error) {next(error);}
}

export async function createDictionary(req: Request, res: Response, next: NextFunction): Promise<void> {
  try { res.status(201).json({success:true,data:await writeContent(req.user!, req.body)}); } catch(error) { next(error); }
}
export async function updateDictionary(req: Request, res: Response, next: NextFunction): Promise<void> {
  try { res.json({success:true,data:await writeContent(req.user!, req.body, req.params.id)}); } catch(error) { next(error); }
}
export async function deleteDictionary(req: Request, res: Response, next: NextFunction): Promise<void> {
  try { await removeContent(req.user!,req.params.id); res.json({success:true,data:{message:'Đã xóa mục từ điển.'}}); } catch(error) { next(error); }
}

export async function listCategories(_req: Request, res: Response, next: NextFunction): Promise<void> {
  try {res.json({success:true,data:await Category.find().sort({sortOrder:1,name:1})});} catch(error) {next(error);}
}
export async function createCategory(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {res.status(201).json({success:true,data:await Category.create(req.body)});} catch(error) {next(error);}
}
export async function updateCategory(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const category=await Category.findByIdAndUpdate(req.params.id,{$set:req.body},{new:true,runValidators:true});
    if(!category) throw notFound();
    res.json({success:true,data:category});
  } catch(error) {next(error);}
}
export async function deleteCategory(req: Request, res: Response, next: NextFunction): Promise<void> {
  try { await removeCategory(req.params.id); res.json({success:true,data:{message:'Đã xóa danh mục.'}}); } catch(error) { next(error); }
}
