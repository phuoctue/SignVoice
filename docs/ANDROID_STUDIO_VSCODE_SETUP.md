# Chạy SignVoice web và Android trên máy này

## Chạy máy ảo Medium Phone (yêu cầu cập nhật)

Máy này đã có AVD `Medium_Phone`, Android 15/API 35, x86_64. Trong ảnh, thanh thiết bị vẫn chọn Windows (desktop), và máy ảo chưa được khởi động.

1. Trong Device Manager, bấm tam giác Play bên phải **Medium Phone**, chờ tới màn hình Android.
2. Trên thanh công cụ Android Studio, đổi **Windows (desktop)** thành **Medium Phone / emulator-...**.
3. Đổi run configuration **main.dart** thành **SignVoice Medium Phone** đã thêm trong `.run/SignVoice_Medium_Phone.run.xml`. Nếu danh sách chưa cập nhật, đóng/mở lại project. Có thể tạo thủ công cấu hình Flutter với entrypoint `lib/main.dart` và Additional run args:

```text
--dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=AI_SERVICE_URL=http://10.0.2.2:8001
```

4. Dùng chế độ Debug mặc định và bấm Run. Không chọn cấu hình USB/Profile cho máy ảo. Không cần cáp USB hay script `connect-android-usb.ps1`.
5. Backend 3000 và AI 8001 vẫn chạy trong VS Code theo phần bên dưới; web Chrome có thể chạy riêng trên 8080. Trong máy ảo, `10.0.2.2` trỏ tới máy tính chủ, còn `localhost` trỏ vào chính máy ảo.

### Dùng webcam thật của máy tính trong máy ảo

Kiểm tra cấu hình hiện tại: camera trước đang là `emulated`, camera sau `virtualscene`, nên chưa đưa hình webcam vào app. Máy tính có **Integrated Webcam**, được emulator nhận là **webcam0**.

1. Tắt Medium Phone nếu đang chạy. Device Manager → dấu ba chấm của Medium Phone → Edit.
2. Mở Show Advanced Settings/Additional Settings → Camera → Front = **Webcam0**. Camera sau có thể giữ VirtualScene; khi vào app hãy chuyển sang camera trước. Save/Finish rồi khởi động lại, dùng Cold Boot nếu vẫn nhận cấu hình cũ.
3. Vào app → Ký hiệu → Giọng nói → đồng ý màn xin quyền và thông báo camera của Android. Đảm bảo Windows cho phép desktop apps truy cập camera.
4. Khi test máy ảo, đóng camera trên web/test_camera.py/ứng dụng đang chiếm webcam.

Nếu cần mở từ terminal thay vì Device Manager, lệnh sau dùng webcam cho camera trước chỉ trong lần chạy này:

```powershell
& 'E:\Android\Sdk\emulator\emulator.exe' -avd Medium_Phone -camera-front webcam0
```

Chỉ dùng khi AVD này chưa chạy; không mở hai phiên của cùng AVD. Sau khi máy ảo sẵn sàng, `flutter devices` cho biết ID. Ví dụ nếu ID là `emulator-5554`:

```powershell
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=AI_SERVICE_URL=http://10.0.2.2:8001
```

Nếu máy ảo đã hiện Android nhưng menu Flutter vẫn chỉ có Chrome/Edge/Windows: kiểm tra `adb devices -l` và `flutter devices`. Ngày 19/10, cả hai lệnh đã nhận `emulator-5554` là Android 15/API 35, và daemon Flutter mới cũng phát sự kiện `device.added` cho ID này. Có thể thấy tên **sdk gphone64 x86 64**, không nhất thiết là Medium Phone. Khi CLI nhận thiết bị mà IDE chưa hiện, dùng lệnh trên trong Terminal Android Studio để chạy ngay. Lưu công việc rồi thoát/mở lại toàn bộ Android Studio; restart Flutter Daemon riêng đã không giải quyết được trường hợp đang kiểm tra. Không cần xóa/tạo lại AVD hoặc reset dữ liệu app chỉ vì lỗi danh sách IDE.

