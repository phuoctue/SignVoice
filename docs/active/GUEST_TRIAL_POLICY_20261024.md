# Phiên dùng thử của khách — 24/10/2026

## Căn cứ và thời hạn đã chốt

Đã đọc `E:\WorkSpace\Đồ án chuyên ngành\Mo_ta_du_an_SignVoice_Web_App.docx`. Mục 3, đoạn 66 ghi:

> Khách có thể xem kho công khai và dùng thử một phiên học hoặc phiên dịch.

Đoạn này cũng dành lưu bộ thẻ, đồng bộ tiến độ và quản lý hội thoại cho tài khoản cá nhân. Tài liệu không ấn định số phút. Trong cuộc trao đổi ngày 24/10/2026, chủ dự án chọn **10 phút kể từ khi bắt đầu phiên thử**. Cơ chế dưới đây áp dụng cho những chức năng phiên dịch đang có; không tự triển khai thêm các màn học thẻ/quiz trong tài liệu.

## Hành vi sử dụng

1. Vào Khách rồi xem từ điển, chủ đề, ảnh/video công khai: **chưa tính giờ**.
2. Mở chức năng phiên dịch: hiện lời giải thích và nút **Bắt đầu phiên thử 10 phút**. Camera/micro vẫn cần người dùng cấp quyền riêng.
3. Bấm bắt đầu: máy chủ ghi mốc bắt đầu và kết thúc cách nhau đúng **600 giây**, dùng chung cho camera và Giọng nói → Hình ảnh. Gọi lại, đổi màn hình, tải lại, làm mới token hay tạm rời ứng dụng không gia hạn.
4. Trong phiên có đồng hồ đếm ngược. Khách có thể vào từ điển rồi quay lại trong khoảng thời gian còn lại.
5. Hết hạn: màn nhập camera/micro được tháo khỏi giao diện và dừng thiết bị; gateway đóng kết nối AI đang mở. Màn khóa cho đăng nhập, tạo tài khoản hoặc xem từ điển công khai. Bản nháp văn bản ở bộ nhớ ứng dụng vẫn xem/sao chép được trên màn khóa; không tự lưu lên server.
6. Lưu hội thoại, lưu yêu thích và màn đồng bộ cá nhân yêu cầu tài khoản chính thức. Các đường đọc/xuất/xóa dữ liệu riêng cũ vẫn tôn trọng quyền sở hữu và quyền xóa dữ liệu, kể cả khi phiên thử hết hạn.
7. Đăng ký nâng cấp từ khách giữ ID tài khoản và dữ liệu cũ; tài khoản chính thức không còn hạn 10 phút. Đăng nhập tài khoản khác tuân theo cơ chế tách dữ liệu giữa tài khoản hiện có.

## Cách giữ hạn dùng

- Collection `guest_trials` lưu mã băm của định danh bản cài đặt, `startedAt`, `expiresAt`; không có ảnh, âm thanh, nội dung hội thoại hay email.
- Tài khoản guest tham chiếu bản ghi hạn dùng qua trường không xuất ra DTO công khai `guestTrialId`.
- Trình duyệt dùng cookie HttpOnly `signvoice_guest_device` và định danh ngẫu nhiên của bản cài đặt. Native dùng định danh ngẫu nhiên 32 byte trong SharedPreferences. Đăng xuất giữ định danh này để lần vào Khách tiếp theo nhận cùng hạn cũ, không được cấp thêm 10 phút.
- Tài khoản khách có sẵn được gắn định danh khi kiểm tra/bắt đầu phiên; thời gian không tính từ ngày tạo tài khoản cũ.
- Mốc bắt đầu được cập nhật nguyên tử, nên nhiều yêu cầu đồng thời chỉ tạo một hạn dùng. Máy chủ không nhận `expiresAt` hoặc số phút do client gửi.
- Không đặt TTL xóa bản ghi vừa hết hạn vì xóa sẽ làm cấp lại lượt thử. Bản ghi hạn dùng độc lập với dữ liệu tài khoản để vẫn ghi nhận lượt đã dùng sau đăng xuất/xóa tài khoản.
- Đây là hạn dùng theo định danh bản cài đặt/trình duyệt, không xác minh một người duy nhất trên mọi thiết bị. Xóa toàn bộ cookie/bộ nhớ ứng dụng, dùng trình duyệt ẩn danh hay bản cài đặt khác có thể tạo định danh mới. Không sử dụng IP hoặc dấu vân tay thiết bị để tự suy đoán danh tính.

## Kiểm tra ở máy chủ và đường AI

