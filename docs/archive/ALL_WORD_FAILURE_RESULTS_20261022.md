# Chẩn đoán chung cho 181 từ — 22/10/2026

**Đã kiểm đủ 297 clip phát triển thuộc 157/181 từ; 24 từ thiếu calibration. Không thay model hoặc policy trong app.**

Đối chứng khớp 297/297 clip ở mọi đầu vào, output và sự kiện; còn khớp reference đã đóng băng. Kết quả stream giữ nguyên: 171 đúng, 8 sai, 118 không chốt. Có 101 từ có ít nhất một clip không chốt đúng cuối cùng.

## Các tầng lỗi

Word head clip cắt xếp đúng đầu 255/297; sẵn sàng nhãn đúng 213/297. Có 3 clip không đủ đầu vào để chạy clip cắt. Ranh giới clip cắt dùng thông tin tương lai và chưa chạy dwell, nên không coi là accuracy live hoặc số VAL của notebook.

| Trạng thái quan sát trên 126 clip không chốt đúng cuối cùng | Clip | Tỷ lệ |
|---|---:|---:|
| Candidate đúng reliable, chuỗi ngắn hơn dwell | 61 | 48.4% |
| Nhãn đúng chưa từng đứng đầu cửa sổ live | 19 | 15.1% |
| Từng đứng đầu cửa sổ, chưa sẵn sàng ở head được chọn | 36 | 28.6% |
| Không có cửa sổ inference live hợp lệ | 8 | 6.3% |
| Có cửa sổ đúng eligible nhưng chưa được head chọn để chốt | 2 | 1.6% |

Không có nhóm nào vượt 50%; lỗi hỗn hợp theo định nghĩa chốt trước.

Trong nhóm thất bại, 85 clip xếp nhãn đúng đầu ở clip cắt; 51 clip còn đủ điều kiện head ở clip cắt. Không quy toàn bộ nhóm này cho dwell: bảng phân rã trong verified-reading.json giữ từng trạng thái riêng.

Nhóm “từng đứng đầu cửa sổ, chưa sẵn sàng ở head được chọn” có thể gồm ngưỡng, mask, ưu tiên slot gốc và cạnh tranh giữa cửa sổ. Không đọc nó thành chỉ một nguyên nhân. Nhóm “có cửa sổ đúng eligible” là eligibility thực tế sau ưu tiên slot gốc; không dựng oracle từ điểm cực đại từng nhãn.

Trong 93 clip thất bại có nhãn đúng đứng đầu decision ít nhất một bước inference, tỷ lệ lý do đã được chuẩn hóa trong từng clip, rồi trung bình:

| Tập lý do cùng xuất hiện ở bước decision nhãn đúng | Trung bình tỷ lệ bước trong clip |
|---|---:|
| head_readiness | 1.83% |
| qualified | 47.03% |
| score+head_readiness | 30.03% |
| score+margin+head_readiness | 21.11% |

`qualified` nghĩa là bước đã qua cổng điểm/margin/readiness, không đồng nghĩa đã phát sự kiện. Startup chưa inference bị loại. Các tỷ lệ có điều kiện này không đại diện cho toàn bộ 126 clip thất bại, và không tự xác định nguyên nhân của clip chưa từng đứng đầu decision.

## Kiểm tra phía nhận nhầm

Có 16 sự kiện sai, không chỉ 8 clip sai cuối cùng. Điểm decision của sự kiện sai nằm trong [0.6152; 0.9624]; trung vị 0.7445, so với 0.8985 của sự kiện đúng. Đây chỉ là mô tả tại thời điểm phát; chưa phải replay ngưỡng mới.

Không có candidate đúng đủ dwell mà thiếu confirmed không giải thích được. Có 0 sự kiện trùng nhãn liên tiếp; chưa thể xác định tất cả là phát lặp sai vì clip nguồn không có ranh giới số lần ký độc lập.

Mọi sự kiện sai giữ video ID, nhãn nguồn, nhãn phát, thời gian, score và margin trong verified-reading.json. Nhãn chào KhangCN chưa xác minh được báo riêng trong summary.json; không tự sửa nhãn theo model.

## Đầu vào thiếu

- giúp — `9aaca0849148573a`: fewer_than_3_usable_hand_frames. Vẫn giữ trong mẫu số stream.
- hâm mộ — `ad505619dcbccb84`: fewer_than_3_usable_hand_frames. Vẫn giữ trong mẫu số stream.
- phiên dịch — `19f1cc0c5e28a0f5`: fewer_than_3_usable_hand_frames. Vẫn giữ trong mẫu số stream.

## Đọc kết quả khi cân nhắc đổi model

Model hiện tại chưa đáp ứng yêu cầu webcam của người dùng. Tuy nhiên, số 255/297 xếp đúng ở clip cắt so với 171/297 chốt đúng stream cho thấy cần giải quyết cả nhận diện theo thời gian và cách lấy đầu vào; không đủ bằng chứng quy toàn bộ lỗi cho dung lượng kiến trúc. Clip cắt dùng tương lai nên chênh lệch này không phải mức tăng live có thể lấy lại chắc chắn.

Trong 51 clip thất bại nhưng đủ điều kiện ở clip cắt, 45 có candidate đúng reliable nhưng chưa đủ dwell ở stream. Không giảm dwell hàng loạt: có sự kiện sai đạt 0,9624 và chưa có nền thật; score cao không phải bảo đảm đúng.

Hướng tiếp theo: (1) xử lý chất lượng đầu vào và khả năng giữ dự đoán ổn định trong cửa sổ live bằng một thay đổi chung, kiểm cả clip được và mất trên cohort cố định; (2) nếu thử checkpoint/kiến trúc mới, kiểm nhãn và schema feature, checksum, đặc biệt không để các clip đánh giá đã nằm trong TRAIN của candidate; (3) so cả stream, sự kiện sai và latency thiết bị thật, rồi xác nhận trên webcam/người/nền độc lập. Chưa chọn tên kiến trúc mới theo một vài clip và chưa train lại từ báo cáo này.

Ba nhánh thay thế đã thử trong FIXED_COMPONENT_RESULTS_20261022.md chưa đủ điều kiện thay cấu hình hiện tại. Giữ nó làm mốc so sánh không đồng nghĩa đã công nhận chất lượng sản phẩm đạt.

## Tệp và phạm vi

- Bảng đủ 181 từ: `.runtime\all-word-failures-20261022\full-v2\all-181-words-failures.csv`.
- Bảng từng clip: `.runtime\all-word-failures-20261022\full-v2\per-video-failures.csv`.
- Trace, hợp đồng và đối chứng: `.runtime\all-word-failures-20261022\full-v2`.
- Giao thức: `docs/ALL_WORD_FAILURE_PROTOCOL_20261022.md`.
- Triển khai công cụ: `ai_service/analyze_word_failures.py`, `ai_service/review_word_failures.py`.

Chỉ là dữ liệu phát triển đã xem nhiều lần; người ký và nhãn chưa được thẩm định toàn bộ. Chưa đo nền thật hoặc webcam độc lập. Không suy diễn số clip từ nguồn thành độ chính xác camera điện thoại, không tính false accept/phút bằng 0, không chọn ngưỡng/model tự động. Không có kết quả được chứng minh cho 24 từ thiếu calibration.
