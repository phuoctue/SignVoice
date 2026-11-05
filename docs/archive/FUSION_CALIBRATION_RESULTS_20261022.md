# Kết quả calibration giới hạn cặp model mới, 22/10/2026

## Quyết định

Đã chạy xong sáu cấu hình đăng ký trước. Chưa có cấu hình mới vượt tiêu chí phát triển hoặc tốt hơn app hiện tại trên phần dữ liệu chung được thử. Giữ model/policy đang chạy; không triển khai các cấu hình mới lên public.

Kết luận chỉ áp dụng cho sáu điểm này, với cặp encoder/prototype/TCN AD mới đã đóng băng và luồng app hiện tại. Không chứng minh mọi cách fusion đều vô ích, model mới kém trên mọi dữ liệu hoặc cần đổi kiến trúc. Việc camera thực tế vẫn nhận từ kém chưa được sửa xong bằng lượt này.

## Đã làm và đã kiểm

- 10 unit test về cấu hình, lựa chọn không dùng epoch/webcam, loại nhãn nghi vấn, thiếu nhánh, sự kiện sai và tách split: đạt.
- SMOKE 5 clip: đạt; FULL cùng băm mã/giao thức/asset, không sửa evaluator giữa hai lượt.
- FULL 204 clip: 95 calibration và 109 epoch VAL; 93 audit bị loại trước I/O feature/source. Không dùng TRAIN rau.
- Mỗi clip chạy đối chứng app và cặp mới mốc 50/50, rồi lặp hai đối chứng. Vectors/output/events tại mọi input và sự kiện đóng băng đều khớp; 204/204 clip đạt kiểm tra.
- Checksum model/encoder/prototype/normalizer/split và feature/source giữ nguyên. Reader thứ hai tính lại từ journal, kiểm lựa chọn, sự kiện, metric/paired report và độ phủ: đạt.
- Phần chọn chỉ dùng 94 calibration sau khi tách 1 clip chào KhangCN chưa xác minh, phủ 86 nhãn. Lựa chọn đã ghi file trước epoch và webcam.
- Luồng app cố định: score 0,60, margin 0,20, dwell 0,30, interval 0,25s, gap 0,60s, không đổi smoothing/buffer/pair/motion/slot matching.
- Thời gian đến hết phần source replay khoảng 540 giây trên máy này, không phải độ trễ camera hay tốc độ trên điện thoại.

## Calibration dùng để chọn: 94 video

| Cấu hình | Đúng | Chốt sai cuối | Không chốt | Precision trong số chốt | Sự kiện sai | Macro recall |
|---|---:|---:|---:|---:|---:|---:|
| App hiện tại | 56 | 0 | 38 | 100,00% | 1 | 59,30% |
| Cặp mới mốc 50/50 | 48 | 2 | 44 | 96,00% | 2 | 51,74% |
| TCN 25% | 48 | 6 | 40 | 88,89% | 6 | 51,74% |
| TCN 75% | 49 | 6 | 39 | 89,09% | 9 | 52,33% |
| Làm TCN tự tin hơn, nhiệt độ 0,75 | 50 | 2 | 42 | 96,15% | 3 | 53,49% |
| Làm embedding tự tin hơn, nhiệt độ 0,04 | 49 | 4 | 41 | 92,45% | 4 | 52,91% |
| Làm embedding bớt tự tin, nhiệt độ 0,09 | 43 | 1 | 50 | 97,73% | 1 | 45,93% |

100% ở dòng app là **56/56 kết quả chốt cuối đúng trong tập phát triển này**, không phải nhận đúng 94/94, accuracy webcam hay không có sự kiện sai. Sự kiện trung gian được tính riêng, vì clip chốt đúng cuối vẫn có thể từng chốt sai.

Không cấu hình nào qua toàn bộ tiêu chí so với anchor mới:

