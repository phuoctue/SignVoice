/** Deterministic dictionary lookup, not a sign-language grammar translator. */
export interface SignMediaEntry {
  _id: unknown;
  word: string;
  videoUrl?: string;
  thumbnailUrl?: string;
  imageUrls?: string[];
  notes?: string;
}

const key = (value: string) => value.normalize('NFC').toLocaleLowerCase('vi').trim().replace(/\s+/gu, ' ');
const safeUrl = (value?: string) => {
  if (!value) return undefined;
  try { const url = new URL(value); return ['http:', 'https:'].includes(url.protocol) ? url.href : undefined; }
  catch { return undefined; }
};

export function composeSignSequence(text: string, entries: SignMediaEntry[]) {
  const dictionary = new Map<string, SignMediaEntry[]>();
  let maxWords = 1;
  for (const entry of entries) {
    const normalized = key(entry.word);
    if (!normalized) continue;
    dictionary.set(normalized, [...(dictionary.get(normalized) || []), entry]);
    maxWords = Math.max(maxWords, normalized.split(' ').length);
  }
  // Preserve original offsets/spelling. Punctuation is a hard phrase boundary.
  const tokens = [...text.matchAll(/[\p{L}\p{M}\p{N}]+|[^\s\p{L}\p{M}\p{N}]+/gu)];
  const segments: Record<string, unknown>[] = [];
  for (let i = 0; i < tokens.length;) {
    const token = tokens[i];
    if (!/^[\p{L}\p{M}\p{N}]+$/u.test(token[0])) {
      segments.push({ type: 'punctuation', text: token[0], start: token.index, end: token.index! + token[0].length });
      i++; continue;
    }
    let end = i;
    let matches: SignMediaEntry[] | undefined;
    for (let j = i; j < Math.min(tokens.length, i + maxWords); j++) {
      if (!/^[\p{L}\p{M}\p{N}]+$/u.test(tokens[j][0])) break;
      const found = dictionary.get(key(tokens.slice(i, j + 1).map(t => t[0]).join(' ')));
      if (found) { matches = found; end = j; }
    }
    const startOffset = token.index!;
    const endOffset = tokens[end].index! + tokens[end][0].length;
    const original = text.slice(startOffset, endOffset);
    if (!matches) segments.push({ type: 'missing', text: original, start: startOffset, end: endOffset });
    else if (matches.length !== 1) segments.push({ type: 'ambiguous', text: original, start: startOffset, end: endOffset });
    else {
      const entry = matches[0];
      const images = (entry.imageUrls || []).map(safeUrl).filter((v): v is string => !!v);
      const videoUrl = safeUrl(entry.videoUrl);
      segments.push({ type: images.length || videoUrl ? 'sign' : 'missing_media', text: original,
        start: startOffset, end: endOffset, word: entry.word, entryId: String(entry._id),
        videoUrl, thumbnailUrl: safeUrl(entry.thumbnailUrl), imageUrls: images,
        attribution: entry.notes?.startsWith('Nguồn:') ? entry.notes : undefined });
    }
    i = end + 1;
  }
  return { text, segments, catalogEntries: entries.length, mode: 'dictionary_sequence' };
}
