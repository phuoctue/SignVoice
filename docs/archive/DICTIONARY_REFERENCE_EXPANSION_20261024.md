# Mở rộng từ điển và Giọng nói → Hình ảnh — 24/10/2026

Cập nhật sau đợt nhập: đã rà lại 152 từ ở nhóm dự phòng và thêm sắp xếp A–Z/Z–A. Xem [báo cáo phân loại và sắp xếp mới nhất](DICTIONARY_CATEGORIES_AND_SORT_20261024.md). Số liệu bên dưới ghi nhận tại thời điểm nhập kho ban đầu.

## Kết quả đã nhập và kiểm tra

- **3.425 mục xuất bản**: thêm 3.245, cập nhật 180; 0 mục trùng tên. Giữ nguyên 180 ID cũ và các bộ đếm/liên kết yêu thích.
- **3.424 video riêng, 17.120 ảnh JPEG**; “xin chào” dùng chung media của “chào”. Toàn bộ ảnh đã giải mã và kiểm tra giới hạn kích thước; kiểm tra video mẫu H.264, HTTP ảnh 200 và MP4 Range 206.
- Theo số mục: 3.237 từ `user_Dataset.tgz`, 96 từ `KhangCN/Video_VSL`, 92 từ `namwu/ViSignLanguage-Video` (đã gồm mục dùng chung “xin chào”).
- 33 chữ cái Latin/Vietnamese có media. Không chọn được nhãn “tháng trước” vì hai video không đạt giới hạn thời lượng/kích thước; API vẫn trả hai mẫu thật `tháng` + `trước`. Một ứng viên chữ Â bị loại, nhưng có mẫu Â hợp lệ khác.
- API thật xác nhận `xin chào tôi là bạn` → ký hiệu `xin chào`, `tôi`, đánh vần `là`, ký hiệu `bạn`; `bánh pizza` có mẫu riêng; `nộm` dùng mẫu `gỏi/nộm`; `nước Anh` có mẫu riêng. Giữ được văn bản Unicode dạng phân tách dấu và tra cứu số.
- Kiểm tra số mục của từng nhóm qua API khớp bộ đếm. Giữ hai danh mục cũ rỗng để không xóa dữ liệu cấu hình trước đây.
- **152 Flutter tests, 121 backend tests, 5 tests bộ lọc Python đạt**; Flutter analyze sạch; TypeScript/OpenAPI, Web release và APK debug build đạt. Sau review đã sửa lỗi dropdown khi chủ đề đang chọn bị quản trị viên ẩn.
- Mã băm bốn file runtime camera khớp trước khi sửa, manifest model không đổi, health vẫn **181 từ / probability_ensemble**. Web đang phục vụ khớp bản build mới.

| Chủ đề tham khảo | Số mục |
| --- | ---: |
| Giao tiếp và câu hỏi | 198 |
| Gia đình và quan hệ | 134 |
| Cảm xúc và thái độ | 283 |
| Hành động và tương tác | 455 |
| Cơ thể và sức khỏe | 205 |
| Ăn uống | 211 |
| Học tập và công việc | 464 |
| Thời gian | 109 |
| Đi lại và vị trí | 349 |
| Thiên nhiên và động vật | 305 |
| Sinh hoạt và đồ dùng | 333 |
| Mua bán và số lượng | 170 |
| Chữ cái và số | 57 |
| Từ vựng khác | 152 |

Backup trước nhập: `.runtime/speech-sign-library/dictionary-20261024/before-import-1792786148272.json`. Ledger: `import-ledger.json` cùng thư mục. Kết quả đối chiếu database: `.runtime/dictionary-db-preservation.json`; nguồn/media/API/camera: `.runtime/dictionary-final-verification.json`.

## Phạm vi

Kho tham khảo dùng chung cho **Từ điển** và **Giọng nói → Hình ảnh**, bao gồm văn bản nhập tay. Camera **Ký hiệu → Giọng nói** giữ model 181 từ. Không train lại, không sửa nhãn hoặc trọng số nhận diện và không đưa các từ tham khảo vào đầu ra camera.

Nguồn local: `E:\WorkSpace\SignVoice\SignVoice_Dataset_ToanBo_MoRong_2026-10-16.zip`. Chỉ đọc danh sách `DAILY_WORD_GROUPS` trong file văn bản người dùng cung cấp bằng AST/literal; không chạy notebook hay các lệnh tải/train trong file đó.

## Chủ đề và cách hiển thị

12 chủ đề sinh hoạt: Giao tiếp và câu hỏi; Gia đình và quan hệ; Cảm xúc và thái độ; Hành động và tương tác; Cơ thể và sức khỏe; Ăn uống; Học tập và công việc; Thời gian; Đi lại và vị trí; Thiên nhiên và động vật; Sinh hoạt và đồ dùng; Mua bán và số lượng. Thêm **Chữ cái và số** và **Từ vựng khác** cho những nhãn còn lại.

Danh sách gốc được bổ sung quy tắc từ khóa và các nhãn đã rà lại để tránh nhầm đồng âm/đa nghĩa: “nước mắm” thuộc Ăn uống, “Tiền Giang” thuộc Đi lại và vị trí, “buồn nôn” thuộc Cơ thể và sức khỏe, “băng dính” thuộc Sinh hoạt và đồ dùng. Cấu hình có thể sửa tại `backend/src/config/sign-library-categories.json`; quản trị viên vẫn có thể sửa danh mục của từng mục từ.

