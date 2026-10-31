import dns from 'node:dns';
import mongoose from 'mongoose';
import { env } from './env';

// Ensure DNS resolution succeeds for mongodb+srv
try {
  dns.setServers(['8.8.8.8', '8.8.4.4']);
} catch {
  // Ignore fallback
}

/**
 * Connect to MongoDB using Mongoose
 */
export async function connectDatabase(): Promise<void> {
  try {
    if (process.env.NODE_ENV === 'test' && !/^signvoice_test_[a-z0-9_]+$/i.test(new URL(env.MONGODB_URI).pathname.slice(1))) {
      throw new Error('Refusing to connect tests to a non-test database');
    }
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        await mongoose.connect(env.MONGODB_URI, {
          maxPoolSize: 10,
          // Cold DNS/TLS through a tunnel/VPN can exceed five seconds even
          // when Atlas is reachable. Keep this bounded, below HTTP's 30s budget.
          serverSelectionTimeoutMS: 15000,
          socketTimeoutMS: 45000,
        });
        break;
      } catch (error) {
        // Retry a transient startup selection failure once. Authentication and
        // configuration errors still fail immediately rather than looping.
        if (attempt !== 0 || (error as Error).name !== 'MongooseServerSelectionError') throw error;
        console.warn('MongoDB initial connection timed out; retrying once.');
        await mongoose.disconnect();
        await new Promise(resolve => setTimeout(resolve, 250));
      }
    }

    console.log('✅ MongoDB connected successfully');
    console.log(`   Database: ${mongoose.connection.name}`);
    console.log(`   Host: ${mongoose.connection.host}`);

    // Handle connection events
    mongoose.connection.on('error', (error) => {
      console.error('❌ MongoDB connection error:', error);
    });

    mongoose.connection.on('disconnected', () => {
      console.warn('⚠️  MongoDB disconnected');
    });

    mongoose.connection.on('reconnected', () => {
      console.log('✅ MongoDB reconnected');
    });

  } catch (error) {
    console.error('❌ Failed to connect to MongoDB:', error);
    throw error;
  }
}

/**
 * Disconnect from MongoDB
 */
export async function disconnectDatabase(): Promise<void> {
  try {
    await mongoose.disconnect();
    console.log('✅ MongoDB disconnected');
  } catch (error) {
    console.error('❌ Error disconnecting from MongoDB:', error);
    throw error;
  }
}

/**
 * Check if MongoDB is connected and ready
 */
export function isDatabaseReady(): boolean {
  return mongoose.connection.readyState === 1;
}

/**
 * Get database connection info (safe for logging)
 */
export function getDatabaseInfo() {
  return {
    connected: isDatabaseReady(),
    name: mongoose.connection.name,
    host: mongoose.connection.host,
    readyState: mongoose.connection.readyState,
    // 0 = disconnected, 1 = connected, 2 = connecting, 3 = disconnecting
  };
}
