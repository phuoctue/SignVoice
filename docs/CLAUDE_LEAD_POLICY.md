# Claude Lead

## Brief và ngân sách đọc

- Mỗi brief ghi mục tiêu, base commit, file đầu vào/được sửa, ngoài phạm vi, dependency, rủi ro, skill, tiêu chí chấp nhận và kiểm tra.
- Worker bắt đầu với 3–6 file và phần task liên quan; ngân sách không phải giới hạn cứng. Đọc hướng dẫn bắt buộc riêng; mở rộng để kiểm chứng caller/ownership/bảo mật và ghi lý do. Lead điều phối mở rộng phạm vi sửa.
- Tìm file/symbol bằng rg; chỉ đọc phần cần thiết trong TASKS, log, lockfile và generated code. Tránh đọc/kiểm tra lặp khi source và bằng chứng chưa đổi.

## Chọn model

- Lead dùng model chủ dự án chọn.
- Worker nhỏ, ít rủi ro: model tiết kiệm đủ năng lực, effort low/medium.
- Logic/UI thông thường: coding model, effort medium.
- Auth/session/permission/security/migration/deployment: model mạnh, effort high và reviewer độc lập tương xứng.
- Đây là tiêu chí chọn năng lực model; danh sách thay đổi cần duyệt tay trước merge theo Definition of Done trong docs/SPEC.md, không suy ra từ model/effort.
- Chỉ dùng effort được hỗ trợ; ràng buộc model riêng của task được ưu tiên.
- Dispatch ghi task ID, agent, model ID, effort, worktree, lý do chọn. Chọn model thật sự khả dụng trong Orca và xác minh receipt/runtime. Prompt không tự đổi model; nếu chưa xác minh được phải báo giới hạn. Nâng model khi độ khó hoặc bằng chứng thất bại yêu cầu.

## Skill

- Chọn skill tối thiểu theo task/stack từ catalog session, xác minh SKILL.md tồn tại trước khi giao việc.
- Đọc đầy đủ hướng dẫn đã chọn, chỉ mở reference cần thiết.
- Nếu thiếu skill, báo rõ và chọn phương án phù hợp; không giữ bảng tên skill cố định dễ lỗi thời.

## Điều phối

- Dùng skill Orca CLI/orchestration hiện có và tải hướng dẫn đúng phiên bản trước điều phối. Mỗi worker có worktree riêng khi có thể; bảo toàn thay đổi local. Bắt đầu một worker; chỉ song song khi phạm vi sửa/dependency không chồng lấn.
- Reviewer session sạch nhận brief, base/head, diff và bằng chứng. Review kết quả tích hợp khi ghép task; quyền tích hợp theo CLAUDE.md và policy dự án.
- Khởi chạy Reviewer bằng session mới, không resume/fork lịch sử Worker. Lưu session/launch ID, cấu hình model/effort đã xác minh, prompt đầu vào và base/head trong artifact task. Đối chiếu lịch sử tool mở các file bắt buộc; lời tự khai của Reviewer không thay thế bằng chứng khởi chạy.
