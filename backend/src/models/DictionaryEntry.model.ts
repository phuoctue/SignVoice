import { Schema, model, Document, Types } from 'mongoose';

/**
 * Entry status
 */
export enum EntryStatus {
  DRAFT = 'DRAFT', // Staff working on it
  PUBLISHED = 'PUBLISHED', // Live and visible
  ARCHIVED = 'ARCHIVED', // Hidden but not deleted
}

/**
 * Difficulty levels
 */
export enum DifficultyLevel {
  BEGINNER = 'BEGINNER',
  INTERMEDIATE = 'INTERMEDIATE',
  ADVANCED = 'ADVANCED',
}

/**
 * Related word reference
 */
export interface IRelatedWord {
  entryId: Types.ObjectId;
  relationshipType: 'SYNONYM' | 'ANTONYM' | 'RELATED' | 'SEE_ALSO';
}

/**
 * Dictionary entry document interface
 */
export interface IDictionaryEntry extends Document {
  _id: Types.ObjectId;
  
  // Basic info
  word: string; // The sign language word/phrase (Vietnamese)
  aliases?: string[];
  definition: string; // Explanation
  
  // Media
  videoUrl: string; // Primary demo video (required)
  thumbnailUrl?: string; // Video thumbnail
  imageUrls?: string[]; // Additional reference images
  
  // Categorization
  categoryId: Types.ObjectId;
  tags?: string[]; // Additional searchable tags
  difficulty?: DifficultyLevel;
  
  // Metadata
  usageExample?: string; // Example sentence
  notes?: string; // Additional notes for learners
  relatedWords?: IRelatedWord[]; // References to other entries
  
  // Status
  status: EntryStatus;
  rejectionReason?: string;
  
  // Statistics (denormalized)
  viewCount: number;
  favoriteCount: number;
  
  // Authorship
  createdBy: Types.ObjectId; // Staff/Admin who created
  lastModifiedBy?: Types.ObjectId;
  publishedAt?: Date;
  
  // Timestamps
  createdAt: Date;
  updatedAt: Date;
  
  // Methods
  isPublished(): boolean;
  incrementViewCount(): Promise<void>;
}

/**
 * Dictionary entry schema
 */
const DictionaryEntrySchema = new Schema<IDictionaryEntry>(
  {
    word: {
      type: String,
      required: [true, 'Word is required'],
      trim: true,
      minlength: [1, 'Word must be at least 1 character'],
      maxlength: [200, 'Word must be less than 200 characters'],
    },
    
    definition: {
      type: String,
      required: [true, 'Definition is required'],
      trim: true,
      minlength: [5, 'Definition must be at least 5 characters'],
      maxlength: [2000, 'Definition must be less than 2000 characters'],
    },

    aliases: {
      type: [String], default: [],
      validate: { validator: (values: string[]) => values.length <= 20 && values.every(value => value.length > 0 && value.length <= 200),
        message: 'Invalid dictionary aliases' },
    },
    
    videoUrl: {
      type: String,
      required: [true, 'Video URL is required'],
      trim: true,
      validate: {
        validator: function(v: string) {
          // Basic URL validation
          return /^https?:\/\/.+/.test(v);
        },
        message: 'Invalid video URL format',
      },
    },
    
    thumbnailUrl: {
      type: String,
      trim: true,
    },
    
    imageUrls: {
      type: [String],
      default: [],
      validate: {
        validator: function(arr: string[]) {
          return arr.length <= 10; // Max 10 images
        },
        message: 'Maximum 10 images allowed',
      },
    },
    
    categoryId: {
      type: Schema.Types.ObjectId,
      ref: 'Category',
      required: [true, 'Category is required'],
      index: true,
    },
    
    tags: {
      type: [String],
      default: [],
      validate: {
        validator: function(arr: string[]) {
          return arr.length <= 20; // Max 20 tags
        },
        message: 'Maximum 20 tags allowed',
      },
    },
    
    difficulty: {
      type: String,
      enum: Object.values(DifficultyLevel),
    },
    
    usageExample: {
      type: String,
      trim: true,
      maxlength: [1000, 'Usage example must be less than 1000 characters'],
    },
    
    notes: {
      type: String,
      trim: true,
      maxlength: [2000, 'Notes must be less than 2000 characters'],
    },
    
    relatedWords: {
      type: [{
        entryId: {
          type: Schema.Types.ObjectId,
          ref: 'DictionaryEntry',
          required: true,
        },
        relationshipType: {
          type: String,
          enum: ['SYNONYM', 'ANTONYM', 'RELATED', 'SEE_ALSO'],
          required: true,
        },
      }],
      default: [],
    },
    
    status: {
      type: String,
      enum: Object.values(EntryStatus),
      default: EntryStatus.DRAFT,
      required: true,
      index: true,
    },
    
    rejectionReason: {
      type: String,
      trim: true,
      maxlength: [500, 'Rejection reason must be less than 500 characters'],
    },
    
    viewCount: {
      type: Number,
      default: 0,
      min: [0, 'View count cannot be negative'],
      required: true,
    },
    
    favoriteCount: {
      type: Number,
      default: 0,
      min: [0, 'Favorite count cannot be negative'],
      required: true,
    },
    
    createdBy: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'Creator is required'],
      index: true,
    },
    
    lastModifiedBy: {
      type: Schema.Types.ObjectId,
      ref: 'User',
    },
    
    publishedAt: {
      type: Date,
      index: true,
    },
  },
  {
    timestamps: true,
    collection: 'dictionary_entries',
  }
);

