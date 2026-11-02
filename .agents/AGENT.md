Dự án SignVoice sử dụng Flutter cho Mobile/Web.

Quy tắc khi thực hiện các task tiếp theo:
- Chỉ đọc file liên quan, không quét toàn bộ dự án nếu không cần.
- Tận dụng code và kiến trúc hiện tại, tránh refactor không cần thiết.
- Giữ nguyên business logic, API, database và chức năng đang hoạt động.
- Chỉ sửa lỗi xác định được, ưu tiên thay đổi nhỏ và an toàn.
- Không cài package mới nếu chưa thực sự cần.
- Kiểm tra bằng các lệnh phù hợp sau khi sửa.
- Trả lời ngắn gọn: lỗi phát hiện, file đã sửa, kết quả kiểm tra và vấn đề còn lại.
- Không tạo báo cáo dài hoặc giải thích code không cần thiết.

Quy tắc README và phát hành theo yêu cầu của chủ dự án / GitHub Support:
- Không thêm link tải APK, EXE, ZIP hoặc file nhị phân/thực thi vào bất kỳ README nào; không thêm link tải từ dịch vụ chia sẻ file hay tunnel tạm như Conveyor.
- Không đưa đường dẫn bản cài đặt trên máy phát triển vào README. Giữ các liên kết tài liệu, mã nguồn và thông tin nguồn/giấy phép hợp lệ.
- File cài đặt chỉ được phân phối bằng GitHub Releases khi chủ dự án yêu cầu phát hành; không tự tải binary lên repository hoặc Releases.
- Trước khi commit/push, chạy `node scripts/check-readme-download-links.cjs`; trước khi push phải kiểm tra cả nội dung commit bằng `node scripts/check-readme-download-links.cjs --ref HEAD`.
- Hook `.githooks/pre-push` kiểm tra các commit thực sự được đẩy. Không bỏ qua hook bằng `--no-verify` hoặc vô hiệu hóa kiểm tra để đẩy link bị cấm.
- Trên checkout mới, bật hook bằng `git config --local core.hooksPath .githooks` và cấp quyền thực thi cho `.githooks/pre-push` nếu hệ điều hành yêu cầu.
