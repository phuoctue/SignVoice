import {Schema, model} from 'mongoose';

// Separate from the immutable lifecycle ledger: private, retryable filesystem work.
export const GuestMediaCleanup = model('GuestMediaCleanup', new Schema({
  _id: {type: String, required: true}, paths: {type: [String], required: true},
  attempts: {type: Number, default: 0}, createdAt: {type: Date, required: true}, lastAttemptAt: Date,
}, {collection: 'guest_media_cleanup', versionKey: false}));
