---
id: non-ai-baseline
scope: repository baseline
status: completed
depends-on: []
---

## Objective

Return the project to the user's pushed origin/main commit `78efbe2`, preserving a recovery
copy of all recent AI work. Do not reset unrelated files or remove installed models/software.

## Context

Read docs/INDEX.md and docs/active/NON_AI_DELIVERY.md. Current branch task/non-ai-baseline.
All 22 currently modified tracked paths are the AI changes from this conversation.
The untracked android/build directory existed before AI work and must be left untouched.

## Path

Restore only the tracked paths currently reported by `git diff --name-only origin/main`.
Move these explicitly known AI additions to an ignored recovery directory under `.runtime`:
docs/LM_STUDIO_LOCAL.md, lib/ai_test_page.dart, lib/config/ai_config.dart,
lib/services/lm_studio_service.dart, lib/services/video_analysis_service.dart,
scripts/start-video-ai.ps1, test/ai_test_page_test.dart, test/lm_studio_service_test.dart,
test/video_analysis_service_test.dart, video_backend/.
Do not move the entire lib/config directory if it contains other files.
Do not move the new delivery docs or touch secrets in backend/.env.

## Implementation

First save a binary patch for tracked changes and copies of the listed additions in a
timestamped ignored recovery folder; verify all destination/source absolute paths remain
under this workspace before any move. Preserve original filenames and a restoration manifest.
Restore the tracked paths from origin/main, then move only the listed AI additions out of the
active project. Restore pub packages/generated registrants using flutter pub get.
Stop only the video AI process started by this conversation if its executable/command line
and listening port match the recorded local runtime metadata. Do not close the user's LM Studio.
Verify no active LM Studio imports/routes/packages remain. Record results in this task doc.
Commit only the delivery docs and any necessary baseline cleanup evidence on this branch.

## Verification

git diff origin/main should show delivery docs only, no active AI additions. Preserve
android/build and backend/.env. Run the baseline analyzer/tests and document pre-existing
failures rather than correcting application features in this task. Report the commit and
backup location for orchestrator merge.

## Completion evidence — 2026-10-16

- Restored all 22 tracked AI modifications from origin/main `78efbe2`. Only delivery
  documentation differs from that pushed baseline; no application feature was changed.
- Recovery: `.runtime/non-ai-recovery-20261016-152545/` contains the binary tracked patch,
  original tracked/addition copies under `files/`, moved AI additions under `moved/`, and
  `manifest.json` with paths and restoration instructions. `git apply --check` accepts the
  recovery patch. All moved addition files match their backup SHA-256 hashes.
- Preserved `backend/.env` byte hash and the complete preexisting `android/build` file count.
  Did not alter installed LM Studio, downloaded models, or other runtime environments.
- The recorded Video AI PID 6232 did not exist and port 8000 had no listener at cleanup.
  No process needed stopping. LM Studio was not closed.
- `flutter pub get` passed and regenerated platform registrants using the pushed packages.
  Search found no active LM Studio page/service/configuration, video backend references,
  `image_picker` dependency, or associated imports in application/test/server source.

### Baseline checks

| Check | Result |
| --- | --- |
| Backend `npm test` | Passed: 53 tests in 7 files |
| Backend `npm run typecheck` | Passed |
| Backend `npm run docs:validate` | Passed: 48 OpenAPI paths |
| Backend `npm run docs:coverage` | Passed: 63/63 routes documented |
| Flutter `flutter test` | Passed: 75 tests |
| Flutter `flutter analyze` | Preexisting failure: 42 findings (2 warnings, 40 info), no errors |

Local logs are `.runtime/non-ai-baseline-{backend-tests,backend-typecheck,docs-validation,
docs-coverage,flutter-tests,flutter-analyze}.log`. These are baseline regression checks,
not evidence that incomplete product flows satisfy the broader completion contract.

### Findings for subsequent implementation tasks

The restored analyzer reports unnecessary null checks/assertions in
`lib/screens/user/dictionary_detail_screen.dart:114-115`, an undeclared direct `intl`
dependency in `lib/screens/user/history_screen.dart`, deprecated Radio group APIs in
`lib/screens/user/dictionary_list_screen.dart` and `lib/screens/user/settings_screen.dart`,
null-aware collection-style findings in service files, and a missing control-flow block in
`test/admin_workspace_test.dart:411`. These existed in the pushed baseline and were
intentionally left for the frontend delivery task rather than mixed into recovery cleanup.
