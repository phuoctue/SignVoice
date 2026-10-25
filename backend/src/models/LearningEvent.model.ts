import { Schema, model } from 'mongoose';

export const LearningEvent = model('LearningEvent', new Schema({
  userId: { type: Schema.Types.ObjectId, required: true },
  topicId: { type: Schema.Types.ObjectId, required: true },
  entryId: { type: Schema.Types.ObjectId, default: null },
  quizId: { type: Schema.Types.ObjectId, default: null },
  kind: { type: String, enum: ['TOPIC_STARTED', 'SELF_RATED', 'QUIZ_REVIEWED'], required: true },
  word: { type: String, default: '', maxlength: 200 },
  topicName: { type: String, required: true, maxlength: 200 },
  stage: { type: String, enum: ['LEARNING', 'REMEMBERED', 'REVIEW', null], default: null },
  score: { type: Number, default: null, min: 0, max: 10 },
  applied: { type: Boolean, default: true },
  firstLearning: { type: Boolean, default: false },
}, { timestamps: { createdAt: true, updatedAt: false }, collection: 'learning_events' })
  .index({ userId: 1, createdAt: -1, _id: -1 })
  .index({ userId: 1, entryId: 1, createdAt: -1 })
  .index({ userId: 1, quizId: 1, entryId: 1 }, { unique: true, partialFilterExpression: { kind: 'QUIZ_REVIEWED' } }));
