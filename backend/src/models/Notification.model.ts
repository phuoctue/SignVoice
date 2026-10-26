import {Schema, model} from 'mongoose';

export const UserNotification = model('UserNotification', new Schema({
  userId: {type: Schema.Types.ObjectId, required: true, ref: 'User'},
  key: {type: String, required: true},
  kind: {type: String, enum: ['NEW_WORDS', 'REVIEW', 'TEST'], required: true},
  title: {type: String, required: true},
  body: {type: String, required: true},
  route: {type: String, required: true},
  read: {type: Boolean, default: false},
  expiresAt: {type: Date, required: true},
}, {timestamps: true, collection: 'user_notifications'})
  .index({userId: 1, key: 1}, {unique: true})
  .index({userId: 1, createdAt: -1})
  .index({expiresAt: 1}, {expireAfterSeconds: 0}));

export const NotificationDevice = model('NotificationDevice', new Schema({
  userId: {type: Schema.Types.ObjectId, required: true, ref: 'User'},
  token: {type: String, required: true, unique: true},
  platform: {type: String, enum: ['android', 'ios'], required: true},
  sessionFamily: {type: String, required: true},
  deliveredAt: {type: Date, required: true, default: Date.now},
  checkedAt: {type: Date, default: () => new Date(0)},
  leaseUntil: {type: Date, default: () => new Date(0)},
  expiresAt: {type: Date, required: true},
}, {timestamps: true, collection: 'notification_devices'})
  .index({userId: 1}).index({checkedAt: 1}).index({expiresAt: 1}, {expireAfterSeconds: 0}));
