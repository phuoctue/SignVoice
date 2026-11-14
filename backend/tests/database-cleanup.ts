import { MongoClient } from 'mongodb';

export async function cleanupFileDatabases(uri: string, control: string, fileId: string, timeoutMS = 5000): Promise<void> {
  const parsed = new URL(uri);
  const app = parsed.pathname.slice(1);
  if (parsed.protocol !== 'mongodb:' || parsed.hostname !== '127.0.0.1' || parsed.username || parsed.password ||
      [...parsed.searchParams.keys()].some(key => key !== 'replicaSet') || !/^[a-f0-9]{12}$/.test(fileId) ||
      !new RegExp(`^signvoice_test_app_[a-z0-9]{24}_${fileId}$`).test(app) ||
      control !== app.replace('signvoice_test_app_', 'signvoice_test_control_')) {
    throw new Error('Refusing unsafe per-file database cleanup');
  }
  const client = new MongoClient(uri, { serverSelectionTimeoutMS: timeoutMS, connectTimeoutMS: timeoutMS,
    socketTimeoutMS: timeoutMS, timeoutMS, maxPoolSize: 1 });
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([
      (async () => {
        await client.db(app).dropDatabase();
        await client.db(control).dropDatabase();
      })(),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error('Per-file database cleanup timed out')), timeoutMS);
      }),
    ]);
  } finally {
    clearTimeout(timer);
    await client.close(true);
  }
}
