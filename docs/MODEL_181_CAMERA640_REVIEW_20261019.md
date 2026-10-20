# Model 181 camera640 và đường truyền landmark độc lập JPEG

## Nguồn đã kiểm tra

- ZIP: `E:\WorkSpace\SignVoice\SignVoice_Model_Files (1).zip` (71.185.597 byte).
- Notebook tải xuống: `C:\Users\Phuoc Tue\Downloads\Train_SignVoice_Transfer_v3_2026.ipynb`, SHA-256 `46d6246927cea806fb6c89308665faf43aae7e0db2364b9f233be143d3238d40`.
- Không truy cập được trang Colab bằng công cụ web; browser local đang bị tắt trong Work settings. Không thay đổi notebook trên Drive. Đã đọc notebook tải xuống: không có output lỗi, CELL 9 xác minh ZIP thành công. `SHARED_CAMERA_SOURCE` trong notebook khớp từng byte với `test_camera.py` trong ZIP (166.398 byte; SHA-256 `09e5fa1fdd071a353531338c35f7c54f76e95c44033a9f9fa776a01b8645351c`).
- Manifest model mới: `af23aa8892a736db57dedf4ac0e688cdc22da1fbe160dfbcd937e05da2f8609b`.
- Model mới nằm riêng ở `ai_service/models/181_2026_10_19_camera640`. Không trộn file với export cũ và không ghi đè thư mục model cũ. Selection cũ được giữ ở `.runtime/new-bundle-review/previous-model-selection.json`.

## Kết quả và giới hạn

- 181 từ, 219 nhãn tổng cộng, pipeline `stable_two_hand_v6_camera640`. Hai mạng `embedding_model_v2.keras` và `word_temporal.keras` cùng được dùng trong nhánh từ; ensemble 50/50, score .60, margin .20, dwell .30 giây theo export. LM Studio không tham gia nhận diện camera.
- Clean source VAL: 849 video, 157 nhãn, TCN top-1 86,34%; prototype top-1 81,63%. Đây là video cắt sẵn, không có từ chối theo score/dwell.
- Source calibration stream: 297 video, đúng 56,23%, coverage 58,59%, 14 wrong events. Các video source VAL được dùng chọn policy; các số này không phải accuracy webcam độc lập. Không so trực tiếp với bản trước 57 video để tuyên bố cải thiện accuracy.
- 24 từ chưa có VAL, chưa có tập VAL nền sinh hoạt độc lập. Dữ liệu chưa chứng minh khả năng từ chối chuyển động không phải ký hiệu ngoài thực tế.
- Nhánh chữ/số chọn trên 31 source VAL: macro 61,29%, dynamic macro 80%. Trọng số embedding .30 có bằng chứng lựa chọn trong notebook; giữ đúng export sau khi đọc bản notebook. Không dùng video TEST để tự chọn lại trọng số hoặc hạ threshold.
- Body ablation đã tắt; không có nhánh vai/khuỷu tay được chọn trong ZIP này.

## Video phản hồi và nguyên nhân được xác minh

Video `1792426622375_49545263168060327_3028160589505783569.mp4` dài 36,522 giây. Trong ảnh màn hình có các chữ đã chốt như `ô`, `x`, `h`, `i`, nhưng không khớp chuỗi người dùng đang thử. Trace phiên `20261019T160821Z_c319ad16.npz` có 345 mẫu trong 32,543 giây, 46 ảnh; inference trung vị khoảng 495 ms, P90 khoảng 773 ms. Landmark tại thiết bị nhanh hơn nhịp JPEG tới service.

Đối chiếu 19 cửa sổ của trace này với runtime trước/sau tối ưu lần trước, dùng cùng bundle cũ và cả embedding thật: vector điểm và readiness mask bằng nhau từng phần tử. Chưa có bằng chứng tối ưu NumPy trước đó làm đổi dự đoán. Không khẳng định chỉ từ video rằng thuật toán đã gây regression accuracy. Trace/test chỉ dùng hồi quy, không dùng TRAIN hoặc chọn policy.

## Thay đổi camera/service

- Worker web 8.5 gửi quan sát XYZ/handedness đo thật ngay trong preview, trước JPEG; Android gửi cùng metadata trong preview native. Điểm XY hiển thị không bị dùng thay XYZ nhận diện.
- Flutter gửi gói JSON nhỏ riêng trong mode Chữ cái/Chữ số khi server quảng bá `live_glyph_observations`. Giới hạn 10 Hz theo timestamp capture, một gói chờ ACK, không tạo hàng đợi tích lũy. Chế độ từ/all tiếp tục yêu cầu pipeline ảnh/mốc mặt.
- Server kiểm tra SDK, hash hand model, kích thước, timestamp, số tay và XYZ hữu hạn; giới hạn JSON 16 KiB, một quan sát chờ. Gói sai model không được giả làm kết quả CPU. MediaPipe vẫn có một owner executor trong mỗi session.
- Quan sát landmark có thể chạy và phát kết quả trước cả JPEG đầu tiên. OpenCV/face vẫn chạy trên ảnh thực; gói chỉ có landmark dùng context zero mask, không gán mặt từ ảnh cũ thành phép đo mới.
- Ảnh JPEG đến muộn hơn quan sát mới chỉ phục vụ phân tích ảnh, không đưa điểm cũ quay ngược tracker/chuỗi. Timestamp trùng/lùi không được thêm lại. Snapshot inference được gửi ngay khi hoàn tất như sửa trước.
- Giữ hỗ trợ cả pipeline v5 và v6, kiểm tra checksum face/template cho cả hai. Giữ cache DTW/gom điểm chính xác và cơ chế hold/rearm đã kiểm thử. Giữ policy nhận diện của bundle mới.

## Xác minh

- 66 Python tests, 23 Flutter tests, 22 worker JS tests qua. Dart analyze không có vấn đề.
- `:app:compileDebugKotlin --offline --no-daemon` thành công, 111 tasks; đây là kiểm tra biên dịch, không phải đo FPS điện thoại thật hoặc cài APK.
- Flutter web release build thành công. Service public khớp SHA mã runtime/engine và manifest model mới.
- WSS public tại `https://newtanboard42.conveyor.cloud`: gửi 10 quan sát giả lập, tối đa 995 byte/gói, **0 JPEG**; service ACK đủ, chạy inference và gửi snapshot mới với đúng timestamp cuối. Source worker public khớp source trên đĩa. Đây là transport smoke test, không chứng minh nhận đúng ký hiệu/accuracy/FPS. Trace giả lập đã tách sang `.runtime/smoke-replays`.
- Báo cáo máy đọc được: `.runtime/new-bundle-review/review_summary.json`, `replay_comparison.json`, `public_verification.json`.

Cần test lại ă/â/ê/ô/ơ trên điện thoại với bản web vừa tải lại để đo thời gian từ động tác tới chốt chữ. Không đảm bảo dưới một giây hoặc nhận đúng toàn bộ ký hiệu khi chưa có lần đo đó. Chạy public tiếp bằng `scripts/start-public-server.ps1`; selection mới đã được pin, không cần train lại chỉ để nhận thay đổi transport.
