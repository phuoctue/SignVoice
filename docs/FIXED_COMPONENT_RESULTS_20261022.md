# Kết quả so sánh model theo luồng — 22/10/2026

Đã chạy xong **331/331 video**: 297 clip calibration phát triển thuộc **157/181 từ**, và 34 clip TRAIN “rau” để chẩn đoán pipeline. Cả bốn cấu hình đều được chạy trên toàn bộ 157 từ có dữ liệu, không chỉ “rau”. Bảng `all-181-words-coverage.csv` liệt kê đủ 181 từ, số clip và đúng/sai/không chốt của từng nhánh; 24 từ thiếu calibration được đánh dấu rõ, không tính thành đã đạt. Đã kiểm lại checksum nguồn và feature của cả 331 clip, tính lại thống kê từ journal, và đối chứng cấu hình tham chiếu của từng clip đều khớp. Tám clip trùng giữa smoke và full cũng cho mảng landmark/ngữ cảnh và dự đoán giống hệt nhau.

**Quyết định: giữ cấu hình app hiện tại, không tăng embedding lên 75%, không thay bằng nhánh TCN hoặc nhánh embedding từ phép thử này.** Không thay model, ngưỡng, cấu hình service hoặc public deployment.

## 297 clip calibration phát triển

Mọi nhánh dùng cùng nguồn RGB và feature đã trích lại, score=0,60, margin=0,20, dwell=0,30 giây và cùng nhịp dự đoán. Đây là checkpoint đang trong app, không phải checkpoint reference mới hơn trên Colab. Không dùng cache landmark cũ khác phiên bản. Cách trích offline dùng CPU VIDEO detector và face context đồng bộ; không coi con số này là tái hiện tuyệt đối Chrome GPU hoặc kết quả calibration cũ.

| Cấu hình | Đúng | Sai | Không chốt | Precision của kết quả đã chốt | Sự kiện sai |
|---|---:|---:|---:|---:|---:|
| **Hiện tại: TCN 50% + embedding 50%** | **171** | **8** | 118 | **95,53%** | **16** |
| Điểm từ của TCN | 179 | 18 | 100 | 90,86% | 35 |
| Điểm từ của embedding, giữ nền TCN | 159 | 20 | 118 | 88,83% | 35 |
| TCN 25% + embedding 75% | 168 | 15 | 114 | 91,80% | 23 |

Precision 95,53% = 171/(171+8), chỉ tính những clip đã chốt. Nó **không phải độ chính xác webcam 95,53%**: cấu hình hiện tại vẫn không chốt ở 118/297 clip, chốt đúng 171/297 và chưa được đo nền webcam thật.

- TCN thêm 8 clip đúng nhưng cũng thêm 10 clip sai và 19 sự kiện sai. Chưa đạt sàn precision 95% đã đăng ký.
- Tăng embedding lên 75% mất ròng 3 clip đúng, thêm 7 clip sai và 7 sự kiện sai.
- Nhánh điểm từ embedding mất ròng 12 clip đúng, thêm 12 clip sai và 19 sự kiện sai. Nhánh này vẫn dùng xác suất nền của TCN, không phải detector nền chỉ dùng embedding.
- Nhiệt độ và ngưỡng giữ nguyên: kết quả này mô tả bốn điểm vận hành đã đăng ký, không chứng minh mọi cách hiệu chỉnh TCN/embedding đều kém hơn.

### So sánh cặp

| Nhánh so với tham chiếu | Clip được thêm đúng | Clip bị mất đúng | Delta macro recall | Khoảng mô tả 95% |
|---|---:|---:|---:|---|
| TCN | 22 | 14 | +3,18 điểm % | [+0,48; +5,73] |
| Embedding giữ nền TCN | 12 | 24 | −4,46 điểm % | [−7,17; −1,91] |
| Embedding 75% | 10 | 13 | −1,59 điểm % | [−3,66; +0,48] |

Khoảng được tính bằng 2.000 lần paired cluster bootstrap tuyến tính hóa, giữ trọng số theo từ và residual đã định tâm. Có 296 nhóm cho 297 clip, gần như theo từng video; signer chưa xác minh. Vì vậy đây chỉ là khoảng mô tả trên dữ liệu phát triển đã xem nhiều lần, không chứng minh cải thiện với người mới. Tín hiệu macro recall của TCN không bù được việc tăng nhận nhầm và tụt precision.

