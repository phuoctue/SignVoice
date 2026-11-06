# SignVoice — Task board

## Quy ước

Mỗi task phải có mục tiêu, phạm vi file, đầu vào cụ thể, tiêu chí kiểm tra và ngoài phạm vi. Trạng thái: `TODO`, `IN_PROGRESS`, `REVIEW`, `DONE`, `BLOCKED`.

## Baseline — 2026-11-05

- `flutter analyze`: **FAIL**, 1 info tại `test/guest_preferences_test.dart:16:7` (`curly_braces_in_flow_control_structures`).
- `flutter test`: **FAIL**, 538 test chạy; 11 test fail, chủ yếu ở các flow learning/web/layout.
- `backend/npm run typecheck`: **PASS**.
- `backend/npm run lint`: **FAIL**, backend chưa có ESLint configuration.
- `backend/npm test`: chưa chạy baseline thành công trong lượt đầu vì đã thử nhầm cờ Jest `--runInBand`; Vitest không hỗ trợ cờ này. Lệnh đúng là `npm test`.

## T-001 — Tạo lệnh check tổng hợp

Trạng thái: `DONE`

Mục tiêu: tạo một lệnh PowerShell ở root để chạy các kiểm tra hiện có theo thứ tự, giữ đủ exit code và báo cáo rõ bước nào fail.

Phạm vi file:

- Được sửa: `scripts/check.ps1`, mục task này trong `docs/TASKS.md`.
- Không được sửa: `lib/`, `test/`, `backend/src/`, `backend/src/routes/sign-collection.routes.ts`, package/dependency files.

Đầu vào cần đọc:

- `AGENTS.md`, `CLAUDE.md`, `.agents/AGENT.md`.
- `pubspec.yaml`.
- `backend/package.json`.

Tiêu chí hoàn thành:

- `pwsh -File scripts/check.ps1` chạy được từ root.
- Chạy Flutter analyze/test và backend typecheck/lint/test.
- Không dừng ở bước đầu tiên; cuối cùng trả exit code khác 0 nếu có bước fail.
- Không che giấu baseline failures.

Lệnh kiểm tra: `pwsh -File scripts/check.ps1`.

Ngoài phạm vi: sửa lỗi test/lint, thêm ESLint config, sửa code sản phẩm, cài package.

## T-002 — Sửa lint curly braces trong guest_preferences_test

Trạng thái: `DONE`

Mục tiêu: sửa lint `curly_braces_in_flow_control_structures` tại `test/guest_preferences_test.dart:16`.

Phạm vi file:

- Được sửa: `test/guest_preferences_test.dart`, mục task này trong `docs/TASKS.md` (Orchestrator).
- Không được sửa: `lib/`, `backend/`, package files, các test khác.

Đầu vào cần đọc: `test/guest_preferences_test.dart`; baseline trong `docs/BASELINE.md`.

Tiêu chí hoàn thành:

- `flutter analyze test/guest_preferences_test.dart` không còn issue nào.
- `flutter test test/guest_preferences_test.dart` vẫn pass (baseline: 2/2 pass).
- Chỉ `test/guest_preferences_test.dart` thay đổi (ngoài `docs/TASKS.md`).

Lệnh kiểm tra: `flutter analyze test/guest_preferences_test.dart`; `flutter test test/guest_preferences_test.dart`.

Ngoài phạm vi: sửa 11 test Flutter đang fail trong baseline, refactor, sửa cảnh báo/lỗi ở file khác, thêm package.

## audit/us-002-guest-trial — Audit US-002 Guest Trial

Trạng thái: `BLOCKED`

Tiến độ 2026-11-06: Worker `signvoice-22` đã bàn giao audit tài liệu; API/UI thực tế và test bị chặn/chưa chạy. Native `turn_context` xác nhận worker dùng `gpt-5.6-luna`, effort `medium`; reviewer cũ `signvoice-23` cùng model chỉ nhận WAIT, không review. Orchestrator đã sửa project default; reviewer thay thế session sạch `signvoice-24` được xác minh native `turn_context` dùng `gpt-6.1-sol`, effort `medium`, và đã báo user/orchestrator trước giao việc. Vòng 1/2: BLOCKER; đã sửa tài liệu về xung đột thời điểm bắt đầu, cấp lại lượt, quyền xóa dữ liệu, bằng chứng lệnh và consent/empty state. Vòng cuối 2/2: PASS phần tài liệu tại thời điểm đó; còn thiếu runtime và khi đó chờ quyết định F-003..F-005 nên giữ BLOCKED. Chu kỳ cũ đã dùng đủ 2 vòng. Nay chủ dự án đã chốt F-003..F-005 ở policy delta dưới đây; source/test vẫn UNFIXED, runtime/test vẫn NOT_RUN. User đã cho phép chu kỳ review delta mới tối đa 2 vòng riêng, không phải vòng 3 cũ; verdict ghi ngoài tài liệu trong AO, chưa có verdict delta. Không chuyển DONE hoặc sửa source.

