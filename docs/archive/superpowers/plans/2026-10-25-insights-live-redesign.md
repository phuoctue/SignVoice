# Live goals and daily activity drill-down

**Later request implemented:** Removed five-second polling. Goals refresh on open, explicit refresh, settings save, return from learning pages and app resume. Camera quiz now forwards measured observations and face context, shows hand/recognition feedback, retains confirmed captures through null updates/disconnects and starts a fresh inference session for retry/next/previous question. Socket protocol smoke passed (JPEG and three live observation responses, no false confirmation); this is not a physical gesture accuracy test.

**Request:** Redesign today's goals and chart. Live done/target counters, green completion and motion; dropdown7/30; tapping a day shows actual studied/reviewed words; explain reinforcement operation.

**Design:** Animated goal tiles with explicit counts, completion status and last-sync/error indicator. Poll a lightweight owner-scoped GET /learning/today every5s only while insights route is current and app foreground; no overlapping requests, cancel on dispose, preserve existing snapshot on network failure. Full refresh on resume/return and new Vietnam date. Goal edits keep their existing transaction and owner guard.

Chart uses controlled dropdown and animated bars. Day selection opens a bottom sheet with Học/Ôn tabs,10 words/page, actual last event/quiz time and history links. GET /learning/activity takes strict real YYYY-MM-DD, kind learned|reviewed, page; UTC+7 windows, same owner/source/dedup rules as chart. No synthetic old sessions or client-supplied owner.

Reinforcement rules stay unchanged. Add visible how-it-works steps, explain empty state and why a word can remain after a recent correct result (30-day history); improve outcome badges/actions. No forced quiz scoring or LM changes.

## Tasks

- [x] Failing tests: today parity, day-word lists/dedup/date validity/paging/privacy, live goal updates/green/paused-disposed lifecycle, dropdown and day selection.
- [x] Share activity aggregation; add lightweight today and daily word-list endpoints/OpenAPI.
- [x] Add animated goal card and day detail sheet, update chart/dropdown and polling/error handling.
- [x] Clarify reinforcement UI/docs; focused tests, analyzer/build and review.
- [x] Restart Local, verify HTTP/deployed UI, preserve .env and unpushed work.

## Review focus

- Day detail totals match chart unique-word/day counts for real camera results, including older completed quizzes.
- Live refresh never replaces valid data with zeros on errors or shows another account's results.
- Requests stop in background/hidden routes and do not overlap; date rollover shifts the chart correctly.
- Goal counts remain legible at360px/large text; animations respect reduced motion and stop.
- Existing history, review plan and personal analysis continue working.

## Verification

- Backend: 43 related tests passed across seven files, using a newly isolated test database removed after the run.
- Flutter: 33 related tests passed; after final quiz help copy change, reran affected insights/history/camera suites (24 passed).
- Focused Dart analyzer: no issues. TypeScript build passed. OpenAPI valid, 106/106 routes documented.
- Review found a day modal session-change issue; fixed with owner epoch/listener, immediate data clearing and route removal. Logout regression passes; reviewer confirmed the fix.
- Web release build passed; restarted managed Local at http://localhost:3002. Backend/database and camera AI readiness passed (181 words). Served main.dart.js SHA256 matches the final local build.
- Authenticated HTTP smoke passed for 7/30-day insights, persisted goals, lightweight today parity and daily word lists. Temporary verification account deleted. Existing .env hash unchanged; no commit or push.
