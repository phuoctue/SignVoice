# Hồ sơ phát hành Facebook Login — SignVoice

Trạng thái: **website đã có HTTPS công khai; Facebook Login chưa được Meta phát hành**. Không đánh dấu đã xác minh doanh nghiệp hoặc đã xét duyệt nếu Meta chưa xác nhận.

Người vận hành do chủ dự án xác nhận: **Trí**. Email hỗ trợ công khai: **trivo2k0@gmail.com**.
Chủ dự án xác nhận **chưa có doanh nghiệp đăng ký pháp lý**; mục business verification vẫn chưa hoàn tất.

## 1. Website HTTPS

Conveyor CLI đã được tải vào `.tools/conveyor/conveyorcli.exe`; .NET runtime đã có.
Chủ dự án đã xác nhận mở UI/API/AI qua Conveyor với Atlas hiện tại. Tunnel đang chạy:
**https://newshinydart76.conveyor.cloud**.
Đã xác nhận HTTP 200 cho giao diện, `/privacy`, `/data-deletion`, backend readiness và AI health qua Internet.
Endpoint Facebook start trả 302 với callback HTTPS đúng origin; cookie OAuth có Secure, HttpOnly, SameSite=Lax.
Chưa có cấu hình nào được lưu lên dashboard Meta từ phiên làm việc này và chưa hoàn tất một lần chấp thuận Facebook thật trên URL HTTPS mới.

Sau khi có xác nhận và đã đăng nhập tài khoản Conveyor, chạy tại gốc repo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-service.ps1 -Python .\.tools\python311\python.exe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-signvoice.ps1 Public
```

Nếu cần đăng nhập Conveyor, chủ tài khoản chạy trực tiếp:

```powershell
.\.tools\conveyor\conveyorcli.exe config -s
```

Không gửi mật khẩu Conveyor qua chat. Nếu chưa có tài khoản, đăng ký ở trang Conveyor.
Tunnel phụ thuộc máy này, kết nối mạng và tiến trình đang chạy. Trước khi nộp xét duyệt, phải duy trì URL ổn định và truy cập được trong suốt thời gian Meta kiểm tra.

## 2. Các giá trị cấu hình Meta

Hiện dùng `ORIGIN = https://newshinydart76.conveyor.cloud`, không thêm dấu `/` ở cuối.
Nếu Conveyor cấp hostname mới, cập nhật tất cả URL trên Meta/Google theo origin mới trước khi thử đăng nhập.

| Trường trên Meta | Giá trị |
| --- | --- |
| Tên ứng dụng | SignVoice |
| App domains | Chỉ hostname của ORIGIN, không có `https://` hoặc đường dẫn |
| Website / Site URL | ORIGIN |
| Privacy policy URL | ORIGIN/privacy |
| User data deletion — instructions URL | ORIGIN/data-deletion |
| Valid OAuth redirect URIs | ORIGIN/api/v1/auth/oauth/facebook/callback |
| Quyền sử dụng | public_profile, email |

Chọn kiểu **hướng dẫn xóa dữ liệu** nếu dashboard có lựa chọn đó. Không nhập trang HTML `/data-deletion` vào ô **data deletion callback**, vì bản này chưa triển khai callback signed_request tự động của Meta.

Script Local/Public tự gán WEB_ORIGIN, CORS, hai OAUTH origin và callback theo origin của lần chạy. Không cần ghi đè localhost bằng một URL tunnel cũ trong `.env`.
Trong Google Cloud phải đăng ký thêm ORIGIN/api/v1/auth/oauth/google/callback nếu dùng Google trên bản public.

## 3. Chính sách và xóa tài khoản

Trong `backend/.env`, cần xác nhận thông tin công khai:

```dotenv
PRIVACY_OPERATOR_NAME=Trí
SUPPORT_EMAIL=trivo2k0@gmail.com
```

Thông tin trên đã được áp dụng trên bản public. Khi thiếu thông tin trong lần triển khai khác, `/privacy` và `/data-deletion` trả HTTP 503 cùng nội dung **BẢN NHÁP**, không nên gửi Meta xét duyệt.
Chủ dự án còn phải xác nhận chính sách lưu log/bản sao lưu và cập nhật nội dung chính sách cho đúng cách vận hành thực tế.

