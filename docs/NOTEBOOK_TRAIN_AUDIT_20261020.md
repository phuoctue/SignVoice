# Kiểm tra notebook train — 20/10/2026

Đã đọc và cập nhật trực tiếp notebook Google Drive ID `1Jo-DuBTsrOxbaj8ZLme315iG0v9p7zZW`, giữ nguyên ID, tên và thứ tự các cell. Nội dung đã được đọc lại từ Drive và khớp byte với bản cập nhật. Chưa chạy lại toàn bộ Colab và chưa đổi model đang phục vụ app.

## Kết luận từ bản trước sửa

Chưa có cơ sở gọi mô hình là tối ưu tốt nhất. Log train TCN ở epoch 60 ghi train accuracy 0.9230 và val accuracy 0.8417, nhưng causal stream trên calibration chỉ đạt 0.5623 accuracy, coverage 0.5859. Hai loại chỉ số đo các tác vụ khác nhau; clip nguồn đã cắt không chứng minh nhận diện camera liên tục tốt.

Kiến trúc thực tế trong notebook là embedding BiLSTM(32) + attention + embedding 48 chiều; nhánh từ là Conv1D 64 kênh + GRU(96) + Dense(128), 185.270 tham số trong log hiện có. Không phải nhánh từ cũ khoảng 58 nghìn tham số. Chưa có bằng chứng để tiếp tục tăng dung lượng mạng hoặc ép một trọng số embedding cố định từ kết quả TEST cá nhân.

## Sai lệch đã sửa

1. **Replay khi chọn cấu hình khác triển khai.** Causal calibration tạo recognizer thiếu `feature_pipeline`, vì vậy `GestureBuffer.repair_gaps` bị tắt; đồng thời dùng mặc định khoảng mất tay 0.60 giây thay vì 0.90 giây của bản xuất. CELL 1 định nghĩa chung `WORD_LIVE_SETTINGS`; CELL 6B và CELL 7 dùng cùng clock/buffer/gap/pipeline.
2. **Raw mất tay bị thay bằng tọa độ đã nội suy.** CELL 5 trước đây ghi đè `raw_pose/raw_wrist` sau sửa khoảng trống. Replay vì thế có thể coi khung suy diễn là khung thực sự quan sát được. Bản sửa giữ nguyên raw và mask; tạo view đã sửa riêng cho model, lưu timestamp đúng của đoạn đã cắt. Hàm chuẩn bị TRAIN được dùng chung ở các vị trí xây view.
3. **Tay đứng yên có thể bị coi là nền.** Ngoài ít chuyển động, proxy nền giờ phải có bằng chứng tay hướng xuống và thấp hơn vùng ký hiệu; nếu có mốc mặt phải ở dưới tương ứng. Tư thế tay đang giữ gần mặt/ngực không tự động thành background. Đây vẫn là proxy từ TRAIN, không thay thế nền sinh hoạt thật được người kiểm tra.
4. **Tập calibration dùng chọn nhiều cấu hình chưa có phần kiểm tra riêng.** Chia nhóm VAL thành epoch / calibration / audit, không chia một source group qua nhiều vai trò. Audit chỉ replay sau khi khóa cấu hình bằng SHA256 và không chỉnh ngưỡng/model từ kết quả đó. Các từ không đủ nhóm được báo thiếu audit; không lấy TEST bù.
5. **Nền VAL thật chỉ được đếm nhưng chưa tham gia gate.** Nếu người dùng bổ sung manifest nền độc lập có kiểm tra, gate nay so số sự kiện nhận nhầm nền của candidate với baseline. Khi chưa có dữ liệu, false accepts được ghi unknown, không coi bằng không.
6. **Thiếu mô phỏng thời gian cập nhật mốc mặt.** TRAIN augmentation bổ sung giữ mốc mặt đo thật theo nhịp 0.15–0.80 giây và thời hạn tối đa 1.2 giây, đồng thời vẫn có missing mask. Không tạo mốc mặt giả từ bàn tay.
7. **Tái sử dụng model và kiểm tra xuất.** Thêm fingerprint gồm recipe, split ownership, augmentation, normalizers và runtime source. Không dùng lại embedding sau khi thay recipe/split mà chỉ dựa vào danh sách video. CELL 9 kiểm tra training identity và policy đã khóa trước khi xuất.

Đã bỏ generator TRAIN/VAL tạm bị ghi đè ngay ở CELL 6A. Bổ sung `chào / tạm biệt / cho` vào bảng rà biến thể TRAIN, không tự đổi nhãn theo dự đoán. Hai TEST mới nhất bị khóa bằng tên và checksum đọc từ file gốc, bên cạnh raw TEST đã khóa trước đó.

## Những thứ cố ý giữ để đánh giá có kiểm soát

- Kiến trúc, feature version, hàm suy luận/runtime xuất và định dạng model không đổi.
- Ngân sách background 25%, sampler cân bằng nhãn/nguồn/nhóm và số epoch giữ nguyên; không khẳng định tỷ lệ 10% hay embedding 80% tốt hơn khi chưa so sánh độc lập.
- Chỉ chọn epoch trên epoch VAL, chọn operating point trên calibration; camera TEST không tham gia TRAIN/normalizer/model selection.
- TRAIN người/phiên mới và nền sinh hoạt thật chưa có. Augmentation không tạo ra người ký mới hay sửa được nhãn/biến thể sai.

