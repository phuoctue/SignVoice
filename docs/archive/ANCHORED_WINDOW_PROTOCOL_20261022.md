# Thử giữ điểm bắt đầu cửa sổ — 22/10/2026

Đăng ký trước khi chạy: một thay đổi chung, cùng model và policy app, cùng 297 clip phát triển thuộc 157 từ. Đây là giả thuyết gợi ý bởi tập đã xem nhiều lần, không phải TEST độc lập. Không dùng audit và không quét tham số. Nhánh giữ nhãn cũ ở Colab không được xem là bằng chứng cho phép thử này.

## Can thiệp duy nhất

Khi word head hiện tại chọn một cửa sổ đủ điều kiện và có readiness, ghi điểm bắt đầu active interval đó. Trong tối đa `tracking_gap_seconds` hiện tại (0,60 giây), thêm tối đa một cửa sổ bắt đầu tại đó và kết thúc ở quan sát mới nhất trong buffer. Không gia hạn thời điểm tạo anchor. Nếu buffer mất đầu đoạn, hết hạn hoặc reset, xóa anchor. Sau khi hết hạn chỉ được tạo anchor mới từ một dự đoán hiện tại đủ điều kiện.

Cửa sổ bổ sung chứa các mẫu tay/context thật mới đến, bao gồm cả mất tay, dùng cùng sửa khoảng trống và mask quan sát như cửa sổ gốc. Tối thiểu 6 quan sát tay và span 0,35 giây như buffer gốc. Cửa sổ trùng được loại; head vẫn tự dedup feature. Các cửa sổ gốc được giữ lại. Không nhớ nhãn để ưu tiên nhãn, không lấy lại điểm cũ, không đóng băng cả đoạn, không suy diễn landmark hoặc trộn điểm cực đại từng nhãn. Thuật toán chọn một cửa sổ và mọi cổng score/margin/coverage/pair/motion/dwell, background, smoothing giữ nguyên. Nhịp suy luận không đổi.

## Đối chứng trước phép so sánh

1. Unit test: anchor hết hạn/reset; không dùng đầu vào cũ; không tạo anchor từ dự đoán chưa đủ điều kiện; nhánh tắt không thêm cửa sổ; thêm metadata không đổi output; từ chối runtime khác.
2. Smoke riêng 9 clip cố định (3 đúng, 3 sai, 3 không chốt), không dùng để kết luận hiệu quả. Chỉ chạy FULL sau khi smoke qua, không sửa mã giữa hai lượt.
3. Với từng clip FULL: reference phải khớp event đã đóng băng; nhánh metadata/adapter tắt phải khớp mọi vector điểm đầu vào (atol 2e-5, rtol 5e-4), output/ranking/flag và event phải giống hệt. Nhánh bật không can thiệp lớp quyết định. Identity model/config/runtime gốc trước/sau giữ nguyên.
4. Dữ liệu video/feature nguồn được xác minh checksum. Hợp đồng băm mã, dependency, cohort và webcam JSON. Lưu kết quả từng clip để tiếp tục cùng hợp đồng.

## Tiêu chí đọc đã chốt

Chỉ gọi là qua sàng lọc phát triển nếu đồng thời: số clip đúng tăng; cận dưới CI mô tả paired cluster macro-recall delta >0; precision >= max(0,95, reference); clip sai, sự kiện sai và sự kiện trùng không tăng; số đúng của các từ ưu tiên có mẫu không giảm. Phải báo riêng clip được/mất, theo nguồn, thiếu mẫu, phần loại chào KhangCN chưa xác minh. Cụm gần như từng video, không diễn giải CI thành kiểm chứng người mới. Sàng lọc nghiêm có thể không đạt; khi đó không kết luận phương pháp vô ích.

Replay thêm bản ghi webcam đã xem với đúng batch/generation/allow_prediction. Reference/metadata null phải khớp 231 batch gốc. Kết quả candidate chỉ là probe phát triển, không đo accuracy độc lập. Không dùng các khung webcam này để chỉnh tham số nếu kết quả không đẹp.

Chưa có nền thật hoặc tập webcam độc lập, nên **không tự triển khai**, kể cả nếu các điều kiện phát triển đều đạt. Không đo latency thiết bị thật bằng wall time offline. Thêm một cửa sổ có thể tăng lượng suy luận, cần đo riêng nếu phương pháp hứa hẹn.
