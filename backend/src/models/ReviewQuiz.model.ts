import { Schema, model } from 'mongoose';

import type {Types} from 'mongoose';
export const ReviewQuiz = model('ReviewQuiz', new Schema({
  userId: { type: Schema.Types.ObjectId, required: true },
  topicId: { type: Schema.Types.ObjectId, required:function(this:{collectionId?:Types.ObjectId}) { return !this.collectionId; } },
  collectionId: { type: Schema.Types.ObjectId },
  collectionName:{type:String,maxlength:80},
  libraryChanged:{type:Boolean,default:false},
  status: { type: String, enum: ['DRAFT', 'COMPLETED', 'ABANDONED'], default: 'DRAFT', required: true },
  kind: { type: String, enum: ['TEXT', 'CAMERA', 'VIDEO_CHOICE', 'VIDEO_RECALL'], default: 'TEXT', required: true },
  questions: { type: [Schema.Types.Mixed], required: true },
  answers: { type: [String], default: [] },
  captures: { type: [Schema.Types.Mixed], default: [] },
  hintedEntries: { type: [String], default: [] },
  recallResponses: { type: [Schema.Types.Mixed], default: [] },
  result: { type: Schema.Types.Mixed, default: null },
  gradingToken: { type: String, default: '' },
  gradingUntil: { type: Date, default: null },
  completedAt: { type: Date, default: null },
}, { timestamps: true, collection: 'learning_review_quizzes' })
  .index({ userId: 1, topicId: 1 }, { name:'draft_topic_scope', unique: true, partialFilterExpression: { status: 'DRAFT', topicId:{$exists:true} } })
  .index({ userId: 1, collectionId: 1 }, { name:'draft_collection_scope', unique: true, partialFilterExpression: { status: 'DRAFT', collectionId:{$exists:true} } })
  .index({ userId: 1, createdAt: -1 })
  .index({ userId: 1, status: 1, completedAt: -1 }));
