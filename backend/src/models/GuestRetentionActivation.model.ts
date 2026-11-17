import {Schema, model} from 'mongoose';

const schema = new Schema({_id: {type: String, required: true}, activatedAt: {type: Date, required: true, immutable: true}},
  {collection: 'guest_retention_activation', versionKey: false, autoCreate: false, autoIndex: false});
schema.pre(['updateOne', 'updateMany', 'findOneAndUpdate', 'replaceOne', 'findOneAndReplace', 'deleteOne', 'deleteMany', 'findOneAndDelete'], function () {
  throw new Error('Guest retention activation is insert-only');
});
export const GuestRetentionActivation = model('GuestRetentionActivation', schema);
