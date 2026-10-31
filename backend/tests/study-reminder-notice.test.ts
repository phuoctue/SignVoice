import {describe, expect, it} from 'vitest';
import {dueStudyReminder, ReminderPlan} from '../src/services/study-reminder-notice';

const plan: ReminderPlan = {enabled: true, hour: 19, minute: 30, weekdays: [5], timezone: 'Asia/Ho_Chi_Minh'};
describe('study reminder due occurrence', () => {
  it('rolls the occurrence date at midnight in the saved timezone', () => {
    const midnight = {...plan, hour: 0, minute: 0, weekdays: [6]};
    expect(dueStudyReminder(midnight, new Date('2026-10-30T16:59:59Z'))).toBeNull();
    expect(dueStudyReminder(midnight, new Date('2026-10-30T17:00:00Z'))?.key).toContain('2026-10-31');
    expect(dueStudyReminder(midnight, new Date('2026-10-31T17:00:00Z'))).toBeNull();
  });
  it('uses the saved timezone and fires only on selected days after the due minute', () => {
    expect(dueStudyReminder(plan, new Date('2026-10-30T12:29:59Z'))).toBeNull();
    expect(dueStudyReminder(plan, new Date('2026-10-30T12:30:00Z'))?.time).toBe('19:30');
    expect(dueStudyReminder(plan, new Date('2026-10-31T12:30:00Z'))).toBeNull();
    expect(dueStudyReminder({...plan, enabled: false}, new Date('2026-10-30T12:30:00Z'))).toBeNull();
  });
  it('returns a stable idempotency key and does not replay a newly saved time already past', () => {
    const now = new Date('2026-10-30T13:00:00Z');
    expect(dueStudyReminder(plan, now)?.key).toBe(dueStudyReminder(plan, new Date('2026-10-30T14:00:00Z'))?.key);
    expect(dueStudyReminder(plan, now, new Date('2026-10-30T12:45:00Z'))).toBeNull();
    expect(dueStudyReminder(plan, now, new Date('2026-10-29T12:45:00Z'))).not.toBeNull();
    expect(dueStudyReminder({...plan, timezone: 'invalid/zone'}, now)).toBeNull();
  });
});