| Đường gọi | Điều kiện |
| --- | --- |
| `GET /api/v1/guest-trial/status` | Phiên xác thực hợp lệ; đọc trạng thái, không bắt đầu giờ |
| `POST /api/v1/guest-trial/start` | Phiên xác thực hợp lệ; tạo hạn hoặc trả lại hạn cũ |
| `POST /api/v1/guest-trial/ai-ticket` | Khách đang trong hạn hoặc tài khoản chính thức; ticket mở stream có hiệu lực 30 giây |
| `POST /api/v1/sign-sequence` | Có xác thực; khách phải bắt đầu phiên và còn hạn |
| `POST /sign-ai/v1/compose` | Có xác thực; khách còn hạn |
| `WS /sign-ai/v1/stream?ticket=...` | Ticket ký đúng mục đích và phiên còn hợp lệ; đóng cả hai đầu kết nối ở hạn dùng của khách |
| Kho từ điển, danh mục, media, AI health | Vẫn công khai |
| Ghi hội thoại/yêu thích | Tài khoản chính thức |

Các mã lỗi gồm `GUEST_TRIAL_NOT_STARTED`, `GUEST_TRIAL_EXPIRED` (HTTP 403). Hết hạn thử không thu hồi phiên đăng nhập của khách, vì khách còn cần xem kho, xuất/xóa dữ liệu cũ hoặc nâng cấp tài khoản. Thời hạn access/refresh token 15 phút/7 ngày là cơ chế xác thực riêng.

Ticket được bỏ khỏi URL trước khi chuyển tới AI và không ghi vào log; định danh bản cài đặt cũng được che trong log API. Gateway không phân tích hoặc sửa frame, landmark, ngưỡng nhận diện hay model. AI vẫn chạy trên loopback, giữ **181 từ / probability_ensemble**.

## Chạy web và Android

Gateway `/sign-ai` mặc định được gắn trong backend, trước JSON parser và sau CORS. Service AI giữ loopback `127.0.0.1:8001`; truy cập từ app qua gateway có xác thực. Cấu hình `AI_PUBLIC_PROXY=false` sẽ tắt gateway.

Web cùng origin dùng cấu hình build hiện tại:

```powershell
flutter build web --release --no-pub --no-web-resources-cdn --dart-define=API_BASE_URL=/api/v1 --dart-define=AI_SERVICE_URL=/sign-ai
```

Khi chạy riêng frontend/backend hoặc Android emulator, trỏ AI tới gateway của backend:

```powershell
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=AI_SERVICE_URL=http://localhost:3000/sign-ai
flutter run -d <android-device> --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=AI_SERVICE_URL=http://10.0.2.2:3000/sign-ai
```

Máy thật thay `10.0.2.2` bằng IP LAN của máy chạy backend. Khách sử dụng gateway của API hiện tại, kể cả khi còn lưu URL AI cũ ở thiết bị. Không public trực tiếp service loopback để tránh đi vòng kiểm tra hạn dùng.

## Kết quả kiểm tra

- **133 backend tests đạt / 16 files**: hạn đúng 600 giây; bắt đầu đồng thời, refresh và vào lại khách không gia hạn; từ chối sửa hạn bằng payload; vẫn xem kho sau khi hết hạn; nâng cấp tài khoản mở lại chức năng; ticket đúng mục đích; kết nối khách và kết nối AI phía sau đều được đóng.
- **165 Flutter tests đạt, 1 test có cờ cấu hình được bỏ qua**; kiểm tra riêng dừng micro, đóng camera đang khởi tạo, giữ văn bản đang nhận trước khi kết thúc, màn yêu cầu tài khoản và thử lại khi mạng lỗi. Flutter analyze sạch.
- TypeScript, OpenAPI 66 paths / 85 method-route, Flutter Web release và APK debug build đạt.
- Đã kiểm tra API và WebSocket với AI thật bằng tài khoản QA riêng: handshake 181 từ, hạn ban đầu 600 giây, đóng stream theo deadline, sau hết hạn trả 403, từ điển trả 200, vào lại Khách vẫn hết hạn, nâng cấp tài khoản trở thành `unlimited`.
- Để kiểm tra ngắt stream ngay mà không thay hạn dùng của người dùng thật, chỉ deadline của tài khoản QA được rút ngắn trong bước mô phỏng; các tài khoản QA và bản ghi hạn dùng QA được dọn sau kiểm tra.
- Model manifest và bốn file runtime camera giữ nguyên. Không nghiệm thu camera/micro trên điện thoại vật lý hoặc bằng trình duyệt tự động trong đợt này; dùng widget tests và kiểm tra API/AI thật.

Log: `.runtime/guest-trial-*.log`. Bằng chứng API thật: `.runtime/guest-trial-live-verification.json`; mốc bảo toàn model: `.runtime/guest-trial-model-baseline.json`. Các file local này không được đưa vào Git.
