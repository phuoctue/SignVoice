import { Schema, model, Document, Types, Model } from 'mongoose';

/**
 * Action types for audit logging
 */
export enum AuditAction {
  // User actions
  USER_REGISTER = 'USER_REGISTER',
  USER_LOGIN = 'USER_LOGIN',
  USER_LOGOUT = 'USER_LOGOUT',
  USER_UPDATE = 'USER_UPDATE',
  USER_DELETE = 'USER_DELETE',
  USER_SUSPEND = 'USER_SUSPEND',
  USER_RESTORE = 'USER_RESTORE',
  GUEST_CONVERT = 'GUEST_CONVERT',
  
  // Password & auth actions
  PASSWORD_CHANGE = 'PASSWORD_CHANGE',
  PASSWORD_RESET = 'PASSWORD_RESET',
  TOKEN_REFRESH = 'TOKEN_REFRESH',
  SESSION_REVOKE = 'SESSION_REVOKE',
  
  // Dictionary actions
  ENTRY_CREATE = 'ENTRY_CREATE',
  ENTRY_UPDATE = 'ENTRY_UPDATE',
  ENTRY_DELETE = 'ENTRY_DELETE',
  ENTRY_PUBLISH = 'ENTRY_PUBLISH',
  ENTRY_ARCHIVE = 'ENTRY_ARCHIVE',
  ENTRY_VIEW = 'ENTRY_VIEW',
  
  // Category actions
  CATEGORY_CREATE = 'CATEGORY_CREATE',
  CATEGORY_UPDATE = 'CATEGORY_UPDATE',
  CATEGORY_DELETE = 'CATEGORY_DELETE',
  
  // User interaction actions
  FAVORITE_ADD = 'FAVORITE_ADD',
  FAVORITE_REMOVE = 'FAVORITE_REMOVE',
  
  // Admin actions
  ROLE_CHANGE = 'ROLE_CHANGE',
  SETTINGS_UPDATE = 'SETTINGS_UPDATE',
  
  // System actions
  SYSTEM_ERROR = 'SYSTEM_ERROR',
  SECURITY_ALERT = 'SECURITY_ALERT',
}

/**
 * Audit severity levels
 */
export enum AuditSeverity {
  INFO = 'INFO',
  WARNING = 'WARNING',
  ERROR = 'ERROR',
  CRITICAL = 'CRITICAL',
}

/**
 * Audit log document interface
 */
export interface IAuditLog extends Document {
  _id: Types.ObjectId;
  
  // Who
  userId?: Types.ObjectId; // Can be null for system actions
  actorRole?: string; // Role at time of action
  
  // What
  action: AuditAction;
  severity: AuditSeverity;
  
  // Context
  resourceType?: string; // e.g., 'User', 'DictionaryEntry', 'Category'
  resourceId?: Types.ObjectId;
  details?: Record<string, any>; // Additional context (JSON)
  
  // Where
  ipAddress?: string;
  userAgent?: string;
  
  // Result
  success: boolean;
  errorMessage?: string;
  
  // Timestamps
  timestamp: Date;
  createdAt: Date;
}

/**
 * Audit log model interface with static methods
 */
export interface IAuditLogModel extends Model<IAuditLog> {
  log(params: {
    userId?: Types.ObjectId;
    actorRole?: string;
    action: AuditAction;
    severity?: AuditSeverity;
    resourceType?: string;
    resourceId?: Types.ObjectId;
    details?: Record<string, any>;
    ipAddress?: string;
    userAgent?: string;
    success?: boolean;
    errorMessage?: string;
  }): Promise<IAuditLog>;
  getUserActivity(userId: Types.ObjectId, options?: { limit?: number; skip?: number }): Promise<IAuditLog[]>;
  getResourceHistory(resourceType: string, resourceId: Types.ObjectId, options?: { limit?: number }): Promise<IAuditLog[]>;
  getFailedActions(options?: { since?: Date; limit?: number; ipAddress?: string; userId?: Types.ObjectId }): Promise<IAuditLog[]>;
  getSecurityAlerts(options?: { since?: Date; limit?: number }): Promise<IAuditLog[]>;
  getActionStats(options?: { since?: Date; until?: Date }): Promise<Array<{ _id: AuditAction; count: number }>>;
}

/**
 * Audit log schema
 */
const AuditLogSchema = new Schema<IAuditLog>(
  {
    userId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      index: true,
    },
    
    actorRole: {
      type: String,
    },
    
    action: {
      type: String,
      enum: Object.values(AuditAction),
      required: [true, 'Action is required'],
      index: true,
    },
    
    severity: {
      type: String,
      enum: Object.values(AuditSeverity),
      default: AuditSeverity.INFO,
      required: true,
      index: true,
    },
    
    resourceType: {
      type: String,
      index: true,
    },
    
    resourceId: {
      type: Schema.Types.ObjectId,
      index: true,
    },
    
    details: {
      type: Schema.Types.Mixed,
    },
    
    ipAddress: {
      type: String,
      maxlength: 45, // IPv6
    },
    
    userAgent: {
      type: String,
      maxlength: 500,
    },
    
    success: {
      type: Boolean,
      default: true,
      required: true,
    },
    
    errorMessage: {
      type: String,
      maxlength: 1000,
    },
    
    timestamp: {
      type: Date,
      default: Date.now,
      required: true,
    },
  },
  {
    timestamps: { createdAt: true, updatedAt: false }, // Only createdAt
    collection: 'audit_logs',
  }
);

