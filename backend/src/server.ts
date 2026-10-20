import dns from 'node:dns';

// Fix querySrv ECONNREFUSED on local/restricted Wi-Fi networks
try {
  dns.setServers(['8.8.8.8', '8.8.4.4']);
} catch {
  // Fallback to system default if setting custom servers fails
}

import { createApp } from './app';
import { env, validateEnv } from './config/env';
import { connectDatabase, disconnectDatabase } from './config/database';

/**
 * Start the server
 */
async function startServer(): Promise<void> {
  try {
    // Validate environment variables
    console.log('🔍 Validating environment variables...');
    validateEnv();
    console.log('✅ Environment variables validated');

    // Connect to database
    console.log('🔌 Connecting to MongoDB...');
    await connectDatabase();

    // Create Express app
    const app = await createApp();

    // Start HTTP server
    const server = app.listen(env.PORT, () => {
      console.log('');
      console.log('🚀 SignVoice Backend API');
      console.log(`   Environment: ${env.NODE_ENV}`);
      console.log(`   Server: http://localhost:${env.PORT}`);
      console.log(`   Health: http://localhost:${env.PORT}/health/live`);
      console.log('');
      console.log('✅ Server is running');
      console.log('');
    });
    app.locals.attachAiUpgrade?.(server);

    // Graceful shutdown
    const shutdown = async (signal: string) => {
      console.log(`\n⚠️  ${signal} received, shutting down gracefully...`);
      
      server.close(async () => {
        console.log('✅ HTTP server closed');
        
        try {
          await disconnectDatabase();
          console.log('✅ Database disconnected');
          process.exit(0);
        } catch (error) {
          console.error('❌ Error during shutdown:', error);
          process.exit(1);
        }
      });

      // Force shutdown after 10 seconds
      setTimeout(() => {
        console.error('❌ Forced shutdown after timeout');
        process.exit(1);
      }, 10000);
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));

  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Start server if this file is run directly
if (require.main === module) {
  startServer();
}

export { startServer };
