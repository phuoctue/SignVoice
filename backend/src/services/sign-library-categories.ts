import categoryData from '../config/sign-library-categories.json';

const taxonomy = categoryData as {
  groups: Record<string, string[]>; keywords: Record<string, string[]>;
  fallbackCategory: string; alphabetCategory: string; reviewedCategories?: Record<string, string>; aliases?: Record<string, string[]>;
};
export const referenceCategories = [...Object.keys(taxonomy.groups), taxonomy.alphabetCategory, taxonomy.fallbackCategory];
const normalize = (text: string) => text.normalize('NFC').toLocaleLowerCase('vi').trim().replace(/\s+/gu, ' ');
const exact = new Map(Object.entries(taxonomy.groups).flatMap(([name, words]) => words.map(word => [normalize(word), name] as const)));
export const reviewedReferenceCategories = taxonomy.reviewedCategories || {};
for (const [word, category] of Object.entries(reviewedReferenceCategories)) exact.set(normalize(word), category);
const patterns = Object.entries(taxonomy.keywords).flatMap(([name, words]) => words.map(keyword => ({name, length: keyword.length,
  term: ' ' + keyword.replace(/[^\p{L}\p{M}\p{N}]+/gu, ' ') + ' '})))
  .sort((a, b) => b.length - a.length);

export function referenceCategory(word: string) {
  const value = normalize(word);
  if (/^[a-zăâđêôơư]$/u.test(value) || /^\d[\d\s.]*(?:\s*\([^)]*\))?$/u.test(value)) return taxonomy.alphabetCategory;
  if (exact.has(value)) return exact.get(value)!;
  const tokens = ' ' + value.replace(/[^\p{L}\p{M}\p{N}]+/gu, ' ') + ' ';
  return patterns.find(pattern => tokens.includes(pattern.term))?.name ?? taxonomy.fallbackCategory;
}

export function referenceAliases(word: string): string[] {
  const value = normalize(word), aliases = [...(taxonomy.aliases?.[value] || [])];
  if (/[?!]$/u.test(value)) aliases.push(value.replace(/[?!]+$/u, '').trim());
  const number = value.match(/^(\d[\d\s.]*)\s*\(([^)]+)\)$/u);
  if (number) aliases.push(number[1].replace(/[\s.]/gu, ''), number[2].trim());
  const country = value.match(/\((nước [^)]+)\)$/u);
  if (country) aliases.push(country[1]);
  if (value === 'cảm ơn') aliases.push('cám ơn');
  if (value === 'ngôn ngữ ký hiệu') aliases.push('ngôn ngữ kí hiệu');
  if (value === 'ngôn ngữ kí hiệu') aliases.push('ngôn ngữ ký hiệu');
  return [...new Set(aliases)].filter(alias => !!alias && alias !== value);
}

export function referenceSlug(name: string) {
  return name.normalize('NFD').replace(/\p{M}/gu, '').replace(/đ/giu, 'd').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}
