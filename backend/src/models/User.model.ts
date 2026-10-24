import { Schema, model, Document, Types } from 'mongoose';

/**
 * User roles in the system
 * - USER: Regular user (default)
 * - STAFF: Staff members (can moderate content)
 * - ADMIN: Administrators (full access)
 */
export enum UserRole {
  USER = 'USER',
  STAFF = 'STAFF',
  ADMIN = 'ADMIN',
}

/**
 * Account types
 * - LOCAL: Email/password authentication
 * - GOOGLE: Google OAuth
 * - FACEBOOK: Facebook OAuth
 * - GUEST: Temporary guest account
 */
export enum AccountType {
  LOCAL = 'LOCAL',
  GOOGLE = 'GOOGLE',
  FACEBOOK = 'FACEBOOK',
  GUEST = 'GUEST',
}

/**
 * Account status
 * - ACTIVE: Normal active account
 * - SUSPENDED: Temporarily suspended (by admin)
 * - DELETED: Soft-deleted account
 */
export enum AccountStatus {
  ACTIVE = 'ACTIVE',
  SUSPENDED = 'SUSPENDED',
  DELETED = 'DELETED',
}

/**
 * OAuth provider data
 */
export interface IOAuthProvider {
  providerId: string; // Google/Facebook user ID
  email?: string;
  displayName?: string;
  photoUrl?: string;
}

/**
 * User document interface
 */
export interface IUser extends Document {
  _id: Types.ObjectId;
  
  // Basic info
  email?: string; // Optional for GUEST accounts
  displayName: string;
  avatarUrl?: string;
  
  // Authentication
  accountType: AccountType;
  passwordHash?: string; // Only for LOCAL accounts
  passwordVersion: number;
  dataVersion: number;
  passwordResetTokenHash?: string;
  passwordResetExpiresAt?: Date;
  passwordResetRequestedAt?: Date;
  googleProvider?: IOAuthProvider;
  facebookProvider?: IOAuthProvider;
  
  // Authorization
  role: UserRole;
  customRoleId?: Types.ObjectId;
  status: AccountStatus;
  
  // Guest account handling
  isGuest: boolean;
  guestConvertedAt?: Date; // When guest → permanent account
  guestTrialId?: Types.ObjectId;
  
  // Tracking
  lastLoginAt?: Date;
  lastLoginIp?: string;
  suspensionReason?: string;
  createdAt: Date;
  updatedAt: Date;
  
  // Methods
  isActive(): boolean;
  canConvertFromGuest(): boolean;
}

/**
 * User schema
 */
const UserSchema = new Schema<IUser>(
  {
    email: {
      type: String,
      lowercase: true,
      trim: true,
      // The unique sparse index is declared once below (no implicit nonunique index).
      validate: {
        validator: function(v: string) {
          if (!v) return true; // Allow empty for guests
          return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
        },
        message: 'Invalid email format',
      },
    },
    
    displayName: {
      type: String,
      required: [true, 'Display name is required'],
      trim: true,
      minlength: [2, 'Display name must be at least 2 characters'],
      maxlength: [50, 'Display name must be less than 50 characters'],
    },
    
    avatarUrl: {
      type: String,
      trim: true,
    },
    
    accountType: {
      type: String,
      enum: Object.values(AccountType),
      required: true,
      default: AccountType.LOCAL,
    },
    
    passwordHash: {
      type: String,
      select: false, // Never include in queries by default
    },
    passwordVersion: { type: Number, default: 0, select: true },
    dataVersion: { type: Number, default: 0, select: false },
    customRoleId: { type: Schema.Types.ObjectId, ref: 'Role', index: true },
    passwordResetTokenHash: { type: String, select: false },
    passwordResetExpiresAt: { type: Date, select: false },
    passwordResetRequestedAt: { type: Date, select: false },
    
    googleProvider: {
      providerId: String,
      email: String,
      displayName: String,
      photoUrl: String,
    },
    
    facebookProvider: {
      providerId: String,
      email: String,
      displayName: String,
      photoUrl: String,
    },
    
    role: {
      type: String,
      enum: Object.values(UserRole),
      default: UserRole.USER,
      required: true,
    },
    
    status: {
      type: String,
      enum: Object.values(AccountStatus),
      default: AccountStatus.ACTIVE,
      required: true,
    },
    
    isGuest: {
      type: Boolean,
      default: false,
      required: true,
    },
    
    guestConvertedAt: {
      type: Date,
    },
    guestTrialId: {type: Schema.Types.ObjectId, ref: 'GuestTrial', select: false},
    
    lastLoginAt: {
      type: Date,
    },
    
    lastLoginIp: {
      type: String,
    },
    
    suspensionReason: {
      type: String,
    },
  },
  {
    timestamps: true, // Adds createdAt, updatedAt
    collection: 'users',
  }
);

