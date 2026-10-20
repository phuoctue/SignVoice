# Android camera latency review — 19/10/2026

## Phạm vi và bằng chứng

Đã xem các khung hình trích từ `C:\Users\Phuoc Tue\Downloads\Recording 2026-10-19 181259.mp4`: video 36,63 giây, 2558×1472, bản quay màn hình 30 FPS. Webcam đã đi vào Medium Phone và có landmark được vẽ. FPS của bản quay màn hình không phải FPS detector; không dùng bản quay này để suy ra số FPS camera hoặc đánh giá accuracy.

Hai trace Android gần nhất đã lưu là 17:51/17:54 giờ Việt Nam, ghi nguồn `android_cpu`. Chúng không khớp thời điểm video 18:12, nên không gán số đo của hai trace đó cho video mới. Chưa đo FPS trước/sau trên điện thoại thật, cũng chưa có số đo FPS sau sửa trên emulator bằng một phiên camera mới.

## Các thay đổi

1. **Giảm hàng chờ ảnh và lưu lượng qua platform channel.** Trước đây ACK của lệnh gửi ảnh chỉ xác nhận native nhận được, trong khi detector còn xử lý; camera vẫn copy và gửi ảnh tiếp. Camera Android nay đợi kết quả landmark đo thật trước khi lấy khung mới để đưa sang native. Kiểm tra credit diễn ra trước bước tạo map/copy planes. Ảnh cũ không chờ thêm một vòng xử lý ở hàng đợi native. Có watchdog 3 giây để chuyển sang đường dự phòng nếu detector ngừng trả kết quả.
2. **Bỏ một bản sao YUV ở Dart.** CameraX đã chuyển planes sang các buffer Dart riêng; giữ buffer đó cho tới khi MethodChannel hoàn tất thay vì lại tạo `Uint8List.fromList`. Luồng dự phòng gửi ảnh sang service vẫn giữ cơ chế sở hữu dữ liệu như trước.
3. **Gộp chuyển màu và xoay sensor.** Chuyển YUV/BGRA trực tiếp sang mảng ARGB đã xoay; không tạo bitmap gốc rồi thêm bitmap xoay. Mảng ARGB scratch được tái sử dụng trên đúng thread detector. `Bitmap.createBitmap` sao chép pixels nên encoder vẫn có thể giữ bitmap bất biến của ảnh trước. Không lật pixels camera trước; chỉ preview được lật như trước.
4. **JPEG không làm chậm landmark.** Kết quả local vẫn được phát trước JPEG. Chỉ đưa ảnh vào encoder khi transport sẵn sàng, và giãn các lần nén tối thiểu 66 ms. Đây là cadence ảnh gửi service, không giới hạn detector/overlay xuống 15 FPS. Encoder vẫn có thread và hàng chờ riêng.
5. **Thêm số đo để kiểm chứng lần thử tiếp theo.** Cài đặt camera có `Ảnh → mốc tay ... ms`, tính từ lúc Dart nhận callback ảnh tới lúc nhận kết quả native. Số này chưa bao gồm thời gian sensor/CameraX xử lý trước callback. Metadata observation Android cũng có FPS/processing_ms để service lưu vào trace khi tracing được bật.

Không đổi model, nhãn, chuẩn hóa, số tay, ngưỡng MediaPipe hay ngưỡng xác nhận từ. Không làm mượt bằng cách tạo landmark giả hoặc giữ mốc cũ lâu hơn. Video người dùng chỉ là dữ liệu kiểm thử, không được đưa vào TRAIN hay chọn ngưỡng.

## Kiểm chứng

- 12 kiểm thử Flutter qua, gồm không nhầm ACK với hoàn tất detector; kết quả cũ không được giải phóng credit của ảnh mới; detector lỗi có fallback; landmark local không tự xác nhận từ.
- 5 kiểm thử Kotlin qua, gồm padded YUV/BGRA, chroma pixel stride, các góc 0/90/180/270 trên ảnh không vuông, không lật camera trước, và buffer scratch không đổi màu.
- Dart analyze các file thay đổi: không có vấn đề.
- `:app:testDebugUnitTest :app:assembleDebug`: thành công; log `.runtime/android-camera-latency-build.log`.
- APK có native libs arm64-v8a/armeabi-v7a/x86_64. Model hand detector vẫn có SHA256 `fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1`.
- Bộ nhận diện Python không đổi: SHA256 `ai_service/model_runtime.py` vẫn là `5b4e6dfcb1bf756d466e819e49c1a462f8aa0a1e054ab11e82094f2be7d01b8e`.
- Đã chạy lại bằng Flutter CLI với các URL `10.0.2.2`, cài APK mới trên `emulator-5554` và mở MainActivity. Đã detach CLI để app tiếp tục chạy. Không tự mở camera/cấp quyền thay người dùng. Log khởi động emulator có `Skipped ... frames` và JIT/GC trước khi kiểm thử camera mới; không xem các log khởi động đó là số đo detector.

Kiểm thử trên không chứng minh tăng FPS hay accuracy thực tế. Việc đợi kết quả trước khi lấy ảnh có thể giảm số ảnh gửi đi trên thiết bị chậm, đổi lại tránh xử lý thêm ảnh cũ và giảm tải bộ nhớ/bridge. Cần đo độ trễ và chất lượng chuỗi ký hiệu trên thiết bị đích.

## Cách thử lại

Giữ backend 3000, AI 8001 và Medium Phone đang mở. Sau thay đổi Kotlin, cần dừng phiên Flutter cũ rồi chạy lại toàn bộ:

```powershell
.\Chay_App_Medium_Phone.bat
```

Mở màn nhận diện, đồng ý cấp quyền camera và dùng camera trước Webcam0. Khi test, đóng camera trên Chrome/test_camera.py để không tranh webcam. Mở cài đặt camera, ghi lại FPS landmark tại thiết bị, ms xử lý, `Ảnh → mốc tay`, nguồn Android CPU/GPU và số ảnh gửi/giây. Đo riêng lúc mới vào camera và sau 30–60 giây; so cùng cảnh, số tay và chuyển động.

Medium Phone chạy bằng tài nguyên máy tính và webcam; kết quả không đại diện hiệu năng điện thoại. Trên điện thoại thật cần thử profile/release, kiểm tra cả camera trước/sau và GPU/CPU. Điện thoại có thể chạy nhanh hơn emulator nhưng chưa thể cam kết một mức FPS khi chưa đo. Nhận diện từ vẫn phụ thuộc model, dữ liệu và sự khớp động tác, không chỉ tốc độ landmark.

Tài liệu: [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance), [MediaPipe Hand Landmarker Android](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/android).
