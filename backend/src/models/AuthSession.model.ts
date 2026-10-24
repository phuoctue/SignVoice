import { Schema, model, Document, Types, Model } from 'mongoose';

/**
 * Session types
 */
export enum SessionType {
  ACCESS = 'ACCESS',
  REFRESH = 'REFRESH',
}

/**
 * Session status
 */
export enum SessionStatus {
  ACTIVE = 'ACTIVE',
  REVOKED = 'REVOKED', // Manually revoked (logout)
  EXPIRED = 'EXPIRED', // Expired naturally
}

/**
 * Auth session document interface
 */
export interface IAuthSession extends Document {
  _id: Types.ObjectId;
  
  // Relationships
  userId: Types.ObjectId;
  sessionFamily?: string;
  passwordVersion: number;
  
  // Token data
  sessionType: SessionType;
  tokenHash: string; // SHA-256 hash of the JWT
  
  // Session metadata
  deviceInfo?: string; // User agent
  ipAddress?: string;
  location?: string; // Geo location (optional)
  
  // Status
  status: SessionStatus;
  
  // Timestamps
  expiresAt: Date;
  lastUsedAt: Date;
  revokedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
  
  // Methods
  isValid(): boolean;
  revoke(): Promise<IAuthSession>;
}

/**
 * Auth session model interface with static methods
 */
export interface IAuthSessionModel extends Model<IAuthSession> {
  revokeAllForUser(userId: Types.ObjectId, exceptTokenHash?: string): Promise<number>;
  cleanupExpired(): Promise<number>;
  getActiveSessionsForUser(userId: Types.ObjectId): Promise<IAuthSession[]>;
}

/**
 * Auth session schema
 */
const AuthSessionSchema = new Schema<IAuthSession>(
  {
    userId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'User ID is required'],
      index: true,
    },
    
    sessionType: {
      type: String,
      enum: Object.values(SessionType),
      required: [true, 'Session type is required'],
    },
    sessionFamily: { type: String, index: true },
    passwordVersion: { type: Number, default: 0 },
    
    tokenHash: {
      type: String,
      required: [true, 'Token hash is required'],
      unique: true,
      index: true,
    },
    
    deviceInfo: {
      type: String,
      maxlength: 500,
    },
    
    ipAddress: {
      type: String,
      maxlength: 45, // IPv6 max length
    },
    
    location: {
      type: String,
      maxlength: 100,
    },
    
    status: {
      type: String,
      enum: Object.values(SessionStatus),
      default: SessionStatus.ACTIVE,
      required: true,
    },
    
    expiresAt: {
      type: Date,
      required: [true, 'Expiration date is required'],
      index: true, // For cleanup jobs
    },
    
    lastUsedAt: {
      type: Date,
      default: Date.now,
      required: true,
    },
    
    revokedAt: {
      type: Date,
    },
  },
  {
    timestamps: true,
    collection: 'auth_sessions',
  }
);

// ============================================================================
// INDEXES
// ============================================================================

// Primary queries
AuthSessionSchema.index({ userId: 1, status: 1 });
AuthSessionSchema.index({ userId: 1, sessionType: 1, status: 1 });

// Cleanup jobs
AuthSessionSchema.index({ status: 1, expiresAt: 1 });
AuthSessionSchema.index({ createdAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 90 }); // TTL: 90 days

// Admin queries
AuthSessionSchema.index({ ipAddress: 1, createdAt: -1 });

// ============================================================================
// METHODS
// ============================================================================

/**
 * Check if session is currently valid
 */
AuthSessionSchema.methods.isValid = function(): boolean {
  return (
    this.status === SessionStatus.ACTIVE &&
    this.expiresAt > new Date()
  );
};

/**
 * Revoke this session
 */
AuthSessionSchema.methods.revoke = async function(): Promise<IAuthSession> {
  this.status = SessionStatus.REVOKED;
  this.revokedAt = new Date();
  return await this.save();
};

// ============================================================================
// STATIC METHODS
// ============================================================================

/**
 * Revoke all sessions for a user
 */
AuthSessionSchema.statics.revokeAllForUser = async function(
  userId: Types.ObjectId,
  exceptTokenHash?: string
): Promise<number> {
  const query: any = {
    userId,
    status: SessionStatus.ACTIVE,
  };
  
  if (exceptTokenHash) {
    query.tokenHash = { $ne: exceptTokenHash };
  }
  
  const result = await this.updateMany(
    query,
    {
      $set: {
        status: SessionStatus.REVOKED,
        revokedAt: new Date(),
      },
    }
  );
  
  return result.modifiedCount;
};

/**
 * Clean up expired sessions
 */
AuthSessionSchema.statics.cleanupExpired = async function(): Promise<number> {
  const result = await this.updateMany(
    {
      status: SessionStatus.ACTIVE,
      expiresAt: { $lt: new Date() },
    },
    {
      $set: {
        status: SessionStatus.EXPIRED,
      },
    }
  );
  
  return result.modifiedCount;
};

/**
 * Get active sessions for a user
 */
AuthSessionSchema.statics.getActiveSessionsForUser = async function(
  userId: Types.ObjectId
): Promise<IAuthSession[]> {
  return await this.find({
    userId,
    status: SessionStatus.ACTIVE,
    expiresAt: { $gt: new Date() },
  })
    .sort({ lastUsedAt: -1 })
    .exec();
};

// ============================================================================
// HOOKS
// ============================================================================

/**
 * Update lastUsedAt on each access
 */
AuthSessionSchema.pre('save', function() {
  if (this.isNew || this.isModified('status')) {
    // Only update lastUsedAt if session is being used (not just status change)
    if (this.isNew && this.status === SessionStatus.ACTIVE) {
      this.lastUsedAt = new Date();
    }
  }
});

// ============================================================================
// EXPORT MODEL
// ============================================================================

export const AuthSession = model<IAuthSession, IAuthSessionModel>('AuthSession', AuthSessionSchema);
