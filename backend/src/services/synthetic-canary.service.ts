import {Types} from 'mongoose';
import {open} from 'node:fs/promises';
import path from 'node:path';
import {z} from 'zod';

export interface SyntheticCanaryRegistry {
  contains: (userId: Types.ObjectId) => Promise<boolean | undefined>;
  hasActiveGuests: boolean;
  cleanupExemptUntil?: number;
}
/** Unconfigured runs grant no cleanup exemption. */
export const syntheticCanaryRegistry: SyntheticCanaryRegistry = {
  hasActiveGuests: false,
  contains: async (userId: Types.ObjectId): Promise<boolean | undefined> => {void userId; return false;},
};

const entries = z.array(z.object({alias: z.string().trim().min(1), kind: z.enum(['guest', 'permanent']),
  userId: z.string().regex(/^[a-f0-9]{24}$/i), status: z.string().min(1)}));
// The K+S envelope's metadata and extra entry fields are discarded, never logged.
const registrySchema = z.union([entries, z.object({accounts: entries}).transform(value => value.accounts)]);
const maxRegistryBytes = 64 * 1024;

/** A bounded, per-run snapshot; invalid configuration must abort before any deletion. */
export async function loadSyntheticCanaryRegistry(file: string | undefined): Promise<SyntheticCanaryRegistry> {
  if (file === undefined) return syntheticCanaryRegistry;
  try {
    if (!path.isAbsolute(file)) throw new Error();
    const handle = await open(file, 'r');
    try {
      const stat = await handle.stat();
      if (!stat.isFile() || stat.size > maxRegistryBytes) throw new Error();
      // Bound the read too: the file may grow after stat().
      const bytes = Buffer.alloc(maxRegistryBytes + 1);
      let size = 0;
      while (size < bytes.length) {
        const {bytesRead} = await handle.read(bytes, size, bytes.length - size, null);
        if (!bytesRead) break;
        size += bytesRead;
      }
      if (size > maxRegistryBytes) throw new Error();
      const parsed = registrySchema.parse(JSON.parse(bytes.subarray(0, size).toString('utf8')));
      const ids = new Set(parsed.filter(entry => entry.kind === 'guest' && entry.status === 'active').map(entry => entry.userId.toLowerCase()));
      return {hasActiveGuests: ids.size > 0, contains: async userId => ids.has(String(userId))};
    } finally {await handle.close();}
  } catch {throw new Error('Synthetic registry unavailable or invalid');}
}

export async function isSyntheticCanary(userId: Types.ObjectId, registry = syntheticCanaryRegistry): Promise<boolean> {
  try { return await registry.contains(userId) === true; }
  catch { return false; }
}
