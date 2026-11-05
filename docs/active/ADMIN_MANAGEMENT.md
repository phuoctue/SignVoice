# Quản trị và role tùy chỉnh

Tab **Quản trị** là tab thứ năm của navbar. Dashboard và các trang quản lý nằm riêng với **Cá nhân**. Tài khoản có quyền `admin:access` mới thấy tab này; mỗi module yêu cầu quyền đọc tương ứng.

## Sử dụng

1. Đăng nhập admin, mở **Quản trị → Role & phân quyền → Thêm mới**.
2. Điền tên, mã duy nhất (ví dụ `CONTENT_EDITOR`), mô tả và chọn quyền. Chọn **Truy cập tab Quản trị** nếu cần dùng dashboard. Chọn quyền xem cho module cần mở và quyền sửa nếu cần thao tác.
3. Mở **Tài khoản**, tạo tài khoản mới hoặc chỉnh sửa tài khoản có sẵn và chọn role vừa tạo.
4. Tạo **Danh mục** đang hoạt động, sau đó thêm **Từ điển** với từ/cụm từ, định nghĩa, URL video và danh mục.
5. Lưu **Bản nháp**, kiểm tra ở **Duyệt nội dung**, rồi chuyển **Đã xuất bản**. Trang Từ điển của người dùng lấy dữ liệu cloud và chỉ hiển thị mục đã xuất bản; bấm video để mở URL video.

Các danh sách tài khoản, từ điển và phiên có phân trang. Tài khoản và từ điển có tìm kiếm, lọc trạng thái. Phiên đăng nhập có thể thu hồi để yêu cầu thiết bị đăng nhập lại. Yêu thích trong giao diện hiện vẫn lưu trong phiên ứng dụng.

## Bộ quyền

| Quyền | Tác dụng |
|---|---|
| `admin:access` | Truy cập khu vực Quản trị |
| `staff:access` | Truy cập khu vực nhân viên |
| `users:read` / `users:write` | Xem / tạo, sửa, vô hiệu hóa tài khoản và gán role |
| `roles:read` / `roles:write` | Xem / tạo, sửa, xóa role tùy chỉnh |
| `dictionary:read` / `dictionary:write` | Xem toàn bộ / tạo, sửa, xóa mục từ |
| `content:publish` | Xuất bản và sửa/xóa nội dung đã xuất bản |
| `categories:read` / `categories:write` | Xem / tạo, sửa, xóa danh mục |
| `sessions:read` / `sessions:write` | Xem / thu hồi phiên đăng nhập |

Ví dụ biên tập viên dùng `admin:access`, `dictionary:read`, `dictionary:write`. Người duyệt thêm `content:publish`. Người quản lý tài khoản dùng `admin:access`, `users:read`, `users:write`; danh sách role để gán chỉ gồm các role có quyền nằm trong bộ quyền người quản lý.

## Quy tắc quản lý

- `USER`, `STAFF`, `ADMIN` là role hệ thống cố định. Các role tạo mới có thể đổi tên, mã, quyền và xóa.
- Role tùy chỉnh lưu trong `roles`; tài khoản tham chiếu bằng `customRoleId`. Backend đọc quyền hiện tại từ database ở mỗi request, kể cả khi JWT đã được cấp trước khi đổi quyền.
- Không thể cấp hoặc quản lý bộ quyền cao hơn quyền đang có. Không thể tự đổi role, khóa hoặc xóa tài khoản đang dùng. Khi sửa role của chính mình, không được bỏ quyền truy cập hoặc quản lý role.
- Role đang được gán cho tài khoản không thể xóa. Cần chuyển các tài khoản đó sang role khác trước.
- Xóa tài khoản là vô hiệu hóa và thu hồi phiên. Email vẫn được giữ trong database.
- Danh mục còn chứa mục từ hoặc danh mục con không thể xóa. Chuyển/xóa nội dung trước, hoặc lưu trữ danh mục.
- Từ điển mới mặc định là bản nháp. Chuyển trạng thái xuất bản, lưu trữ hoặc xóa đồng bộ số mục đã xuất bản của danh mục.
- Các API cũ ở `/dictionary` và `/staff/content` cũng kiểm tra quyền; sửa bản nháp qua API cũ không thể chèn trạng thái để vượt quyền xuất bản.

API và cấu trúc dữ liệu: `backend/docs/openapi.yaml`. Tests backend dùng MongoDB local dành cho kiểm thử, không chạy bộ test trên Atlas đang phục vụ web.
