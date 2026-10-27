import {readFile, stat} from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(__dirname, '../../../.runtime/sign-library-media');
const previews = new Map<string, string>();
const pending = new Map<string, Promise<string>>();
let retained = 0;
const budget = 4 * 1024 * 1024;

/** Inline only bounded, existing generated JPEGs from already authorized DTOs.
 * A topic/list response can display its first cards without another tunnel RTT.
 * Original full-resolution media URLs and publication checks remain in place.
 */
async function preview(value: unknown, directory: string): Promise<string> {
  if (typeof value !== 'string') return '';
  let name: string;
  try {
    const uri = new URL(value, 'http://localhost');
    if (uri.search || uri.hash || !/^\/sign-media\/[a-f0-9]{64}-[1-5]\.jpg$/.test(uri.pathname)) return '';
    name = path.basename(uri.pathname);
  } catch { return ''; }
  const filename = path.join(directory, name);
  const existing = previews.get(filename);
  if (existing) {
    previews.delete(filename);
    previews.set(filename, existing);
    return existing;
  }
  const active = pending.get(filename);
  if (active) return active;
  const request = (async () => {
    try {
      if ((await stat(filename)).size > 96 * 1024) return '';
      const bytes = await readFile(filename);
      if (bytes.length > 96 * 1024 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) return '';
      const result = `data:image/jpeg;base64,${bytes.toString('base64')}`;
      while (previews.size && retained + result.length > budget) {
        const first = previews.keys().next().value!;
        retained -= previews.get(first)!.length;
        previews.delete(first);
      }
      previews.set(filename, result);
      retained += result.length;
      return result;
    } catch { return ''; } // Optional preview must never break dictionary access.
  })();
  pending.set(filename, request);
  try { return await request; } finally { pending.delete(filename); }
}

export async function addInlineThumbnails<T extends Record<string, unknown>>(
  entries: T[], field: 'thumbnailUrl' | 'imageUrl' = 'thumbnailUrl', directory = root,
): Promise<T[]> {
  return Promise.all(entries.map(async (entry, index) => {
    const image = index < 20 ? await preview(entry[field], directory) : '';
    return image ? {...entry, [field === 'imageUrl' ? 'imageDataUrl' : 'thumbnailDataUrl']: image} : entry;
  }));
}
