# Tạo bản dự án trên GitHub của riêng anh

Tạo repository mới trong tài khoản anh giúp anh quản lý quyền truy cập và tiếp tục phát triển độc lập. Việc sao chép hoặc đổi Git remote không tự chuyển bản quyền của code, video, dữ liệu hoặc model của người khác.

## Tách toàn bộ các nhánh và lịch sử đang có trên GitHub

1. Tạo repository **Private, trống** trong tài khoản anh. Không khởi tạo README để bản sao đẩy lên một repo trống; không thêm chủ repo cũ làm collaborator.
2. Thực hiện trong một thư mục mới, sau khi đã kiểm tra quyền sử dụng/chuyển giao mã nguồn:

```powershell
git clone --bare https://github.com/phuoctue/SignVoice.git SignVoice-copy.git
git -C SignVoice-copy.git push --mirror https://github.com/TAI_KHOAN_CUA_ANH/SignVoice.git
```

Lệnh mirror này sao chép các nhánh/tag/lịch sử trên GitHub vào repository trống mới. Chỉ dùng cho repository đích trống, vì mirror có thể ghi đè/xóa các refs đã có ở đích. Đây là bản sao độc lập trên GitHub; lịch sử vẫn ghi nhận tác giả đã đóng góp.

3. Để thư mục làm việc hiện tại đẩy vào repo mới, sau khi anh test và chấp nhận các thay đổi local:

```powershell
git remote set-url origin https://github.com/TAI_KHOAN_CUA_ANH/SignVoice.git
git remote -v
```

Thay đổi chưa commit trong máy không nằm trong bản sao từ GitHub. Các thay đổi mật khẩu hiện tại đang được giữ local theo yêu cầu của anh; chưa chạy lệnh sao chép, đổi remote hay push nào trong hướng dẫn này.

## Tách cấu hình và dữ liệu vận hành

- Dùng MongoDB, tài khoản admin, SMTP/Gmail, Google/Facebook OAuth, JWT secrets và tài khoản tunnel do anh quản lý.
- Kiểm tra hostname/repository/model-download URL nào còn trỏ tới dịch vụ của người khác trong cấu hình và tài liệu.
- Media, model AI, `.env`, công cụ và dữ liệu runtime bị Git bỏ qua cần được chuẩn bị/sao chép riêng theo tài liệu setup. Không đưa credentials vào repository mới.
- Nếu dùng Git LFS, cần chuyển cả các LFS objects theo hướng dẫn GitHub; một bản sao chỉ có pointer chưa chứa dữ liệu LFS.

## Quyền sở hữu và giấy phép

Hiện không thấy file LICENSE cho toàn bộ dự án ở thư mục gốc; `backend/package.json` có metadata `license: ISC`, và thư viện/media có thể có điều khoản riêng. Metadata này không đủ để kết luận toàn bộ dự án được chuyển giao độc quyền cho anh. Cần xác minh giấy phép/quyền của từng phần; nếu muốn sở hữu độc quyền phần có sẵn, cần thỏa thuận chuyển giao hoặc quyền sử dụng phù hợp với chủ thể có quyền. Giữ các thông báo bản quyền/giấy phép được yêu cầu; đổi tên repo hoặc xóa lịch sử Git không thay thế việc chuyển giao quyền.

Nguồn chính thức:

- [GitHub — Duplicating a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/duplicating-a-repository)
- [GitHub — Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
