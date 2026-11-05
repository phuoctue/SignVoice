# Camera web — kiểm tra ngày 19/10/2026

Đã bỏ LM Studio khỏi quyết định nhận diện camera, kể cả client còn lưu vision=true. LM chỉ còn vai trò xử lý câu ở luồng riêng.

Browser gửi landmark XYZ và JPEG lấy từ cùng một khung hình. Service chỉ dùng landmark này khi phiên bản SDK, SHA256 model, kích thước và timestamp khớp; nếu không hỗ trợ thì dùng CPU. OpenCV vẫn chạy. Retry IMAGE trên CPU có backoff khi thất bại liên tiếp.

Kiểm thử: 27 Python, 109 Flutter; phân tích Dart không có lỗi; build web release thành công.

Replay Recording 2026-10-18 231542.mp4 (video màn hình, không phải raw):
- Words: 662 kết quả GPU, median GPU 38.6 ms, service 6.45 ms.
- All: 857 kết quả GPU, median GPU 38.5 ms, service 4.7 ms.
- Trước sửa, replay CPU words median xử lý service 301 ms. ROI và điều kiện replay khác nhau nên đây là số chẩn đoán, không phải benchmark đối chứng chính xác.
- Số bàn tay trước/sau bộ lọc service giống nhau trong replay GPU.
- Vẫn có kết quả sai: con mèo/mèo; mode all còn phát chữ cái trong lúc thực hiện từ. Chưa chứng minh độ chính xác webcam tăng.
- Video có landmark/khung cũ đè lên tay; cần kiểm tra camera thật hoặc raw không overlay để đánh giá dò tay.

Không thay đổi model 181 từ, ngưỡng, dữ liệu train; không dùng video này để huấn luyện hoặc chọn ngưỡng. Validation causal của model trước đó chỉ đạt 17/57; tốc độ camera được cải thiện không giải quyết hết lỗi phân loại.

Service dùng cổng 8001. Flutter web dùng 8080. Trong cài đặt camera, kiểm tra thông báo AI dùng landmark GPU cùng khung hình. Nếu là CPU dự phòng, kiểm tra WebGL/worker của trình duyệt.