Mục tiêu: kiểm tra thực tế US-002 từ Backend đến Flutter UI; ghi bằng chứng, sai lệch hợp đồng và khoảng trống kiểm thử. Đây là task audit, không phải task sửa lỗi.

Phạm vi file:

- Được sửa: mục task này trong `docs/TASKS.md`; tạo/cập nhật [báo cáo audit](active/US-002_GUEST_TRIAL_AUDIT.md).
- Không được sửa: `lib/`, backend source, test code, package/lock files, file Excel và mọi file ngoài hai tài liệu trên. Đặc biệt không chạm `backend/src/routes/sign-collection.routes.ts` hoặc thay đổi chưa commit của người dùng.
- Không tự sửa code, thêm package, đổi API/schema/auth/migration; không vẽ Use Case, Activity hoặc Sequence Diagram; không tự push hoặc merge.

Đầu vào cụ thể (chỉ đọc; lần theo import/call liên quan khi cần, không quét toàn repo):

- `AGENTS.md`, `.agents/AGENT.md`, `docs/SPEC.md`, `docs/BASELINE.md`, `docs/active/GUEST_TRIAL_POLICY_20261024.md`, `docs/active/API_ENDPOINT_REFERENCE.md`.
- Backend: `backend/src/routes/auth.routes.ts`, `backend/src/routes/guest-trial.routes.ts`, `backend/src/controllers/auth.controller.ts`, `backend/src/services/auth.service.ts`, `backend/src/services/guest-trial.service.ts`, `backend/src/services/guest-device.service.ts`, `backend/src/validation/auth.validation.ts`.
- Auth/quyền/lỗi: `backend/src/common/middlewares/auth.middleware.ts`, `backend/src/common/middlewares/guest-trial.middleware.ts`, `backend/src/common/middlewares/validate.middleware.ts`, `backend/src/common/middlewares/errorHandler.ts`, `backend/src/models/GuestTrial.model.ts`, `backend/src/ai-public-proxy.ts`; lần theo nơi mount route và kiểm tra quyền ghi dữ liệu guest.
- Flutter: `lib/app.dart`, `lib/core/app_route.dart`, `lib/core/app_state.dart`, `lib/features/auth/auth_screens.dart`, `lib/features/auth/web_auth_layout.dart`, `lib/providers/auth_provider.dart`, `lib/services/auth/auth_service.dart`, `lib/services/auth/guest_trial_access.dart`, `lib/services/auth/guest_device_identity.dart`, `lib/widgets/guest_access_gate.dart`, `lib/features/library/library_screens.dart`, `lib/features/speech/speech_screens.dart`, `lib/features/recognition/live_camera_screen.dart`.
- Test: `backend/tests/guest-trial.test.ts`, `backend/tests/auth.test.ts`, `backend/tests/auth-security.test.ts`, `backend/tests/ai-public-proxy.test.ts`; `test/guest_trial_test.dart`, `test/auth_test.dart`, `test/guest_preferences_test.dart`, `test/public_startup_session_test.dart`, `test/web_account_navigation_test.dart`, `test/api_navigation_latency_test.dart`.

Trình tự và kiểm tra:

1. Ghi branch/HEAD, thời điểm, môi trường và `git status --short` ban đầu; dùng worktree riêng, không đổi cấu hình/dữ liệu đang dùng của người dùng.
2. Đối chiếu route → validation → service → auth/session → quyền guest → error handler → Flutter caller. Dùng chính sách hiện hành làm kỳ vọng; đánh dấu mâu thuẫn tài liệu/code, không tự chọn lại nghiệp vụ.
3. Chạy lệnh bên dưới và kiểm tra API/UI thực tế theo ma trận trong báo cáo. Dùng tài khoản/dữ liệu QA cô lập; không chạy seed/cleanup/migration lên database người dùng. Nếu thiếu môi trường, ghi rõ `BLOCKED`/`NOT_RUN` và cách tái hiện còn thiếu.
4. Ghi từng finding với mức độ, `file:line`, bước tái hiện, kỳ vọng/thực tế và bằng chứng; phân biệt lỗi tái hiện, nghi vấn từ đọc code, thiếu test và baseline đã có.
5. Xem `git diff` và kiểm tra chỉ hai file tài liệu được phép đổi trước khi bàn giao reviewer.

