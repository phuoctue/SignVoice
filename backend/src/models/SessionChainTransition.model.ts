import mongoose, { Schema, Model } from 'mongoose';

export interface IChainTransition {
  _id: string;
  transitionId: string;
  policyVersion: string;
  windowMs: number;
  clockBudgetMs: number;
  cutoverAt: Date;
  sunsetAt: Date;
}
const schema = new Schema<IChainTransition>({
  _id: {type: String, enum: ['session-chain-transition'], required: true, immutable: true},
  transitionId: {type: String, required: true, immutable: true},
  policyVersion: {type: String, required: true, immutable: true},
  windowMs: {type: Number, required: true, immutable: true},
  clockBudgetMs: {type: Number, required: true, immutable: true},
  cutoverAt: {type: Date, required: true, immutable: true},
  sunsetAt: {type: Date, required: true, immutable: true},
}, {versionKey: false, autoCreate: false, autoIndex: false});
// Activation uses the operator's separate insert-only principal. App code only reads.
schema.pre(['updateOne', 'updateMany', 'findOneAndUpdate', 'replaceOne', 'findOneAndReplace', 'deleteOne', 'deleteMany', 'findOneAndDelete'], function () {
  throw new Error('Session chain transition is insert-only');
});
/** The control store shares the server connection, never the application database or a fallback. */
export function sessionChainTransitionModel(): Model<IChainTransition> {
  const database = process.env.SESSION_CHAIN_CONTROL_DB;
  const collection = process.env.SESSION_CHAIN_CONTROL_COLLECTION;
  if (!database || !collection || !/^[a-zA-Z0-9_-]+$/.test(database) || !/^[a-zA-Z0-9_-]+$/.test(collection) ||
      database.toLowerCase() === mongoose.connection.name?.toLowerCase() ||
      (process.env.NODE_ENV === 'test' && !/^signvoice_test_/i.test(database))) {
    throw new Error('Explicit separate session chain control namespace required');
  }
  const control = mongoose.connection.useDb(database, {useCache: true});
  const existing = control.models.SessionChainTransition as Model<IChainTransition> | undefined;
  if (existing && existing.collection.name !== collection) throw new Error('Session chain control collection changed');
  return existing || control.model<IChainTransition>('SessionChainTransition', schema, collection);
}
