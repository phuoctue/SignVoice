import { describe, expect, it } from 'vitest';
import { learningCalendar, fillLearningDays } from '../src/services/learning-insights.service';

describe('Vietnam learning calendar', () => {
  it('uses Vietnam midnight and fills all seven days including missing dates', () => {
    const period = learningCalendar(7, new Date('2026-10-25T17:01:00Z'));
    expect(period.endDate).toBe('2026-10-26');
    expect(period.startDate).toBe('2026-10-20');
    expect(period.start.toISOString()).toBe('2026-10-19T17:00:00.000Z');
    const days = fillLearningDays(period, [{ _id: '2026-10-26', learned: 3, newWords: 1 }], [{ _id: '2026-10-25', reviewed: 2 }]);
    expect(days).toHaveLength(7);
    expect(days[0]).toEqual({ date: '2026-10-20', learned: 0, newWords: 0, reviewed: 0 });
    expect(days[6]).toMatchObject({ date: '2026-10-26', learned: 3, newWords: 1, reviewed: 0 });
    expect(days[5].reviewed).toBe(2);
  });
  it('keeps the previous local day immediately before Vietnam midnight and spans month boundaries', () => {
    const period = learningCalendar(30, new Date('2026-10-01T16:59:00Z'));
    expect(period.endDate).toBe('2026-10-01');
    expect(period.startDate).toBe('2026-09-02');
    expect(fillLearningDays(period, [], [])).toHaveLength(30);
  });
});