// ============================================================================
// INDEXES
// ============================================================================

// Primary queries
AuditLogSchema.index({ timestamp: -1 }); // Chronological queries
AuditLogSchema.index({ userId: 1, timestamp: -1 }); // User activity
AuditLogSchema.index({ action: 1, timestamp: -1 }); // Action filtering
AuditLogSchema.index({ resourceType: 1, resourceId: 1, timestamp: -1 }); // Resource history
AuditLogSchema.index({ severity: 1, timestamp: -1 }); // Severity filtering

// Security & monitoring
AuditLogSchema.index({ ipAddress: 1, timestamp: -1 }); // IP tracking
AuditLogSchema.index({ success: 1, severity: 1, timestamp: -1 }); // Failed actions

// TTL index - auto-delete logs older than 1 year
AuditLogSchema.index(
  { timestamp: 1 },
  { expireAfterSeconds: 60 * 60 * 24 * 365 }
);

// ============================================================================
// STATIC METHODS
// ============================================================================

/**
 * Log an action
 */
AuditLogSchema.statics.log = async function(params: {
  userId?: Types.ObjectId;
  actorRole?: string;
  action: AuditAction;
  severity?: AuditSeverity;
  resourceType?: string;
  resourceId?: Types.ObjectId;
  details?: Record<string, any>;
  ipAddress?: string;
  userAgent?: string;
  success?: boolean;
  errorMessage?: string;
}): Promise<IAuditLog> {
  return await this.create({
    userId: params.userId,
    actorRole: params.actorRole,
    action: params.action,
    severity: params.severity || AuditSeverity.INFO,
    resourceType: params.resourceType,
    resourceId: params.resourceId,
    details: params.details,
    ipAddress: params.ipAddress,
    userAgent: params.userAgent,
    success: params.success !== false, // Default true
    errorMessage: params.errorMessage,
    timestamp: new Date(),
  });
};

/**
 * Get user activity log
 */
AuditLogSchema.statics.getUserActivity = async function(
  userId: Types.ObjectId,
  options: { limit?: number; skip?: number } = {}
): Promise<IAuditLog[]> {
  return await this.find({ userId })
    .sort({ timestamp: -1 })
    .limit(options.limit || 50)
    .skip(options.skip || 0)
    .exec();
};

/**
 * Get resource history
 */
AuditLogSchema.statics.getResourceHistory = async function(
  resourceType: string,
  resourceId: Types.ObjectId,
  options: { limit?: number } = {}
): Promise<IAuditLog[]> {
  return await this.find({ resourceType, resourceId })
    .sort({ timestamp: -1 })
    .limit(options.limit || 20)
    .populate('userId', 'displayName email')
    .exec();
};

/**
 * Get failed actions (security monitoring)
 */
AuditLogSchema.statics.getFailedActions = async function(
  options: {
    since?: Date;
    limit?: number;
    ipAddress?: string;
    userId?: Types.ObjectId;
  } = {}
): Promise<IAuditLog[]> {
  const filter: any = { success: false };
  
  if (options.since) {
    filter.timestamp = { $gte: options.since };
  }
  
  if (options.ipAddress) {
    filter.ipAddress = options.ipAddress;
  }
  
  if (options.userId) {
    filter.userId = options.userId;
  }
  
  return await this.find(filter)
    .sort({ timestamp: -1 })
    .limit(options.limit || 100)
    .exec();
};

/**
 * Get security alerts
 */
AuditLogSchema.statics.getSecurityAlerts = async function(
  options: { since?: Date; limit?: number } = {}
): Promise<IAuditLog[]> {
  const filter: any = {
    $or: [
      { severity: AuditSeverity.CRITICAL },
      { severity: AuditSeverity.ERROR },
      { action: AuditAction.SECURITY_ALERT },
    ],
  };
  
  if (options.since) {
    filter.timestamp = { $gte: options.since };
  }
  
  return await this.find(filter)
    .sort({ timestamp: -1 })
    .limit(options.limit || 50)
    .exec();
};

/**
 * Get action statistics
 */
AuditLogSchema.statics.getActionStats = async function(
  options: { since?: Date; until?: Date } = {}
): Promise<Array<{ _id: AuditAction; count: number }>> {
  const matchStage: any = {};
  
  if (options.since || options.until) {
    matchStage.timestamp = {};
    if (options.since) matchStage.timestamp.$gte = options.since;
    if (options.until) matchStage.timestamp.$lte = options.until;
  }
  
  return await this.aggregate([
    ...(Object.keys(matchStage).length > 0 ? [{ $match: matchStage }] : []),
    {
      $group: {
        _id: '$action',
        count: { $sum: 1 },
      },
    },
    { $sort: { count: -1 } },
  ]);
};

// ============================================================================
// HOOKS
// ============================================================================

/**
 * Sanitize sensitive data before saving
 */
AuditLogSchema.pre('save', function() {
  // Remove sensitive fields from details
  if (this.details) {
    const sensitiveFields = ['password', 'passwordHash', 'token', 'accessToken', 'refreshToken'];
    
    sensitiveFields.forEach(field => {
      if (this.details && field in this.details) {
        this.details[field] = '[REDACTED]';
      }
    });
  }
});

// ============================================================================
// EXPORT MODEL
// ============================================================================

export const AuditLog = model<IAuditLog, IAuditLogModel>('AuditLog', AuditLogSchema);
