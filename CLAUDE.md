# Hướng dẫn Claude cho SignVoice

@AGENTS.md

- Quy tắc Ponytail dùng chung với Codex nằm trong AGENTS.md; Lead đưa yêu cầu này vào brief coding/review của worker và reviewer, không chỉ bật trong session Lead.
- Chỉ đọc phần task liên quan trong `docs/TASKS.md`.
- Lead phải mở và đọc [policy Lead](docs/CLAUDE_LEAD_POLICY.md) trước khi điều phối, cùng [handoff/source map](docs/CLAUDE_LEAD_HANDOFF.md). Reviewer phải mở và đọc [policy Reviewer](docs/CLAUDE_REVIEW_POLICY.md) trước khi review. Link Markdown không tự nạp nội dung; agent phải thực hiện bước đọc theo vai trò.
- Theo AGENTS.md, mọi vai trò phải đọc `.agents/AGENT.md`, `docs/SPEC.md` và `docs/ORCHESTRATOR_POLICY.md` trước task; import AGENTS.md không tự nạp nội dung các link Markdown bên trong.
- Xác minh branch/HEAD, thay đổi local và quan hệ với `gitlab/dev`; snapshot handoff có thể đã cũ.
- Audit chỉ ghi findings; sửa lỗi là task triển khai riêng.
- Worker và Reviewer không push/merge. Theo [Quy trình task](docs/ORCHESTRATOR_POLICY.md#quy-trình-task), Lead chỉ commit/cherry-pick/merge vào nhánh tích hợp local riêng sau khi chủ dự án duyệt kết quả sau review, gắn với verdict và source ref cụ thể qua chat hoặc quyết định lưu trong task. Duyệt giao task không phải duyệt tích hợp. Lead ghi tham chiếu bằng chứng duyệt; PASS của Reviewer không cấp quyền. Merge vào dev và push remote cần quyền cấp rõ cho task tương ứng; giữ mọi bước duyệt bắt buộc của policy.
- Lead, Worker và Reviewer báo cáo chat dưới 10 dòng: task/source ref, file, kiểm tra/kết quả, số findings theo mức độ, blocker/bước tiếp theo. Chi tiết findings dài đặt trong artifact task và dẫn liên kết; nếu chủ dự án yêu cầu xem trực tiếp thì trình bày đầy đủ trong chat theo yêu cầu.
- Telemetry theo AGENTS.md; khi không có số liệu, ghi UNKNOWN.
