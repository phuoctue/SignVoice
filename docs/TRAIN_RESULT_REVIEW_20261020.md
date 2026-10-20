# Kết quả train mới — 20/10/2026

Đã đọc notebook đang lưu trên Drive và tải các báo cáo từ `models/rgb_camera_audit_2026_10_20`. Các cell 6–9 hoàn tất, không có traceback; CELL 9 xác nhận ZIP và kiểm tra lưu/nạp model thành công. Mã nguồn notebook vẫn khớp bản đã rà. Chưa thay model đang phục vụ app.

## Kết luận

Chưa có bằng chứng bản mới nhận diện webcam tốt hơn. Những chỉ số hiện có chưa đủ để khuyến nghị thay bản đang chạy. Không được dùng train accuracy khoảng 93% để kết luận accuracy webcam.

## So với bản 181 từ trước

| Chỉ số báo cáo | Bản trước | Bản mới |
|---|---:|---:|
| Clip calibration dùng replay | 297 | 286 |
| Accuracy nhãn được chốt cuối cùng | 56,23% | 55,59% |
| Coverage clip có kết quả | 58,59% | 58,74% |
| Sự kiện khác nhãn đích | 14 | 16 |
| TRAIN sanity đúng, tập con 362 clip | 235 | 232 |

Các tập calibration đã thay đổi; bảng tổng trên chỉ là thông tin lịch sử, không phải A/B trên cùng TEST. Pipeline mới còn giữ mask mất tay đúng hơn nên cách xử lý cũng thay đổi.

Đối chiếu **91 video ID chung** trong hai báo cáo calibration, nhãn đích khớp toàn bộ:

- Bản trước: đúng 53/91, có kết quả 53/91, không có sự kiện khác nhãn đích.
- Bản mới: đúng 48/91, có kết quả 50/91, hai sự kiện khác nhãn đích.

Đây vẫn là các clip đã dùng calibration, không phải TEST độc lập. Chưa chạy lại hai bundle bằng cùng một harness trên TEST camera.

## Audit sau khi khóa cấu hình của bản mới

536 video / 149 từ; accuracy nhãn chốt cuối 58,40%; macro recall 55,38%; 40 sự kiện khác nhãn đích. Không có nền sinh hoạt audit độc lập và không xác minh người ký mới. Không có báo cáo audit tương ứng của bản cũ để kết luận chênh lệch trên tập này.

| Từ người dùng thường test | Đúng / số clip audit | Ghi chú |
|---|---:|---|
| chào | 0/7 | 5 clip không có kết quả cuối; 2 sự kiện nhầm |
| nghe | 0/1 | Không có kết quả |
| nhìn | 0/1 | Không có kết quả |
| rau | 0/1 | Không có kết quả |
| cứu | 1/1 | Một mẫu chưa đủ kết luận ổn định |
| bàn tay | — | Chưa có clip audit riêng |

## Hai model có được dùng cùng nhau không?

Có. Cấu hình mới vẫn chọn `probability_ensemble`, TCN 50% và embedding 50%, cùng temperature TCN 1.0 / embedding 0.06, score 0.60, margin 0.20, dwell 0.30 giây như bản trước. Hash model đã thay đổi, không phải tái xuất lại weights cũ.

Clean calibration clip của bản mới: TCN top-1 84,16%, prototype top-1 79,90% trên 587 clip. Bản trước tương ứng 86,34% / 81,63% trên 849 clip; số liệu này cũng không phải so sánh trên cùng tập. Chênh lệch giữa clean clip và causal stream cho thấy cần tiếp tục kiểm tra đoạn chuyển động, điều kiện xác nhận, đặc trưng và biến thể thay vì chỉ tăng epoch.

Bằng chứng tại thư mục `notebook_audit_20261020` trong workspace: `result_check_20261020.ipynb`, các file `new_result_*.json`, `new_vs_old_reported_calibration.json`. Bước xác định bản nào phù hợp triển khai là replay hai bundle đã khóa trên cùng TEST camera riêng, đo đúng/nhầm/bỏ sót và thời gian chốt, không chỉnh ngưỡng theo TEST.
