# SignVoice — Baseline kiểm tra

Thời điểm kiểm tra: 2026-11-05, 23:01:53 → 23:05:13 (+07:00).
Commit: `fdf3af0` (nhánh `ao/signvoice-orchestrator`), working tree sạch.

## Lệnh đã chạy

- `npm ci` tại `backend/` (thành công, 462 package; không đổi `package.json`/`package-lock.json`; `node_modules` bị git ignore).
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1` — chạy đúng một lần, exit code **1**. Máy không có `pwsh`.
- Trước T-002: `flutter analyze test/guest_preferences_test.dart` và `flutter test test/guest_preferences_test.dart` (23:07).

## Kết quả `scripts/check.ps1`

| Bước | Kết quả | Chi tiết |
|---|---|---|
| `flutter analyze` | FAIL (exit 1) | 1 issue (info): `test/guest_preferences_test.dart:16:7` — `curly_braces_in_flow_control_structures` |
| `flutter test` | FAIL (exit 1) | 538 pass, 2 skip, 11 fail (tổng 551) |
| `backend npm run typecheck` | PASS (exit 0) | `tsc --noEmit` |
| `backend npm run lint` | FAIL (exit 2) | ESLint 8.57.1 không tìm thấy file cấu hình |
| `backend npm test` | FAIL (exit 1) | 42/42 file không chạy được, "no tests": `tests/setup.ts` yêu cầu `TEST_MONGODB_URI` trỏ tới DB `signvoice_test_*`; biến này chưa được đặt |

Số test: Flutter 538 pass / 11 fail / 2 skip. Backend: không test nào được thực thi (0 pass / 0 fail), do guard môi trường.

## 11 test Flutter đang fail (baseline có sẵn)

- `learning_analysis_test.dart`: changing tabs discards a pending stale analysis
- `learning_analysis_test.dart`: personal analysis is separate from working coach (lm-studio)
- `learning_analysis_test.dart`: personal analysis is separate from working coach (rules)
- `learning_coach_service_test.dart`: dev learning UI labels lm-studio advice without changing progress
- `learning_coach_service_test.dart`: dev learning UI labels rules advice without changing progress
- `sign_ai_test.dart`: camera screen waits for user action and contains no fake result
- `sign_sequence_panel_test.dart`: opens the selected keyframe while retaining chronological images
- `web_account_navigation_test.dart`: guest account menu exposes preferences without profile or schedule
- `widget_test.dart`: dictionary resets a selected topic removed by an administrator
- `widget_test.dart`: dictionary sort resets page and persists through category and search filters
- `widget_test.dart`: dictionary topic selector filters the server catalog on phone layout

## Kiểm tra mục tiêu cho T-002 (trước khi sửa)

- `flutter analyze test/guest_preferences_test.dart`: exit 1, đúng 1 info `curly_braces_in_flow_control_structures` tại dòng 16:7; không có warning/error khác.
- `flutter test test/guest_preferences_test.dart`: exit 0, 2/2 test pass. Test mục tiêu **không** fail từ baseline.

## Phân loại

- **Liên quan T-002:** chỉ lint `curly_braces_in_flow_control_structures` tại `test/guest_preferences_test.dart:16:7`.
- **Không liên quan T-002 (baseline có sẵn, không sửa):**
  - 11 test Flutter fail ở trên (không có test nào nằm trong `guest_preferences_test.dart`).
  - Backend lint: thiếu cấu hình ESLint.
  - Backend test: thiếu `TEST_MONGODB_URI` (không tự đặt để tránh trỏ nhầm DB).
- **Ghi chú:** output chạy bằng Windows PowerShell 5.1 có dòng nhiễu `System.Management.Automation.RemoteException` (NIT của Reviewer T-001, không ảnh hưởng kết quả/exit code).
- **Chênh lệch với ghi chú cũ trong `docs/TASKS.md`:** baseline cũ ghi 538 test chạy; lần này 538 pass + 2 skip + 11 fail. Backend typecheck PASS khớp ghi chú cũ.
