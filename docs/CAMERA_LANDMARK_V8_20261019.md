> Cập nhật khởi động web worker 8.1: xem [phân tích CPU/GPU và sửa cold start](CAMERA_STARTUP_20261019.md). Đường web hiện mặc định khởi tạo VIDEO detector chính; các số kiểm thử v8 bên dưới là mốc trước cập nhật này.

# Camera landmark v8 — 19/10/2026

Đã tách tốc độ đo/vẽ bàn tay khỏi tốc độ nén ảnh, mạng và suy luận từ. Bộ 181 từ và đặc trưng huấn luyện giữ nguyên; LM Studio không tham gia nhận diện camera.

## Những thay đổi thực tế

- Web: worker nhận khung mới từ camera, phát landmark đo được trước JPEG. Detector không chờ JPEG nữa. Bộ nén dùng canvas riêng và snapshot bất biến: một ảnh đang nén + một ảnh mới nhất chờ; ảnh cũ bị thay thế và giải phóng. Ảnh gửi service và XYZ luôn cùng timestamp/kích thước/khung hình.
- Web: GPU ưu tiên, CPU tại trình duyệt dự phòng. Service nhận XYZ hợp lệ sẽ bỏ lượt detector CPU trùng lặp. Chế độ chữ/số không chạy recovery chỉ để tìm thêm tay thứ hai; bộ dò chính vẫn hỗ trợ hai tay.
- Android APK: MediaPipe 0.10.32 chạy trực tiếp trên điện thoại, GPU ưu tiên/CPU dự phòng. Tạo/chạy/đóng GPU trên cùng một executor. Hàng đợi YUV và JPEG đều chỉ giữ khung mới nhất; JPEG chạy trên executor khác, landmark phát qua EventChannel ngay sau phép đo. Mã này dùng chung camera trước/sau, xử lý row/pixel stride của YUV và xoay ảnh cảm biến; chỉ preview được soi gương ở camera trước.
- Model hand_landmarker.task của Android được lấy từ đúng asset web khi build, kiểm SHA-256 trước khi khởi tạo: `fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1`.
- Vẽ landmark hết hạn sau 180 ms; khi dò tại thiết bị đang hoạt động, không lấy tọa độ server cũ để vẽ thay. Các khớp vẽ ra đều là phép đo, không ngoại suy điểm bị mất.
- Các chỉ số service không dựng lại toàn màn hình ở mọi khung: giới hạn khoảng 8 Hz khi trạng thái ổn định, vẫn cập nhật ngay khi đổi trạng thái/kết quả. Landmark dùng notifier riêng.
- Android yêu cầu camera 30 FPS ở độ phân giải medium. Đây là yêu cầu cho camera, không phải cam kết detector đạt 30 FPS trên mọi thiết bị.
- Script mở web mặc định dùng release để giảm tải debug. Có thể thêm `-DebugMode` khi sửa giao diện.

## Áp dụng trên web

Service AI: `http://localhost:8001`; giao diện: `http://localhost:8080`.
Dừng lượt Flutter cũ bằng `q`, rồi chạy trong thư mục app:

```powershell
flutter run -d chrome --release --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=AI_SERVICE_URL=http://localhost:8001
```

Hoặc chạy `Chay_App_AI_Web.bat`. Bản release cần khởi chạy lại khi cập nhật mã; không dùng hot reload để nhận worker mới. Worker v8 được đổi URL để tránh dùng bản v7 trong cache.

Trong cài đặt nhận diện, đọc **FPS landmark tại thiết bị** và thời gian ms. FPS này khác FPS service và FPS preview camera. Đo sau khi detector đã khởi tạo, ở cùng ánh sáng/khoảng cách và từng camera trước/sau. Không dùng điểm confidence làm thước đo độ trễ.

## Điện thoại Android

APK mới phải được cài lại để có Kotlin bridge; chỉ làm mới trang web không cập nhật mã native.

Build release cho điện thoại thật bằng script (thay IP máy tính của bạn):

```powershell
.\scripts\build-ai-android.ps1 -ApiBaseUrl http://192.168.1.10:3000/api/v1 -AiServiceUrl http://192.168.1.10:8001
```