## Cách chạy và đọc kết quả mới

Mở lại notebook trên link hiện có, chọn GPU runtime mới, chạy CELL 1 → 9. Model mới sẽ lưu vào `MyDrive/Train_AI_SignVoice/models/rgb_camera_audit_2026_10_20`; báo cáo xử lý nằm ở `processed/words_camera_audit_2026_10_20`. Cache raw landmark đúng schema/hash vẫn có thể được dùng lại từ thư mục cache chung.

CELL 9 xuất ZIP kèm các báo cáo bổ sung:

- `word_audit_report.json`: kết quả audit sau khi khóa model/policy, từng video và từng từ, các sự kiện nhầm, thời điểm chốt đúng đầu tiên.
- `word_audit_per_word.csv`: support, recall, số clip không nhận, sự kiện nhầm và từ chưa có audit.
- `validation_roles.csv`: nguồn gốc nhóm của epoch/calibration/audit.
- `training_identity.json`: recipe/fingerprint cho lần train này.
- `deployment_readiness.json`: trạng thái thử nghiệm và dữ liệu độc lập còn thiếu.

Thời điểm chốt trong báo cáo tính từ đầu clip nguồn; chưa có mốc bắt đầu động tác được gán nhãn độc lập nên không gọi đó là latency từ lúc bắt đầu ký hiệu. Audit nguồn chưa phải test người mới/nền camera mới. Không tự động thay model app chỉ vì train đã hoàn tất; cần so sánh bundle đã khóa trên cùng TEST riêng.

## Kiểm chứng bản sửa

13 kiểm thử đều qua, gồm syntax toàn bộ cell, raw mask không bị nội suy ghi đè, augmentation 160 view một/hai tay có clock/mask đồng bộ, cấm augment VAL/TEST, proxy nền không nhận tư thế tay gần mặt/ngực, chia nhóm không trùng và có tính xác định, causal replay bật đúng gap repair, thiếu nền được ghi unknown, và train một batch bằng model thật rồi lưu/nạp lại kiểm tra weights/output.

Đây là kiểm thử tính đúng của code, không phải một lần train hoàn chỉnh hay bằng chứng tăng accuracy.

Backup và bằng chứng tại `C:/Users/Phuoc Tue/Documents/Codex/2026-10-08/https-colab-research-google-com-drive/notebook_audit_20261020/`:

- `remote_before.ipynb`: notebook gốc đầy đủ output cũ.
- `remote_verified.ipynb`: nội dung đã đọc lại từ Drive.
- `publication_report.json`, `tests.log`: kết quả lưu và kiểm thử.

SHA256 bản đã lưu: `0303bed6a7a55e1f4f1d9f0f7468063bf61640e2ede5ea3102d05e1dc2fea13c`.

## Rà lại lần hai theo yêu cầu

Đã tải lại notebook từ Drive; SHA256 vẫn khớp bản trên. Không phát hiện thêm lỗi ở các nhánh được kiểm tra nên không thay đổi model, ngưỡng hay notebook chỉ để tạo một phiên bản mới.

Mở rộng lên **16 kiểm thử, tất cả đều qua**, gồm chạy nối tiếp mã thật của CELL 6A → CELL 6 → CELL 6B và khối audit của CELL 7 trên bộ mẫu tích hợp nhỏ. Hai nhánh neural đều thực sự fit, lưu và nạp lại; nhánh tìm cấu hình trên hơn 10 lớp cùng gate nền cũng được chạy bằng bộ mẫu tính toán riêng. Ngân sách train của bộ mẫu được rút xuống một epoch để kiểm tra thực thi, không phải train toàn bộ dữ liệu. Các chỉ số accuracy của bộ mẫu này không có ý nghĩa đánh giá model 181 từ.

Thử thêm 100 view augmentation trên landmark đo từ một clip `bàn tay` đã đối chiếu SHA256 và xác nhận thuộc TRAIN của bundle hiện tại. Clock/shape/finite và dữ liệu raw được giữ đúng; không dùng clip VAL/TEST để augment.

Đã tải manifest dữ liệu nguồn thực của lần train trước từ Drive, gồm **13.427 dòng**, kiểm tra phân chia nhóm bằng chính hàm trong notebook mới. Không thấy nhóm TRAIN trộn với VAL. Phân chia VAL có 698 clip epoch, 587 clip calibration và 536 clip audit; phạm vi từ được hỗ trợ tương ứng **173 / 157 / 149 trên 181 từ**. Có **32 từ chưa có audit riêng**, trong đó có `bàn tay`. Đây là kiểm tra cấu trúc dữ liệu trước lần train mới, chưa phải accuracy sau train; số lượng sẽ được tính lại sau QC khi chạy Colab.

Các bằng chứng mới: `tests_second_review.log`, `real_train_augmentation_check.json`, `actual_validation_group_check.json` trong thư mục backup phía trên. Kết luận: notebook đã qua các kiểm tra code này và có thể chạy lại; chưa có căn cứ xác nhận là mô hình tối ưu nhất hoặc bảo đảm chính xác trên webcam. Cần kết quả train mới và so sánh các bundle đã khóa trên cùng TEST camera độc lập, đồng thời bổ sung TRAIN người/phiên/nền thật riêng nếu còn sai.
