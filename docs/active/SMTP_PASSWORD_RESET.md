# Khôi phục mật khẩu qua Gmail SMTP

Luồng: Đăng nhập → Quên mật khẩu → nhập email → mở liên kết trong thư → đặt mật khẩu mới.
Chỉ tài khoản LOCAL đang hoạt động có thể nhận thư. Địa chỉ email cần là hộp thư thật bạn truy cập được.
Tài khoản demo `admin@signvoice.com` không phải Gmail của bạn; muốn nhận thư cho tài khoản này cần có quyền truy cập hộp thư đó.

## Cấu hình

Trong tài khoản Google dùng gửi thư, bật xác minh hai bước rồi tạo App Password:
https://myaccount.google.com/apppasswords
Hướng dẫn Google: https://support.google.com/accounts/answer/185833

Điền trực tiếp trong `backend/.env` (file đã được Git bỏ qua):

```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-google-app-password
SMTP_FROM="SignVoice <your-email@gmail.com>"
PASSWORD_RESET_ORIGIN=
```

SMTP_PASS là App Password, không phải mật khẩu đăng nhập Google. Không đặt các biến SMTP trong Flutter hoặc commit vào Git.
Nếu dùng cổng 587, đặt `SMTP_SECURE=false`; backend bắt buộc STARTTLS. Cổng 465 dùng TLS ngay khi kết nối.

`PASSWORD_RESET_ORIGIN` có thể để trống khi chạy bằng script Conveyor: link lấy từ PUBLIC_ORIGIN.
Nếu frontend chạy riêng, điền origin HTTPS của frontend (không thêm đường dẫn), ví dụ `https://your-link.conveyor.cloud`.
Local development dùng WEB_ORIGIN. Khi Conveyor cấp URL mới, khởi động server với PublicOrigin mới.

## Kiểm tra

Trong thư mục `backend`:

```powershell
npm run smtp:verify
```

Lệnh chỉ kiểm tra kết nối và xác thực SMTP, không gửi email. Sau khi cấu hình thành công,
khởi động lại server public tại thư mục gốc dự án:

```powershell
.\scripts\stop-public-server.ps1
.\scripts\start-public-server.ps1 -SkipBuild -PublicOrigin https://your-link.conveyor.cloud
```

Đăng ký một tài khoản SignVoice bằng email thật, rồi dùng Quên mật khẩu để nhận thư.
SMTP_USER là người gửi; email nhập trên màn hình là người nhận và phải trùng email tài khoản.
Kiểm tra Spam nếu không thấy thư. Nếu SMTP chưa cấu hình, màn hình sẽ báo chưa khả dụng.
Nếu SMTP gửi thất bại, xem thông báo `Password reset email delivery failed` trong log; không ghi mật khẩu hoặc token vào log.
API trả cùng thông báo cho email không tồn tại và yêu cầu hợp lệ để tránh lộ danh sách tài khoản.

## API và bảo vệ liên kết

- `POST /api/v1/auth/forgot-password`: `{ "email": "your-email@gmail.com" }`.
- `POST /api/v1/auth/reset-password`: `{ "token": "64 ký tự hex", "newPassword": "NewPassword123" }`.
- Token ngẫu nhiên 32 byte, chỉ lưu SHA-256 trong MongoDB, hết hạn sau 15 phút, dùng một lần.
- Mỗi tài khoản nhận tối đa một yêu cầu trong 60 giây; liên kết mới thay thế liên kết cũ.
- Đặt mật khẩu và tiêu thụ token thực hiện bằng một cập nhật MongoDB nguyên tử.
- Tăng passwordVersion và thu hồi toàn bộ phiên cũ; phiên phát sinh đồng thời từ mật khẩu cũ cũng không dùng được.
- Token nằm trong fragment `/#/reset-password?token=...`, không xuất hiện trong HTTP request URL hoặc referrer.
- Có giới hạn 30 yêu cầu khôi phục/đặt lại trong 15 phút cho mỗi IP kết nối backend.
  Với Conveyor, nhiều người có thể chung IP proxy. Giới hạn IP dùng bộ nhớ một tiến trình;
  khi chạy nhiều backend cần shared rate-limit store và cấu hình proxy phù hợp.

App Password thiếu: cấu hình SMTP_PASS. Lỗi EAUTH: kiểm tra đúng Gmail và App Password.
Lỗi ETIMEDOUT/ESOCKET: kiểm tra mạng/firewall và cổng 465/587. Không tắt xác minh TLS để khắc phục.