APK nằm ở `build/app/outputs/flutter-apk/app-release.apk`. Script mặc định ARM64; có tùy chọn TargetPlatform cho các ABI khác. Script mặc định không truyền URL thì dùng Android emulator. Đã bổ sung xử lý lỗi Java NIO temp và tắt incremental Kotlin bị lỗi khi nguồn/plugin cache nằm trên hai ổ đĩa Windows khác nhau; những thiết lập này chỉ ảnh hưởng build, không thay đổi tốc độ detector.

Suy luận từ vẫn dùng service riêng trên máy tính. Khi thử bằng điện thoại thật, dùng IP LAN của máy tính trong cài đặt AI (không dùng localhost/10.0.2.2). Chạy service cho LAN bằng:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-ai-service.ps1 -ListenHost 0.0.0.0
```

Dừng service localhost cũ trước khi dùng cùng cổng. Điện thoại và máy tính phải kết nối được với nhau trên mạng. Không mở cổng ra Internet. Android emulator có thể dùng `http://10.0.2.2:8001`.

Chạy camera từ Chrome trên điện thoại là đường web (cần HTTPS phù hợp); đường MediaPipe Android native ở trên chỉ dùng khi cài APK. iOS hiện giữ đường camera gửi service, chưa có nhánh MediaPipe native mới.

## Giới hạn xác nhận

Chưa có điện thoại vật lý kết nối và chưa đo lại webcam trực tiếp sau bản sửa. Vì vậy chưa công bố FPS/độ trễ thực tế hay tăng accuracy của sáu từ. Tối ưu luồng landmark không chứng minh model phân loại từ đã chính xác hơn. Các video raw TEST cũ vẫn chỉ dùng kiểm thử hồi quy, không dùng để train hoặc chỉnh ngưỡng.

## Tài liệu API đã đối chiếu

- [MediaPipe Hand Landmarker Android](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/android)
- [CameraX image analysis / keep latest](https://developer.android.com/media/camera/camerax/analyze)
- [MPImage Bitmap ownership](https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/java/com/google/mediapipe/framework/image/BitmapImageContainer.java)

Kết quả kiểm tra/build được ghi cuối báo cáo khi hoàn tất.


## Kết quả kiểm tra cuối cùng

- Dart analyze các file camera/UI đã sửa: không có lỗi/cảnh báo.
- Flutter: **111 tests pass**, gồm màn hình xin quyền, luồng kết quả và landmark cũ không hiện lại.
- Service Python: **42 tests pass**; protocol Android dùng đúng schema, ảnh xoay/timestamp/model hash bị lệch sẽ bị từ chối.
- Web worker: **12 tests pass**, gồm JPEG bị chậm, thay ảnh cũ bằng ảnh mới, giải phóng snapshot, khung/XYZ cùng timestamp, GPU -> CPU, và luồng camera đầy không làm nghẽn tác vụ nén.
- Android: **3 JUnit tests pass** về YUV row stride, chroma pixel stride và BGRA padding/kênh màu.
- **Web release build thành công**. Worker trong `build/web` giống SHA-256 của source hiện tại.
- **Android debug build thành công** (`:app:assembleDebug :app:testDebugUnitTest`). Đã kiểm tra APK chứa đúng hand model, JNI MediaPipe và mã bridge mới. APK kiểm tra: `build/app/outputs/apk/debug/app-debug.apk`; đây là bản debug để kiểm tra tích hợp, không dùng số FPS debug để đại diện cho release.
- Health service thực tế: `camera_ensemble_v8`, `181` từ, `probability_ensemble`, `vision_enabled=false` trong kiểm tra WebSocket. Manifest model vẫn là `391a2e2ab46581a4b20aa6f418594a231a53d62fb63ca8873145203fc76b62cd`.
- Kiểm tra WebSocket bằng ảnh đen không có tay đã đi qua đường Android local observation; đây chỉ là thử protocol, không phải benchmark detector/accuracy. Trace giả lập được lưu riêng trong `.runtime/smoke-replays`, không trộn với raw TEST webcam.
- Chưa đo FPS thực tế trên webcam hoặc điện thoại vật lý sau thay đổi; chưa kiểm tra release APK/iOS trên thiết bị.
