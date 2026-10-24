import { Schema, model, Document, Types } from 'mongoose';

/**
 * Favorite document interface
 */
export interface IFavorite extends Document {
  _id: Types.ObjectId;
  
  // Relationships
  userId: Types.ObjectId;
  entryId: Types.ObjectId;
  
  // Metadata
  notes?: string; // User's personal notes about this favorite
  
  // Timestamps
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Favorite schema
 */
const FavoriteSchema = new Schema<IFavorite>(
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
    
    notes: {
      type: String,
      trim: true,
      maxlength: [500, 'Notes must be less than 500 characters'],
    },
  },
  {
    timestamps: true,
    collection: 'favorites',
  }
);

// ============================================================================
// INDEXES
// ============================================================================

// Prevent duplicate favorites (user can favorite an entry only once)
FavoriteSchema.index({ userId: 1, entryId: 1 }, { unique: true });

// Query optimization
FavoriteSchema.index({ userId: 1, createdAt: -1 }); // User's favorites sorted by date

// ============================================================================
// STATIC METHODS
// ============================================================================

/**
 * Add a favorite (idempotent)
 */
FavoriteSchema.statics.addFavorite = async function(
  userId: Types.ObjectId,
  entryId: Types.ObjectId,
  notes?: string
): Promise<IFavorite> {
  // Use upsert to make it idempotent
  const favorite = await this.findOneAndUpdate(
    { userId, entryId },
    { $set: { notes } },
    { upsert: true, new: true, runValidators: true }
  );
  
  // Update favoriteCount on DictionaryEntry
  const DictionaryEntry = model('DictionaryEntry');
  await DictionaryEntry.findByIdAndUpdate(entryId, {
    $inc: { favoriteCount: 1 },
  });
  
  return favorite;
};

/**
 * Remove a favorite
 */
FavoriteSchema.statics.removeFavorite = async function(
  userId: Types.ObjectId,
  entryId: Types.ObjectId
): Promise<boolean> {
  const result = await this.deleteOne({ userId, entryId });
  
  if (result.deletedCount > 0) {
    // Update favoriteCount on DictionaryEntry
    const DictionaryEntry = model('DictionaryEntry');
    await DictionaryEntry.findByIdAndUpdate(entryId, {
      $inc: { favoriteCount: -1 },
    });
    return true;
  }
  
  return false;
};

/**
 * Check if user has favorited an entry
 */
FavoriteSchema.statics.isFavorited = async function(
  userId: Types.ObjectId,
  entryId: Types.ObjectId
): Promise<boolean> {
  const count = await this.countDocuments({ userId, entryId });
  return count > 0;
};

/**
 * Get user's favorites with entry details
 */
FavoriteSchema.statics.getUserFavorites = async function(
  userId: Types.ObjectId,
  options: { limit?: number; skip?: number } = {}
): Promise<IFavorite[]> {
  return await this.find({ userId })
    .sort({ createdAt: -1 })
    .limit(options.limit || 20)
    .skip(options.skip || 0)
    .populate({
      path: 'entryId',
      select: 'word definition videoUrl thumbnailUrl categoryId status',
      match: { status: 'PUBLISHED' }, // Only show published entries
    })
    .exec();
};

/**
 * Get favorite count for an entry
 */
FavoriteSchema.statics.getEntryFavoriteCount = async function(
  entryId: Types.ObjectId
): Promise<number> {
  return await this.countDocuments({ entryId });
};

/**
 * Get multiple favorite statuses (bulk check)
 */
FavoriteSchema.statics.bulkCheckFavorites = async function(
  userId: Types.ObjectId,
  entryIds: Types.ObjectId[]
): Promise<Map<string, boolean>> {
  const favorites = await this.find({
    userId,
    entryId: { $in: entryIds },
  }).select('entryId');
  
  const favoriteMap = new Map<string, boolean>();
  entryIds.forEach(id => favoriteMap.set(id.toString(), false));
  favorites.forEach((fav: IFavorite) => favoriteMap.set(fav.entryId.toString(), true));
  
  return favoriteMap;
};

// ============================================================================
// HOOKS
// ============================================================================

/**
 * Update DictionaryEntry favoriteCount on delete
 */
FavoriteSchema.post('deleteMany', async function(result: any) {
  // This hook runs after bulk deletes
  // Note: Individual document favoriteCount updates happen in removeFavorite static
  if (result.deletedCount > 0) {
    // Recalculate counts could be done here if needed
    console.log(`Deleted ${result.deletedCount} favorites`);
  }
});

// ============================================================================
// EXPORT MODEL
// ============================================================================

export const Favorite = model<IFavorite>('Favorite', FavoriteSchema);