Nếu terminal Android Studio vẫn báo `No supported devices` khi máy ảo đang mở, dùng launcher đã thêm:

```powershell
.\Chay_App_Medium_Phone.bat
```

Launcher gọi đúng Flutter và SDK bằng đường dẫn tuyệt đối, bật Android trong Flutter config, tìm ID máy ảo dựa vào AVD `Medium_Phone` thay vì đoán luôn là `emulator-5554`, và đặt thư mục socket Java phù hợp cho Windows. Không thay model. Kiểm tra chỉ kết nối bằng `.\Chay_App_Medium_Phone.bat -CheckOnly`. Đã kiểm tra `-CheckOnly` trên Windows PowerShell 5.1 và nhận đúng `emulator-5554`. Chẩn đoán được lưu tại `.runtime/emulator-launch-diagnostics.json`, gồm đường dẫn Flutter mặc định, SDK trước khi chạy, danh sách ADB/Flutter và lỗi nếu có; không thu thập toàn bộ môi trường. Chưa xác định được nguyên nhân chính xác vì terminal của người dùng báo thiếu thiết bị nhưng các lần kiểm tra CLI độc lập đều nhận AVD.

Máy ảo giúp thử giao diện, quyền camera và kết nối nhận diện. FPS đo ở đây thuộc emulator và webcam máy tính, không đại diện FPS điện thoại thật. Flutter dùng Debug trên emulator; hướng dẫn Profile/USB bên dưới chỉ dành cho điện thoại vật lý.

## Lỗi trong ảnh và phần đã sửa

- Android Studio đang mở `E:\WorkSpace\SignVoice\SignVoice\android`. Để chạy Flutter, mở **`E:\WorkSpace\SignVoice\SignVoice`**, nơi có `pubspec.yaml` và `lib/main.dart`.
- AGP 9.1 tạo `generateDebugUnitTestConfig` bằng đường dẫn tương đối. Nguồn plugin nằm ở Pub cache ổ C, nhưng cấu hình cũ ép output mọi plugin sang ổ E, gây lỗi `this and base files have different roots`.
- `android/build.gradle.kts` hiện giữ output app trong `build/app`, còn output plugin khác ổ được đặt trên cùng ổ với nguồn. Trên máy này, cache build plugin nằm dưới `%LOCALAPPDATA%\SignVoice\gradle-build`. Không chuyển hoặc xóa Pub cache.
- `android/gradle.properties` dùng Kotlin compiler trong tiến trình Gradle, không dùng incremental cache giữa hai ổ.
- Flutter đã được khai báo Android SDK `E:\Android\Sdk`; `flutter doctor -v` ngày 19/10/2026 báo không còn lỗi. Plugin Flutter và Dart của Android Studio đã được cài.

## 1. Mở đúng dự án ở cả hai IDE

1. Android Studio: **File → Close Project**, rồi **Open** thư mục `E:\WorkSpace\SignVoice\SignVoice`. Không chọn riêng thư mục `android`.
2. Settings → Languages & Frameworks → Flutter: Flutter SDK là `E:\WorkSpace\flutter` (không thêm `\bin`). Nếu chưa thấy mục Flutter, kiểm tra Settings → Plugins → Installed, bật Flutter và Dart rồi khởi động lại IDE.
3. Tools → SDK Manager: Android SDK Location là `E:\Android\Sdk`.
4. Chạy `flutter pub get` tại thư mục gốc. Đợi Android Studio nhận diện Flutter và hoàn tất Gradle sync. Nếu cần, bấm **Sync Project with Gradle Files**.
5. VS Code cũng mở cùng thư mục gốc. Hai IDE có thể cùng mở mã nguồn; không cùng khởi động hai phiên Flutter cho cùng một thiết bị/cổng web.