// ============================================================================
// INDEXES
// ============================================================================

// Unique sparse index for email (allows multiple nulls for guests)
// Use a distinct name so legacy nonunique email_1 indexes can coexist.
UserSchema.index({ email: 1 }, { name: 'oauth_email_unique', unique: true, sparse: true });
UserSchema.index({ passwordResetTokenHash: 1 }, { sparse: true });

// OAuth provider IDs
UserSchema.index({ 'googleProvider.providerId': 1 }, { name: 'oauth_google_subject_unique', unique: true, sparse: true });
UserSchema.index({ 'facebookProvider.providerId': 1 }, { name: 'oauth_facebook_subject_unique', unique: true, sparse: true });

// Query optimization
UserSchema.index({ accountType: 1, status: 1 });
UserSchema.index({ isGuest: 1, createdAt: 1 }); // For guest cleanup jobs
UserSchema.index({ role: 1 });
UserSchema.index({ lastLoginAt: -1 }); // For admin dashboard

// ============================================================================
// METHODS
// ============================================================================

/**
 * Check if user account is active
 */
UserSchema.methods.isActive = function(): boolean {
  return this.status === AccountStatus.ACTIVE;
};

/**
 * Check if guest account can be converted to permanent
 */
UserSchema.methods.canConvertFromGuest = function(): boolean {
  return this.isGuest && this.status === AccountStatus.ACTIVE && !this.guestConvertedAt;
};

// ============================================================================
// VIRTUALS
// ============================================================================

/**
 * Get user's primary identifier for display
 */
UserSchema.virtual('identifier').get(function() {
  return this.email || this.displayName || `Guest-${this._id.toString().slice(-6)}`;
});

// ============================================================================
// HOOKS
// ============================================================================

/**
 * Pre-save validation
 */
UserSchema.pre('save', function() {
  // LOCAL accounts must have email and password
  if (this.accountType === AccountType.LOCAL && !this.isGuest) {
    if (!this.email) {
      throw new Error('Email is required for LOCAL accounts');
    }
    if (!this.passwordHash && this.isNew) {
      throw new Error('Password is required for LOCAL accounts');
    }
  }
  
  // GOOGLE accounts must have Google provider
  if (this.accountType === AccountType.GOOGLE && !this.googleProvider?.providerId) {
    throw new Error('Google provider ID is required for GOOGLE accounts');
  }
  
  // FACEBOOK accounts must have Facebook provider
  if (this.accountType === AccountType.FACEBOOK && !this.facebookProvider?.providerId) {
    throw new Error('Facebook provider ID is required for FACEBOOK accounts');
  }
  
  // GUEST accounts should have isGuest = true
  if (this.accountType === AccountType.GUEST) {
    this.isGuest = true;
  }
  
  // If converting from guest, set conversion timestamp
  if (this.isModified('isGuest') && !this.isGuest && this.accountType !== AccountType.GUEST) {
    this.guestConvertedAt = new Date();
  }
});

// ============================================================================
// EXPORT MODEL
// ============================================================================

export const User = model<IUser>('User', UserSchema);
