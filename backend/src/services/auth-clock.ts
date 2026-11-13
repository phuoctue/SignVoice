/** UTC is injected by deterministic boundary tests; host synchronization is an ops obligation. */
export const authClock = { now: (): Date => new Date() };
