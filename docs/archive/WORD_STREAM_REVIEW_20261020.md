# Kiểm tra chế độ từ/cụm từ — 20/10/2026

## Model đang chạy

Đã kiểm tra service thực tế qua `/sign-ai/health`, không chỉ kiểm tra file trên ổ đĩa:

- Model 181 từ, pipeline `stable_two_hand_v6_camera640`.
- Manifest SHA256: `af23aa8892a736db57dedf4ac0e688cdc22da1fbe160dfbcd937e05da2f8609b`.
- Word model SHA256: `09b1bb7a6459e4cf1d6df2dc48860df1a57b41ec87927ac439af46d033a2343b`.
- Nhánh từ dùng `probability_ensemble`: TCN và embedding mỗi nhánh 50%.
- Giữ chính sách xuất từ Colab: score 0.60, margin 0.20, dwell 0.30 giây. Không hạ ngưỡng theo video TEST.
- LM Studio không tham gia nhận diện camera.

## Lỗi tích hợp đã xác định và sửa

Hai video kiểm tra là `Recording 2026-10-20 000842.mp4` và `1792429555039_49545263168060327_3028160589505783569.mp4`. Trace tương ứng cho thấy không có sự kiện từ được chốt. Khoảng cách trung vị giữa các mẫu thực tế tới model khoảng 0.56 giây trên desktop và 0.72 giây trên điện thoại. Đây là tốc độ mẫu đầu vào model, không phải FPS hiển thị preview.

Luồng tọa độ bàn tay độc lập đã được bật cho chữ/số nhưng chưa được bật cho từ/cụm từ. Chế độ từ vẫn phụ thuộc ảnh JPEG và tốc độ xử lý ảnh. Model cần tối thiểu sáu mẫu quan sát thực; nhiều đoạn không tạo được cửa sổ hợp lệ hoặc mất trạng thái khi khoảng trống quá dài.

Đã cập nhật:

1. Worker web gửi tọa độ XYZ đo được của cả hai tay cho chế độ từ và tất cả, trước khi JPEG hoàn thành.
2. Flutter và WebSocket service hỗ trợ luồng này cho chế độ từ. Tốc độ gửi tối đa khoảng 15 mẫu/giây, phù hợp tần số model; tốc độ thực phụ thuộc thiết bị và mạng.
3. Chỉ giữ một gói đang chờ ACK và một mẫu mới nhất. Khi ACK về, gửi mẫu mới nhất ngay; không tích lũy hàng đợi khung cũ.
4. Mốc mặt lấy từ ảnh thật được dùng lại tối đa 1.2 giây, chỉ khi tỷ lệ ảnh phù hợp. Mốc hết hạn/khác tỷ lệ dùng mask thiếu dữ liệu. Không suy diễn mốc mặt từ bàn tay.
5. Ảnh cũ vẫn cập nhật phần xử lý ảnh nhưng không được chèn tọa độ cũ ngược vào chuỗi thời gian đã có mẫu mới.

Thay đổi nằm trong `ai_service/engine.py`, `model_runtime.py`, `server.py`, `protocol.py`, `session_trace.py`, `web/signvoice_hand_worker.js`, `lib/services/sign_ai/local_hand_tracker_web.dart` và `lib/features/recognition/live_camera_screen.dart`.

## Kiểm chứng

- 70 bài kiểm thử Python, 24 bài kiểm thử Flutter, 23 bài kiểm thử worker JS đều qua; Dart analyzer không có lỗi.
- Build web release thành công. SHA256 của `main.dart.js` và worker 8.6 trên địa chỉ public khớp bản vừa build; mã runtime và adapter đang chạy cũng khớp file cục bộ.
- Kiểm tra tích hợp thật qua WebSocket public: video nguồn VAL của `nghe`, gửi 30 gói tọa độ thật và sáu ảnh JPEG, tạo được sự kiện `nghe`, điểm 0.734. Đây là kiểm tra đường truyền và suy luận, không phải kết quả webcam người dùng.
- Cùng đặc trưng của sáu clip nguồn, lấy mẫu thưa 0.7 giây không có lượt suy luận hợp lệ; lấy mẫu dày khoảng 15 Hz tạo được sự kiện đúng cho `nghe`, `nhìn`, `rau` (VAL) và `bàn tay` (TRAIN). Không được gọi đây là độ chính xác 4/6 vì có mẫu TRAIN và số clip quá nhỏ.

## Giới hạn còn lại

Một clip VAL sạch của `chào` và một clip VAL sạch của `cứu` vẫn không được chốt. Trích lại vùng camera từ hai bản ghi màn hình người dùng ở tốc độ dày cũng chưa nhận đúng được sáu từ; desktop có một sự kiện nhầm `cho`, điện thoại không có sự kiện. Bản ghi màn hình chứa overlay, biến đổi kích thước và khả năng lật ảnh nên không tương đương video camera raw.

Do đó, bản sửa này xử lý lỗi thiếu mẫu chuyển động đã chứng minh được; chưa chứng minh chất lượng nhận diện sáu ký hiệu người dùng đã đạt yêu cầu. Không dùng hai video này để train, chọn trọng số hoặc điều chỉnh ngưỡng. Cần kiểm tra lại bằng phiên camera trực tiếp sau cập nhật để phân biệt phần lỗi đường truyền đã sửa với phần sai khác biến thể/khả năng tổng quát của model. Nếu model vẫn sai trên đầu vào đủ mẫu và đúng đặc trưng, cần bổ sung TRAIN độc lập theo người/phiên và biến thể, rồi đánh giá trên TEST giữ riêng.

## Cách dùng bản cập nhật

Địa chỉ đang phục vụ: https://newtanboard42.conveyor.cloud

Đóng tab cũ rồi mở lại với `?v=20261020-wordstream` để tải giao diện mới. Bản public đã được build và service đã cập nhật. Nếu chạy Flutter debug riêng, dùng hot restart để nhận thay đổi Dart; nếu trình duyệt vẫn giữ worker cũ thì tải lại trang. Với APK đã cài, cần build/cài lại để nhận mã Flutter mới.

Các bằng chứng được lưu riêng tại `.runtime/words_20261020/`: `public_verification.json`, `public_word_integration.json`, `pipeline_replay_report.json`, các log kiểm thử và ảnh kiểm tra. Trace kiểm thử nguồn được tách sang `.runtime/smoke-replays`, không gộp vào TEST camera người dùng.
