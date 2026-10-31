# So checkpoint Colab mới với app — 22/10/2026

**Đã đối chiếu byte model/config trên Drive và chạy đủ 204 video được phép; không chạy model mới trên 93 video audit. App/public chưa thay đổi.**

Không nhánh thay thế nào qua sàng lọc phát triển đã chốt; chưa có cơ sở chọn checkpoint mới để thay app ở các điểm vận hành này.

Bản mới nhất là AD seed137 (21/10), đối chiếu thêm reference137 và reference42. Mọi model/config/encoder/prototype/normalizer khớp checksum. TRAIN không trùng theo ID hoặc content hash với tập đánh giá; các hàm feature AST khớp. Giữ runtime app, cadence 0,25s và gap 0,60s. Đây là kiểm tra checkpoint khi port vào app, không phải tái hiện số Colab dùng cadence 0,15s/gap 0,90s.

## Calibration chung — 95 clip, 87 từ

297 video cũ phân thành 95 calibration mới, 109 epoch VAL và 93 audit mới. Không so kết quả 95/204 với số 171/297 trước đó. Cả bảy nhánh dùng cùng 95 clip cho bảng này.

Lưu ý lộ dữ liệu giữa hai giao thức: 93 video audit mới đã từng được chạy với app trong các lượt 297 clip trước khi đối chiếu vai trò Colab. Vì vậy không thể coi phần này hoàn toàn chưa được xem đối với toàn bộ quá trình phát triển. Lượt hiện tại loại chúng trước I/O source/feature và không chạy checkpoint mới trên chúng. Kiểm chứng cuối vẫn cần dữ liệu webcam độc lập mới.

| Nhánh | Đúng | Sai | Không chốt | Precision trên clip đã chốt | Sự kiện sai |
|---|---:|---:|---:|---:|---:|
| App hiện tại: TCN + embedding cũ | 56 | 0 | 39 | 100.00% | 1 |
| TCN cũ, điểm chung 0,60 | 58 | 7 | 30 | 89.23% | 10 |
| Reference42 mới, TCN 0,60 | 52 | 10 | 33 | 83.87% | 20 |
| Reference137 mới, TCN 0,60 | 49 | 9 | 37 | 84.48% | 14 |
| AD mới nhất, TCN 0,60 | 48 | 11 | 36 | 81.36% | 15 |
| AD, score export 0,80 trong app | 38 | 6 | 51 | 86.36% | 7 |
| Cặp AD + embedding mới, phối hợp cố định | 48 | 2 | 45 | 96.00% | 2 |

Precision không tính clip không chốt, không phải accuracy webcam. Các điểm TCN 0,60 dùng cùng cổng/feature/luồng để kiểm trọng số. Cặp mới 50/50, temperature 1/0,06 là điểm phối hợp cố định chưa calibration lại; không diễn giải nó thành chất lượng tối ưu của encoder mới.

App chốt đúng 56/95 clip, bỏ qua 39 clip và vẫn có 1 sự kiện sai giữa clip. Precision 100% ở kết quả cuối không có nghĩa nhận đúng 95/95 hoặc không từng phát sai.

## So sánh cặp calibration

- app_tcn: thêm đúng 7, mất đúng 5; McNemar exact p=0.7744; qua sàng lọc phát triển=False.
- reference42_tcn: thêm đúng 4, mất đúng 8; McNemar exact p=0.3877; qua sàng lọc phát triển=False.
- reference137_tcn: thêm đúng 4, mất đúng 11; McNemar exact p=0.1185; qua sàng lọc phát triển=False.
- latest137_tcn: thêm đúng 5, mất đúng 13; McNemar exact p=0.0963; qua sàng lọc phát triển=False.
- latest137_export_score: thêm đúng 2, mất đúng 20; McNemar exact p=0.0001; qua sàng lọc phát triển=False.
- latest137_pair_fixed: thêm đúng 1, mất đúng 9; McNemar exact p=0.0215; qua sàng lọc phát triển=False.

