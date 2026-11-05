# Đồng bộ và dọn source — 25/10/2026

Nhánh `dev` đã fast-forward từ `23cd866` đến `390ca74` của `https://github.com/phuoctue/SignVoice.git`. Thay đổi local được sao lưu và ghép lại; không tạo merge commit, không push. Một xung đột fixture được giải quyết bằng cách giữ cả dữ liệu học mới và hỗ trợ guest local. Tham số test trùng được gộp; test DictionaryScreen local được tách khỏi route S22 nay dùng LearningHub.

## Đã dọn

- 43 file nguồn không còn được import:42 Dart và1 TypeScript. Kiểm tra toàn bộ đồ thị import/export/part, bao gồm import có điều kiện web/native, từ `lib/main.dart`, tất cả tests, backend server và scripts. Không xóa file web/native chỉ vì không có import trực tiếp.
- Các màn hình auth/user đời cũ, provider/service/model và file `.g.dart` chỉ phục vụ những màn đó; trang thử ảnh LM Studio và cấu hình riêng của trang thử; proxy backend AI không mount.
- 70 file sinh tự động:69 cache `.pyc` và package-lock.json rỗng ở gốc (không có package.json). Giữ backend/package-lock.json và pubspec.lock.
- 4 file dist còn sót của route AI đã bỏ:JS,source map,declaration,declaration map.
- 5 test backend và3 test Flutter của quiz nhập câu/chấm LM Studio đã lỗi thời, cùng fake service và import chỉ dùng cho các test đó. Người dùng đã yêu cầu bỏ test cũ lỗi. Giữ2 test quiz về auth/enrollment/quyền sở hữu/xóa tài khoản và các test camera hiện hành.

Giữ module phân tích AI, báo cáo thực nghiệm, scripts đánh giá, test dữ liệu/quyền, model181 từ, media từ điển, cấu hình riêng, dependencies, build đang dùng và backup. Việc không nằm trong đường chạy web chưa đủ để coi một script offline là rác.

## Sao lưu phục hồi

- Trước đồng bộ: `.runtime/git-sync-20261024-235553/local-files-before-sync.zip`, baseline/patch; stash `953f4a21282ec7861914ab49d2d2bb45c164f9f5` và ref `refs/backups/dev-sync-20261024-235553`.
- File nguồn/cache đã xóa: `.runtime/source-cleanup-20261025-000543/removed-files.zip`; danh sách/hash/kích thước trong `manifest.json` cùng thư mục.
- Các test lỗi thời trước khi xóa: `.runtime/git-sync-20261024-235553/obsolete-tests-before-removal.zip`.

## Xác minh sau dọn

- Flutter:180 đạt,1 test được bỏ qua sẵn; analyze không lỗi/cảnh báo/info.
- Backend:143 tests/18files đạt trên MongoDB replica set tạm; TypeScript build đạt.
- OpenAPI:79paths,100/100 method/route,độ phủ100%.
- Hand worker JavaScript:33tests đạt trong lượt đồng bộ trước khi dọn (không sửa worker trong đợt dọn).
- Không có file Git unmerged. Các sửa local có chủ ý và các thao tác xóa chưa commit vẫn hiển thị trong git status.

Logs ở `.runtime/source-cleanup-*.log`. Tài liệu BATCH_02 và docs/plan là hồ sơ lịch sử, có thể nhắc tới đường dẫn đã thay thế. Chưa nghiệm thu thao tác microphone/camera trên điện thoại thật trong đợt này.

## Bản chạy local sau đồng bộ

Backend và web đã được cập nhật tại http://localhost:3002 bằng script quản lý local; giữ nguyên tiến trìnhAI. Web release build đạt, file main.dart.js phục vụ khớp bảnbuild. API học mới trả401khi chưa đăng nhập; API từ điển trả3424mục xuất bản ở database hiện tại; không thực hiện import/seed/migration trong đợt này. AI ready,181từ/probability_ensemble. Hash backend/.env giữ nguyên. Bằng chứng `.runtime/source-cleanup-api-smoke.json`.
