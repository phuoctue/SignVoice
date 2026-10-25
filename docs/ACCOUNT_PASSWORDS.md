# Đổi mật khẩu tài khoản

## Người dùng tự đổi

Đăng nhập tài khoản email → **Cá nhân → Đổi mật khẩu**. Chức năng dùng chung cho USER, STAFF và ADMIN.

1. Nhập mật khẩu hiện tại.
2. Nhập mật khẩu mới: 8–128 ký tự, gồm chữ cái và số, khác mật khẩu cũ.
3. Nhập lại chính xác mật khẩu mới → **Lưu mật khẩu mới**.

Mỗi ô có nhãn, hướng dẫn nhập và nút hiện/ẩn mật khẩu. Nhập lại chưa khớp hoặc mật khẩu mới chưa hợp lệ sẽ chưa gửi API. Nếu mật khẩu hiện tại sai, hiển thị lỗi để thử lại và giữ phiên đăng nhập. Khi đổi thành công, thu hồi các phiên cũ và yêu cầu đăng nhập lại bằng mật khẩu mới trên các thiết bị.

API hiện có: `POST /api/v1/auth/change-password`, body gồm `currentPassword`, `newPassword`. Xác nhận nhập lại thực hiện trên giao diện; giữ nguyên hợp đồng API.

Tài khoản Google/Facebook đổi mật khẩu ở nhà cung cấp tương ứng. Tài khoản dùng thử cần tạo tài khoản email trước.

## Admin đặt lại cho tài khoản khác

**Quản trị → Tài khoản → Thao tác → Đặt lại mật khẩu**. Nhập mật khẩu mới hai lần rồi lưu. Hộp thoại hiển thị tài khoản đích và thông báo thu hồi phiên đăng nhập cũ.

- Chỉ admin có quyền `users:write` được thực hiện; không quản lý được tài khoản có quyền cao hơn quyền đang có.
- Chỉ đặt lại cho tài khoản email trong hệ thống, gồm USER/STAFF/ADMIN mà người thao tác đủ quyền quản lý. Tài khoản Google/Facebook, dùng thử và đã xóa không có thao tác này.
- Tự đổi mật khẩu của admin vẫn cần xác nhận mật khẩu hiện tại qua mục Cá nhân.
- Tài khoản bị khóa vẫn giữ trạng thái khóa sau khi đặt lại mật khẩu.
- Lưu mật khẩu băm, tăng `passwordVersion`, thu hồi access/refresh sessions và hủy liên kết đặt lại mật khẩu trước đó trong cùng giao dịch. Ghi audit người thao tác/tài khoản đích, không ghi mật khẩu.
- Lỗi khi lưu cho phép thử lại; đăng xuất hoặc đổi phiên quản trị sẽ đóng hộp thoại để bảo vệ dữ liệu đang nhập.

API: `POST /api/v1/admin/users/:id/password`, body `{"newPassword":"<mật khẩu mới>"}`. Backend không trả mật khẩu/mật khẩu băm trong phản hồi. Người dùng đích cần đăng nhập lại bằng mật khẩu mới; phiên của admin đang thao tác được giữ.
