# SignVoice — Development Specification

## Mục tiêu

SignVoice là ứng dụng Flutter mobile/web hỗ trợ tra cứu, học và luyện tập ngôn ngữ ký hiệu, kết nối backend Node.js/Express và các dịch vụ AI khi được cấu hình.

## Phạm vi vận hành của orchestrator

- Orchestrator chia task, giữ phạm vi, quyết định merge và cập nhật `docs/TASKS.md`.
- Worker thực hiện thay đổi trong phạm vi file được giao, tự chạy kiểm tra và báo cáo ngắn.
- Reviewer ở session sạch, review diff theo hướng tìm lỗi; không coi báo cáo worker là bằng chứng.

## Definition of Done

- Tiêu chí hoàn thành trong task được đáp ứng.
- Lệnh kiểm tra phù hợp đã chạy và kết quả được ghi lại.
- Không có file ngoài phạm vi bị thay đổi.
- Test/docs được cập nhật nếu hành vi hoặc hợp đồng thay đổi.
- Không tự merge các thay đổi liên quan auth, thanh toán, migration, xóa dữ liệu hoặc dữ liệu nhạy cảm.

## Quy tắc nền

- Một task nên hoàn thành trong một buổi làm việc và một session.
- Không đọc toàn bộ repo nếu task chỉ rõ file đầu vào.
- Tối đa 2 vòng sửa sau review; sau đó dừng để chủ dự án quyết định.
- Đây là nguồn sự thật cấp cao; chi tiết task nằm trong `docs/TASKS.md`.