CI tuyến tính hóa giữ trọng số lớp có thể suy biến khi mỗi từ chỉ có một clip; cờ trong verified-reading.json. P-value trên nhiều nhánh chưa hiệu chỉnh đa kiểm định, chỉ để mô tả, không dùng một p-value để chọn model. Không dùng khoảng rất hẹp để khẳng định khả năng với người mới. Tập calibration đã được sử dụng nhiều lần nên mọi số vẫn là phát triển. Danh sách clip được/mất và đối chiếu riêng trọng số TCN giữ trong verified-reading.json.

## Epoch VAL — 109 clip, báo riêng

| Nhánh | Đúng | Sai | Không chốt | Sự kiện sai |
|---|---:|---:|---:|---:|
| App hiện tại: TCN + embedding cũ | 60 | 5 | 44 | 8 |
| TCN cũ, điểm chung 0,60 | 67 | 6 | 36 | 13 |
| Reference42 mới, TCN 0,60 | 65 | 8 | 36 | 20 |
| Reference137 mới, TCN 0,60 | 58 | 9 | 42 | 12 |
| AD mới nhất, TCN 0,60 | 55 | 8 | 46 | 12 |
| AD, score export 0,80 trong app | 48 | 4 | 57 | 6 |
| Cặp AD + embedding mới, phối hợp cố định | 58 | 2 | 49 | 4 |

Epoch đã tham gia chọn checkpoint nên không gộp với calibration hoặc coi là kiểm thử độc lập.

## Bản ghi webcam đã xem

Reference khớp 231/231 batch gốc; reference lặp lại cũng khớp. Bản ghi người dùng làm chào → nghe → nhìn → rau. Ranh giới video chỉ xấp xỉ. Các sự kiện dưới đây không phải accuracy độc lập:

- app: `[]`.
- app_tcn: `[{"time": 7.215, "label": "biết"}, {"time": 11.103, "label": "hiểu"}, {"time": 15.999, "label": "áp dụng"}, {"time": 20.335, "label": "mèo"}]`.
- reference42_tcn: `[{"time": 6.015, "label": "không biết"}, {"time": 10.543, "label": "điếc"}, {"time": 15.343, "label": "điếc"}]`.
- reference137_tcn: `[{"time": 6.912, "label": "biết"}, {"time": 10.543, "label": "điếc"}, {"time": 13.823, "label": "áp dụng"}, {"time": 20.687, "label": "phiên dịch"}, {"time": 21.343, "label": "cà phê"}]`.
- latest137_tcn: `[{"time": 11.103, "label": "điếc"}, {"time": 20.335, "label": "cảm ơn"}]`.
- latest137_export_score: `[]`.
- latest137_pair_fixed: `[]`.

## Kết luận và phạm vi

Không tự thay model hoặc ngưỡng trong app. Qua sàng lọc trên 95 clip không chứng minh webcam/người mới/nền thật đã tốt; chưa có false accept/phút. Không đạt chỉ nói chưa có bằng chứng chọn checkpoint đó ở các điểm vận hành đã thử, không chứng minh mọi cách calibration hay kiến trúc mới đều vô ích.

Bảng đủ 181 từ có 94 từ thiếu mẫu calibration chung; không suy diễn đúng/sai cho các từ đó. 93 audit chỉ được dùng ID để loại, không mở source/feature hoặc suy luận model mới.

- Bảng từng từ: `.runtime\checkpoint-comparison-20261022\full\all-181-words-comparison.csv`.
- Contract, journal, kiểm lại và clip được/mất: `.runtime\checkpoint-comparison-20261022\full`.
- Giao thức: `docs/CHECKPOINT_COMPARISON_PROTOCOL_20261022.md`.
- Nguồn checkpoint mới nhất: https://drive.google.com/file/d/1iPmRtlmD54X2Lr-2a2xvAVP8DvUfBGzu/view.
- Nguồn model reference và encoder/prototypes: https://drive.google.com/drive/folders/1pL10d-l2xKCO9v3Embsi7LXt0y11pHQy.