## 2. Bật backend và AI tại VS Code

Chạy mỗi lệnh trong một terminal riêng, giữ cửa sổ đang chạy. Nếu service đúng đã bật, dùng lại service đó.

Terminal backend:

```powershell
Set-Location 'E:\WorkSpace\SignVoice\SignVoice\backend'
npm run dev
```

Database và cấu hình backend dùng như trước. Backend cần kết nối database thành công để đăng nhập/từ điển hoạt động.

Terminal AI:

```powershell
Set-Location 'E:\WorkSpace\SignVoice\SignVoice'
.\Chay_AI_Service.bat
```

Chờ AI báo sẵn sàng tại cổng **8001**. Không cần bật LM Studio để nhận diện camera. Model được lấy theo bộ đã chọn trong project, không thay model trong lần sửa cấu hình Android này.

Kiểm tra từ trình duyệt máy tính:

- `http://127.0.0.1:3000/health/live`: backend đã bật. `/health/ready` kiểm tra backend/database sẵn sàng.
- `http://127.0.0.1:8001/health`: AI, cần thấy `ready: true`.

## 3. Kết nối điện thoại Android thật bằng USB

1. Trên điện thoại: Settings → About phone → bấm Build number theo hướng dẫn của hãng để bật Developer options.
2. Bật **USB debugging** trong Developer options.
3. Cắm cáp hỗ trợ truyền dữ liệu, mở khóa điện thoại, chọn truyền dữ liệu nếu cần. Đồng ý hộp thoại **Allow USB debugging** của máy tính này.
4. Trong terminal ở gốc project:

```powershell
& 'E:\Android\Sdk\platform-tools\adb.exe' devices -l
flutter devices
```

Phải thấy điện thoại ở trạng thái `device`. `unauthorized` nghĩa là cần đồng ý trên điện thoại; danh sách rỗng thì kiểm tra cáp, USB mode và driver hãng. Không dùng emulator để kết luận FPS camera điện thoại thật.

5. Nối cổng backend/AI qua USB:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\connect-android-usb.ps1
```

Script chỉ chạy `adb reverse` cho hai cổng **3000** và **8001**, rồi kiểm tra health. Nếu có nhiều thiết bị, thêm `-DeviceId 'ID_DIEN_THOAI'`. Chạy lại sau khi rút cáp, khởi động lại điện thoại hoặc ADB.

USB reverse cho phép app điện thoại gọi `127.0.0.1` và được chuyển tới máy tính; giữ cáp trong khi test. Không cần mở firewall LAN hoặc cho AI lắng nghe `0.0.0.0` với cách này.

## 4. Chạy app điện thoại từ Android Studio

1. Chọn điện thoại thật trong danh sách thiết bị.
2. Chọn run configuration **SignVoice USB - Profile**, đã tạo trong `.run/SignVoice_USB_Profile.run.xml`, rồi Run.
3. Nếu IDE chưa hiện cấu hình: **Run → Edit Configurations → + → Flutter**:
   - Name: `SignVoice USB - Profile`
   - Dart entrypoint: `lib/main.dart` trong project gốc.
   - Additional run args:

```text
--profile --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1 --dart-define=AI_SERVICE_URL=http://127.0.0.1:8001
```

4. Dùng **Run**, không dùng Debug với cấu hình `--profile`. Cũng có thể chọn **Run → Flutter Run main.dart in Profile Mode**. Nếu chỉ sửa giao diện và cần hot reload, bỏ `--profile` để chạy debug; đo FPS thì quay lại profile/release.
5. App mở trên điện thoại → Ký hiệu → Giọng nói → đồng ý màn xin quyền → cho phép camera trong thông báo Android. Chọn chế độ Từ/Chữ/Số phù hợp. Đổi camera trước/sau bằng nút trên preview.
6. Trong cài đặt camera, địa chỉ AI phải là `http://127.0.0.1:8001`. Với USB reverse, không dùng địa chỉ emulator `10.0.2.2`.

