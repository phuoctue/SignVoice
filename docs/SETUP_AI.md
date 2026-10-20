# Chạy SignVoice và AI trên máy khác

## 1. Chuẩn bị

- Windows x64, Git, Python **3.11 x64**, Flutter **3.47.6 stable / Dart 3.13.5** (phiên bản đã kiểm thử) trên PATH, Chrome và Node.js **20+ / npm 10+**. `pubspec.yaml` yêu cầu Dart từ 3.13.2. Chạy `flutter doctor` và xử lý các mục của nền tảng muốn dùng. Python/TensorFlow chạy CPU, không bắt buộc NVIDIA/CUDA.
- Android: cài Android Studio, Android SDK, Flutter/Dart plugin; khai báo `ANDROID_HOME` tới SDK của chính máy bạn. Không sao chép `android/local.properties` hoặc `.venv` từ máy khác.
- Chuẩn bị vài GB ổ trống cho Python/TensorFlow, Flutter/Gradle và model. Lần đầu tải thư viện cần Internet; model runtime ZIP khoảng **67.8 MiB**, không phải dataset TRAIN 46 GB.

```powershell
git clone --branch dev https://github.com/phuoctue/SignVoice.git
cd SignVoice
flutter pub get
.\scripts\setup-ai-service.ps1
```

Nếu `python` mặc định không phải 3.11, truyền đường dẫn của bạn:

```powershell
.\scripts\setup-ai-service.ps1 -Python 'C:\duong-dan-python311\python.exe'
```

