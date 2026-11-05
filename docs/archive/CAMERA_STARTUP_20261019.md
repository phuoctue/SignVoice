# Khởi động camera web — 19/10/2026

## Bằng chứng từ các lượt test vừa lưu

Các lượt test dưới đây là những phiên khác nhau. Log cũ chỉ có FPS nhận/xử lý tại service, chưa có FPS detector tại trình duyệt hoặc lý do worker không khởi tạo được. Vì vậy không thể kết luận một phiên đã tự chuyển GPU sau đúng 1–2 phút hay riêng shader compilation gây toàn bộ thời gian chờ.

| Phiên | Số khung / thời lượng | Nguồn landmark | FPS service trung vị | Xử lý service trung vị |
|---|---:|---|---:|---:|
| `20261019T095527Z_77f38986.npz` | 116 / 38.0 s | {'cpu': 116} | 3.4 | 215.2 ms |
| `20261019T095603Z_c5379c59.npz` | 10 / 0.8 s | {'cpu': 10} | 10.1 | 80.6 ms |
| `20261019T095653Z_51d132e4.npz` | 394 / 41.9 s | {'cpu': 8, 'browser_gpu': 386} | 9.6 | 3.8 ms |

Có phiên chỉ dùng CPU dự phòng với tốc độ thấp, và phiên sau phần lớn dùng GPU tại trình duyệt. Đây là bằng chứng về thay đổi đường xử lý, không phải bằng chứng model được train thêm khi mở camera. Trọng số nhận diện giữ nguyên.

## Vấn đề mã nguồn đã xác nhận

- Worker trước đây tạo cả VIDEO detector và IMAGE recovery detector trên GPU rồi mới báo ready. Thời gian khởi tạo bộ phụ nằm trên đường mở camera.
- Trong khi worker đang tải/khởi tạo, camera vẫn gửi ảnh cho detector CPU ở tốc độ bình thường, gây thêm tải CPU trong lúc WASM/GPU cần tài nguyên.
- Deadline cũ 15 giây cho toàn bộ khởi tạo có thể làm mất worker chậm, sau đó giữ CPU dự phòng. Log cũ không ghi lỗi/giai đoạn nên chưa chứng minh đây chính là nguyên nhân ở một phiên cụ thể.

## Sửa tại worker 8.1

- Đường mặc định của web chỉ tạo bộ VIDEO chính (hai tay). Bộ này vẫn dùng cơ chế phát hiện lại bàn tay của MediaPipe khi tracking mất. Recovery IMAGE riêng còn là tùy chọn trong worker cho client cũ; chưa khẳng định chất lượng vùng che khuất tương đương sau thay đổi.
- Trong lúc khởi tạo, chừa 1,5 giây đầu cho bộ dò tại thiết bị; CPU fallback sau đó tối đa khoảng 2 khung/giây để giữ kết nối, thay vì tranh tài nguyên ở tốc độ đầy đủ. Khi worker ready hoặc thất bại, giới hạn khởi động kết thúc.
- Hiển thị banner “Đang khởi tạo bộ dò tay…”; banner được bỏ sau phép đo đầu hoặc sau khi chuyển fallback. Camera preview vẫn hiển thị.
- Giới hạn khởi tạo tối đa 30 giây; phép đo đầu có 10 giây trước khi fallback, các lần xử lý đang chạy có watchdog 3 giây. Đây là giới hạn xử lý lỗi, không phải thời gian đợi bình thường được cam kết.
- Bỏ callback đến muộn từ worker đã bị hủy để tránh trạng thái ready giả.
- Ghi riêng init_ms, processing_ms, fps tại trình duyệt, trạng thái khởi tạo, giai đoạn/lý do fallback vào trace. Số FPS service vẫn riêng. Cài đặt hiển thị thời gian khởi tạo khi có landmark.
- URL worker đổi sang `?v=8.1`. Bộ 181 từ, chính sách xác nhận và LM camera tắt giữ nguyên.

## Áp dụng và đo lại

Dừng lượt Flutter cũ bằng q rồi chạy lại bản release hoặc Chay_App_AI_Web.bat. Bản build web nằm ở build/web. Theo dõi FPS landmark tại thiết bị và thời gian khởi tạo trong cài đặt, rồi thử một/hai tay và các động tác gần mặt. Chưa đo trực tiếp webcam sau bản sửa nên chưa công bố thời gian mở camera/FPS mới.

## Tham chiếu

[MediaPipe Hand Landmarker web: phát hiện lòng bàn tay và tracking ở VIDEO](https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker/web_js)

Kết quả kiểm tra/build cập nhật sau khi hoàn tất.


## Kiểm tra

- Node worker: 13 kiểm thử qua, gồm khởi tạo chỉ một detector, báo giai đoạn khởi động và giữ metadata thời gian riêng.
- Flutter: 15 kiểm thử liên quan qua (banner khởi tạo giữ đến khung đầu, kết quả, stale landmarks, xin quyền camera/mic và bridge native).
- Python: toàn bộ 44 kiểm thử qua; kiểm tra cả chẩn đoán GPU thành công lẫn CPU fallback có giai đoạn/lý do lỗi.
- Dart analyze các file sửa: không có vấn đề.
- Chưa đo lại thời gian mở camera/FPS thực tế sau sửa.

- Build web release thành công; đã đối chiếu worker source với build/web và kiểm tra JS chứa mã startup mới nhất. Service đang chạy đúng adapter hiện tại, bộ 181 từ.