// ============================================================================
// INDEXES
// ============================================================================

// Full-text search (word and definition)
DictionaryEntrySchema.index(
  { word: 'text', definition: 'text', tags: 'text' },
  { weights: { word: 10, definition: 5, tags: 3 } }
);

// Primary queries
DictionaryEntrySchema.index({ status: 1, publishedAt: -1 }); // Published entries
DictionaryEntrySchema.index({ categoryId: 1, status: 1 }); // Category filtering
DictionaryEntrySchema.index({ status: 1, viewCount: -1 }); // Popular entries
DictionaryEntrySchema.index({ createdBy: 1, status: 1 }); // Staff's entries

// Compound for filtering
DictionaryEntrySchema.index({ status: 1, categoryId: 1, difficulty: 1 });

// ============================================================================
// METHODS
// ============================================================================

/**
 * Check if entry is published
 */
DictionaryEntrySchema.methods.isPublished = function(): boolean {
  return this.status === EntryStatus.PUBLISHED && !!this.publishedAt;
};

/**
 * Increment view count (atomic)
 */
DictionaryEntrySchema.methods.incrementViewCount = async function(): Promise<void> {
  const Model = this.constructor as any;
  await Model.findByIdAndUpdate(this._id, {
    $inc: { viewCount: 1 },
  });
  this.viewCount += 1; // Update in-memory instance
};

// ============================================================================
// STATIC METHODS
// ============================================================================

/**
 * Search published entries
 */
DictionaryEntrySchema.statics.search = async function(
  query: string,
  options: {
    categoryId?: Types.ObjectId;
    difficulty?: DifficultyLevel;
    limit?: number;
    skip?: number;
  } = {}
): Promise<IDictionaryEntry[]> {
  const filter: any = {
    status: EntryStatus.PUBLISHED,
    $text: { $search: query },
  };
  
  if (options.categoryId) {
    filter.categoryId = options.categoryId;
  }
  
  if (options.difficulty) {
    filter.difficulty = options.difficulty;
  }
  
  return await this.find(filter)
    .select({ score: { $meta: 'textScore' } })
    .sort({ score: { $meta: 'textScore' }, viewCount: -1 })
    .limit(options.limit || 20)
    .skip(options.skip || 0)
    .populate('categoryId', 'name slug')
    .exec();
};

/**
 * Get published entries by category
 */
DictionaryEntrySchema.statics.getByCategory = async function(
  categoryId: Types.ObjectId,
  options: { limit?: number; skip?: number } = {}
): Promise<IDictionaryEntry[]> {
  return await this.find({
    categoryId,
    status: EntryStatus.PUBLISHED,
  })
    .sort({ publishedAt: -1 })
    .limit(options.limit || 20)
    .skip(options.skip || 0)
    .exec();
};

/**
 * Get popular entries
 */
DictionaryEntrySchema.statics.getPopular = async function(
  limit: number = 10
): Promise<IDictionaryEntry[]> {
  return await this.find({ status: EntryStatus.PUBLISHED })
    .sort({ viewCount: -1, publishedAt: -1 })
    .limit(limit)
    .populate('categoryId', 'name slug')
    .exec();
};

/**
 * Increment favorite count
 */
DictionaryEntrySchema.statics.incrementFavoriteCount = async function(
  entryId: Types.ObjectId,
  delta: number = 1
): Promise<void> {
  await this.findByIdAndUpdate(entryId, {
    $inc: { favoriteCount: delta },
  });
};

// ============================================================================
// HOOKS
// ============================================================================

/**
 * Set publishedAt when status changes to PUBLISHED
 */
DictionaryEntrySchema.pre('save', function() {
  if (this.isModified('status') && this.status === EntryStatus.PUBLISHED && !this.publishedAt) {
    this.publishedAt = new Date();
  }
});

/**
 * Normalize tags (lowercase, trim)
 */
DictionaryEntrySchema.pre('save', function() {
  if (this.tags && this.tags.length > 0) {
    this.tags = this.tags
      .map(tag => tag.toLowerCase().trim())
      .filter((tag, index, arr) => tag && arr.indexOf(tag) === index); // Unique non-empty
  }
});

// ============================================================================
// EXPORT MODEL
// ============================================================================

export const DictionaryEntry = model<IDictionaryEntry>('DictionaryEntry', DictionaryEntrySchema);
