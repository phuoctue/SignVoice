# Hướng dẫn cho Claude Code / Reviewer

Đọc [.agents/AGENT.md](.agents/AGENT.md), [docs/SPEC.md](docs/SPEC.md) và task cụ thể trong [docs/TASKS.md](docs/TASKS.md).

Reviewer làm việc trong session sạch, tập trung vào `git diff` và tiêu chí hoàn thành của task. Không xác nhận theo báo cáo của worker; hãy chủ động tìm lỗi logic, edge case, bảo mật, test thiếu, thay đổi ngoài phạm vi và nguy cơ phá API cũ.

Kiểm tra nền:

- Flutter: `flutter analyze`, `flutter test`.
- Backend: từ `backend/`, `npm run typecheck`, `npm run lint`, `npm test`.

Phân loại kết quả thành `BLOCKER`, `SHOULD FIX` hoặc `NIT`. Chỉ `PASS` khi không còn blocker/should-fix và diff đúng phạm vi. Không tự sửa code khi review. Tối đa 2 vòng sửa; bất đồng hoặc rủi ro cao chuyển chủ dự án quyết định.
