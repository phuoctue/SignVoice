# SignVoice

Flutter Web/Android gửi dữ liệu camera tới **service AI Python riêng cổng 8001**, tách khỏi backend Node.js cổng 3000. Service dùng OpenCV và bộ model Colab 181 từ: kết hợp `embedding_model_v2.keras` với `word_temporal.keras`. **Không cần LM Studio để nhận diện camera**; LM chỉ là tùy chọn xử lý câu. Phát giọng nói dùng TTS trên trình duyệt/thiết bị.

## Cài trên máy khác

Hướng dẫn đầy đủ: **[SETUP_AI.md](docs/SETUP_AI.md)**. Cần Git, Python **3.11 x64**, Flutter stable và Node.js **20+**. Model được tải từ GitHub Release và kiểm tra SHA256; không cần tải dataset TRAIN 46 GB.

```powershell
git clone --branch dev https://github.com/phuoctue/SignVoice.git
cd SignVoice
.\scripts\setup-ai-service.ps1
.\scripts\start-ai-service.ps1
```

Giữ cửa sổ service mở; kiểm tra `http://localhost:8001/health` có `ready: true`, `word_classes: 181`, `word_engine: probability_ensemble`. Mở terminal khác để cấu hình backend theo hướng dẫn, rồi chạy:

```powershell
flutter pub get
.\scripts\run-ai-web.ps1
```

Bản này giữ model 181 từ đang dùng trên máy phát triển, **không tự thay bằng kết quả train mới chưa đạt yêu cầu**. Cài được cùng model không có nghĩa webcam mọi người đạt cùng FPS/độ chính xác: chế độ từ vẫn còn hạn chế trên video kiểm thử thực tế. Xem [báo cáo train gần nhất](docs/TRAIN_RESULT_REVIEW_20261020.md). Các báo cáo camera cũ bên dưới mô tả từng thời điểm; cách cài hiện hành nằm trong SETUP_AI.

**SignVoice** là ứng dụng hỗ trợ giao tiếp ngôn ngữ ký hiệu Việt Nam, bao gồm Flutter Frontend (Android + Web) và Node.js Backend.

## 📚 API Documentation (Swagger)

Backend API đã được tích hợp **Swagger UI** đầy đủ để test và tài liệu hóa.

### Truy cập Swagger UI:

```
http://localhost:3000/api-docs
```

### OpenAPI Specification:

```
http://localhost:3000/api-docs/openapi.json
```

### Tài liệu hướng dẫn:

- **Hướng dẫn test API:** [docs/SWAGGER_TESTING_GUIDE.md](docs/SWAGGER_TESTING_GUIDE.md)
- **Báo cáo tích hợp:** [docs/SWAGGER_INTEGRATION_REPORT.md](docs/SWAGGER_INTEGRATION_REPORT.md)
- **API Reference:** [docs/API_ENDPOINT_REFERENCE.md](docs/API_ENDPOINT_REFERENCE.md)

### Khởi động Backend với Swagger:

```powershell
# 1. Dùng MongoDB Atlas hoặc replica set local
# Xem docs/SETUP_AI.md trước khi khởi động database local.

# 2. Khởi động Backend
cd backend
npm install  # Lần đầu tiên
npm run dev

# 3. Mở Swagger UI
# Truy cập: http://localhost:3000/api-docs
```

**Features:**
- ✅ API được mô tả trong OpenAPI hiện hành
- ✅ JWT Bearer authentication
- ✅ Interactive testing ("Try it out")
- ✅ USER/STAFF/ADMIN role testing
- ✅ OpenAPI 3.0.3 specification
- Kiểm tra độ phủ tài liệu bằng `npm run docs:coverage` trong backend

---

## Flutter Frontend

Giao diện được chuyển từ `D:\Games\SignVoice_Flutter_FE\signvoice_flutter` vào dự án `sign_voice`. Giữ cấu hình nền tảng của dự án hiện tại.

## Chạy ứng dụng

Public bản web bằng Conveyor: [hướng dẫn chạy](docs/CONVEYOR_PUBLISHING.md).

```powershell
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

Để chạy trên Android hoặc nền tảng khác, dùng `flutter devices` rồi `flutter run -d <device-id>`.

## 2. Các luồng đã có

### Đăng nhập JWT và phân quyền

Đăng nhập, đăng ký và dùng thử đã kết nối backend. Flutter nhận `data.user`
và `data.tokens`, gửi access token qua `Authorization: Bearer`, tự làm mới
cả cặp token một lần khi access token hết hạn. Đăng xuất thu hồi cả access
và refresh token của thiết bị hiện tại.

| Vai trò | Quyền truy cập |
| --- | --- |
| USER / Guest | Các màn hình người dùng |
| STAFF | Quyền USER và quản lý nội dung |
| ADMIN | Quyền STAFF và quản trị hệ thống |

Các mục quản lý nằm trong **Cá nhân** và chỉ xuất hiện theo vai trò của tài khoản.
Backend xác minh JWT, phiên đăng nhập, trạng thái và vai trò hiện tại trong MongoDB
trước mỗi API yêu cầu quyền. Đăng ký công khai luôn tạo tài khoản USER.

Chạy web với cổng cố định trong danh sách CORS của backend:

```powershell
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

