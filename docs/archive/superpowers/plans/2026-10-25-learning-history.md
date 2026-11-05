# Learning history

**Goal:** Show personal word-learning history while keeping the current dev UI, coach and progress analysis.

**Design:** A history page under Đang học, plus a per-word history link in topic study cards. New authenticated GET /learning/history supports page/search/entryId and returns ten newest events. History records topic starts, changed self ratings and camera quiz word results in the same user transactions as the original changes. Quiz resubmission/topic restart must not duplicate events. A read-only legacy snapshot of WordProgress is included only for words without event history and labeled "Trạng thái đã lưu"; it uses the actual stored last-review/update time, not invented earlier sessions.

**Storage:** learning_events, user/time and user/entry/time indexes. Snapshot word/topic labels survive later edits. User reset/account deletion removes owned events; export includes events and current progress. No LM Studio or recognition model changes. History does not auto-mark a viewed word as remembered.

## Tasks

- [x] Failing API tests: owner isolation, paging/search, legacy state, idempotent starts/ratings/quiz, atomic rollback and reset/export/deletion.
- [x] Add model/read service and transaction hooks for enrollment, self rating and quiz submission.
- [x] Add Flutter history route/page/service and entry links; tests for search/paging and per-word filter.
- [x] Verify existing learning/analysis/coach behavior, API docs, analyzer/build and source review.
- [x] Document feature, restart Local, check health/deployed build. Keep uncommitted, no push.

## Scope

Implement history only. Propose daily review inbox, week activity chart and frequently forgotten words as follow-up ideas, not new features in this change.

## Evidence

- 32 focused backend tests passed across learning/history/analysis/coach. History fixtures cover old timestamps, 13 records across two pages, search, owner isolation, duplicate starts/ratings/quiz, rollback, export/reset/deletion.
- 20 Flutter tests passed across history/analysis/coach/quiz camera, including actual navigation from the study hub and a word card, per-word filter, search and paging.
- Backend and web release build passed; targeted analyzer clean. OpenAPI valid, 102/102 mounted methods documented.
- Source review found no important introduced issue in ownership, transaction hooks, legacy fallback, ordering, reset/export or route lifecycle.
- Local restarted at localhost:3002; backend/camera health ready and served main.dart.js hash equals the built web artifact. .env hash unchanged.
- Test database generated for this task was removed. No commit or push.
