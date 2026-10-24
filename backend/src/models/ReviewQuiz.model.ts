import { Schema, model } from 'mongoose';

export const ReviewQuiz = model('ReviewQuiz', new Schema({
  userId: { type: Schema.Types.ObjectId, required: true },
  topicId: { type: Schema.Types.ObjectId, required: true },
  status: { type: String, enum: ['DRAFT', 'COMPLETED', 'ABANDONED'], default: 'DRAFT', required: true },
  kind: { type: String, enum: ['TEXT', 'CAMERA'], default: 'TEXT', required: true },
  questions: { type: [Schema.Types.Mixed], required: true },
  answers: { type: [String], default: [] },
  captures: { type: [Schema.Types.Mixed], default: [] },
  result: { type: Schema.Types.Mixed, default: null },
  gradingToken: { type: String, default: '' },
  gradingUntil: { type: Date, default: null },
  completedAt: { type: Date, default: null },
}, { timestamps: true, collection: 'learning_review_quizzes' })
  .index({ userId: 1, topicId: 1 }, { unique: true, partialFilterExpression: { status: 'DRAFT' } })
  .index({ userId: 1, createdAt: -1 }));
