export type ReminderPlan = {enabled: boolean; hour: number; minute: number; weekdays: number[]; timezone: string};

function localParts(date: Date, timezone: string) {
  const values = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', weekday: 'short', hourCycle: 'h23',
  }).formatToParts(date).map(part => [part.type, part.value]));
  return {date: `${values.year}-${values.month}-${values.day}`,
    minute: Number(values.hour) * 60 + Number(values.minute),
    weekday: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].indexOf(values.weekday) + 1};
}

/** Only today's due occurrence; saving a time already past schedules the next occurrence. */
export function dueStudyReminder(plan: ReminderPlan | undefined, now: Date, savedAt?: Date) {
  if (!plan?.enabled) return null;
  try {
    const local = localParts(now, plan.timezone);
    const scheduled = plan.hour * 60 + plan.minute;
    if (!plan.weekdays.includes(local.weekday) || local.minute < scheduled) return null;
    if (savedAt) {
      const saved = localParts(savedAt, plan.timezone);
      if (saved.date === local.date && saved.minute > scheduled) return null;
    }
    const time = `${String(plan.hour).padStart(2, '0')}:${String(plan.minute).padStart(2, '0')}`;
    return {key: `STUDY_REMINDER:${local.date}:${time}:${plan.timezone}`, time};
  } catch { return null; }
}
