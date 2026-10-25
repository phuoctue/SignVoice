# Personal learning progress analysis

**Request:** Keep the dev learning UI and the working review suggestions; add the missing personal learning progress analysis.

**Design:** Add a separate "Phân tích tiến độ cá nhân" action in Đang học. Backend computes a snapshot across all active, enrolled topics and published words, then asks the existing SignVoice LM Studio model to analyze that snapshot. UI shows deterministic remembered percentage/topic counts and clearly labels AI versus rules fallback. Coach and camera quiz retain their behavior.

**API:** `POST /api/v1/learning/analysis`, strict empty body, authenticated owner from token, no-store, three requests/minute/user. Returns source, summary, up to 40 named topic summaries, analysis, generatedAt. No free-form prompt, account IDs or raw media sent to AI. Backend waits 90s, client 100s.

**Limits:** Analysis concerns current recorded learning state. No invented study time, streaks, before/after trend, or camera accuracy. Total words means published words in started topics, not words mastered. Legacy collections are not migrated or removed. Keep .env/leaf project untouched.

## Steps

- [x] Write failing snapshot/API and UI tests, including more than ten topics, due review, account isolation, AI failure and slow response.
- [x] Reuse the enrolled-topic aggregation for both the existing overview and the new analysis; add analysis service/route.
- [x] Add LearningService.analyzeProgress and an analysis card/action in the existing Đang học tab. Preserve the review suggestion action/result.
- [x] Verify focused tests, unchanged coach tests, OpenAPI, build and source review.
- [x] Update setup docs, restart Local, verify a real analysis response and retain uncommitted work.

## Review focus

- Counts must include all enrolled topics, not only the current ten-topic page.
- Another account, inactive category and draft word must not enter the snapshot.
- An overdue remembered word is REVIEW, matching the existing learning summary.
- AI unavailability or invalid output retains a usable deterministic snapshot and a truthful source label.
- Navigating/refreshing while analysis is pending must not attach stale results to new data.

## Verification evidence

- 27 focused backend tests passed (analysis API5, analysis unit6, coach8, existing learning8).
- 16 Flutter tests passed (analysis6, coach3, quiz-camera7), including rate-limit display, tab-change invalidation, 360px/large text, and a 45 second response.
- Targeted analyzer clean; backend and Flutter web release builds passed.
- OpenAPI valid: 80 paths, 101/101 mounted route methods documented.
- Real analysis API returned `source: lm-studio` in 23 seconds with synthetic 2-word / 50% remembered snapshot and unchanged progress. Test database dropped afterward.
- Local readiness/camera healthy on port3002; deployed main.dart.js hash matches the new build. .env matches its backup.
- Source review found one test cleanup compatibility issue; fixed to delete fixture IDs and always disconnect, then reviewer confirmed no remaining concern. Product source review found no Critical/Important issue.
- No commit/push. Existing upstream quiz/auth test failures documented in the previous integration plan remain outside this feature.
