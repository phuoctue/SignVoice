# Public SignVoice qua Conveyor

Conveyor CLI nằm tại `.tools/conveyor/conveyorcli.exe` (không commit vào Git).
Tài liệu của nhà cung cấp: https://conveyor.cloud/Home/How_To_Install

## 1. Lưu tài khoản tunnel trên máy

Tạo tài khoản tại https://conveyor.cloud/Account/Register nếu chưa có, sau đó chạy
trong PowerShell tại thư mục dự án:

```powershell
.\.tools\conveyor\conveyorcli.exe config -s
```

Nhập email và mật khẩu trực tiếp vào Conveyor CLI.

## 2. Mở tunnel và lấy Internet URL

```powershell
.\.tools\conveyor\conveyorcli.exe -p 3001i
```

Giữ cửa sổ này đang chạy. Sao chép **Internet URL HTTPS** do Conveyor trả về.
Remote URL có IP riêng là địa chỉ LAN, không phải link Internet.

## 3. Chạy giao diện và API chung một cổng

Trong cửa sổ PowerShell khác, tại thư mục dự án:

```powershell
# Nếu bản server public trước đó vẫn đang chạy:
.\scripts\stop-public-server.ps1

# Thay giá trị dưới đây bằng Internet URL của bạn, không thêm đường dẫn.
.\scripts\start-public-server.ps1 -PublicOrigin https://your-link.conveyor.cloud
```

Script build Flutter với `API_BASE_URL=/api/v1`, build backend và chạy tiến trình
Node nền ở cổng 3001. Giao diện và API cùng origin nên đăng nhập, refresh cookie
và phân quyền hoạt động qua cùng một link. Backend hiện tại ở cổng 3000 được giữ lại.

Nếu vừa build xong và chưa sửa mã nguồn, thêm `-SkipBuild` để dùng bản build đó.

`PUBLIC_ORIGIN` cho phép chính xác origin HTTPS của Conveyor. Nếu Conveyor cấp link
khác ở lần chạy sau, dừng server public và khởi động lại với giá trị mới.

Nếu bật Google/Facebook, đặt `OAUTH_BACKEND_ORIGIN` và `OAUTH_FRONTEND_ORIGIN` trong
`backend/.env` bằng origin HTTPS hiện tại, đồng thời đăng ký lại callback tương ứng
tại Google/Meta khi link thay đổi. Script không thay các cấu hình OAuth này giúp bạn.
Xem [đầy đủ biến môi trường và callback](../active/OAUTH_SETUP.md). Không đưa credentials vào
bản build Flutter. Backend dùng Atlas hoặc MongoDB replica set để hỗ trợ giao dịch.

## Kiểm tra và dừng

Mở Internet URL bằng trình duyệt. Health check nằm tại `/health/ready`.
Log server và PID nằm trong `.runtime/`, được bỏ qua bởi Git.

```powershell
.\scripts\stop-public-server.ps1
```

Nhấn Enter trong Conveyor CLI để đóng tunnel. Link dùng để chia sẻ bản chạy trên
máy này; cần giữ máy, backend, MongoDB và Conveyor đang hoạt động.
