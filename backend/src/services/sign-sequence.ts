/** Deterministic dictionary lookup, not a sign-language grammar translator. */
export interface SignMediaEntry {
  _id: unknown;
  word: string;
  aliases?: string[];
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
  const exact = new Set(entries.map(entry => key(entry.word)));
  let maxWords = 1;
  for (const entry of entries) {
    for (const normalized of new Set([key(entry.word), ...(entry.aliases || []).map(key).filter(alias => !exact.has(alias))])) {
      if (!normalized) continue;
      dictionary.set(normalized, [...(dictionary.get(normalized) || []), entry]);
      maxWords = Math.max(maxWords, normalized.split(' ').length);
    }
  }
  const media = (entry: SignMediaEntry, original: string) => {
    const images = (entry.imageUrls || []).map(safeUrl).filter((v): v is string => !!v);
    const videoUrl = safeUrl(entry.videoUrl);
    return {type: images.length || videoUrl ? 'sign' : 'missing_media', text: original,
      word: entry.word, entryId: String(entry._id), videoUrl,
      thumbnailUrl: safeUrl(entry.thumbnailUrl), imageUrls: images,
      attribution: entry.notes?.startsWith('Nguồn:') ? entry.notes : undefined};
  };
  const spell = (original: string) => {
    const letters = [];
    let hasTone = false;
    for (const character of original.normalize('NFC')) {
      // Keep ă/â/ê/ô/ơ/ư distinct; only tone marks are represented by the text.
      const base = key(character).normalize('NFD').replace(/[\u0300\u0301\u0303\u0309\u0323]/gu, '').normalize('NFC');
      if (!/^[a-zăâđêôơư\d]$/u.test(base)) return undefined;
      const matches = dictionary.get(base);
      if (matches?.length !== 1) return undefined;
      const letter = media(matches[0], character);
      if (letter.type !== 'sign') return undefined;
      hasTone ||= key(character) !== base;
      letters.push(letter);
    }
    return letters.length ? {type: 'fingerspelling', letters, hasTone} : undefined;
  };
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
    if (!matches) segments.push({ ...(spell(original) || {type: 'missing'}), text: original, start: startOffset, end: endOffset });
    else if (matches.length !== 1) segments.push({ type: 'ambiguous', text: original, start: startOffset, end: endOffset });
    else {
      const entry = matches[0];
      segments.push({ ...media(entry, original), start: startOffset, end: endOffset });
    }
    i = end + 1;
  }
  return { text, segments, catalogEntries: entries.length, mode: 'dictionary_sequence' };
}
