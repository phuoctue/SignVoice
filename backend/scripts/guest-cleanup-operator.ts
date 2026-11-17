import {mongo} from 'mongoose';
import {isIP} from 'node:net';

/** Parse without connecting; never expose driver errors, which can echo credentials. */
export function assertOperatorTarget(uri: string, allowCopy?: string, requireAuth = false, testOnly = false) {
  try {
    if (!uri || uri.length > 8192 || !uri.startsWith('mongodb://') && !uri.startsWith('mongodb+srv://')) throw new Error();
    const client = new mongo.MongoClient(uri), options = client.options;
    const local = uri.startsWith('mongodb://') && !!options.hosts.length && options.hosts.every(({host}) =>
      host === 'localhost' || host === '::1' || !!host && isIP(host) === 4 && host.split('.')[0] === '127');
    if (options.proxyHost || !options.dbName || options.dbName === 'test' || ['admin', 'config', 'local'].includes(options.dbName)) throw new Error();
    if (!local && !requireAuth && (!allowCopy || !/^(?:signvoice_)?copy_[a-z0-9_-]+$/i.test(allowCopy) || options.dbName !== allowCopy)) throw new Error();
    if (allowCopy && options.dbName !== allowCopy) throw new Error();
    const test = testOnly && process.env.NODE_ENV === 'test' && local && /^signvoice_test_[a-z0-9_]+$/i.test(options.dbName);
    if ((requireAuth || !local) && !options.credentials?.username && !test) throw new Error();
    return {database: options.dbName, local};
  } catch {throw new Error('Explicit safe target and authenticated operator required; remote reads require --allow-copy matching a copy_* database');}
}

export async function readOperatorUri() {
  // stdin can be fed by an OS secret prompt; credentials never enter argv, env files or logs.
  if (process.stdin.isTTY) throw new Error('Provide the DB URI on stdin from a hidden secret prompt');
  let uri = '';
  for await (const chunk of process.stdin) {
    uri += String(chunk);
    if (uri.length > 8192) throw new Error('Invalid operator input');
  }
  return uri.trim();
}
export async function operatorDatabase(uri: string, allowCopy?: string, mutation = true) {
  const target = assertOperatorTarget(uri, allowCopy, mutation);
  const client = new mongo.MongoClient(uri, {serverSelectionTimeoutMS: 5000, connectTimeoutMS: 5000, timeoutMS: 30000});
  try {
    await client.connect();
    const db = client.db(target.database);
    if (mutation || !target.local) {
      const status = await db.command({connectionStatus: 1});
      if (!status.authInfo?.authenticatedUsers?.length) throw new Error('Operator authentication required');
    }
    return {client, db};
  } catch {await client.close(); throw new Error('Operator database connection/authentication failed');}
}
export async function serverTime(db: mongo.Db) {
  const time = (await db.command({hello: 1})).localTime;
  if (!(time instanceof Date) || !Number.isFinite(+time)) throw new Error('Database server time unavailable');
  return time;
}
