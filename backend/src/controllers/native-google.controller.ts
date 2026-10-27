import {randomBytes} from 'crypto';
import {Request,Response,NextFunction} from 'express';
import {env} from '../config/env';
import {NativeGoogleChallenge} from '../models/NativeGoogleChallenge.model';
import {User,AccountType,AccountStatus,IUser} from '../models/User.model';
import {AuditLog,AuditAction} from '../models/AuditLog.model';
import {digest,resolveOAuthUser} from '../services/oauth.service';
import {verifyGoogleIdentity,ProviderIdentity} from '../services/oauth-provider.service';
import {loginOAuthUser} from '../services/auth.service';
import {authorizationFor} from '../services/authorization.service';
import {AppError} from '../common/errors/AppError';

function clientId() {
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_ID.endsWith('.apps.googleusercontent.com')) {
    throw new AppError('Máy chủ chưa cấu hình Google Web Client ID.',503,'OAUTH_DISABLED');
  }
  return env.GOOGLE_CLIENT_ID;
}
export async function challenge(_req:Request,res:Response,next:NextFunction) {
  try {
    const client=clientId(), value=randomBytes(32).toString('base64url'), nonce=randomBytes(32).toString('base64url');
    await NativeGoogleChallenge.create({challengeHash:digest(value),nonce,clientId:client,expiresAt:new Date(Date.now()+300000)});
    res.setHeader('Cache-Control','no-store');
    res.json({success:true,data:{challenge:value,nonce,clientId:client}});
  } catch(error){next(error);}
}
async function identity(req:Request):Promise<ProviderIdentity> {
  const record=await NativeGoogleChallenge.findOneAndDelete({challengeHash:digest(req.body.challenge),
    clientId:clientId(),expiresAt:{$gt:new Date()}});
  if(!record) throw new AppError('Phiên Google đã hết hạn. Vui lòng bắt đầu lại.',400,'OAUTH_CHALLENGE_INVALID');
  return verifyGoogleIdentity(req.body.idToken,record.clientId,record.nonce);
}
async function safeUser(user:IUser) {
  return {id:user._id.toString(),email:user.email,displayName:user.displayName,avatarUrl:user.avatarUrl,
    accountType:user.accountType,isGuest:user.isGuest,status:user.status,createdAt:user.createdAt,updatedAt:user.updatedAt,
    googleLinked:!!user.googleProvider?.providerId,...await authorizationFor(user)};
}
export async function login(req:Request,res:Response,next:NextFunction) {
  try {
    const verified=await identity(req);
    const user=await resolveOAuthUser('google',verified);
    const result=await loginOAuthUser(user,{ipAddress:req.socket.remoteAddress,userAgent:req.get('user-agent')});
    res.setHeader('Cache-Control','no-store');
    res.json({success:true,data:{...result,user:{...result.user,googleLinked:!!user.googleProvider?.providerId}}});
  } catch(error){next(error);}
}
export async function link(req:Request,res:Response,next:NextFunction) {
  try {
    const verified=await identity(req);
    await User.init();
    const user=await User.findById(req.user!.id);
    if(!user?.isActive() || user.isGuest || user.accountType!==AccountType.LOCAL) {
      throw new AppError('Hãy đăng nhập bằng tài khoản email trước khi liên kết Google.',400,'OAUTH_LINK_NOT_ALLOWED');
    }
    if(!verified.email || user.email?.toLowerCase()!==verified.email) {
      throw new AppError('Chọn tài khoản Google có cùng email với tài khoản SignVoice.',400,'OAUTH_LINK_EMAIL_MISMATCH');
    }
    if(user.googleProvider?.providerId && user.googleProvider.providerId!==verified.subject) {
      throw new AppError('Tài khoản đã liên kết với danh tính Google khác.',409,'OAUTH_ALREADY_LINKED');
    }
    if(user.googleProvider?.providerId!==verified.subject) {
      const linked=await User.findOneAndUpdate({_id:user._id,status:AccountStatus.ACTIVE,email:verified.email,
        passwordVersion:user.passwordVersion,$or:[{'googleProvider.providerId':{$exists:false}}, {'googleProvider.providerId':verified.subject}]},
        {$set:{googleProvider:{providerId:verified.subject}}},{new:true,runValidators:true});
      if(!linked)throw new AppError('Tài khoản vừa thay đổi. Vui lòng thử lại.',409,'OAUTH_LINK_CONFLICT');
      await AuditLog.log({userId:user._id,actorRole:(await authorizationFor(linked)).role,action:AuditAction.USER_UPDATE,
        resourceType:'User',resourceId:user._id,details:{googleLinked:true},ipAddress:req.ip,userAgent:req.get('user-agent')});
      res.setHeader('Cache-Control','no-store');
      res.json({success:true,data:{user:await safeUser(linked)}});
    }else{
      res.setHeader('Cache-Control','no-store');res.json({success:true,data:{user:await safeUser(user)}});
    }
  } catch(error){
    // Failed Google proof must not log out a valid password session.
    if(error instanceof AppError && error.code==='OAUTH_IDENTITY_INVALID') {
      next(new AppError(error.message,400,error.code));
    }else if((error as {code?:number}).code===11000){
      next(new AppError('Danh tính Google đã được liên kết với tài khoản khác.',409,'OAUTH_ACCOUNT_COLLISION'));
    }else{next(error);}
  }
}
