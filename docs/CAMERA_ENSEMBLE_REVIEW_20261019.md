# Camera và ensemble — 19/10/2026

Service 8001 đã xác minh chạy `probability_ensemble`, bộ 181 từ, trọng số TCN/embedding 50/50, runtime V6. WebSocket nhận 61 kết quả và có `score_kind=probability_ensemble`. LM Studio không tham gia camera. Hash runtime đang chạy khớp file trên ổ đĩa.

## Cách kết hợp

Cosine embedding được đổi thành phân phối từ với temperature 0.08; TCN dùng temperature 1. Trộn hai phân phối, giữ phần xác suất nền từ TCN, rồi mới kiểm tra nền và các điều kiện xác nhận. Policy chọn trên source VAL: score 0.45, margin 0.10, dwell 0.30 giây. Không chọn tham số bằng video TEST. Policy gắn với hash export, model và thứ tự nhãn; export khác cần hiệu chỉnh lại.

Không thay trọng số hai file Keras. Score chưa được kiểm định thành xác suất đúng cho webcam; không có VAL nền thực tế độc lập.

## Kết quả trên source VAL

54 video cache khớp ID VAL hiện tại, 26 nhãn, không trùng ID TRAIN:

| Kiểm tra | TCN | Ensemble |
|---|---:|---:|
| Đoạn cắt: chấp nhận đúng | 22/54 | 32/54 |
| Đoạn cắt: chấp nhận sai | 3 | 2 |
| Vòng causal: kết quả cuối đúng | 16/54 | 28/54 |
| Vòng causal: kết quả cuối sai | 6 | 4 |
| Vòng causal: tổng sự kiện sai | 6 | 5 |

Đây là VAL đã dùng chọn cấu hình, không phải đánh giá độc lập. Causal chạy riêng từng clip, chưa phải chuỗi giao tiếp dài có hoạt động nền.

Replay `Recording 2026-10-19 120310.mp4` vẫn không nhận đúng sáu từ. Sau khi cắt lại vùng camera và dò bằng CPU, TCN phát “phục hồi”, “làm quen”; ensemble còn phát “không biết”. Video màn hình có landmark vẽ đè, nên replay không tái hiện nguyên vẹn đầu vào GPU. Policy giữ nguyên sau replay. Chưa chứng minh tăng accuracy trên TEST này hoặc đo FPS camera V6 thực tế.

## Sửa lỗi

- Sửa mask đo thật đi cùng pose/wrist khi chuyển tay đơn từ slot 0 sang slot 1. Đã tái hiện lỗi bằng test thất bại trước sửa; các điểm nội suy vẫn không được tính là đo thật.
- Browser nhận anchor mặt từ service, dùng cùng quy tắc bán kính XYZ theo tỉ lệ mặt. Tay gấp nhỏ không còn bị overlay loại chỉ vì ngưỡng 2D cố định 0.055. Lọc tay nền trước bước đếm tay và recovery.
- Giữ native VideoFrame stream, fallback bitmap/CPU, recovery có backoff và JPEG/XYZ cùng khung.
- Script khởi động kiểm tra code cũ trong RAM và engine ensemble chưa được nạp.

## Notebook và lần train sau

Đã sửa mask trong CELL 4 và cả hai bản runtime được CELL 6C đóng gói trên cùng notebook Drive `1Jo-DuBTsrOxbaj8ZLme315iG0v9p7zZW`. Đã đọc lại xác nhận SHA256 `9248b12aa9198025a7762dc40625a209d8f7c53403a44eb1240713c268e76855`. Không chạy train; output cũ được ghi chú là của ngày 18/10. Ensemble hiện do service adapter và `.runtime/word-ensemble.json` quản lý.

Trước lần train tiếp cần:

- Bổ sung VAL theo người/phiên cho những từ còn thiếu: export chỉ phủ 29/181 từ. Bốn video cùng phiên không chứng minh tổng quát hóa.
- Bổ sung TRAIN/VAL nền thực tế; manifest dữ liệu thật mới hiện chưa có. Giữ TEST hồi quy tách riêng.
- Rà biến thể theo nguồn, người/phiên, một/hai tay. Chuẩn hóa nhãn trùng chính tả như “ngôn ngữ kí hiệu” và “ngôn ngữ ký hiệu”.
- Giữ sampler label/source/session-balanced đã có, không thêm frequency weighting lần nữa chỉ theo số file.
- Kiểm tra augmentation giảm FPS/mất quan sát và ranh giới ký hiệu trên TRAIN, giữ timestamp/mask đồng bộ. Không gán nhãn bừa cho prefix chưa hoàn tất.
- TCN hiện đã dùng Conv1D 64, GRU 96, Dense 128; không phải mạng cũ 58K tham số. Đánh giá thay đổi bằng causal VAL và sự kiện sai, không chỉ Train Accuracy.

## Log và Android

Service hiện bật log tọa độ ở `.runtime/camera-replays`, tối đa 3600 quan sát/phiên. File được lưu khi quay lại/đóng camera, gồm pose/wrist/context, timestamp, kết quả và policy. Không lưu ảnh/âm thanh trong trace. Metadata đánh dấu `regression_only`, `use_for_training=false`. Đã kiểm tra lưu/đọc được file 61 quan sát.

APK dùng `camera_capture_native.dart`, hỗ trợ camera trước/sau và xoay sensor; không dùng worker Chrome. Bản native hiện gửi ảnh về service, nên phụ thuộc mạng. `10.0.2.2` chỉ dành cho emulator; điện thoại thật cần URL LAN/HTTPS truy cập được.

Chưa triển khai hoặc đo MediaPipe Android trên thiết bị thật. Hướng tối ưu tiếp là detector chạy nền trên thiết bị, giữ khung mới nhất; chuyển mạng nhận diện sang định dạng di động cần kiểm tra tương thích và đo thực tế. Không mặc định GRU/LSTM sẽ được GPU di động tăng tốc.

[Hướng dẫn MediaPipe Android chính thức](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/android)

## Xác minh

35 Python tests, 109 Flutter tests, 6 worker tests qua; Dart analyze sạch và build web release thành công. Service 8001 xác nhận hai model chạy và trace lưu được. Chưa đo FPS trình duyệt V6 hoặc kiểm thử APK thật.

Restart bổ sung bị automatic review chặn. Đã giữ service V6 được xác minh và bỏ các thay đổi log phụ chưa nạp; không dùng cách khác để vượt chặn.