Lệnh tương đương để chạy trong terminal Android Studio nếu cần:

```powershell
flutter run -d ID_DIEN_THOAI --profile --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1 --dart-define=AI_SERVICE_URL=http://127.0.0.1:8001
```

Nếu Java báo `Unable to establish loopback connection`, đặt biến **trong terminal chạy lệnh** rồi chạy lại:

```powershell
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=E:\Android\tmp'
```

Thư mục `E:\Android\tmp` đã tồn tại trên máy này. Nếu chạy bằng nút Run của IDE, đặt cùng biến trong **Edit Configurations → Environment variables**.

## 5. Chạy web tại VS Code cùng lúc

Sau khi lần build Android đầu hoàn tất, mở terminal thứ ba:

```powershell
Set-Location 'E:\WorkSpace\SignVoice\SignVoice'
flutter run -d chrome --release --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=AI_SERVICE_URL=http://localhost:8001
```

Hoặc chọn cấu hình **SignVoice Web - Release (8080)** trong VS Code Run and Debug. File `.vscode/launch.json` đã có cấu hình này.

Hai giao diện dùng chung backend **3000** và AI **8001**, chỉ khởi động mỗi service một lần. Web dùng **8080**; không gán `AI_SERVICE_URL` về 8080. Nếu 8080 đang có Flutter cũ, dùng cửa sổ cũ hoặc dừng phiên cũ bằng `q`/Ctrl+C trước khi chạy phiên mới.

Để so FPS khách quan, khi đo điện thoại hãy rời màn camera ở web; khi đo web hãy rời màn camera điện thoại. Hai giao diện vẫn có thể mở. Chạy đồng thời hai camera sẽ chia tài nguyên máy tính/AI và không phản ánh riêng hiệu năng một thiết bị.

## 6. Đọc số đo camera

Trong màn nhận diện, mở cài đặt ở góc phải:

- **FPS landmark tại thiết bị**: tốc độ đo mốc tay trên điện thoại, kèm GPU/CPU và ms detector.
- **FPS dò tay / ms xử lý AI**: tốc độ phía service, có thể khác FPS tại thiết bị.
- FPS của Flutter Performance Overlay là tốc độ vẽ giao diện, không phải số lần nhận diện tay mỗi giây.

Đo trong profile trên điện thoại thật, thử cả lúc vừa mở camera và sau khoảng 30–60 giây. Không suy ra accuracy từ FPS; kiểm tra riêng kết quả ký hiệu và thời gian chốt kết quả.

## Tài liệu chính thức

- [Flutter: Android setup và thiết bị thật](https://docs.flutter.dev/platform-integration/android/setup)
- [Flutter: đo hiệu năng bằng profile trên máy thật](https://docs.flutter.dev/perf/ui-performance)
- [Android: adb reverse để truy cập server máy tính](https://developer.android.com/develop/ui/views/layout/webapps/access-local-server)
- [Dart Code: cấu hình launch.json](https://dartcode.org/docs/launch-configuration/)

## Giới hạn kiểm chứng

Kiểm tra sau sửa: cả 5 tác vụ `generateDebugUnitTestConfig` của camera/lifecycle/image picker/shared preferences/URL launcher chạy thành công; `:app:testDebugUnitTest` qua 3 kiểm thử chuyển đổi pixel, 0 lỗi; `:app:assembleDebug` thành công. Lượt build mất 4 phút 23 giây do tạo lại output plugin. Log: `.runtime/android-studio-setup-build.log`. File PowerShell, JSON và XML cấu hình đều đã kiểm tra cú pháp. Chưa thao tác nút Sync/Run trong Android Studio.

Ngày 19/10/2026, ADB chưa nhận điện thoại vật lý. Kiểm tra môi trường/build trên máy tính không thay thế việc cài app, cấp quyền, kiểm tra camera và đo FPS trên điện thoại thật.