Lệnh kiểm tra (không sửa test/config để làm xanh):

- Tại `backend/`: `npm run typecheck`; `npm run lint`; `npm test -- tests/guest-trial.test.ts tests/auth.test.ts tests/auth-security.test.ts tests/ai-public-proxy.test.ts`.
- Tại root: `flutter analyze`; `flutter test --no-pub test/guest_trial_test.dart test/auth_test.dart test/guest_preferences_test.dart test/public_startup_session_test.dart test/web_account_navigation_test.dart test/api_navigation_latency_test.dart`.
- Kiểm tra tài liệu/phạm vi: `git diff --check`; `git diff -- docs/TASKS.md`; đọc file audit mới (file chưa tracked không hiện trong diff thường); `git status --short`.
- Ghi exit code, số pass/fail/skip và giới hạn của từng lệnh; baseline trong board không thay cho kết quả chạy mới. Không dùng cờ Jest `--runInBand` cho Vitest.

Tiêu chí hoàn thành:

- Ma trận Backend có route/API, service, validation, auth/session, quyền guest, error handling và test; ma trận UI có màn/navigation, loading/empty/error/retry, mobile/web, text scaling, keyboard, contrast/accessibility, widget test và API lỗi/chậm.
- Có bằng chứng mới cho các mục đã chạy; mỗi mục còn lại có lý do và ảnh hưởng. Không dùng việc đọc source hoặc widget test để tuyên bố đã nghiệm thu trên thiết bị thật.
- Kiểm tra mốc bắt đầu, hạn 600 giây, gọi lại/đồng thời/refresh/reload/vào lại; guest hết hạn vẫn xem kho và được xử lý dữ liệu cũ theo quyền sở hữu; quyền ghi cá nhân, nâng cấp tài khoản và dừng camera/micro/stream được đối chiếu chính sách.
- Báo cáo [US-002_GUEST_TRIAL_AUDIT.md](active/US-002_GUEST_TRIAL_AUDIT.md) đủ kết quả, finding, bằng chứng, test và phần chưa xác minh; không sửa lỗi sản phẩm trong task này.
- Reviewer dùng session sạch, tự đọc diff/source và bằng chứng, không coi lời worker là bằng chứng. Tối đa 2 vòng review/sửa tài liệu; còn bất đồng hoặc rủi ro auth/quyền cần chủ dự án quyết định. Không tự mở rộng thành sửa code.
- Chỉ chuyển `DONE` khi review hoàn tất và các giới hạn được ghi rõ; mục kiểm tra bắt buộc bị chặn phải được chủ dự án chấp nhận trước khi đóng task.

Báo cáo worker: dưới 10 dòng, gồm việc làm, hai file đổi, lệnh/kết quả, finding chính, giới hạn và trạng thái review. Reviewer báo `PASS` hoặc `BLOCKER`/`SHOULD FIX`/`NIT` với lý do và vị trí; ghi số vòng 1/2 hoặc 2/2.

Ngoài phạm vi: sửa code/test, triển khai chức năng còn thiếu, sửa baseline failures, benchmark toàn dự án, audit các US khác, diagram và xuất/sửa Excel.


## US-002 owner policy delta — 2026-11-06

