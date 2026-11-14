import {Schema, model, Types} from 'mongoose';
export interface IGuestTrial {
  _id: Types.ObjectId;
  deviceHash: string;
  startedAt?: Date;
  expiresAt?: Date;
  lastGrantRequestHash?: string;
  legacyFallbackDisabledAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}
const schema = new Schema<IGuestTrial>({
  deviceHash: {type: String, required: true, unique: true}, startedAt: Date, expiresAt: Date,
  lastGrantRequestHash: {type: String, select: false},
  legacyFallbackDisabledAt: {type: Date, immutable: true},
}, {timestamps: true, collection: 'guest_trials'});
// Spent allowances must survive their expiry to prevent granting another trial.
export const GuestTrial = model<IGuestTrial>('GuestTrial', schema);
