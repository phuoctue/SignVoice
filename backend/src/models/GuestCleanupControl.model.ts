import {Schema, model, Types} from 'mongoose';

export interface CleanupControl {
  _id: string; paused: boolean; reason: string; changedAt: Date; changedBy: string; version: number;
  lease?: {holder: string; expiresAt: Date; revision: number};
  cursor?: Types.ObjectId;
}
export const GuestCleanupControl = model<CleanupControl>('GuestCleanupControl', new Schema<CleanupControl>({
  _id: {type: String, required: true}, paused: {type: Boolean, required: true},
  reason: {type: String, required: true}, changedAt: {type: Date, required: true}, changedBy: {type: String, required: true},
  version: {type: Number, required: true},
  lease: {type: new Schema({holder: String, expiresAt: Date, revision: Number}, {_id: false}), default: undefined},
  // Round-robin scanning prevents unknown legacy rows or exempt canaries starving other guests.
  cursor: Schema.Types.ObjectId,
}, {collection: 'guest_cleanup_control', versionKey: false, autoCreate: false, autoIndex: false}));
export function validCleanupControl(row: CleanupControl | null): row is CleanupControl {
  return !!row && row._id === 'guest-cleanup' && typeof row.paused === 'boolean' &&
    typeof row.reason === 'string' && !!row.reason.trim() && typeof row.changedBy === 'string' && !!row.changedBy.trim() &&
    row.changedAt instanceof Date && Number.isFinite(+row.changedAt) && Number.isSafeInteger(row.version) && row.version >= 0 &&
    (row.cursor === undefined || row.cursor instanceof Types.ObjectId) &&
    (row.lease === undefined || row.lease !== null && typeof row.lease === 'object' && typeof row.lease.holder === 'string' && !!row.lease.holder &&
      row.lease.expiresAt instanceof Date && Number.isFinite(+row.lease.expiresAt) &&
      Number.isSafeInteger(row.lease.revision) && row.lease.revision >= 0);
}