- Owner decisions via `signvoice-17`, relayed by `signvoice-21`: F-003 trial starts ONLY on explicit **Start**, with no login/restore/browsing auto-start; F-004 the same identity allowance persists across logout AND `newGuest`, including expiry, with no renewal/reset; F-005 guest can delete OWN conversations THROUGH UI, including after expiry; deny nonowned/anonymous access.
- These replace pending decisions, not source/test evidence: F-003..F-005 remain **UNFIXED** discrepancies, runtime/test execution **NOT_RUN**; audit remains **BLOCKED** for execution evidence. Owner decisions are not code fixes or execution evidence. SPEC/API/policy files stay unchanged.
- Original Luna provenance and historical reviewer PASS 2/2 above remain history. User authorized a NEW policy-delta review cycle, maximum 2 rounds, not old round 3. Delta verdict is recorded externally in AO; no delta PASS is claimed. All metadata is prepared before review; no file edits after PASS.
- Delta worker `signvoice-25`: coordinator `signvoice-21` verified native `turn_context` `rollout-2026-11-06T21-03-59-01a1b12c-6537-79b3-a6f3-b14ceb6b7084.jsonl:10`, timestamp `2026-11-06T14:04:02.888Z`, `gpt-6.1-sol` / `medium`; user/orchestrator informed before assignment. Only the two assigned docs in `signvoice-21` are edited; worker worktree remains untouched. This step runs no QA/runtime/tests/analyze/build/apps/API/AI/browser/fixtures/install and makes no source/test/package/lock/Excel changes or commit/push/merge/PR.

## qa/us-002-guest-trial-runtime — US-002 runtime acceptance

Status: `TODO` — planning only; runtime acceptance incomplete, no execution authorized in this documentation step.

Objective: verify US-002 from Backend to Flutter UI against the settled owner decisions, with isolated QA evidence; record current-policy failures without repairing product code/tests to force PASS.

Scope: US-002 routes/services/validation/auth/session/guest ownership/error handling and its Flutter UI/navigation/trial/device-stream behavior only. Future reporting edits are limited to this task and `docs/active/US-002_GUEST_TRIAL_AUDIT.md`. Source/tests/package/lock/SPEC/API/policy/Excel, diagrams, installs, migrations/seed/cleanup on user data, commit/push/merge/PR and other US are out of scope. Do not change `backend/src/routes/sign-collection.routes.ts` or user edits; existing tests are read/run only.

Concrete existing inputs (read only, no broad scan): `.agents/AGENT.md`, `docs/SPEC.md`, `docs/TASKS.md`, `docs/BASELINE.md`, `docs/active/US-002_GUEST_TRIAL_AUDIT.md`, `docs/active/GUEST_TRIAL_POLICY_20261024.md`, `docs/active/API_ENDPOINT_REFERENCE.md`; reuse the exact Backend/Flutter/Test file list in `audit/us-002-guest-trial` above, following only US-002-related imports/calls when needed. The audit's F-003..F-005 source/test locations are reproduction starting points, not a correct policy oracle; settled owner decisions define expectations.

Prerequisites (DEFINE ONLY; do not create/probe/install now):

- Future worker MUST use project-default **Codex GPT-6.1-Sol Medium** (`gpt-6.1-sol` / `medium`), no substitute or model override. Spawn WAIT ONLY; coordinator must verify actual native `turn_context` model AND effort and report both to user/orchestrator BEFORE assignment/start. Default configuration or session display alone is insufficient.
- Healthy preprovided Flutter/Dart/Node/npm and existing dependencies; missing prerequisites mean **BLOCKED**, no installation/repair. Isolated QA database/services with a specified base URL, separate from user/live data.
- Preprovided QA guest/permanent identities, tokens, cookies and stable device key for same-identity logout/newGuest checks; own/nonowned conversation data and anonymous cases. Never expose actual secrets or identity keys in evidence.
- Available browser/device/emulator for mobile/web, camera/micro permissions and QA AI gateway/streams; preprovided API/AI error/delay fixtures for offline/slow/timeout/401/403/500. Define fixture configuration and limits only in this step; create/run none now.

Future acceptance (all currently **NOT_RUN**, not complete):

- Entry, public browsing and restore remain untimed until explicit **Start**; no start at login/restore/mount/resume. After Start, **600 seconds by server time**; repeated/concurrent Start, refresh, reload and re-entry do not extend expiry. Compare server timestamps and UI countdown.
- Expired allowance survives logout AND `newGuest` for the same identity/cookie/device key, with no renewal/reset. Check expiry/public/session boundaries, access tokens, trial ticket purpose/TTL, validation and response errors.
- Active/expired guest deletes own conversations THROUGH UI and verify API/persistence; deny nonowned/anonymous read/delete including individual/bulk where supported. Keep read/export/delete-all checks separate; one endpoint does not prove another. Retain personal write restrictions within US-002 scope.
- Retain guest-to-permanent conversion and ownership checks, AI ticket/expiry/upstream closure, camera/micro/stream stop and draft behavior at expiry; verify no transmission continues after expiry, distinguishing widget fixtures from real device evidence.
- UI navigation/deep links/back/forward/reload, consent/restore old/new choices, loading/empty/error/retry; mobile/web sizes 360x800, 390x844, 768x1024, 1440x900; text scale 100/150/200%, keyboard/focus, contrast and semantics/screen reader. Execute existing widget tests; record device/browser limitations.
- Offline/slow/timeout/401/403/500 API/UI/AI fixtures and retry: verify fail-closed/session handling, loading termination, usable navigation, distinct empty/error states and stream lifecycle. Source inspection or fixtures alone cannot establish real device acceptance.