Trên những clip được cả hai nhánh chốt đúng, trung vị chênh lệch thời điểm chốt đúng đầu tiên bằng 0 giây cho cả ba phép so sánh. Không dùng chênh lệch trung vị trên hai tập clip thành công khác nhau để tuyên bố nhánh mới nhanh hơn. Các mốc tính từ đầu clip, không phải từ đầu ký hiệu đã gán nhãn hoặc độ trễ camera điện thoại.

### Theo nguồn và giới hạn độ phủ

- KhangCN: 177 clip. Tham chiếu 110 đúng/5 sai; TCN 107/12; embedding 75% 112/7.
- Namwu: 118 clip. Tham chiếu 60 đúng/3 sai; TCN 71/6; embedding 75% 56/7.
- Hai nguồn còn lại chỉ có một clip mỗi nguồn, không đủ kết luận theo nguồn.
- Hai clip “chào” calibration đều thuộc KhangCN và còn nghi vấn nhãn/biến thể. Khi loại chúng, tham chiếu vẫn 171 đúng/8 sai; embedding 75% còn 166 đúng/15 sai. Hai điểm được thêm ở “chào” không phải bằng chứng đã sửa webcam chào.
- “nghe”, “nhìn”, “rau”, “cứu” mỗi từ chỉ có hai clip calibration; “bàn tay” không có clip. Không suy diễn chênh lệch một clip thành hơn/kém chắc chắn cho từng từ.
- Tổng cộng 24 từ không có mẫu calibration trong bộ này. Nhãn nguồn chưa được thẩm định độc lập hết; không tự sửa nhãn theo kết quả model.

## 34 clip TRAIN “rau”

Các clip được xác nhận thuộc danh sách TRAIN của đúng bundle; 33 từ namwu, một từ nguồn từ điển. Chỉ dùng để tìm lỗi pipeline, không gộp vào calibration hoặc đo khái quát.

| Cấu hình | Clip cắt: xếp “rau” đầu | Clip cắt: “rau” đạt điều kiện word head | Stream: chốt đúng “rau” |
|---|---:|---:|---:|
| Hiện tại 50/50 | 31/34 | 28/34 | 25/34 |
| TCN | 31/34 | 29/34 | 26/34 |
| Embedding giữ nền TCN | 26/34 | 23/34 | 22/34 |
| Embedding 75% | 29/34 | 25/34 | 23/34 |

Clip cắt sử dụng ranh giới từ toàn video, có thông tin tương lai, chỉ gọi word head và **không chạy dwell**. Vì vậy không gọi 31/34 là “độ chính xác live”, và không gọi toàn bộ chênh lệch 31→25 là lỗi dwell. Trong sáu clip cắt xếp đúng đầu nhưng stream không chốt đúng, có hai clip chưa đạt ngưỡng ngay cả ở clip cắt.

Bốn mẫu mà clip cắt thực sự đạt điều kiện nhưng stream không chốt đúng:

| Video ID | Score rau ở clip cắt | Kết quả stream |
|---|---:|---|
| `274f8e3c25e8771c` | 0,7440 | Không chốt |
| `3daa7484d5bab40f` | 0,7246 | phiên dịch |
| `814a2ae5bf5befbf` | 0,6785 | con mèo |
| `b1755afb6d88e9ed` | 0,6411 | Không chốt |

Trace chi tiết cho thấy mẫu `274f8e3c25e8771c` không có bước stream đủ điều kiện, target peak chỉ 0,546. Ba mẫu còn lại có đoạn candidate đủ điều kiện dài nhất lần lượt 0,261 / 0,267 / 0,277 giây, chưa tới dwell 0,30 giây. Đây là phân rã có bằng chứng, không gán tất cả chênh lệch clip/stream cho một nguyên nhân.

Điều này chỉ ra một nhóm cụ thể cần đối chiếu cửa sổ/thời điểm chốt, đồng thời cho thấy model có thể xếp đúng “rau” trên phần lớn các mẫu nguồn đã học. Nó chưa phân biệt được tất cả nguyên nhân lệch trên webcam: biến thể động tác, landmark thực tế, góc nhìn, lịch lấy cửa sổ hay phân phối dữ liệu. Ba clip TRAIN còn xếp sai ngay ở clip cắt cũng được giữ trong báo cáo, không bỏ để làm đẹp số.