- TCN 25% không tăng macro recall và tăng lỗi.
- TCN 75% thêm 1 đúng nhưng thêm 4 clip sai, sự kiện sai 2→9.
- TCN nhiệt độ 0,75 thêm 2 đúng, giữ 2 clip sai cuối, nhưng sự kiện sai 2→3. Đây là trường hợp gần cổng nhất; không phải lỗi mã hay model bị hỏng. Ngay cả bỏ điều kiện không tăng sự kiện sai, nó vẫn có ít đúng và nhiều sai hơn app hiện tại trên 94 clip này (50/2 so với 56/0).
- Embedding nhiệt độ 0,04 thêm 1 đúng nhưng thêm lỗi, precision dưới 95%.
- Embedding nhiệt độ 0,09 ít lỗi hơn nhưng mất 5 clip đúng.

Kết quả lựa chọn là `anchor / no_supported_development_improvement`: giữ mốc của thí nghiệm để chạy đối chứng tiếp, **không phải chọn anchor mới thay app**.

Đã lưu cả số liệu 95 clip chưa tách nhãn nghi vấn. Ví dụ TCN 25% và embedding sắc hơn được thêm một chào đúng theo nhãn nguồn ở tập 95; không dùng kết quả đó để chọn vì clip chưa được xác minh. Không sửa nhãn theo dự đoán.

## Kiểm tra lại trên 109 epoch VAL

Vì không có ứng viên hợp lệ, theo đăng ký chỉ chạy app và anchor mới trên phần này. Không có kết luận về năm biến thể còn lại trên epoch.

| Cấu hình | Đúng | Sai cuối | Không chốt | Sự kiện sai |
|---|---:|---:|---:|---:|
| App hiện tại | 60 | 5 | 44 | 8 |
| Cặp mới mốc | 58 | 2 | 49 | 4 |

Cặp mới có ít sai hơn nhưng cũng ít đúng hơn ở phần này; trên calibration lại nhiều sai hơn app. Không gọi đây là phát hiện giảm nhận nhầm ổn định. Epoch đã dùng trong phát triển/chọn checkpoint, không phải TEST độc lập.

Các gained/lost, CI và McNemar theo cặp nằm trong `comparison.json`. Với nhiều nhãn chỉ một clip, bootstrap có thể suy biến và nhóm gần từng video; p-value sau nhiều phép xem không được dùng để chứng nhận tốt hơn hay tổng quát cho người mới.

## Bản ghi webcam của người dùng

Nguồn SHA-256 `e1ba71551e4127463209ef86c7aadfd129876f89583a6859f824f9cfd23be342`.

- App phát lại khớp 206/206 batch: không có sự kiện.
- Anchor mới: chốt **dừng lại tại 24,868 giây**, ở giai đoạn người dùng đang thử rau theo trình tự đã yêu cầu và ảnh lấy mẫu. Đây không phải một trong bốn từ dự định thử.
- Không chạy các cấu hình bị loại để tìm một cấu hình đẹp riêng cho camera này. Không chọn tham số theo webcam, và không dùng nguồn đã xem làm accuracy độc lập.

## Độ phủ dữ liệu: không đánh đồng hai loại thiếu mẫu

Lượt này chỉ đánh giá phần giao an toàn giữa hai giao thức, không phải toàn bộ 587 calibration mới. Sau khi tách chào nghi vấn, 94 selection + 109 epoch chung phủ 142/181 nhãn; 39 nhãn không có mẫu trong giao này. CSV đủ 181 dòng đánh dấu rõ chưa đo, không điền 0 như thể đã đo mà sai.

Kiểm thêm **metadata** của toàn bộ split mới, không mở pixel/feature/prediction audit:

