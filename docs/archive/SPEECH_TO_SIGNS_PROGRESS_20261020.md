# Tiến độ giọng nói → văn bản → ký hiệu, 20/10/2026

## Đã thực hiện

- Tái sử dụng engine nhận giọng nói và màn hình kết quả/chỉnh sửa hiện có.
- Kiểm kê trực tiếp `manifest_all_sources.csv` trong ZIP mở rộng, không giải nén
  toàn bộ ZIP 46 GB. Manifest có 54.455 dòng: 19.734 RGB, 6.267 video chưa gắn nhãn,
  48 mẫu chữ cá nhân và 28.406 skeleton.
- Sau lọc TRAIN, nhãn chữ nguồn đã xác nhận, không cá nhân/không lỗi QC đã biết,
  kiểm tra member ZIP, loại hash trùng và hash có nhãn mâu thuẫn: 14.634 video ứng
  viên thuộc 1.247 nhãn. Đây là coverage metadata, chưa phải nội dung được duyệt.
- Tạo 18 ứng viên xem trước theo nguồn cho chín từ ưu tiên, kiểm SHA256 và giải mã
  năm khung hình/video thành công. Video gốc và contact sheet chỉ lưu cục bộ.
- Thêm `POST /api/v1/sign-sequence`: chỉ lấy từ điển PUBLISHED; ghép cụm dài nhất,
  chuẩn hóa Unicode, giữ dấu/dấu câu/từ lặp và đoạn chưa có mẫu; phát hiện nhãn
  trùng cần chọn biến thể, lọc URL không phải HTTP(S), giới hạn input 2.000 ký tự.
- Thêm `Xem ký hiệu` tại màn hình kết quả giọng nói: thẻ có nhãn, ảnh hướng dẫn
  nếu có, ảnh thumbnail có chú thích xem trước, video phát lại/trước/sau và xem
  lần lượt. Đổi văn bản hủy hiệu lực phản hồi cũ, lỗi mạng giữ nguyên transcript.
- Dùng video_player cho Web/Android; không khởi tạo model camera hoặc LM Studio.
  Transcript gửi bằng POST và được ẩn khỏi request log debug của endpoint này.

## Nhóm từ ưu tiên

| Nhãn | Video TRAIN ứng viên |
|---|---:|
| chào | 149 |
| tôi | 36 |
| bạn | 3 |
| cảm ơn | 128 |
| nghe | 32 |
| nhìn | 26 |
| rau | 35 |
| bàn tay | 4 |
| cứu | 25 |

Không có nhãn canonical khớp chính xác `xin chào` và `là` trong tập đủ điều kiện.
Một số nhãn nguồn `xin_chao` đã được ánh xạ thành `chào` trong pipeline cũ; cần
duyệt nghĩa/động tác trước khi khai báo alias cho luồng văn bản. Không tự bỏ `là`.
Số lượng này độc lập ngưỡng chọn từ TRAIN AI: mẫu từ điển cần kiểm chứng nội dung,
không yêu cầu có bốn video như một lớp học máy.

## Kết quả để duyệt

Thư mục: `E:\WorkSpace\SignVoice\SignVoice\.runtime\speech-sign-library`.

- `review.html`: mở trong trình duyệt để xem ảnh năm thời điểm và video từng nguồn.
- `inventory.csv`: toàn bộ 1.247 nhãn ứng viên và số lượng theo nguồn.
- `candidates.json`: 18 ứng viên có hash, nguồn, đường dẫn, FPS và thời lượng.
- `review_decisions.csv`: bảng chọn mẫu, giữ lại khi audit chạy lại.
- `summary.json`: số liệu lọc và lỗi; lần chạy hiện tại không lỗi giải mã preview.

Trong bảng duyệt, chọn một mẫu đại diện cho mỗi nhãn (`preferred=true`), ghi kết
quả đối chiếu đúng nghĩa/động tác và điều kiện dùng nội dung. Không xuất bản tất
cả biến thể cùng tên vì bộ ghép sẽ báo mơ hồ thay vì tự đoán. Video raw TEST riêng
của người dùng không được lấy làm mẫu public.

## Mở rộng sau lựa chọn của người dùng

Người dùng yêu cầu tự ưu tiên mẫu rõ hình và mở rộng nhiều từ. Đã chuẩn bị bộ tham
khảo theo 181 nhãn hiện có: 179 nhãn có media đạt bộ lọc và thêm mục `xin chào`
dùng chung video `chào`, tổng 180 mục. `tháng trước` và `thương yêu` còn thiếu;
không tự thêm `là`. Metadata nguồn xác nhận nhãn không đồng nghĩa được chuyên gia
duyệt nghĩa/phương ngữ; giới hạn này được giữ trong ghi chú nguồn từng mục.

- Nguồn dùng: namwu/ViSignLanguage-Video (card khai báo CC BY 4.0) và
  KhangCN/Video_VSL (card khai báo Apache 2.0). Card được lưu vào `source_cards.json`.
  Chưa dùng nguồn không có khai báo giấy phép rõ trong lượt này.
- Kiểm tối đa hai clip lớn theo mỗi nguồn/nhãn, giải mã năm thời điểm, chấm độ nét
  ở cùng kích thước, độ phân giải, độ sáng và điểm trừ nền nhiều chi tiết. Chọn
  trong tập ứng viên này, không khẳng định tốt nhất mọi video của dataset.
- Với `chào`, ưu tiên namwu sau kiểm tra trực quan nền và vùng tay, thay cho mẫu
  Khang có nền rối. Lựa chọn được lưu trong script để tái lập.
