# Thử giữ điểm bắt đầu cửa sổ — kết quả 22/10/2026

**Đã chạy đủ 297 clip phát triển thuộc 157/181 từ; mọi đối chứng null khớp. Model, score/margin/dwell và nhịp dự đoán giữ nguyên.**

Can thiệp: thêm tối đa một cửa sổ nối tiếp từ điểm bắt đầu active interval vừa đủ điều kiện, luôn dùng khung mới nhất; hết hạn sau 0,60 giây hoặc khi buffer reset. Không nhớ nhãn, không lấy lại điểm cũ.

| Chỉ số | Reference | Cửa sổ nối tiếp |
|---|---:|---:|
| Clip đúng | 171 | 170 |
| Clip sai cuối cùng | 8 | 9 |
| Không chốt | 118 | 118 |
| Precision trên clip đã chốt | 95.53% | 94.97% |
| Macro recall | 57.01% | 56.37% |
| Sự kiện sai (kể cả clip cuối đúng) | 16 | 17 |
| Sự kiện trùng nhãn liên tiếp | 0 | 0 |

Thêm đúng 0 clip, mất đúng 1 clip; 0 từ tăng và 1 từ giảm số đúng. Danh sách cụ thể giữ trong comparison.json và verified-reading.json, không chỉ xem một từ hứa hẹn.

Cận mô tả 95% của delta macro recall: [-0.006369426751592357, -0.006369426751592357]. Bootstrap tuyến tính hóa giữ trọng số lớp có khoảng suy biến: **True**. Khi khác biệt chỉ ở một lớp có một clip, residual lớp đó bằng 0 nên khoảng này không thể hiện bất định của lớp; không dùng để tuyên bố thua có ý nghĩa thống kê. Kiểm định McNemar exact hai phía cho clip được/mất: p=1.0000. Cụm gần như từng video, không phải kiểm chứng người ký mới; tập phát triển đã được xem nhiều lần.

369 cửa sổ bổ sung được dựng trong lượt này; chưa đo chi phí trên điện thoại thật.

## Các điều kiện đã chốt

- `correct_increased`: **False**.
- `macro_ci_positive`: **False**.
- `precision_floor_met`: **False**.
- `precision_not_lower`: **False**.
- `wrong_clips_not_increased`: **False**.
- `wrong_events_not_increased`: **False**.
- `duplicate_events_not_increased`: **True**.
- `represented_critical_not_lost`: **True**.

Qua toàn bộ sàng lọc phát triển: **False**. Không đạt không chứng minh mọi biến thể cửa sổ đều vô ích; không được đổi tham số sau khi xem rồi gọi đó là kiểm thử độc lập.

## Bản ghi webcam đã xem

Nhánh null khớp 231/231 batch. Reference có 0 sự kiện; candidate có 1: `[{"time": 15.999, "label": "nhìn"}]`.

Bản ghi này theo thứ tự chào → nghe → nhìn → rau, ranh giới đối chiếu video là xấp xỉ. Nhận thêm một từ không chứng minh đã sửa những từ còn lại hoặc cải thiện webcam độc lập. Không dùng video này để chỉnh TTL/ngưỡng cho đẹp kết quả.

## Quyết định

Không bật nhánh thử trong app hoặc public vì chưa qua các điều kiện đã chốt. Giữ reference hiện tại làm đối chứng; không gọi chất lượng webcam hiện tại là đạt.

Không thay kiến trúc hay train lại trong lượt này. Không tuyên bố đã tối ưu FPS hoặc độ trễ điện thoại: mọi lượt ở đây là replay feature offline. Không đo false accept/phút khi thiếu nền thật. 24 từ không có calibration vẫn chưa được kiểm chứng.

## Tệp tái hiện

- Bảng đầy đủ 181 từ: `.runtime\anchored-windows-20261022\full\all-181-words-comparison.csv`.
- Hợp đồng, journal từng clip, bảng clip được/mất và đối chứng: `.runtime\anchored-windows-20261022\full`.
- Giao thức: `docs/ANCHORED_WINDOW_PROTOCOL_20261022.md`.
- Mã thử offline: `ai_service/experiment_anchored_windows.py`; kiểm lại: `ai_service/review_anchored_windows.py`.