Exact FUTURE commands, after runtime assignment and prerequisites only; DO NOT execute in this documentation step:

- Directory `backend/`: `npm run typecheck`; `npm run lint`; `npm test -- tests/guest-trial.test.ts tests/auth.test.ts tests/auth-security.test.ts tests/ai-public-proxy.test.ts`. Vitest: no Jest `--runInBand`.
- Directory repository root: `flutter analyze`; `flutter test --no-pub test/guest_trial_test.dart test/auth_test.dart test/guest_preferences_test.dart test/public_startup_session_test.dart test/web_account_navigation_test.dart test/api_navigation_latency_test.dart`.
- Directory root for documentation handoff: `git diff --check`; `git diff -- docs/TASKS.md`; read untracked audit separately and `git status --short`. Never change tests/config to hide baseline failures.

Evidence/report destination: update `docs/active/US-002_GUEST_TRIAL_AUDIT.md`, summarize here and in AO. Record each command/directory, exit code, pass/fail/skip counts (or no test cases executed), timestamp/environment/branch/HEAD. Each case needs steps, owner-policy expected behavior, actual result/status, sanitized API requests/responses/server timing and UI screenshots/reproduction/stream evidence as available; remove tokens/cookies/device keys/PII. Reproduced current-policy discrepancies are **FAIL**, not repaired to force PASS; missing prerequisites **BLOCKED**, unexecuted cases **NOT_RUN**. Separate baseline/history from new results. Worker/reviewer reports stay under 10 lines. Runtime review follows a later assignment; do not spawn reviewers here. Keep TODO and audit BLOCKED until execution evidence and review/owner disposition of limits exist; planning is not DONE or runtime acceptance.

## Báo cáo worker/reviewer

audit/us-002-guest-trial — Điều phối/review (2026-11-06): Reviewer sạch `signvoice-24` (native `gpt-6.1-sol`/`medium`) PASS tài liệu vòng 2/2 sau khi đối chiếu source và transcript độc lập. Chỉ `docs/TASKS.md` và `docs/active/US-002_GUEST_TRIAL_AUDIT.md` đổi; `git diff --check` PASS. Không test nào thực thi, không nghiệm thu API/UI; Tại handoff cũ F-003..F-005 còn chờ quyết định; nay owner đã chốt ở policy delta bên dưới, source/test vẫn UNFIXED, toolchain/QA/runtime còn mở. Task BLOCKED; không sửa source/test/package/Excel, không commit/push/merge/PR. Hash snapshot được review ghi tại cuối báo cáo audit; cập nhật sau review chỉ ghi trạng thái/kết quả bàn giao.

T-001 — Reviewer (session sạch, 2026-11-05): PASS. NIT: khi chạy bằng Windows PowerShell 5.1, `2>&1` làm output có dòng nhiễu `System.Management.Automation.RemoteException`; không ảnh hưởng kết quả/exit code. Lưu ý: máy không có `pwsh`, đã chạy bằng `powershell -File scripts/check.ps1`.

T-002 — Worker (2026-11-05): Đã thêm `{ }` tại `test/guest_preferences_test.dart:16`; `flutter analyze test/guest_preferences_test.dart` (0 issues), `flutter test test/guest_preferences_test.dart` (2/2 pass); rủi ro: không.
T-002 — Reviewer CLI `codex exec --ephemeral` (session sạch, 2026-11-05): PASS. Diff đúng phạm vi (`test/guest_preferences_test.dart`, `docs/TASKS.md`), không còn warning `curly_braces_in_flow_control_structures`, không phát sinh warning/error mới, test pass 2/2.

Worker phải báo cáo: đã làm gì; file đổi; lệnh và kết quả; rủi ro. Reviewer phải báo cáo: PASS hoặc BLOCKER/SHOULD FIX/NIT và lý do ngắn.
