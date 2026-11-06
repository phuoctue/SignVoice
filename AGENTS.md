# Hướng dẫn cho dự án SignVoice

Đọc [.agents/AGENT.md](.agents/AGENT.md) trước mọi task. Đọc thêm [docs/SPEC.md](docs/SPEC.md) và task cụ thể trong [docs/TASKS.md](docs/TASKS.md); không quét toàn bộ repo nếu task không yêu cầu.

## Cấu trúc

- `lib/`: Flutter mobile/web.
- `test/`, `integration_test/`: kiểm thử Flutter.
- `backend/`: Node.js + TypeScript + Express API.
- `docs/`: đặc tả, hợp đồng và báo cáo dự án.

## Kiểm tra

- Flutter: `flutter analyze`, `flutter test`.
- Backend: từ `backend/`, chạy `npm run typecheck`, `npm run lint`, `npm test`.
- Khi task có lệnh kiểm tra riêng, ưu tiên lệnh trong task.
- Ghi rõ lỗi có sẵn trong báo cáo; không tự mở rộng phạm vi để sửa chúng.

## Quy tắc thay đổi

- Chỉ sửa file trong phạm vi task; không sửa `backend/src/routes/sign-collection.routes.ts` trong task thử nghiệm này vì đang có thay đổi chưa commit của người dùng.
- Không thêm package, đổi API, schema, auth hoặc migration nếu task không yêu cầu.
- Mỗi task dùng branch/worktree riêng khi có thể.
- Trước review phải xem `git diff`, chạy kiểm tra phù hợp và báo cáo dưới 10 dòng.
- Tối đa 2 vòng sửa review; task rủi ro cao cần chủ dự án duyệt tay.

# Quy định Orchestrator

Trước mỗi task, đọc [docs/ORCHESTRATOR_POLICY.md](docs/ORCHESTRATOR_POLICY.md).

Worker phải làm đúng phạm vi task, chạy kiểm tra phù hợp và không tự push/merge.

Audit Backend/UI chỉ ghi nhận findings, không sửa source. Việc sửa lỗi phải là feature task riêng.

Luôn báo cáo trạng thái kiểm tra, blocker và token usage nếu telemetry có sẵn. Không đoán số liệu token khi hệ thống không cung cấp.