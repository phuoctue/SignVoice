import { Schema, model, Document, Types } from 'mongoose';

/**
 * Theme preferences
 */
export enum Theme {
  LIGHT = 'LIGHT',
  DARK = 'DARK',
  SYSTEM = 'SYSTEM',
}

/**
 * Notification preferences
 */
export interface INotificationPreferences {
  newWords: boolean; // Notify when new words added
  favorites: boolean; // Notify about favorited words
  updates: boolean; // App updates & announcements
}

/**
 * User settings document interface
 */
export interface IUserSettings extends Document {
  _id: Types.ObjectId;
  
  // Relationships
  userId: Types.ObjectId;
  
  // Appearance
  theme: Theme;
  language: string;
  fontSize: number; // 12-24 range
  highContrast: boolean;
  speechSpeed: number;
  speechPitch: number;
  autoSpeak: boolean;
  avatarColor: number;
  
  // Notifications
  notificationsEnabled: boolean;
  notificationPreferences: INotificationPreferences;
  studyReminder: {enabled: boolean; hour: number; minute: number; weekdays: number[]; timezone: string};
  
  // Privacy
  shareUsageData: boolean;
  learningGoals: { newWords: number; reviewWords: number };
  
  // Timestamps
  createdAt: Date;
  updatedAt: Date;
}

/**
 * User settings schema
 */
const UserSettingsSchema = new Schema<IUserSettings>(
  {
    userId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'User ID is required'],
      unique: true, // One settings doc per user
      index: true,
    },
    
    language: {type: String, enum: ['vi','en'], default: 'vi'},
    theme: {
      type: String,
      enum: Object.values(Theme),
      default: Theme.SYSTEM,
      required: true,
    },
    
    fontSize: {
      type: Number,
      default: 16,
      min: [12, 'Font size must be at least 12'],
      max: [24, 'Font size must be at most 24'],
      required: true,
    },
    
    highContrast: { type: Boolean, default: false },
    speechSpeed: { type: Number, min: 0.5, max: 2, default: 1 },
    speechPitch: { type: Number, min: 0.5, max: 2, default: 1 },
    autoSpeak: { type: Boolean, default: false },
    avatarColor: { type: Number, min: 0, max: 3, default: 0 },
    notificationsEnabled: {
      type: Boolean,
      default: true,
      required: true,
    },
    studyReminder: {
      enabled: {type: Boolean, default: false},
      hour: {type: Number, min: 0, max: 23, default: 19},
      minute: {type: Number, min: 0, max: 59, default: 0},
      weekdays: {type: [Number], default: [1, 2, 3, 4, 5, 6, 7]},
      timezone: {type: String, default: 'Asia/Ho_Chi_Minh'},
    },
    
    notificationPreferences: {
      newWords: {
        type: Boolean,
        default: true,
      },
      favorites: {
        type: Boolean,
        default: true,
      },
      updates: {
        type: Boolean,
        default: true,
      },
    },
    
    shareUsageData: {
      type: Boolean,
      default: false,
      required: true,
    },
    learningGoals: {
      newWords: { type: Number, default: 5, min: 1, max: 100, validate: Number.isInteger },
      reviewWords: { type: Number, default: 10, min: 1, max: 200, validate: Number.isInteger },
    },
  },
  {
    timestamps: true,
    collection: 'user_settings',
  }
);

// ============================================================================
// INDEXES
// ============================================================================

// Primary lookup

// ============================================================================
// STATIC METHODS
// ============================================================================

/**
 * Get or create default settings for a user
 */
UserSettingsSchema.statics.getOrCreateForUser = async function(
  userId: Types.ObjectId
): Promise<IUserSettings> {
  let settings = await this.findOne({ userId });
  
  if (!settings) {
    settings = await this.create({ userId });
  }
  
  return settings;
};

/**
 * Update user settings (partial update)
 */
UserSettingsSchema.statics.updateForUser = async function(
  userId: Types.ObjectId,
  updates: Partial<IUserSettings>
): Promise<IUserSettings | null> {
  return await this.findOneAndUpdate(
    { userId },
    { $set: updates },
    { new: true, runValidators: true }
  );
};

// ============================================================================
// HOOKS
// ============================================================================

/**
 * Validate font size range
 */
UserSettingsSchema.pre('save', function() {
  if (this.fontSize < 12 || this.fontSize > 24) {
    throw new Error('Font size must be between 12 and 24');
  }
});

// ============================================================================
// EXPORT MODEL
// ============================================================================

export const UserSettings = model<IUserSettings>('UserSettings', UserSettingsSchema);
