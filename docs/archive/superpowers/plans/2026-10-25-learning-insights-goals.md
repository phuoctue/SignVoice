# Learning activity, reinforcement and daily goals

**Goal:** Implement the three approved additions: 7/30 day activity chart, frequently missed quiz words, and editable daily targets/progress bars.

**UI:** Thống kê & mục tiêu, linked from Đang học. Native Flutter grouped bars (tap a day, scroll 30 days), 7/30 switch, goal editor and two progress bars; ten weak words/page with sample/history/topic links. Keep AI analysis, coach, history and quiz behavior.

**Data rules:** Calendar UTC+7 (Vietnam), zero-fill all 7/30 dates through today, ignore future events. Study means distinct word IDs with SELF_RATED events/day. Review means distinct word IDs in completed sign-ai-camera quiz results/day, including unsuccessful recognition and older completed quizzes. New-word goal counts only firstLearning=true, set server-side when the word gets its first progress record; earlier unflagged events are not retroactively called new. Topic starts/legacy snapshots do not create study counts. A word may be studied and reviewed on the same day, counted once in each series.

**Reinforcement:** Current active/published words in the learner's enrolled topics with at least one miss from completed camera quizzes in the last 30 Vietnam calendar days. Rank misses, then miss percentage, then recent attempt; show misses/attempts and latest outcome. This describes recorded quiz outcomes, not model accuracy. Filter before pagination.

**API:** GET /learning/insights?days=7|30&page=1, PATCH /learning/goals {newWords,reviewWords}. Owner from token; no-store; strict validation. UserSettings.learningGoals defaults 5 new/10 review, integer limits1..100 /1..200. Existing settings export/reset/delete carries goals naturally. No new external dependencies or .env changes.

## Tasks

- [x] Add failing calculation/API/UI tests: calendar boundaries/zeros, duplicates, old camera quizzes, private scope, inactive/draft exclusions, goal bounds and persistence/reset.
- [x] Implement firstLearning marker, goal schema/API and statistics service.
- [x] Add insights screen, native accessible charts, goal editor and reinforcement list; wire navigation/service.
- [x] Validate focused regressions, docs/OpenAPI, analyzer/build and source review.
- [x] Restart Local, verify deployed build and endpoints, keep uncommitted/unpushed.

## Checks

- Chart dates must not shift at UTC midnight; always use Vietnam day boundaries.
- Same-word repeated quiz attempts increase attempt/miss totals but only one reviewed word/day.
- Completed quizzes without LearningEvent rows still count; legacy progress alone does not imply a study session.
- Other users and unavailable/currently unjoined topics never enter actionable weak-word list.
- Fast period/page changes and failed goal saves must not overwrite fresh data or discard input.

## Verification

- 41 backend tests passed across 7 focused files; includes 13 weak words across two pages, stable ties, hidden/draft/unjoined exclusions, old camera quizzes, API firstLearning marker/retries, account isolation and goal export/reset.
- 27 Flutter tests passed across 5 files; includes goal validation/save retry with preserved input, failed insights retry, navigation/disposal with pending data, period/page reset and a 30-day chart at 360px with 2.5x text.
- Backend build, targeted analyzer and final Flutter web release build passed. OpenAPI valid:83 paths,104/104 mounted methods documented.
- Fresh source review found no Critical/Important issue. Suggested coverage gaps were filled for firstLearning API writes, weak-word pagination/tie order and failed/disposed fetches.
- Real authenticated Local HTTP probe returned 7/30 chart dates, empty new-account counts, and persisted 7/12 test goals. Temporary guest account deleted afterward; test databases removed.
- Local runs at localhost:3002; .env/model configuration preserved. No commit/push.
