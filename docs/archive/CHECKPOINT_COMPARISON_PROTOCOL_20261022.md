# So checkpoint Colab với app — đăng ký 22/10/2026

Đã truy cập Drive để kiểm phiên bản và tải lại đúng byte model/config: bản mới nhất là complete_context_matched_seed137_v1 (AD), xuất 21/10 16:02 UTC; đối chiếu thêm reference137 (AC) và reference42. Hash model/config khớp training_status và identity đã đóng băng. Cặp encoder/prototypes mới và normalizer được giữ đúng bộ, không ghép prototype cũ với encoder mới.

## Tập so sánh và tránh mở audit

297 video cũ không trùng TRAIN theo video ID hoặc content hash của cả word model và embedding. Nhưng chia vai trò mới là **95 calibration, 109 epoch VAL, 93 audit**. Giữ nguyên 93 audit, không mở source/feature hoặc chạy model mới trên chúng để chọn checkpoint. Phép so sánh chính dùng cùng 95 calibration (87 từ) cho mọi nhánh; 109 epoch VAL (94 từ) báo riêng vì đã tham gia chọn checkpoint. Không so tổng 204 với số 171/297 cũ. Đọc ID/hash/nhãn để phân vùng không phải mở nội dung audit.

Các clip đều là dữ liệu phát triển đã được xem nhiều lần, không phải TEST webcam độc lập. Người ký chưa được xác minh. Mọi bảng theo từ phải hiển thị các từ thiếu mẫu, không biến “không đánh giá” thành “không hỗ trợ” hoặc “đã đúng”. Không chạy audit cuối.

## Đầu vào và các biến giữ cố định

Dùng feature/timestamp đã xác minh của đúng source video. AST các hàm tính landmark/chuỗi/normalization/word feature, hand slot, motion/pair và buffer khớp giữa runtime Colab được lưu và app. Thứ tự 181 nhãn, shape (48×126,48×19), dynamic list và requires_pair khớp; pair gate measured. Kiểm Keras schema và eager-vs-graph trên batch 1 và 3 cho từng TCN và encoder.

Giữ runtime app, buffer, score smoothing/dwell, prediction interval 0,25s và tracking gap 0,60s để so trọng số. Config Colab ghi interval 0,15s và gap 0,90s, nên đây là phép **port checkpoint vào app**, không tái hiện số Colab 587 clip hoặc toàn bộ cài đặt native. Không thay code app, model đang chạy, public hoặc ngưỡng runtime thật.

## Bảy nhánh cố định

1. `app`: cặp model/config đang chạy trong app, ngưỡng 0,60/0,20/0,30.
2. `app_tcn`: word TCN hiện tại ở cùng ngưỡng, không cộng embedding.
3. `reference42_tcn`: trọng số reference42 mới ở đúng cổng/luồng chung của app.
4. `reference137_tcn`: trọng số reference137 mới ở cùng điểm chung.
5. `latest137_tcn`: trọng số AD mới nhất ở cùng điểm chung. So 2→5 là kiểm trọng số TCN ở cùng ngưỡng và feature/gates.
6. `latest137_export_score`: checkpoint AD với policy export (score 0,80, margin 0,20, dwell 0,30, embedding 0), vẫn ở luồng app chung.
7. `latest137_pair_fixed`: cặp TCN AD và embedding/prototype mới, trộn 50/50, temperature TCN=1, embedding=0,06, policy score 0,60/margin 0,20/dwell 0,30. Đây là điểm phối hợp chuyển từ app cũ để chẩn đoán, **chưa calibration cho cặp mới**; không gọi nó là cấu hình tối ưu hoặc được phép triển khai.

Không quét nhiệt độ, tỷ lệ trộn hoặc ngưỡng. Không chọn bản “đẹp nhất” sau khi xem webcam. So reference42/137 là mô tả độ nhạy seed, không đánh giá phương sai đáng tin cậy chỉ với hai seed.

## Kiểm tra và quy tắc đọc

Unit test phát hiện trùng vai trò, TRAIN overlap, ID không rõ vai trò, hỏng journal gốc và bảo đảm audit bị loại trước thao tác I/O feature. Smoke tối đa 6 clip cố định (một đúng/không chốt/sai mỗi vai trò, nếu có), thư mục riêng; không dùng để đánh giá hiệu quả. Không sửa mã giữa smoke và full.

Mỗi clip giữ source/feature checksum. Reference phải giống event gốc; chạy lại reference sau mọi candidate phải khớp vector ở tất cả đầu vào (atol 2e-5, rtol 5e-4), output/ranking/flag và event giống hệt. Mã, model, config, corpus, role, asset và webcam hash trong hợp đồng. Ghi journal từng clip và chỉ resume khi hợp đồng không đổi.

Primary: số đúng/macro recall, precision và sự kiện sai trên 95 calibration; không gộp epoch. Chỉ gọi điểm vận hành hứa hẹn khi số đúng tăng, precision >= max(0,95, app reference), clip sai/sự kiện sai/trùng không tăng, các từ ưu tiên có mẫu không bị mất; luôn báo clip được/mất và mức thiếu mẫu. Báo paired discordance/McNemar và CI mô tả, cảnh báo CI suy biến ở các lớp chỉ một clip. Kết quả không đạt nghĩa là chưa có bằng chứng chọn thay thế ở những điểm này, không chứng minh kiến trúc vô ích.

Replay riêng 231 batch webcam đã xem theo đúng generation/allow_prediction. Reference phải khớp bản ghi; chỉ báo sự kiện mới, không coi là accuracy webcam độc lập. Không chỉnh policy dựa trên đoạn đã xem. Không cộng các p95 thành độ trễ toàn trình và không suy ra FPS điện thoại từ thời gian replay.

Không tự triển khai kể cả khi một nhánh qua sàng lọc, vì nền thật và webcam/người mới chưa đo, nhãn chưa thẩm định hoàn toàn và tập calibration đã dùng nhiều lần. Không thay app bằng checkpoint mới chỉ vì tên file hoặc ngày mới hơn.

Ghi chú khi kiểm lại chéo hai giao thức: 93 video audit của Colab đã xuất hiện trong lượt đánh giá app 297 clip trước đây. Không thể gọi phần đó là hoàn toàn chưa được xem trong toàn bộ quá trình phát triển. Lượt này không mở thêm source/feature hoặc chạy checkpoint mới trên 93 video đó; `audit_access=False` trong hợp đồng có phạm vi lượt so sánh hiện tại, không phủ nhận sự lộ dữ liệu trước đây. Không dùng số cũ trên chúng để chọn model mới; cần TEST webcam độc lập cho kết luận cuối.