- Video H.264/yuv420p, cạnh tối đa 640, faststart, bỏ âm thanh, không cắt mất phần
  động tác bằng giới hạn thời gian; clip quá dài bị loại thay vì cắt tùy tiện.
- Năm ảnh/video giữ đúng thứ tự thời gian, có vuốt ảnh, video phát lại và xem lần
  lượt. Từ chưa có mẫu không bị bỏ qua âm thầm.
- Dùng bộ dò tay hiện có để chọn ảnh đại diện trong năm ảnh, ưu tiên thấy tay rõ
  và vị trí thể hiện động tác; mở thẻ tại ảnh đó, vẫn giữ nguyên thứ tự ảnh để
  vuốt trước/sau. Đã xử lý 179 bộ, 842/895 ảnh có tay được bộ dò quan sát. Đây là
  bước chuẩn bị media, không thêm bộ dò vào luồng giọng nói lúc app chạy.
- Media đặt tại `.runtime/sign-library-media`, tách dataset/model/source Git.
  Endpoint `/sign-media/:file` chỉ phục vụ file có mục PUBLISHED tham chiếu;
  hỗ trợ HTTP Range. Giấy phép có endpoint riêng với danh sách tên cố định.
- Import vào danh mục `Ký hiệu tham khảo`, có ID quản lý theo hash tên từ, giữ mục
  đã xuất bản ngoài bộ import và có ledger; chạy lại cập nhật mục do công cụ quản
  lý, không thêm bản sao. Không tạo dữ liệu tài khoản hay thay model AI.
- Người dùng có thể chọn nhập văn bản trên màn xin quyền mic để thử ký hiệu mà
  không phải bật microphone; đường nhận giọng nói cũ vẫn được dùng.

Script chuẩn bị: `scripts/prepare-sign-library.py`; import:
`backend/scripts/import-sign-library.ts` (mặc định dry run, ghi khi có `--apply`).
Sau chuẩn bị, chạy `scripts/select-sign-keyframes.py` trước khi import để chọn
thumbnail và ảnh mở đầu trong gallery. Chạy lại chuẩn bị sẽ tạo lại catalog, cần
chạy lại bước chọn ảnh đại diện. Giấy phép gốc được tải từ trang Apache/Creative
Commons và phục vụ cùng media; ghi chú chỉ rõ nguồn và các biến đổi đã thực hiện.
Mọi kết quả, provenance và ledger nằm trong `.runtime/speech-sign-library/expanded`.
Nếu URL Conveyor đổi, chạy lại import để cập nhật URL media của các mục do công cụ
quản lý. Máy khác cần chuyển kho media riêng, không chỉ clone code/model.

Sửa local: URL media nội bộ `/sign-media/<hash>` tại màn ký hiệu được resolve
theo `API_BASE_URL`, thay vì tiếp tục dùng hostname Conveyor đã lưu lúc import.
Local/emulator không phụ thuộc tunnel để tải mẫu; URL media bên ngoài giữ nguyên.
Đã kiểm lại 15 ảnh và ba video của `xin chào`, `tôi`, `cảm ơn` qua backend3000:
ảnh200, video Range206, CORS cho localhost8080 hợp lệ. App debug cần hot restart
và tra lại câu để nhận URL mới.

Luồng này tra và ghép theo từ điển, chưa dịch ngữ pháp ngôn ngữ ký hiệu tự nhiên.
Chưa nghiệm thu phát video trên điện thoại thật; cần rà nội dung cùng người dùng/
người biết ký hiệu khi dùng làm tài liệu giảng dạy.

## Kiểm chứng hiện tại

- 4 test công cụ audit qua (split TEST/VAL, dữ liệu cá nhân, mâu thuẫn nhãn,
  Unicode, hash trùng và đường dẫn không an toàn).
- 9 test backend qua; database được mock, không chạm database người dùng.
- 129 test Flutter qua sau bổ sung nhập văn bản và chọn ảnh đại diện, gồm test ghép giao diện,
  lỗi mạng, phản hồi cũ và một test trình phát có mock platform: ngắt tại từ thiếu,
  video dọc trong khung điện thoại, giải phóng từng player khi đổi/đóng.
- 4 test media backend qua: Range 206, không phục vụ bản nháp/file bất kỳ, file thiếu.
- Flutter analyze phần speech sạch; backend TypeScript typecheck qua.
- Chưa đo phát media trên điện thoại thật và chưa xác nhận nghĩa của toàn bộ mẫu.
- Đã triển khai tại `https://nextsparklyboat60.conveyor.cloud`; kiểm tra mới nhất
  trả 180 mục. Cả sáu nhãn `xin chào`, `nghe`, `nhìn`, `rau`, `bàn tay`, `cứu`
  đều ghép thành sign, mỗi nhãn có năm ảnh, thumbnail HTTP 200, video Range HTTP
  206 và ghi nguồn. AI camera vẫn ready với 181 từ, không đổi weights.
- Đã quan sát giao diện public hiện ảnh mẫu và ảnh đại diện đúng chỉ số. Việc
  kiểm tra UI tiếp bị dừng vì local browser use tắt trong Work settings; không
  coi kiểm tra HTTP Range hoặc mock player là nghiệm thu phát trên máy thật.
- Lượt kiểm tra cuối: 13 test Flutter liên quan và 13 test backend liên quan qua;
  `git diff --check` sạch. Không thay đổi bản build trong lượt xác minh này.
