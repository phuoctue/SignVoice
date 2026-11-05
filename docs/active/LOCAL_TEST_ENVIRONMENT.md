# Môi trường test local

- Web: http://localhost:3003/#/home
- API/Swagger: http://localhost:3003/api-docs
- Database riêng: `signvoice_test`; AI riêng ở cổng `8002`.
- Tài khoản USER/STAFF/ADMIN: xem `.runtime/testing/accounts.json` trên máy.
- Bộ mẫu công khai có nhãn QA; dữ liệu cũ trong database test được giữ lại.

Khởi động với mã mới (build Web và backend):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-test-environment.ps1
```

Nếu cổng 3003 đã chạy, dừng đúng tiến trình test trước khi khởi động lại; script giữ nguyên tiến trình đang chiếm cổng để tránh dừng nhầm dịch vụ.

Chuẩn bị dữ liệu mẫu và kiểm tra môi trường (chạy từ thư mục backend):

```powershell
node scripts/prepare-test-data.cjs
node scripts/check-test-environment.cjs
```

Script chuẩn bị dữ liệu chỉ chấp nhận database `signvoice_test`. Mật khẩu mẫu được tạo ngẫu nhiên, lưu cục bộ và không đổi khi chạy lại. Không commit `.env.test` hoặc `.runtime`.

Test thủ công: đăng nhập từng vai trò; mở từ điển/video; mở bộ QA; học/quiz; đổi mật khẩu; mở lại Web để chọn khách cũ/mới; đăng xuất khách. Khi đóng Web, thời gian khách cũ vẫn chạy. Khi đăng xuất trực tuyến, khách bị xóa trên server.

## Link đặt lại mật khẩu Android

Email có link `/auth/reset-password#token=...` mở màn hình reset native; link Web trực tiếp `/#/reset-password?token=...` vẫn được giữ. Nếu trình duyệt đang xử lý link, trang trung gian có nút **Mở trong ứng dụng SignVoice**. Token nằm trong fragment, không gửi đến HTTP endpoint trung gian.

Chạy `scripts/configure-test-app-links.ps1` rồi khởi động lại backend test để phục vụ fingerprint debug tại `/.well-known/assetlinks.json`. HTTP localhost không phải tên miền HTTPS đã được Android xác minh. Khi test localhost có thể chọn SignVoice trong cài đặt Open supported links, hoặc dùng nút mở app trên trang trung gian. Không đánh dấu kết quả này là đã xác minh App Links production.

Với HTTPS thật: build APK với biến môi trường `ORG_GRADLE_PROJECT_signVoiceAppLinkHost` bằng đúng hostname; cấu hình backend `ANDROID_APP_LINK_SHA256` bằng SHA-256 của chứng chỉ ký APK (phân cách dấu phẩy nếu nhiều khóa). Domain phải phục vụ JSON association này qua HTTPS. Không dùng fingerprint debug thay cho khóa ký production/Play App Signing.

OAuth, email thật, push notification và camera/microphone cần cấu hình/quyền thiết bị tương ứng; health check không xác nhận được các luồng này.

## Email và Google

Chạy từ `backend`: `node scripts/configure-test-integrations.cjs --apply` để sao chép các biến tích hợp có sẵn từ `.env` vào `.env.test`, giữ nguyên database/JWT. `node scripts/check-test-integrations.cjs` kiểm tra SMTP; thêm `--send-self` để gửi email test về chính hộp thư SMTP. Cấu hình hiện tại dùng chung nhà cung cấp email/OAuth với môi trường chính; đây không phải project Google tách biệt.

Trong Google Cloud project `signvoice`, Web OAuth client đang dùng cần thêm Authorized redirect URI:
`http://localhost:3003/api/v1/auth/oauth/google/callback`.
Thêm tài khoản Google dùng test vào consent screen Test users nếu ứng dụng còn ở chế độ Testing. Không thay callback Conveyor hiện có.

Android OAuth client phải cùng Google Cloud project với Web client: package `com.example.sign_voice`, SHA-1 khóa debug:
`44:8F:9F:DE:9A:8F:9B:24:22:DD:76:67:D5:4D:37:50:1B:AF:A3:99`.

Android emulator/thiết bị USB cần `adb reverse tcp:3003 tcp:3003` để dùng API `http://127.0.0.1:3003/api/v1`; AI dùng `http://127.0.0.1:3003/sign-ai`. Chạy lại reverse sau khi kết nối lại thiết bị. Link email `localhost:3003` trên điện thoại cũng cần reverse.

Build và cài APK test qua USB: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-android-local.ps1 -DeviceId emulator-5554`. Thay device ID theo kết quả `adb devices`. APK debug dùng package hiện tại nên cập nhật ứng dụng SignVoice đã cài bằng cùng khóa debug, giữ dữ liệu khi cài `-r`; đây không phải ứng dụng sandbox có icon/package riêng.

## Firebase

Android đã có cấu hình project `signvoice-143c9`. File service account cũ không còn tồn tại. Tải service account đúng project trong Firebase Console → Project settings → Service accounts, lưu tại `.runtime/testing/firebase-service-account.json` rồi chạy lại script cấu hình và khởi động backend test. Không gửi private key qua chat hoặc đưa vào APK/Web.

Kiểm tra FCM không gửi thông báo: từ `backend`, chạy `npx tsx scripts/verify-firebase.ts --test`. Cờ `--test` chỉ nạp `.env.test` và kiểm tra đúng tên database trước khi dùng cấu hình Firebase.

Web hiện chỉ có hộp thông báo trong app; chưa có Web push. Muốn bật Web push cần Firebase Web app config, Web Push VAPID public key và tích hợp service worker, quyền thông báo; không thể dùng `google-services.json` Android thay cho Web config.

## Tạo mật khẩu cho tài khoản Google

Đăng nhập Google → Hồ sơ → Chỉnh sửa hồ sơ → Tạo mật khẩu đăng nhập. Nhập mật khẩu mới và xác nhận, không cần mật khẩu cũ. Phiên Google phải mới trong vòng 10 phút; nếu quá hạn, đăng xuất rồi đăng nhập Google lại. Sau khi tạo, đăng nhập lại bằng Google hoặc cùng email/mật khẩu mới. Mã tài khoản, vai trò, liên kết Google và tiến trình học được giữ nguyên. Lần sau mục này trở thành Đổi mật khẩu và yêu cầu mật khẩu hiện tại.
