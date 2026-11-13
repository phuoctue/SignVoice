import { Schema, model, Types } from 'mongoose';

export interface ISessionChain {
  userId: Types.ObjectId;
  chainId: string;
  legacyDerived: boolean;
  status: 'ACTIVE' | 'REVOKED';
  revokedAt?: Date;
  guardRevision: number;
}
const schema = new Schema<ISessionChain>({
  userId: {type: Schema.Types.ObjectId, required: true, immutable: true},
  chainId: {type: String, required: true, immutable: true},
  legacyDerived: {type: Boolean, required: true, immutable: true},
  status: {type: String, enum: ['ACTIVE', 'REVOKED'], required: true},
  revokedAt: Date,
  guardRevision: {type: Number, required: true, validate: Number.isSafeInteger, min: 0},
}, {collection: 'session_chains', versionKey: false});
schema.index({userId: 1, chainId: 1}, {unique: true});
schema.pre('save', function () {
  if (!this.isNew && this.isModified('status') && this.status === 'ACTIVE') throw new Error('Session chain revocation is terminal');
});
schema.pre(['updateOne', 'updateMany', 'findOneAndUpdate'], function () {
  const update = this.getUpdate() as Record<string, any> | null;
  if (update?.status === 'ACTIVE' || update?.$set?.status === 'ACTIVE') throw new Error('Session chain activation is insert-only');
});
schema.pre(['replaceOne', 'findOneAndReplace'], function () {throw new Error('Session chain replacement is forbidden');});
// No TTL: a terminal root must outlive every retained or late descendant.
export const SessionChain = model<ISessionChain>('SessionChain', schema);