Luồng tự xóa đã triển khai: Cá nhân → Quyền riêng tư → Xóa tài khoản → xác nhận.
API `DELETE /api/v1/users/account` chỉ nhận danh tính từ bearer session, không tin userId trong request.
Một transaction xóa user, phiên, cài đặt, hội thoại, mục yêu thích, lịch sử và audit của user; lỗi ở bất kỳ bước nào sẽ rollback.
Không thực hiện xóa trên tài khoản người dùng thật khi kiểm thử. Kiểm thử tự động dùng database `signvoice_test_*` riêng.
Không tự xóa nội dung từ điển công khai đã được nhân sự tạo. File log và bản sao lưu không thuộc transaction xóa database.

## 4. Nội dung dự thảo cho xét duyệt

Mô tả ứng dụng:

> SignVoice hỗ trợ giao tiếp bằng ngôn ngữ ký hiệu, văn bản và giọng nói. Người dùng có thể đăng nhập, sử dụng từ điển ký hiệu và quản lý dữ liệu cá nhân. Facebook Login cung cấp phương thức xác thực tài khoản trong phiên web.

Giải thích quyền:

- `public_profile`: dùng mã định danh Facebook theo ứng dụng và tên để nhận diện đúng tài khoản, tạo hồ sơ SignVoice và duy trì đăng nhập.
- `email`: dùng email nếu Facebook cung cấp để điền hồ sơ và kiểm tra xung đột với tài khoản đã đăng ký. Không giả lập email nếu người dùng không chia sẻ. Bản hiện tại không tự liên kết các tài khoản chỉ vì trùng email.

Hướng dẫn người xét duyệt (điền URL thật trước khi gửi):

1. Mở ORIGIN trong trình duyệt.
2. Vào màn hình Đăng nhập, chọn Facebook và hoàn tất chấp thuận quyền.
3. Xác nhận app mở trang chính với tài khoản vừa đăng nhập; tải lại vẫn giữ phiên.
4. Vào Cá nhân xem hồ sơ và Quyền riêng tư.
5. Trong Quyền riêng tư, chọn Xóa tài khoản và xác nhận; app đăng xuất và phiên cũ không truy cập được.

Chủ app cần quay video thật theo yêu cầu dashboard, thể hiện lần cấp quyền đầu tiên, kết quả hồ sơ, đăng xuất và xóa tài khoản thử. Không dùng video mô phỏng và không cung cấp mật khẩu Facebook thật trong hồ sơ/chụp màn hình.

## 5. Các bước bắt buộc do chủ tài khoản thực hiện

- Xác nhận có doanh nghiệp hợp pháp nếu dashboard yêu cầu business verification; cung cấp giấy tờ thật và hoàn thành xác minh trong Meta. Không tạo doanh nghiệp/giấy tờ giả để qua bước này.
- Điền các URL HTTPS, thông tin pháp lý, contact và nội dung chính sách đã được chủ dự án xác nhận.
- Hoàn tất các mục thử nghiệm, App Review và yêu cầu khác hiển thị trong dashboard; gửi và chờ kết quả Meta.
- Chỉ khi đáp ứng điều kiện, dùng mục **Đăng** để phát hành. Chưa có công cụ kết nối Meta Developers trong phiên này để thay chủ tài khoản nộp hoặc phát hành.
- Kiểm tra bằng một tài khoản Facebook không có vai trò trong app sau khi được Meta cho phép hoạt động công khai. Chỉ một phản hồi chuyển hướng 302 từ backend chưa chứng minh đăng nhập hoàn chỉnh hoặc việc được Meta phê duyệt.

Đã kiểm tra: backend build; 30 kiểm thử OAuth, account deletion và public information đạt trên database thử riêng. Kiểm thử có kiểm tra session cũ bị vô hiệu, không xóa tài khoản khác, rollback khi storage lỗi, và escape HTML trên trang thông tin.