Đổi địa chỉ API khi chạy trên Android emulator:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Native lưu token bằng secure storage. Web giữ access token trong bộ nhớ và dùng
cookie refresh `HttpOnly`, `SameSite=Strict` (thêm `Secure` khi production).
Frontend và backend web cần cùng site, ví dụ cùng `localhost` ở hai cổng khác nhau;
thêm origin chính xác vào `CORS_ALLOWED_ORIGINS`. Thời hạn token lấy từ
`JWT_ACCESS_EXPIRES_IN` và `JWT_REFRESH_EXPIRES_IN`.

Các phiên từ phiên bản JWT cũ cần đăng nhập lại.

- Splash tự chuyển đến onboarding → đăng nhập/đăng ký/dùng thử.
- Kiểm tra email, mật khẩu, mật khẩu xác nhận; hiện/ẩn mật khẩu; đồng ý điều khoản.
- Nhận diện ký hiệu và giọng nói hiển thị chưa tích hợp AI; không tạo hoặc lưu kết quả giả.
- Văn bản tự nhập có thể sửa, sao chép và lưu hội thoại trên backend.
- Lịch sử: tìm kiếm, lọc nguồn/yêu thích, chọn đúng bản ghi, yêu thích, sao chép, xóa có xác nhận.
- Từ điển: nội dung đã xuất bản từ backend, tìm kiếm, phân trang, lọc danh mục, tải lại chi tiết và yêu thích đã lưu.
- Cá nhân: sửa tên/email/màu avatar; tốc độ/cao độ; chế độ tự mở trình phát; sáng/tối/hệ thống; cỡ chữ toàn app; tương phản cao.
- Đồng bộ tải lại dữ liệu thật; quyền riêng tư hỗ trợ xuất JSON, xóa dữ liệu, quản lý phiên và xóa tài khoản có xác nhận.
- 6 trạng thái hệ thống, có thể mở riêng để kiểm tra.

Google/Facebook dùng OAuth web với cấu hình server qua biến môi trường. Xem
[hướng dẫn cấu hình và kiểm thử](docs/OAUTH_SETUP.md). Chưa có credentials thì các
phương thức email và khách vẫn hoạt động. Đăng nhập thật với nhà cung cấp cần bạn
đăng ký ứng dụng và callback; các kiểm thử mô phỏng không thay thế bước đó.

Trên Chrome màn hình rộng, app hiển thị trong khung điện thoại. Trên điện thoại, app dùng toàn bộ màn hình. Nội dung dài có thể cuộn.

### Xem toàn bộ danh sách màn hình

**Cá nhân → Thông tin ứng dụng → Danh mục 37 màn hình.**

## 3. Phạm vi FE và dữ liệu demo

- Đăng nhập JWT, đăng ký, guest và phân quyền đã tích hợp backend. AI, camera thực, microphone thực, TTS, OAuth Google và cloud sync vẫn là demo.
- Đăng nhập kiểm tra tài khoản và mật khẩu trên backend; dữ liệu sai không mở trang chủ.
- Quên mật khẩu không gửi email thật.
- State hội thoại demo nằm trong bộ nhớ qua `ChangeNotifier` + `InheritedNotifier` và được xóa khi đổi tài khoản/đăng xuất. Phiên JWT có thể khôi phục khi mở lại ứng dụng.
- Thông tin đăng nhập được gửi đến API đã cấu hình. Dữ liệu hội thoại/nhận diện trong giao diện hiện tại vẫn là dữ liệu demo.
- Dictionary dùng icon giữ chỗ cho media. Nội dung hướng dẫn `Xin chào` lấy từ source Figma; các mục khác chờ nội dung VSL đã kiểm chứng. Đây chưa phải bộ tài liệu học ngôn ngữ ký hiệu hoàn chỉnh.
- Giao diện giữ màu, cấu trúc và các luồng chính của thiết kế; không cam kết khớp từng pixel. Màn hình hệ thống thật của Android về cấp quyền sẽ bổ sung khi tích hợp thiết bị.

## 4. Cấu trúc code

```text
lib/
  main.dart                       # entrypoint
  app.dart                        # MaterialApp + route registry
  core/
    app_state.dart                # models + state demo
    navigation.dart               # mã/tên màn hình + helpers
    theme.dart                    # màu, theme sáng/tối
  widgets/
    ui.dart                       # nút, card, logo, waveform, dialog...
  features/
    auth/auth_screens.dart        # S01–S07
    home/home_screen.dart         # S08
    recognition/recognition_screens.dart  # S09–S14 + permission component
    speech/speech_screens.dart    # S15–S19
    library/library_screens.dart  # S20–S24
    profile/profile_screens.dart  # S25–S31
    system/system_screens.dart    # SS01–SS06 + danh mục
```

`main.dart` chỉ khởi tạo app; không dồn toàn bộ giao diện vào một hàm.

## Kiểm tra

Cấu hình Gmail SMTP và khôi phục mật khẩu: [hướng dẫn SMTP](docs/SMTP_PASSWORD_RESET.md).
Quản lý tài khoản, role tùy chỉnh và từ điển: [hướng dẫn Quản trị](docs/ADMIN_MANAGEMENT.md).

```powershell
flutter analyze
flutter test
flutter build web
```

Bộ kiểm thử đi kèm kiểm tra 37 màn hình ở kích thước điện thoại, biểu mẫu đăng nhập, điều hướng và dữ liệu demo.
