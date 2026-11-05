# SignVoice — kiểm tra camera ngày 18/10/2026

## Kết quả áp dụng

- Đã khởi động lại riêng Flutter ở `http://localhost:8080`, kết nối AI `http://localhost:8001`.
- AI cũ vẫn chạy bằng chính tiến trình Python 25020, trả về `word_classes: 144`, `stable_two_hand_v5`, `verified_colab_export`. Không khởi động lại AI và không nạp bộ 234 từ trên ổ đĩa.
- Các tài nguyên worker, SDK JavaScript và WASM mới đều trả HTTP 200; WASM có MIME `application/wasm`.
- Service thử nghiệm 8002 đã tắt. Không đổi backend 3000 hay LM Studio.

## Video và mẫu “chào”

Nguồn kiểm tra: `C:\Users\Phuoc Tue\Downloads\Recording 2026-10-18 191159.mp4`, 38,2 giây, 1.146 khung hình, 30 FPS, 756 × 1.390. Đây là bản quay màn hình có giao diện và landmark sẵn, không phải camera raw.

Trang người dùng cung cấp ghi “chào”, vùng miền **Toàn Quốc**: https://tudienngonngukyhieu.com/tu-ngu/chao-11664. Các mẫu namwu đã đối chiếu có một tay hoạt động gần trán rồi đưa ra ngoài, tay còn lại có thể nghỉ phía trước bụng. Việc nhìn thấy hai bàn tay trong ảnh không có nghĩa cả hai cùng thực hiện động tác. Không có căn cứ quy lỗi cho người dùng chỉ vì làm một tay.

Trong bản quay màn hình, khoảng 12,4 giây ứng dụng từng chốt nhầm “bạn gái” khi người dùng đang làm “chào”; “nghe” được nhận muộn, còn “nhìn” chưa được chốt. Điều này cho thấy cần đánh giá cả nhận nhầm, không chỉ đếm số lần hiện kết quả. Không dùng video này để train hoặc chọn ngưỡng.

## Những thay đổi camera

1. Web Worker chạy MediaPipe Hand Landmarker bằng GPU trình duyệt, tối đa hai tay. SDK 0.10.32, WASM và model được lưu trong app, không gọi CDN khi mở camera.
2. Landmark hiển thị chạy độc lập với JPEG, WebSocket, suy luận Colab và LM Studio. Chỉ vẽ lại lớp landmark; không dựng lại toàn bộ màn hình theo từng điểm tay.
3. Mỗi worker chỉ giữ một khung đang xử lý, bỏ khung trùng và đóng ImageBitmap sau khi dùng. Không tạo hàng đợi ảnh cũ làm điểm tay đuổi theo chuyển động.
4. Nếu GPU lỗi hoặc quá hạn, dùng lại điểm từ service. Khi đổi camera/thoát màn hình, hủy worker, timer và subscription. Khi mất kết nối, xóa kết quả cũ.
5. Điểm GPU này chỉ phục vụ hiển thị; **không thay đặc trưng đầu vào của model đã train**. AI vẫn nhận pixel camera gốc, dùng extractor đã xuất từ Colab. Một landmark xuất hiện không được coi là đã nhận đúng từ.
6. Luồng gửi JPEG dùng khung video mới, canvas tái sử dụng và cơ chế ACK; không đợi LM Studio để tiếp tục bắt hình. Giữ màn hình xin phép trước khi mở thiết bị, preview camera trước/sau và kết quả đơn.

## Đo tốc độ và kiểm thử

Thử 20 ảnh raw giống nhau, bỏ ba lượt đầu khi tính trung vị:

| Nhánh đo | Trung vị xử lý | Khung có phát hiện tay |
|---|---:|---:|
| Worker GPU Intel Iris Xe | 56,0 ms | 20/20 |
| Service thử nghiệm CPU | 73,7 ms | 14/20 |

Đây là phép kiểm tra nhỏ trên ảnh có sẵn. Hai nhánh có backend phát hiện khác nhau; thời gian worker và thời gian toàn service cũng không có cùng phạm vi xử lý. Không quy đổi thành FPS webcam thực tế, độ chính xác từ hay mức tăng accuracy. Chưa đo đồng thời camera vật lý + GPU + service trong phiên người dùng.

- 109 kiểm thử Flutter thành công.
- 21 kiểm thử Python service thành công.
- Phân tích Dart phần thay đổi: không phát hiện lỗi.
- Web JavaScript release build thành công tại `build/ai-web`.
- WebSocket thật với candidate 144 từ: 20 khung đi qua pipeline.
- Trang app tải được trong browser kiểm thử, không có lỗi console được ghi nhận; công cụ không chụp được màn hình phiên đó. Không khẳng định đã QA camera vật lý qua browser.

Chứng cứ: `browser_worker_result.json`, `candidate_smoke.json`, `contact.jpg`; log test/build ở `.runtime/gpu-*` trong dự án app.

## Chọn model an toàn cho các lần sau

Bản gốc 144 từ đã được khôi phục và kiểm đủ chín checksum tại:

`E:\WorkSpace\SignVoice\SignVoice\ai_service\models\144_2026_10_16`

File `.runtime/ai-model-selection.json` khóa lần khởi động AI tiếp theo vào bộ này. Manifest SHA256: `5747596b86483e376f135b732ed0c0b478b2360f22cc06463e38d34e23bdaf01`; word model SHA256: `a0d7d3d59079d0952b2178cfed54955495319f1a6d18efb4eaf97138d07154d5`.

Service mới kiểm checksum và hợp đồng đặc trưng, không tự chọn model vì file mới hơn. Bổ sung `probe_video.py` để kiểm tra một bộ model được chọn bằng video raw hoặc ROI rõ ràng. Bản raw hồi quy chỉ dùng kiểm thử.

Các thay đổi Python mới về chọn model, giới hạn thread, thống kê detector và snapshot suy luận đã được kiểm thử ở cổng 8002 nhưng **chưa được nạp vào tiến trình 8001**, để giữ nguyên model đang chạy theo yêu cầu. Health cũ không có model hash nên không khẳng định đối chiếu bitwise được model đang nằm trong RAM với bản khôi phục.

## Giới hạn còn lại và cách kiểm tra

Tối ưu này xử lý độ trễ điểm tay và đường truyền. Chưa chứng minh model 144 từ đã nhận đúng “chào/nhìn” trên webcam. Không hạ ngưỡng, không ép kết quả từ LM Studio và không lấy video TEST làm TRAIN để làm đẹp số liệu.

Trong cửa sổ Flutter vừa mở, vào Ký hiệu → Giọng nói, bấm Cho phép camera; mở cài đặt để xem FPS landmark cục bộ và độ trễ service riêng. Test lại các từ với khoảng nghỉ và cả hoạt động không ký hiệu. Kết quả cần đánh giá cả bỏ sót lẫn nhận nhầm. Khi có bản model mới, kiểm tra feature/checksum và so sánh trên VAL riêng trước khi chủ động đổi model được chọn.