Script tạo môi trường Python riêng và tải [model release 181 từ](https://github.com/phuoctue/SignVoice/releases/tag/models-181-camera640-v1). ZIP, từng file và manifest đều được kiểm tra checksum trước khi cài. Tải gián đoạn: chạy lại lệnh setup để tiếp tục. Có ZIP từ đúng release thì dùng `-ModelArchive 'D:\Downloads\SignVoice_Runtime_181_camera640.zip'`. Không trộn file từ các lần train khác nhau.

Model nằm trong `ai_service/models/runtime_181_camera640`. Lựa chọn cục bộ nằm trong `.runtime/ai-model-selection.json` và dùng đường dẫn tương đối. Nếu máy đã có lựa chọn riêng, setup giữ nguyên; chỉ chạy `python -m ai_service.install_model --activate` bằng Python trong `.venv` khi muốn chủ động thay lựa chọn. Khởi động lại service sau khi chủ động đổi model; setup không thay tiến trình đang chạy.

## 2. Chạy AI độc lập

Terminal 1, tại thư mục project:

```powershell
.\scripts\start-ai-service.ps1
```

Giữ terminal mở. Terminal khác:

```powershell
Invoke-RestMethod http://localhost:8001/health
.\ai_service\.venv\Scripts\python.exe -m ai_service.verify_install
```

Kết quả mong đợi: `ready=true`, `word_classes=181`, `word_engine=probability_ensemble`, `model_manifest_sha256=af23aa8892a736db57dedf4ac0e688cdc22da1fbe160dfbcd937e05da2f8609b`. `verify_install` gửi ảnh đen qua WebSocket của cả bốn chế độ để kiểm tra đường truyền/OpenCV/bộ dò; không mở webcam, không cần video riêng và không đo accuracy. Hai nhánh TCN/embedding cùng chạy theo policy đã đóng gói; không cần LM Studio, GPU hoặc Google Drive. Service có thể warm up TensorFlow vài giây trước khi health sẵn sàng.

## 3. Backend cho đăng nhập và dùng thử

AI không cần MongoDB, nhưng giao diện đầy đủ (kể cả **Dùng thử không cần tài khoản**) cần backend. Máy khác phải tự cấu hình database và secrets; repo không chứa tài khoản hay `.env` của máy phát triển.

```powershell
cd backend
npm ci
Copy-Item .env.example .env
```

Sửa `.env`: nhập **hai** giá trị ngẫu nhiên khác nhau vào `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` (mỗi giá trị ít nhất 32 ký tự). Sinh mỗi giá trị bằng lệnh sau, chạy hai lần:

```powershell
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

Dùng MongoDB replica set riêng. Với Docker Desktop, cấu hình local có sẵn:

```powershell
docker compose up -d --wait
npm run dev
```

Compose mở MongoDB **chỉ trên 127.0.0.1:27017**, tự tạo replica set `rs0`; URI mẫu đã khớp cấu hình này. Đây là database phát triển local, không dùng cấu hình không xác thực này cho máy chủ public. Nếu đã có MongoDB trên cổng 27017, dùng instance replica set đang có và sửa URI; không chạy thêm container trùng cổng. MongoDB Atlas cũng dùng được khi điền URI riêng và cho phép IP máy của bạn.

Kiểm tra `http://localhost:3000/api-docs`. SMTP và Google/Facebook OAuth là tùy chọn; cần thông tin riêng nếu bật các chức năng đó. Không commit `.env`.

## 4. Flutter Web

Terminal 3, tại thư mục project, trong khi AI/backend vẫn chạy:

```powershell
.\scripts\run-ai-web.ps1
```

Mặc định chạy release Chrome cổng 8080; AI cổng **8001** và API cổng **3000**. Chọn Dùng thử/đăng nhập, mở Ký hiệu → Giọng nói và bấm cấp quyền camera. Quyền camera thật do trình duyệt/OS quyết định; nếu trước đó đã cấp, trình duyệt có thể không hỏi lại. Mở cài đặt website để thu hồi/cấp lại. Không đặt `AI_SERVICE_URL=http://localhost:8080` vì đó là giao diện Flutter.

Port bận: dừng đúng phiên cũ bằng `q`/Ctrl+C hoặc chọn `-WebPort 8081` và thêm origin đó vào cấu hình CORS backend/AI. Tránh mở hai ứng dụng cùng chiếm webcam. TTS phụ thuộc giọng tiếng Việt được cài trên thiết bị/trình duyệt.

## 5. Android emulator và điện thoại

- **Medium Phone:** bật AVD trong Android Studio, rồi `./scripts/run-ai-emulator.ps1 -AvdName Medium_Phone`. Script dò Flutter trên PATH và SDK qua `ANDROID_HOME`, `ANDROID_SDK_ROOT` hoặc thư mục SDK mặc định. Có thể truyền `-SdkPath` và `-FlutterPath` nếu cài chỗ khác. Emulator dùng `10.0.2.2:8001` cho AI, `10.0.2.2:3000/api/v1` cho backend; localhost trong emulator không phải PC. Cấu hình camera AVD thành Webcam nếu cần xem tay thật. FPS máy ảo không đại diện cho điện thoại thật.
- **Điện thoại qua USB:** bật USB debugging, chạy `./scripts/connect-android-usb.ps1`; script thiết lập adb reverse cho cổng backend/AI. Dùng đúng device ID từ `flutter devices`, chạy `flutter run --profile -d <ID> --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1 --dart-define=AI_SERVICE_URL=http://127.0.0.1:8001`.
- **APK qua Wi-Fi:** AI vẫn chạy trên PC/server, không được nhúng toàn bộ TensorFlow vào APK. Chạy service với `-ListenHost 0.0.0.0`, mở firewall đúng mạng riêng và dùng IP LAN của PC cho hai URL. Build bằng `scripts/build-ai-android.ps1 -ApiBaseUrl http://IP-PC:3000/api/v1 -AiServiceUrl http://IP-PC:8001`. Máy phải cùng mạng. Không dùng URL `10.0.2.2` trên điện thoại thật.
- **Web trên điện thoại:** cần HTTPS cho quyền camera; xem [PUBLIC_AI_CONVEYOR.md](PUBLIC_AI_CONVEYOR.md). Cài Conveyor và cấu hình tài khoản tunnel riêng; `.tools` và tài khoản tunnel của máy phát triển không được đưa lên Git. `scripts/start-public-server.ps1` chạy frontend/backend/proxy AI, sau khi dependencies/backend/model đã cài. URL tunnel mỗi máy có thể khác.

## Kiểm tra và giới hạn

```powershell
.\ai_service\.venv\Scripts\python.exe -m unittest discover -s ai_service -t . -p 'test_*.py'
node --test test_js/signvoice_hand_worker.test.cjs
flutter test
```

Chỉ kiểm thử camera sau khi health báo ready; nhãn đang hỗ trợ đọc từ model, không dựa vào từ điển demo trong app. Chế độ từ/cụm từ còn cần dữ liệu đa dạng và kiểm thử webcam độc lập; không dùng accuracy TRAIN/VAL để cam kết accuracy trên người mới. Model này nhằm tái lập đúng phiên bản đang sử dụng, không phải tuyên bố nhận đúng mọi từ hay mọi thiết bị. Các nguồn dữ liệu huấn luyện được ghi trong báo cáo; kiểm tra điều khoản của từng nguồn trước khi tái sử dụng thương mại/phân phối tiếp.
