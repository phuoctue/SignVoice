import { Schema, model, Document, Types } from 'mongoose';

/**
 * Individual message in a conversation
 */
export interface IMessage {
  role: 'USER' | 'ASSISTANT';
  content: string;
  timestamp: Date;
  entryReferences?: Types.ObjectId[]; // Dictionary entries mentioned/suggested
}

/**
 * Conversation status
 */
export enum ConversationStatus {
  ACTIVE = 'ACTIVE',
  ARCHIVED = 'ARCHIVED',
}

/**
 * Conversation document interface
 */
export interface IConversation extends Document {
  _id: Types.ObjectId;
  
  // Relationships
  userId: Types.ObjectId;
  
  // Conversation data
  title?: string; // Optional user-set title
  content?: string;
  direction: 'TEXT' | 'SIGN_TO_SPEECH' | 'SPEECH_TO_TEXT';
  favorite: boolean;
  messages: IMessage[];
  
  // Status
  status: ConversationStatus;
  
  // Metadata
  lastMessageAt: Date;
  
  // Timestamps
  createdAt: Date;
  updatedAt: Date;
  
  // Methods
  addMessage(role: 'USER' | 'ASSISTANT', content: string, entryReferences?: Types.ObjectId[]): Promise<IConversation>;
  getRecentMessages(count: number): IMessage[];
}

/**
 * Conversation schema
 */
const ConversationSchema = new Schema<IConversation>(
  {
    userId: {
      type: Schema.Types.ObjectId,
      ref: 'User',
      required: [true, 'User ID is required'],
      index: true,
    },
    
    content: { type: String, trim: true, maxlength: 10000 },
    direction: { type: String, enum: ['TEXT', 'SIGN_TO_SPEECH', 'SPEECH_TO_TEXT'], default: 'TEXT' },
    favorite: { type: Boolean, default: false },
    title: {
      type: String,
      trim: true,
      maxlength: [200, 'Title must be less than 200 characters'],
    },
    
    messages: {
      type: [{
        role: {
          type: String,
          enum: ['USER', 'ASSISTANT'],
          required: true,
        },
        content: {
          type: String,
          required: true,
          maxlength: [10000, 'Message content must be less than 10000 characters'],
        },
        timestamp: {
          type: Date,
          default: Date.now,
          required: true,
        },
        entryReferences: {
          type: [Schema.Types.ObjectId],
          ref: 'DictionaryEntry',
          default: [],
        },
      }],
      default: [],
      validate: {
        validator: function(arr: IMessage[]) {
          return arr.length <= 1000; // Max 1000 messages per conversation
        },
        message: 'Maximum 1000 messages per conversation',
      },
    },
    
    status: {
      type: String,
      enum: Object.values(ConversationStatus),
      default: ConversationStatus.ACTIVE,
      required: true,
    },
    
    lastMessageAt: {
      type: Date,
      default: Date.now,
      required: true,
      index: true,
    },
  },
  {
    timestamps: true,
    collection: 'conversations',
  }
);

// ============================================================================
// INDEXES
// ============================================================================

// Primary queries
ConversationSchema.index({ userId: 1, status: 1, lastMessageAt: -1 }); // User's conversations
ConversationSchema.index({ userId: 1, createdAt: -1 }); // Chronological

// Cleanup jobs
ConversationSchema.index({ status: 1, lastMessageAt: 1 }); // Old archived conversations

// ============================================================================
// METHODS
// ============================================================================

/**
 * Add a message to the conversation
 */
ConversationSchema.methods.addMessage = async function(
  role: 'USER' | 'ASSISTANT',
  content: string,
  entryReferences?: Types.ObjectId[]
): Promise<IConversation> {
  this.messages.push({
    role,
    content,
    timestamp: new Date(),
    entryReferences: entryReferences || [],
  });
  
  this.lastMessageAt = new Date();
  
  // Auto-generate title from first user message if not set
  if (!this.title && role === 'USER' && this.messages.length === 1) {
    this.title = content.slice(0, 50) + (content.length > 50 ? '...' : '');
  }
  
  return await this.save();
};

/**
 * Get recent messages
 */
ConversationSchema.methods.getRecentMessages = function(count: number = 10): IMessage[] {
  return this.messages.slice(-count);
};

// ============================================================================
// STATIC METHODS
// ============================================================================

/**
 * Get or create active conversation for user
 */
ConversationSchema.statics.getOrCreateForUser = async function(
  userId: Types.ObjectId
): Promise<IConversation> {
  let conversation = await this.findOne({
    userId,
    status: ConversationStatus.ACTIVE,
  }).sort({ lastMessageAt: -1 });
  
  if (!conversation) {
    conversation = await this.create({ userId });
  }
  
  return conversation;
};

/**
 * Get user's conversation history
 */
ConversationSchema.statics.getUserHistory = async function(
  userId: Types.ObjectId,
  options: { limit?: number; skip?: number; includeArchived?: boolean } = {}
): Promise<IConversation[]> {
  const filter: any = { userId };
  
  if (!options.includeArchived) {
    filter.status = ConversationStatus.ACTIVE;
  }
  
  return await this.find(filter)
    .sort({ lastMessageAt: -1 })
    .limit(options.limit || 20)
    .skip(options.skip || 0)
    .select('title status lastMessageAt messages createdAt updatedAt')
    .exec();
};

/**
 * Archive old conversations (maintenance job)
 */
ConversationSchema.statics.archiveOldConversations = async function(
  daysOld: number = 90
): Promise<number> {
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - daysOld);
  
  const result = await this.updateMany(
    {
      status: ConversationStatus.ACTIVE,
      lastMessageAt: { $lt: cutoffDate },
    },
    {
      $set: { status: ConversationStatus.ARCHIVED },
    }
  );
  
  return result.modifiedCount;
};

/**
 * Search conversations by content
 */
ConversationSchema.statics.searchByContent = async function(
  userId: Types.ObjectId,
  searchQuery: string,
  options: { limit?: number } = {}
): Promise<IConversation[]> {
  return await this.find({
    userId,
    status: ConversationStatus.ACTIVE,
    'messages.content': { $regex: searchQuery, $options: 'i' },
  })
    .sort({ lastMessageAt: -1 })
    .limit(options.limit || 10)
    .exec();
};

// ============================================================================
// HOOKS
// ============================================================================

/**
 * Update lastMessageAt when messages are added
 */
ConversationSchema.pre('save', function() {
  if (this.isModified('messages') && this.messages.length > 0) {
    const lastMessage = this.messages[this.messages.length - 1];
    this.lastMessageAt = lastMessage.timestamp;
  }
});

// ============================================================================
// VIRTUALS
// ============================================================================

/**
 * Get message count
 */
ConversationSchema.virtual('messageCount').get(function() {
  return this.messages.length;
});

/**
 * Get summary (first user message)
 */
ConversationSchema.virtual('summary').get(function() {
  const firstUserMessage = this.messages.find(m => m.role === 'USER');
  if (!firstUserMessage) return 'New conversation';
  
  const content = firstUserMessage.content;
  return content.slice(0, 100) + (content.length > 100 ? '...' : '');
});

// ============================================================================
// EXPORT MODEL
// ============================================================================

export const Conversation = model<IConversation>('Conversation', ConversationSchema);