### Kiểm tra giả thuyết nhịp dự đoán 0,15 giây

Sau khi đọc trace, chỉ thử offline trên bốn mẫu lỗi TRAIN đã xem và JSON webcam đã xem, giữ nguyên score/margin/dwell/trọng số. Đây là probe kỹ thuật được gợi ý bởi dữ liệu, không phải phép thử độc lập hay lựa chọn policy.

- Hai trong bốn mẫu TRAIN kết thúc với kết quả “rau”; một mẫu trong đó vẫn phát sự kiện sai “phiên dịch” trước khi phát “rau”. Một mẫu không chốt, một mẫu vẫn chốt “con mèo”.
- Trên JSON webcam, số bước dự đoán tăng từ 46 lên 63 nhưng **vẫn không có sự kiện chốt**.
- Như vậy tăng nhịp lấy dự đoán đơn thuần chưa sửa được lượt webcam này. Không triển khai thay đổi nhịp; chưa đo tải/độ trễ thiết bị hoặc nền thật của nhánh thử.
- Đối chứng nhánh webcam tham chiếu vẫn khớp 231/231 batch, và identity model/config gốc trước/sau probe giữ nguyên.

## Việc đã hoàn thành và hướng sửa tiếp

1. So sánh cả bốn cấu hình trên cùng cohort cố định và cùng stream; giữ nguyên app vì không nhánh thay thế nào thỏa các ràng buộc hiện tại.
2. Xác nhận chẩn đoán TRAIN “rau” bằng clip nguồn, không dựa trên tên nhãn hoặc video webcam đơn lẻ.
3. Lưu trace riêng của bốn mẫu trên để phân biệt điểm chưa bao giờ đủ, chuỗi đủ quá ngắn, hay thời điểm kết thúc ký hiệu chưa được lấy mẫu. Đây là nhóm kiểm tra kỹ thuật tiếp theo; chưa tự giảm dwell/score hoặc tạo ngoại lệ riêng cho “rau”.
4. Bất kỳ thay đổi về cửa sổ hoặc chốt kết quả phải được thử trên toàn bộ cohort với cùng tiêu chí, xem cả clip được và mất. Chưa có nền thật nên không triển khai quy tắc chốt sớm chỉ dựa trên kết quả này.

Chưa cần người dùng quay thêm chỉ để lặp lại phân tích vừa làm, và chưa có cơ sở để yêu cầu train lại chỉ nhằm đổi tỷ lệ trộn model. Kiểm thử webcam độc lập và nền thật vẫn cần trước khi đưa ra bảo đảm triển khai.

## Tệp tái hiện

Giao thức: `docs/FIXED_COMPONENT_PROTOCOL_20261022.md`.

Kết quả cục bộ trong `.runtime/component-comparison-20261022/full/`:

- `contract.json`: cohort, model/config/code hash và quy tắc đo đã khóa trước lượt đầy đủ.
- `results.jsonl`: 331 kết quả, có event history của từng nhánh và đối chứng tham chiếu.
- `comparison.json`: thống kê calibration, phần loại chào nghi vấn, TRAIN rau và so sánh cặp.
- `verified-reading.json`: kết quả đã kiểm lại, phân rã theo nguồn, từ ưu tiên và danh sách clip được/mất.
- `rau-cut-diagnostic.json`: phép đối chiếu clip cắt/stream cho cả 34 mẫu.
- `rau-four-stream-misses.json`: trace chi tiết bốn mẫu đạt ngưỡng clip cắt nhưng không chốt đúng ở stream.
- `cadence-015-engineering-probe.json`: probe nhịp dự đoán, không đủ điều kiện triển khai.
- `all-181-words-coverage.csv` / `.json`: bảng đủ 181 từ và các khoảng trống kiểm chứng.

Trang đối chiếu hình/video TRAIN và lượt webcam: `.runtime/component-comparison-20261022/rau-visual/compare.html`. Trang này không yêu cầu sửa nhãn, không thay thế người thẩm định và không tải dữ liệu lên ngoài.

Các kiểm tra tự động về phân bố điểm/nền, cache, metric và đối chứng replay đều qua. Hai công cụ đánh giá chỉ chạy offline; không được import vào đường camera production. Không thêm dependency hay thay file model.