Mỗi mục có video MP4 H.264 bỏ âm thanh và 5 ảnh theo thứ tự thời gian, cạnh dài tối đa 640 px. Mặc định ảnh đại diện lấy ở giữa video; chữ cái và các mẫu được rà chọn thêm khung có bàn tay/chi tiết rõ. Năm ảnh không bị đổi thứ tự. Có ảnh xem trước, vuốt ảnh và phát video trong ứng dụng. Một số video nguồn minh họa nhiều cách ký hiệu; cần xem video đầy đủ để hiểu chuyển động.

Tra cứu ưu tiên cụm dài nhất, giữ nguyên văn bản và dấu câu. Tên thay thế chỉ dùng khi có quy tắc rõ, như `0 (số không)` có thể tìm bằng `0` hoặc `số không`; `gỏi/nộm` bằng `gỏi` hoặc `nộm`. Có 22 nhãn đồng nghĩa được khai báo riêng trong cấu hình. Các nhãn nước có thể tìm bằng cách gọi đầy đủ như `nước Anh`; không tự ánh xạ `anh` sang nước Anh. Không tự bỏ dấu tiếng Việt hoặc bỏ mọi phần trong ngoặc vì có thể đổi nghĩa.

“bạn” có mẫu nguồn riêng. Dataset không có nhãn riêng “là”; trường hợp này dùng **Đánh vần thay thế** với video/ảnh chữ L, A và giữ dấu huyền trong văn bản. Ảnh chữ cơ bản không thể hiện dấu thanh. Chỉ đánh vần khi có đủ media cho tất cả chữ; không âm thầm bỏ chữ, không coi đánh vần là ký hiệu của cả từ và không tuyên bố dịch ngữ pháp ngôn ngữ ký hiệu.

## Chọn nguồn

- Chỉ dùng RGB có nhãn nguồn xác minh, không phải dữ liệu cá nhân, không lỗi chất lượng đã ghi nhận, không xung đột nhãn theo cùng SHA256.
- Không dùng tập validation/test để tạo kho mới. Với phần từ điển gốc `user_Dataset.tgz`, cho phép `train` và nhãn chưa chia tập để làm media tham khảo; quy tắc này không thay đổi bộ lọc TRAIN mặc định của script audit.
- `namwu/ViSignLanguage-Video`: kiểm tra metadata nguồn CC BY 4.0. `KhangCN/Video_VSL`: kiểm tra Apache 2.0. Lưu thông tin nguồn/giấy phép và file giấy phép kèm media.
- Phần `Dataset.tgz` do người vận hành cung cấp không có văn bản giấy phép riêng trong archive; ghi đúng nguồn này, không gán giấy phép của nguồn khác.
- Lọc độ rõ tự động và kiểm tra mẫu ảnh không thay thế xác nhận chuyên gia về nghĩa, phương ngữ hay độ chính xác của mọi ký hiệu.

Media có tên băm, chỉ được phục vụ nếu đang được mục từ đã xuất bản tham chiếu. Không mở thư mục ZIP, video gốc, dữ liệu training hoặc thư mục báo cáo thành web root.

## Tái tạo trên máy khác

Dùng môi trường Python AI hiện có với OpenCV, NumPy, requests, imageio-ffmpeg và MediaPipe. Kho tham khảo và video nằm trong `.runtime`, không được đưa vào Git. Clone code riêng không tự tải lại hàng nghìn video.

Từ gốc dự án:

```powershell
.\ai_service\.venv\Scripts\python.exe scripts/prepare-sign-library.py --archive E:\WorkSpace\SignVoice\SignVoice_Dataset_ToanBo_MoRong_2026-10-16.zip --all-words --output .runtime/speech-sign-library/dictionary-20261024 --media .runtime/sign-library-media
.\ai_service\.venv\Scripts\python.exe scripts/select-sign-keyframes.py --catalog .runtime/speech-sign-library/dictionary-20261024/library.json --media .runtime/sign-library-media --hand-model web/mediapipe/hand_landmarker.task
```

Script lựa chọn nguồn kiểm tra SHA256 gốc, chất lượng giải mã, metadata giấy phép; không tải hoặc nạp trọng số nhận diện camera. Chạy xong mới nhập catalog. Kiểm tra số lượng và nhóm bằng dry-run trước:

```powershell
cd backend
npx tsx scripts/import-sign-library.ts --origin http://localhost:3002
npx tsx scripts/import-sign-library.ts --origin http://localhost:3002 --apply
```

Backend cần MongoDB replica set như ứng dụng hiện tại. Import mặc định không ghi dữ liệu. Khi có `--apply`, script sao lưu mục từ do script quản lý và danh mục vào `before-import-*.json`, rồi dùng transaction để cập nhật. Giữ `_id`, lượt xem, yêu thích; giữ nội dung do người quản lý sửa hoặc chưa xuất bản. Chạy lại không tạo bản trùng hoặc cộng dồn số lượng danh mục. `import-ledger.json` ghi mục mới/cập nhật/giữ nguyên.

Ảnh/video tải qua origin API hiện tại; origin local trong bản ghi không buộc điện thoại truy cập localhost của điện thoại. Cần chạy backend phục vụ media và cấu hình API/LAN như README; không chỉ sao chép APK mà bỏ backend và media.

## Hồ sơ kiểm tra local

Log và catalog nằm trong `.runtime/dictionary-*` và `.runtime/speech-sign-library/dictionary-20261024`. Kiểm thử backend dùng replica set tạm; không chạy test xóa dữ liệu trên database ứng dụng. Bản nhập thật có backup riêng. Kiểm tra bảo toàn camera so sánh SHA256 nguồn/model và health `word_classes: 181` trước/sau.

Kiểm tra trình duyệt tự động bị tắt trong Work settings ở đợt này; dùng Flutter widget tests, API thật và giải mã ảnh/video. Build APK không đồng nghĩa đã nghiệm thu microphone/camera trên điện thoại thật.
