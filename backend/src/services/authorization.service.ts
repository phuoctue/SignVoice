import { IUser, UserRole } from '../models/User.model';
import { Role, permissions, Permission } from '../models/Role.model';
import { AppError } from '../common/errors/AppError';
import { ErrorCodes } from '../common/errors/errorCodes';

export function assertCanGrant(actor: readonly string[], target: readonly string[]): void {
  if(target.some(permission=>!actor.includes(permission))) throw new AppError('Bạn không thể quản lý hoặc cấp quyền cao hơn quyền hiện có.',403,ErrorCodes.AUTH_FORBIDDEN);
}

export const builtInPermissions: Record<UserRole, readonly Permission[]> = {
  ADMIN: permissions,
  STAFF: ['staff:access','dictionary:read','dictionary:write','content:publish','categories:read','categories:write','collections:read','collections:moderate'],
  USER: [],
};
export function roleForPermissions(granted: readonly string[]): UserRole {
  if(granted.includes('admin:access')) return UserRole.ADMIN;
  if(granted.includes('staff:access')) return UserRole.STAFF;
  return UserRole.USER;
}
export async function authorizationFor(user: IUser) {
  if(user.customRoleId) {
    const custom=await Role.findById(user.customRoleId);
    const granted=custom?.permissions || [];
    return {role:roleForPermissions(granted),permissions:granted,customRoleId:user.customRoleId.toString(),customRoleName:custom?.name || 'Role không còn tồn tại'};
  }
  return {role:user.role,permissions:[...builtInPermissions[user.role]]};
}
