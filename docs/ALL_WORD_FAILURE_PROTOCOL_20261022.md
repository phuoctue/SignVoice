# Phân rã lỗi toàn bộ từ — giao thức 22/10/2026

Khóa trước lượt chạy: dùng đúng 297 clip calibration phát triển của bundle app, gồm 157/181 từ. Không dùng audit, không bổ sung clip được chọn vì dễ nhận, không gộp 34 clip TRAIN rau vào kết quả này. Không thay model, policy, cadence hoặc app. Nhãn nguồn và người ký chưa được xác minh độc lập toàn bộ; chào KhangCN được báo riêng.

## Ba tầng và đối chứng

1. Đưa trọn clip qua `prepare_sign_sequence` và `gesture_interval`, rồi gọi word head hiện tại. Ranh giới dùng thông tin tương lai; chỉ là chẩn đoán clip cắt, không phải accuracy live hoặc checkpoint epoch VAL của một notebook khác.
2. Replay nguyên dấu thời gian và landmark đã kiểm checksum, quan sát mọi cửa sổ thực sự được runtime xét. Lưu nhãn đầu, điểm nhãn đúng, mask, coverage, margin, eligibility và cửa sổ được chọn. Không lấy cực đại từng nhãn rồi dựng dự đoán oracle.
3. Quan sát trực tiếp giá trị trả về và trạng thái của `StableDecision.update`; lưu nhãn đầu sau smoothing, reliable/readiness, candidate/since, dwell, lock và sự kiện. Không thay hàm quyết định hoặc lặp lại logic chốt để tạo kết quả mới.

Hook chỉ quan sát. Với từng clip, replay lần hai không hook phải khớp vector điểm ở **mọi khung đầu vào** (atol 2e-5, rtol 5e-4), output/ranking/flag và event phải giống hệt. Event còn phải giống kết quả reference đã đóng băng từ lượt component comparison. Identity model/config/runtime trước và sau phải giữ nguyên. Không khớp thì dừng, không đọc kết quả tiếp.

## Phân loại

Mỗi clip có một nhóm trạng thái theo thứ tự: chốt cuối đúng; từng chốt đúng rồi bị nhãn khác thay thế; candidate đúng đủ dwell nhưng không phát; candidate đúng reliable nhưng chưa đủ dwell; word head ready nhưng decision chưa reliable; có cửa sổ nhãn đúng eligible nhưng chưa chốt; nhãn đúng từng đứng đầu nhưng chưa qua cổng; nhãn đúng chưa từng đứng đầu cửa sổ; không có inference hợp lệ. Đây là mô tả đường đi quan sát được, **không phải chứng minh nguyên nhân duy nhất**. Các cờ clip cắt đúng/đủ điều kiện được báo song song, không dùng để áp đặt nguyên nhân.

Chỉ gọi một nhóm là chiếm đa số nếu nó chứa **hơn 50% clip không chốt đúng cuối cùng**. Nếu không có nhóm nào vượt, kết luận hỗn hợp. Khi tính lý do từ chối, bỏ bước khởi động chưa inference, chỉ xét bước decision đứng đầu là nhãn đúng; chuẩn hóa trong từng clip rồi mới trung bình. Không đếm tổng bước để clip dài chi phối. Không dùng lý do từ chối đầu tiên.

Mọi candidate đúng reliable đã đạt dwell mà không confirmed, không có lock, đều được đánh dấu mâu thuẫn để kiểm tra; không tự quy cho dwell. Lưu riêng mọi sự kiện sai và score/margin lúc phát, kể cả clip cuối cùng đúng. Đếm phát trùng liên tiếp.

## Thực thi và giới hạn

Chạy smoke cố định 9 clip (3 đúng, 3 không chốt, 3 sai) ở thư mục riêng trước. Smoke chỉ kiểm công cụ. Mã/hợp đồng không đổi sau smoke. Lượt đầy đủ ghi JSONL sau từng clip, xác minh hợp đồng khi tiếp tục. Báo đủ 181 từ; 24 từ không có calibration được ghi thiếu dữ liệu.

Không chọn ngưỡng, không thay app từ kết quả này. Không có nền thật nên không tính false accept/phút. Tập đã được xem nhiều lần, kết quả chỉ dùng phát triển. Chẩn đoán webcam là đối chiếu kỹ thuật riêng, không trộn vào mẫu đánh giá nguồn hoặc dùng để tuyên bố đã sửa nhận diện.

Sửa công cụ trước lượt v2: lượt đầu dừng ở clip thiếu quan sát tay. Với dưới 3 khung tay hợp lệ sau chuẩn bị, không gọi model clip cắt; ghi `available=False`, số khung và lý do. Vẫn giữ clip trong mẫu đánh giá stream và mẫu số. Không nuốt những lỗi khác. Đã bổ sung unit test và chạy lại smoke ở thư mục v2; lượt full v1 chưa hoàn tất không được dùng làm báo cáo cuối.
