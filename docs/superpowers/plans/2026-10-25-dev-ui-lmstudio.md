# Connect the dev learning UI to SignVoice LM Studio

> Execute in the existing LMStudio checkout, as requested. Preserve all earlier work in the local backup stash; do not push.

**Goal:** Use the learning interface from dev with the existing SignVoice LM Studio configuration.

**Architecture:** Keep dev's `/learning/coach` endpoint, learning collections and UI. Its backend uses `SIGNVOICE_LM_STUDIO_*` with a fixed SignVoice model, a 90 second AI timeout and an optional API key. Only this Flutter request gets a 100 second timeout; normal API and authentication behavior stay unchanged.

**Spec:** User request on 2026-10-25: preserve the LMS connection, replace the previous interface with the interface from dev, and reconnect it.

## Constraints

- Keep backend/.env byte-identical and retain unrelated startup/.env.example edits.
- Keep the leaf project configuration and downloaded models unchanged.
- Keep upstream learning data and camera quiz behavior; AI advice never modifies progress.
- No old learning-progress routes/screens are restored to the application.
- Keep same-Wi-Fi setup instructions consistent with the new interface.

## Tasks

- [x] Back up dirty work and .env; pull dev fast-forward to 390ca74.
- [x] Add tests for dedicated model/URL configuration, slow AI responses, malformed responses, and isolation from other project settings.
- [x] Connect the existing coach to SignVoice variables; keep bounded data and rules fallback. Extend only the coach HTTP timeout in Flutter.
- [x] Test the new learning UI and backend learning/quiz regressions using an isolated database; distinguish existing upstream failures with an untouched dev snapshot.
- [x] Update setup/docs for Khám phá → Đang học → Gợi ý ôn tập and optional API authentication.
- [x] Build, review, restart Local and verify health plus a real coach response from LM Studio.

## Review focus

- SignVoice must never pick an unrelated first model from /models.
- A model taking 45 seconds must complete through both backend and client.
- Unavailable, blank, truncated or malformed model output must retain progress and use the existing rules fallback.
- Data sent to the model must belong to the requesting user and active published topics.
- Existing .env and old UI backup must remain recoverable, without publishing secrets.

## Backup

Stash: `96b26e114c171a26eb0bdee00e9f76d694cc8aaa`.
Local files: `.runtime/lmstudio-dev-sync-20261025-013652/` (ignored; contains private .env backup).

## Evidence

- Backend build and targeted Flutter analysis passed; Flutter web release build passed.
- Eight coach unit tests passed; backend dictionary-learning tests passed.
- Ten Flutter coach/camera tests passed, including a 45 second response and both source badges on the unchanged dev UI.
- Real `POST /api/v1/learning/coach` using an isolated synthetic account returned `source: lm-studio` in 31 seconds, with 2 total / 1 learning / 1 remembered / 0 review, and unchanged progress records.
- Local web, backend readiness and camera health passed at localhost:3002. Served main.dart.js SHA256 equals the new local build.
- UI directories match origin/dev exactly; .env SHA256 matches the private backup. Fresh source review found no Critical/Important introduced issues.
- Upstream baseline has 7 Flutter failures (3 obsolete LM-graded quiz tests, 2 auth route timeout tests, 2 OAuth provider-copy tests) and 5 obsolete backend LM-graded quiz failures. All were reproduced on an untouched 390ca74 snapshot; this integration does not change the dev quiz/UI to satisfy those old expectations. Logs: .runtime/dev-baseline-flutter.log and .runtime/dev-baseline-backend.log.
- This task's temporary databases were dropped after tests. Existing application data, old legacy progress collections and LM Studio/leaf-project configuration were not changed by test setup.