- Toàn bộ calibration mới có 587 clip nhưng **24 từ không có calibration**. Không phải cả 39 từ thiếu ở giao đều thiếu trên tập đầy đủ.
- 21 từ có TRAIN dưới 8 clip; đây là cờ rà dữ liệu, không tự loại từ hoặc định nghĩa mức hỗ trợ.
- Bàn tay: 4 TRAIN, 0 calibration đầy đủ; có 1 epoch clip ngoài phần giao. Chưa đủ cơ sở báo độ chính xác từ này.
- Chào: 128 TRAIN và 8 calibration đầy đủ, nhưng phần giao sau tách nhãn nghi vấn không có mẫu chào. Không thể dùng lượt này để kết luận riêng chào trên tập mới đầy đủ.
- Nghe: 31 TRAIN, 2 calibration đầy đủ; nhìn 25/1; rau 34/2; cứu 24/1. Chênh một clip theo các từ này rất dễ là dao động nhỏ, không dùng làm bằng chứng thắng.
- Manifest đóng băng chưa có signer ID được điền cho cả 181 từ. Số source group không chứng minh số người khác nhau. Trạng thái `pending` trong manifest không có nghĩa nhãn sai; quyết định rà mới có thể chưa được nạp vào snapshot này.

Không đánh giá app trên toàn bộ 587 clip rồi so trực tiếp nếu chưa loại overlap TRAIN của app cũ. Muốn calibration mới rộng hơn phải giữ tách giao an toàn cho so app và báo riêng phần chỉ kiểm được ở model mới.

## Hướng tiếp theo

1. Giữ bản đang chạy. Dừng quét thêm tỷ lệ/nhiệt độ theo chính bản ghi này, và không giảm dwell để bù xếp hạng sai.
2. Chuyển ưu tiên sang **dữ liệu và quy trình train cho webcam**: nạp đúng các quyết định rà nhãn đã có, xử lý các mẫu đã được người dùng yêu cầu loại, thống kê biến thể/split trước khi train. Không gộp nhãn theo tên hoặc sửa theo model. Bổ sung/tuyển chọn mẫu camera thực cho TRAIN, đoạn không ký và chuyển tiếp; signer/session rõ ràng. Dùng cùng extractor đã kiểm chứng và luồng cửa sổ phù hợp live.
3. Làm trước một thay đổi dữ liệu có kiểm soát so với baseline, không gộp đổi kiến trúc, context và policy trong cùng lượt. Nếu chưa có dữ liệu mới, rà lỗi đầu vào TRAIN/nhãn/cửa sổ trên cache trước; chỉ chạy lại epoch hoặc tăng mạng không giải quyết được thiếu bằng chứng.
4. Với từ thiếu calibration như bàn tay, ưu tiên bổ sung phần đo độc lập và TRAIN theo người/phiên. Không dùng bốn từ người dùng hay thử làm thay mặt cho 181 từ. Bảng `training-data-priorities.csv` đã nêu các khoảng trống cụ thể.
5. Tách dữ liệu phát triển, nền calibration và webcam/người mới kiểm cuối theo tiêu chí đã chốt. Nền thật vẫn chưa được đo; vì thế lượt này không mở quyền thay policy nhận/từ chối trong app.

Không yêu cầu train lại ngay với notebook chưa đổi. Bước chuẩn bị có ích tiếp theo là sửa/hoàn thiện dữ liệu đầu vào và chốt một thay đổi huấn luyện có căn cứ, thay vì thêm một lượt train giống cũ.

## Đầu ra và giới hạn triển khai

Trong `.runtime/fusion-calibration-20261022/full/`:

- `contract.json`, `results.jsonl`, `comparison.json`, `frozen-nominee.json`, `verified-reading.json`.
- `all-181-words.csv`: kết quả theo từ, để trống nhánh/phân vùng chưa đo.
- `training-data-priorities.csv/json`: số TRAIN, độ phủ đầy đủ và độ phủ phần giao; chỉ thống kê metadata.

Model, ngưỡng, code nhận diện, service, public và notebook không thay đổi. Đây là phép thử phát triển đã hoàn thành, không phải bản cập nhật đã cải thiện nhận diện webcam.
