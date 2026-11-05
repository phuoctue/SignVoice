# SignVoice

SignVoice là ứng dụng học và giao tiếp bằng ngôn ngữ ký hiệu Việt Nam. Ứng dụng dùng chung một API cho Web và Android, hỗ trợ tra cứu ký hiệu công khai, học/ôn tập, giao tiếp ký hiệu–giọng nói, tài khoản cá nhân và quản trị nội dung.

## Kiến trúc

```text
SignVoice/
├─ lib/                         Flutter client: Web, Android và desktop
│  ├─ app.dart                  Khởi tạo ứng dụng và route
│  ├─ core/                     Theme, navigation, link/deep-link
│  ├─ features/                 Màn hình theo nghiệp vụ
│  ├─ providers/                Trạng thái phiên và tài khoản
│  ├─ services/                 HTTP client và các service nghiệp vụ
│  └─ widgets/                  Component dùng chung và access gate
├─ android/                     Native Android, Firebase và MediaPipe
├─ backend/                     Node.js + Express + TypeScript
│  ├─ src/routes/               Định tuyến API
│  ├─ src/controllers/          Nhận request và trả response
│  ├─ src/services/             Auth, mail, dữ liệu người dùng và nghiệp vụ
│  ├─ src/models/               Mô hình MongoDB
│  └─ src/config/               Cấu hình môi trường, database, Swagger
├─ ai_service/                  Python service nhận diện ký hiệu
├─ test/                        Flutter widget/regression tests
├─ backend/tests/               API tests
└─ scripts/                     Lệnh chạy, build và kiểm tra local
```

Luồng chính:

```text
Flutter Web/Android ──HTTP──> Backend API ──> MongoDB
         │                         │
         └─────── /sign-ai ────────┴──> AI service Python
```

Backend là nguồn quyết định cuối cùng cho xác thực, quyền truy cập, phiên khách, dữ liệu học tập và giới hạn thời gian. Client chỉ giữ trạng thái hiển thị và gọi API hiện có.

## Yêu cầu môi trường

- Flutter SDK tương thích với `pubspec.yaml`.
- Dart SDK đi kèm Flutter.
- Node.js và npm.
- MongoDB đang chạy ở môi trường phát triển.
- Python 3.11 và môi trường ảo của `ai_service` nếu cần nhận diện camera.
- Android Studio, Android SDK và một Android Emulator nếu chạy Android.

Kiểm tra nhanh:

```powershell
flutter doctor
node --version
npm --version
```

## Cấu hình local

Không commit secret hoặc file credential vào Git.

### Backend

Tạo `backend/.env` từ file mẫu tương ứng và điền tối thiểu:

```env
PORT=3002
NODE_ENV=development
MONGODB_URI=mongodb://127.0.0.1:27017/signvoice
```

Các tính năng email, OAuth, Firebase và reset mật khẩu cần thêm biến môi trường tương ứng. `GOOGLE_APPLICATION_CREDENTIALS` phải trỏ tới file Firebase Admin JSON được lưu ngoài repository, ví dụ:

```env
GOOGLE_APPLICATION_CREDENTIALS=C:/Users/<user>/.signvoice/firebase/firebase-adminsdk.json
```

`android/app/google-services.json` là cấu hình client Android của Firebase. Nếu tạo package hoặc fingerprint Android khác, tải lại cấu hình từ Firebase Console.

### Flutter

Client Web dùng API cùng origin khi chạy qua server local. Khi chạy trực tiếp trên Android Emulator, máy host được truy cập qua `10.0.2.2`.

## Chạy môi trường phát triển

### Web + Backend + AI

Từ thư mục gốc:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-signvoice.ps1 Local
```

Mở `http://localhost:3002/#/home`.

Nếu Web đã build và chỉ cần khởi động lại server:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-signvoice.ps1 Local -SkipBuild
```

Dừng môi trường local:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop-public-server.ps1 -Local
```

### Chạy backend riêng

```powershell
cd backend
npm ci
npm run dev
```

### Chạy Android trên máy tính

Khởi động emulator từ Android Studio hoặc:

```powershell
emulator -avd Medium_Phone
```

Sau khi `adb devices` hiển thị emulator ở trạng thái `device`:

```powershell
flutter pub get
flutter run -d emulator-5554 `
  --dart-define=API_BASE_URL=http://10.0.2.2:3002/api/v1 `
  --dart-define=AI_SERVICE_URL=http://10.0.2.2:3002/sign-ai
```

ID emulator có thể khác `emulator-5554`; dùng `flutter devices` để lấy ID chính xác. Với điện thoại thật, dùng địa chỉ LAN của máy chạy backend hoặc cấu hình `adb reverse` thay cho `10.0.2.2`.

## Route chính

Web dùng hash URL để tương thích với máy chủ hiện tại:

| Route | Mục đích |
| --- | --- |
| `/#/home` | Landing page công khai |
| `/#/login` | Đăng nhập |
| `/#/register` | Tạo tài khoản |
| `/#/dashboard` | Tổng quan sau đăng nhập |
| `/#/dictionary` | Trung tâm thư viện hoặc từ điển theo phiên |
| `/#/dictionary/browse` | Từ điển công khai |
| `/#/profile` | Hồ sơ và cài đặt |

Các alias cũ vẫn được adapter điều hướng tiếp nhận để không làm hỏng liên kết hiện có.

## Kiểm thử và kiểm tra chất lượng

Flutter:

```powershell
flutter analyze
flutter test
```

Backend:

```powershell
cd backend
npm run build
npm test
```

Kiểm tra README trước khi commit hoặc push:

```powershell
node scripts/check-readme-download-links.cjs
node scripts/check-readme-download-links.cjs --ref HEAD
```

Widget test chỉ xác nhận render, tương tác, route, trạng thái lỗi/loading và responsive. Browser test phải chạy riêng trên Chrome/Playwright; không dùng widget test để kết luận FPS hoặc hiệu năng thiết bị thật.

## Bảo mật và phát hành

- Không commit `backend/.env`, `.env.test`, Firebase Admin private key, OAuth client secret, token hoặc dữ liệu database.
- Không đặt credential trong `lib/`, `android/` hoặc README.
- Không đưa liên kết tải binary, file cài đặt hoặc tunnel tạm vào README.
- Binary chỉ được phát hành qua GitHub Releases khi chủ dự án yêu cầu rõ ràng.
- Backend phải kiểm tra quyền và dữ liệu; không tin role hoặc entitlement do client gửi lên.
- Khi thay đổi schema/API, cập nhật OpenAPI và test tương ứng.

## Đóng góp

1. Tạo branch từ `dev`.
2. Giữ thay đổi nhỏ, không sửa API hoặc business logic ngoài phạm vi.
3. Chạy các kiểm tra phù hợp và README guard.
4. Commit mô tả đúng thay đổi.
5. Push branch và mở pull request.

Đơn vị vận hành: **SignVoice**. Người phụ trách: **Phạm Phước Tuệ**.
