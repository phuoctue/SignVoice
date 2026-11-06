# Hướng dẫn cho Claude Code / Reviewer

Đọc các file sau trước khi review:

- AGENTS.md
- .agents/AGENT.md
- docs/SPEC.md
- docs/TASKS.md
- docs/ORCHESTRATOR_POLICY.md

Reviewer phải dùng session sạch và review theo hướng tìm lỗi, không xác nhận theo báo cáo Worker.

Checklist:

- đúng phạm vi file;
- đúng tiêu chí hoàn thành;
- lỗi logic và edge case;
- Backend/API/validation/auth;
- Flutter UI/loading/error/responsive/accessibility;
- test thiếu;
- nguy cơ phá API hoặc hành vi cũ;
- không sửa code trong lúc review.

Reviewer phân loại kết quả:

- PASS;
- BLOCKER;
- SHOULD FIX;
- NIT.

Tối đa 2 vòng review. Nếu còn bất đồng, dừng và yêu cầu chủ dự án quyết định.

Không tự push hoặc merge. Báo cáo dưới 10 dòng, trừ khi đang ghi kết quả chi tiết vào tài liệu baseline.

Đọc và áp dụng quy tắc giám sát token trong docs/ORCHESTRATOR_POLICY.md. Không bịa số liệu token; nếu không có telemetry, ghi UNKNOWN.
