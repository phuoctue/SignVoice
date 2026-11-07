import { randomInt, randomUUID } from 'node:crypto';
import { AppError } from '../common/errors/AppError';

export type MatchQuestion = { entryId: string; word: string; aliases: string[]; videoUrl: string; imageUrls: string[]; thumbnailUrl?: string; matchOptionId?: string };
export type MatchOption = { value: string; label: string; round: number };
export type MatchResponse = { entryId: string; matched: boolean; usedHint: boolean; firstCorrect: boolean;
  selectedOptionId: string; checks: { requestId: string; optionId: string }[] };
const normalized = (s: string) => s.normalize('NFC').trim().toLocaleLowerCase('vi').replace(/_/g, ' ').replace(/\s+/g, ' ');

/** Remove ambiguous labels and duplicate samples before assigning opaque tokens. */
export function matchingBoard<T extends MatchQuestion>(candidates: T[]) {
  const names = new Set<string>(), samples = new Set<string>();
  const selected = candidates.filter(q => {
    const labels = [q.word, ...q.aliases].map(normalized).filter(Boolean);
    const sample = q.videoUrl || q.imageUrls.join('|') || q.thumbnailUrl || '';
    if (!labels.length || labels.some(label => names.has(label)) || sample && samples.has(sample)) return false;
    labels.forEach(label => names.add(label));
    if (sample) samples.add(sample);
    return true;
  }).slice(0, 10);
  if (selected.length < 2) throw new AppError('Cần ít nhất 2 từ có mẫu ký hiệu và nghĩa khác nhau để chơi ghép cặp.', 409, 'QUIZ_MATCH_TOO_SMALL');
  const questions = selected.map(q => ({ ...q, matchOptionId: randomUUID() }));
  const options = questions.map((q, i) => ({ value: q.matchOptionId, label: q.word.normalize('NFC'), round: Math.floor(i / 4) }));
  // Avoid a final round containing only one answer.
  if (options.length % 4 === 1) options[options.length - 2].round++;
  for (let i = options.length - 1; i > 0; i--) {
    const j = randomInt(i + 1); [options[i], options[j]] = [options[j], options[i]];
  }
  return { questions, matchOptions: options };
}

export function recordMatch(questions: MatchQuestion[], options: MatchOption[], responses: MatchResponse[],
  entryId: string, optionId: string, requestId: string, hint: boolean) {
  const index = questions.findIndex(q => q.entryId === entryId);
  if (index < 0) throw new AppError('Từ này không thuộc bài ôn tập.', 400, 'INVALID_QUIZ_WORD');
  const question = questions[index];
  const expected = options.find(o => o.value === question.matchOptionId)!;
  const row = responses.find(r => r.entryId === entryId);
  if (hint) {
    if (row?.matched) return responses;
    const next: MatchResponse = row ? { ...row, usedHint: true } : { entryId, usedHint: true, matched: false, firstCorrect: false, selectedOptionId: '', checks: [] };
    return [...responses.filter(r => r.entryId !== entryId), next];
  }
  const prior = responses.flatMap(r => r.checks.map(check => ({ ...check, entryId: r.entryId }))).find(check => check.requestId === requestId);
  if (prior) {
    if (prior.entryId !== entryId || prior.optionId !== optionId) throw new AppError('Lượt ghép đã được dùng cho lựa chọn khác.', 409, 'QUIZ_MATCH_CONFLICT');
    return responses;
  }
  if (row?.matched) throw new AppError('Cặp này đã ghép đúng.', 409, 'QUIZ_MATCH_LOCKED');
  if (!options.some(o => o.value === optionId && o.round === expected.round)) throw new AppError('Thẻ không thuộc vòng chơi.', 400, 'INVALID_MATCH_OPTION');
  if (responses.some(r => r.matched && r.selectedOptionId === optionId)) throw new AppError('Thẻ đã được ghép đúng với mẫu khác.', 409, 'QUIZ_MATCH_LOCKED');
  if ((row?.checks.length || 0) >= 100 && optionId !== question.matchOptionId) throw new AppError('Hãy dùng gợi ý để ghép cặp này.', 429, 'QUIZ_MATCH_LIMIT');
  const matched = optionId === question.matchOptionId;
  const next: MatchResponse = { entryId, matched, usedHint: row?.usedHint || false,
    firstCorrect: row?.checks.length ? row.firstCorrect : matched,
    selectedOptionId: optionId, checks: [...(row?.checks || []), { requestId, optionId }] };
  return [...responses.filter(r => r.entryId !== entryId), next];
}
