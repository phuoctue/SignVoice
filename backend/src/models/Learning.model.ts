import { Schema, model } from 'mongoose';

export const TopicEnrollment = model('TopicEnrollment', new Schema({
  userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  topicId: { type: Schema.Types.ObjectId, ref: 'Category', required: true },
}, { timestamps: true, collection: 'learning_enrollments' }).index({ userId: 1, topicId: 1 }, { unique: true }).index({ topicId: 1 }));

export const WordProgress = model('WordProgress', new Schema({
  userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
  entryId: { type: Schema.Types.ObjectId, ref: 'DictionaryEntry', required: true },
  topicId: { type: Schema.Types.ObjectId, ref: 'Category', required: true },
  stage: { type: String, enum: ['LEARNING', 'REMEMBERED', 'REVIEW'], default: 'LEARNING', required: true },
  nextReviewAt: { type: Date, default: null },
  reviewedAt: { type: Date, default: null },
}, { timestamps: true, collection: 'learning_word_progress' })
  .index({ userId: 1, entryId: 1 }, { unique: true }).index({ userId: 1, topicId: 1 }));

export const PersonalWord = model('PersonalWord', new Schema({
  userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  word: { type: String, required: true, trim: true, maxlength: 100 },
  definition: { type: String, required: true, trim: true, maxlength: 2000 },
  usageExample: { type: String, default: '', maxlength: 1000 },
  notes: { type: String, default: '', maxlength: 2000 },
  imageUrl: { type: String, default: '', maxlength: 1500000 },
  videoUrl: { type: String, default: '', maxlength: 2000 },
}, { timestamps: true, collection: 'learning_personal_words' }).index({ userId: 1, updatedAt: -1, _id: 1 }));
