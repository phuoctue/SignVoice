import { Schema, model, Document, Types } from 'mongoose';

/**
 * Category status
 */
export enum CategoryStatus {
  ACTIVE = 'ACTIVE',
  ARCHIVED = 'ARCHIVED',
}

/**
 * Category document interface
 */
export interface ICategory extends Document {
  _id: Types.ObjectId;
  
  // Basic info
  name: string; // e.g., "Greetings", "Family", "Numbers"
  slug: string; // URL-friendly: "greetings", "family", "numbers"
  description?: string;
  icon?: string; // Icon name or emoji
  
  // Ordering & hierarchy
  sortOrder: number; // For display order
  parentId?: Types.ObjectId; // For nested categories (optional)
  
  // Status
  status: CategoryStatus;
  
  // Statistics (denormalized for performance)
  wordCount: number; // Number of dictionary entries in this category
  mutationVersion: number;
  
  // Timestamps
  createdAt: Date;
  updatedAt: Date;
  
  // Methods
  isActive(): boolean;
}

/**
 * Category schema
 */
const CategorySchema = new Schema<ICategory>(
  {
    name: {
      type: String,
      required: [true, 'Category name is required'],
      trim: true,
      minlength: [2, 'Category name must be at least 2 characters'],
      maxlength: [50, 'Category name must be less than 50 characters'],
    },
    
    slug: {
      type: String,
      required: [true, 'Category slug is required'],
      unique: true,
      lowercase: true,
      trim: true,
      match: [/^[a-z0-9-]+$/, 'Slug can only contain lowercase letters, numbers, and hyphens'],
      index: true,
    },
    
    description: {
      type: String,
      trim: true,
      maxlength: [500, 'Description must be less than 500 characters'],
    },
    
    icon: {
      type: String,
      trim: true,
    },
    
    sortOrder: {
      type: Number,
      default: 0,
      required: true,
      index: true,
    },
    
    parentId: {
      type: Schema.Types.ObjectId,
      ref: 'Category',
      index: true,
    },
    
    status: {
      type: String,
      enum: Object.values(CategoryStatus),
      default: CategoryStatus.ACTIVE,
      required: true,
    },
    
    mutationVersion: { type: Number, default: 0, select: false },
    wordCount: {
      type: Number,
      default: 0,
      min: [0, 'Word count cannot be negative'],
      required: true,
    },
  },
  {
    timestamps: true,
    collection: 'categories',
  }
);

// ============================================================================
// INDEXES
// ============================================================================

// Primary lookups
CategorySchema.index({ status: 1, sortOrder: 1 }); // For listing active categories
CategorySchema.index({ parentId: 1, sortOrder: 1 }); // For nested categories

// ============================================================================
// METHODS
// ============================================================================

/**
 * Check if category is active
 */
CategorySchema.methods.isActive = function(): boolean {
  return this.status === CategoryStatus.ACTIVE;
};

// ============================================================================
// STATIC METHODS
// ============================================================================

/**
 * Get active categories sorted by order
 */
CategorySchema.statics.getActive = async function(): Promise<ICategory[]> {
  return await this.find({ status: CategoryStatus.ACTIVE })
    .sort({ sortOrder: 1, name: 1 })
    .exec();
};

/**
 * Get top-level categories (no parent)
 */
CategorySchema.statics.getTopLevel = async function(): Promise<ICategory[]> {
  return await this.find({
    status: CategoryStatus.ACTIVE,
    parentId: { $exists: false },
  })
    .sort({ sortOrder: 1, name: 1 })
    .exec();
};

/**
 * Get subcategories of a parent
 */
CategorySchema.statics.getSubcategories = async function(
  parentId: Types.ObjectId
): Promise<ICategory[]> {
  return await this.find({
    status: CategoryStatus.ACTIVE,
    parentId,
  })
    .sort({ sortOrder: 1, name: 1 })
    .exec();
};

/**
 * Increment word count
 */
CategorySchema.statics.incrementWordCount = async function(
  categoryId: Types.ObjectId,
  delta: number = 1
): Promise<void> {
  await this.findByIdAndUpdate(categoryId, {
    $inc: { wordCount: delta },
  });
};

/**
 * Recalculate word count (for admin maintenance)
 */
CategorySchema.statics.recalculateWordCount = async function(
  categoryId: Types.ObjectId
): Promise<number> {
  const DictionaryEntry = model('DictionaryEntry');
  
  const count = await DictionaryEntry.countDocuments({
    categoryId,
    status: 'PUBLISHED',
  });
  
  await this.findByIdAndUpdate(categoryId, {
    $set: { wordCount: count },
  });
  
  return count;
};

// ============================================================================
// HOOKS
// ============================================================================

/**
 * Generate slug from name if not provided
 */
CategorySchema.pre('save', function() {
  if (!this.slug && this.name) {
    this.slug = this.name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }
});

/**
 * Prevent circular parent references
 */
CategorySchema.pre('save', async function() {
  if (this.parentId && this.parentId.equals(this._id)) {
    throw new Error('Category cannot be its own parent');
  }
  
  // Check for circular references (optional, more expensive)
  if (this.parentId && this.isModified('parentId')) {
    let current = await (this.constructor as any).findById(this.parentId);
    const visited = new Set([this._id.toString()]);
    
    while (current?.parentId) {
      if (visited.has(current.parentId.toString())) {
        throw new Error('Circular parent reference detected');
      }
      visited.add(current.parentId.toString());
      current = await (this.constructor as any).findById(current.parentId);
    }
  }
});

// ============================================================================
// VIRTUALS
// ============================================================================

/**
 * Get full path for nested categories
 */
CategorySchema.virtual('path').get(async function() {
  const path = [this.name];
  let current = this;
  
  while (current.parentId) {
    const parent = await (this.constructor as any).findById(current.parentId);
    if (!parent) break;
    path.unshift(parent.name);
    current = parent;
  }
  
  return path.join(' > ');
});

// ============================================================================
// EXPORT MODEL
// ============================================================================

export const Category = model<ICategory>('Category', CategorySchema);
