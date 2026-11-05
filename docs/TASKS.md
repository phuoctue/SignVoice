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

## Báo cáo worker/reviewer

T-001 — Reviewer (session sạch, 2026-11-05): PASS. NIT: khi chạy bằng Windows PowerShell 5.1, `2>&1` làm output có dòng nhiễu `System.Management.Automation.RemoteException`; không ảnh hưởng kết quả/exit code. Lưu ý: máy không có `pwsh`, đã chạy bằng `powershell -File scripts/check.ps1`.

T-002 — Worker (2026-11-05): Đã thêm `{ }` tại `test/guest_preferences_test.dart:16`; `flutter analyze test/guest_preferences_test.dart` (0 issues), `flutter test test/guest_preferences_test.dart` (2/2 pass); rủi ro: không.
T-002 — Reviewer CLI `codex exec --ephemeral` (session sạch, 2026-11-05): PASS. Diff đúng phạm vi (`test/guest_preferences_test.dart`, `docs/TASKS.md`), không còn warning `curly_braces_in_flow_control_structures`, không phát sinh warning/error mới, test pass 2/2.

Worker phải báo cáo: đã làm gì; file đổi; lệnh và kết quả; rủi ro. Reviewer phải báo cáo: PASS hoặc BLOCKER/SHOULD FIX/NIT và lý do ngắn.
