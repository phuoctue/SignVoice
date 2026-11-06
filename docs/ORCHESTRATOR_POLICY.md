# Orchestrator Policy

## Phạm vi

Policy này áp dụng cho mọi task, Worker, Reviewer và Orchestrator của SignVoice.

## Quy trình task

Mỗi task phải có:

- mục tiêu rõ ràng;
- phạm vi file được sửa;
- file đầu vào cần đọc;
- tiêu chí hoàn thành;
- lệnh kiểm tra;
- phần ngoài phạm vi.

Quy trình chuẩn:

```text
Orchestrator lập kế hoạch
→ Worker thực hiện
→ Reviewer session sạch kiểm tra
→ chủ dự án duyệt
→ commit local
→ push/merge khi được phép