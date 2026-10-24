import { Schema, model, Document, Types } from 'mongoose';

/**
 * Search history document interface
 * Tracks when users view dictionary entries
 */
export interface ISearchHistory extends Document {
  _id: Types.ObjectId;
  
  // Relationships
  userId: Types.ObjectId;
  entryId: Types.ObjectId;
  
  // Metadata
  viewedAt: Date;
  createdAt: Date;
}

/**
 * Search history schema
 */
const SearchHistorySchema = new Schema<ISearchHistory>(
  {
    userId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'User ID is required'],
      index: true,
    },
    
    entryId: {
      type: Schema.Types.ObjectId,
      ref: 'DictionaryEntry',
      required: [true, 'Entry ID is required'],
      index: true,
    },
    
    viewedAt: {
      type: Date,
      default: Date.now,
      required: true,
    },
  },
  {
    timestamps: { createdAt: true, updatedAt: false },
    collection: 'search_history',
  }
);

// ============================================================================
// INDEXES
// ============================================================================

// Primary queries
SearchHistorySchema.index({ userId: 1, viewedAt: -1 }); // User's history
SearchHistorySchema.index({ userId: 1, entryId: 1 }); // Check if viewed
SearchHistorySchema.index({ entryId: 1, viewedAt: -1 }); // Entry popularity

// TTL index - auto-delete after 90 days
SearchHistorySchema.index(
  { viewedAt: 1 },
  { expireAfterSeconds: 60 * 60 * 24 * 90 }
);

// ============================================================================
// STATIC METHODS
// ============================================================================

/**
 * Record a view (idempotent - updates viewedAt if exists)
 */
SearchHistorySchema.statics.recordView = async function(
  userId: Types.ObjectId,
  entryId: Types.ObjectId
): Promise<ISearchHistory> {
  // Update or create
  const history = await this.findOneAndUpdate(
    { userId, entryId },
    { $set: { viewedAt: new Date() } },
    { upsert: true, new: true }
  );
  
  return history;
};

/**
 * Get user's search history
 */
SearchHistorySchema.statics.getUserHistory = async function(
  userId: Types.ObjectId,
  options: { limit?: number; skip?: number } = {}
): Promise<ISearchHistory[]> {
  return await this.find({ userId })
    .sort({ viewedAt: -1 })
    .limit(options.limit || 50)
    .skip(options.skip || 0)
    .populate({
      path: 'entryId',
      select: 'word definition videoUrl thumbnailUrl categoryId status',
      match: { status: 'PUBLISHED' },
    })
    .exec();
};

/**
 * Clear user's history
 */
SearchHistorySchema.statics.clearUserHistory = async function(
  userId: Types.ObjectId
): Promise<number> {
  const result = await this.deleteMany({ userId });
  return result.deletedCount;
};

/**
 * Get most viewed entries
 */
SearchHistorySchema.statics.getMostViewed = async function(
  options: { limit?: number; since?: Date } = {}
): Promise<Array<{ entryId: Types.ObjectId; viewCount: number }>> {
  const matchStage: any = {};
  
  if (options.since) {
    matchStage.viewedAt = { $gte: options.since };
  }
  
  return await this.aggregate([
    ...(Object.keys(matchStage).length > 0 ? [{ $match: matchStage }] : []),
    {
      $group: {
        _id: '$entryId',
        viewCount: { $sum: 1 },
      },
    },
    { $sort: { viewCount: -1 } },
    { $limit: options.limit || 20 },
    {
      $project: {
        entryId: '$_id',
        viewCount: 1,
        _id: 0,
      },
    },
  ]);
};

// ============================================================================
// EXPORT MODEL
// ============================================================================

export const SearchHistory = model<ISearchHistory>('SearchHistory', SearchHistorySchema);
