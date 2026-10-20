# Kế hoạch giọng nói → văn bản → ký hiệu

Ngày lập: 20/10/2026. Trạng thái: kế hoạch, chưa triển khai tính năng.

## Mục tiêu và phạm vi bản đầu

Sau khi người dùng nói và dừng ghi nhận, giữ nguyên văn bản để đọc/chỉnh sửa,
đồng thời hiển thị dãy thẻ ký hiệu có nhãn, ảnh hướng dẫn và video mẫu nếu có.
Ưu tiên tra cụm từ hoàn chỉnh trước khi tra từ ngắn. Từ chưa có mẫu được đánh dấu
rõ trong đúng vị trí câu. Đây là ghép ký hiệu theo văn bản; chưa công bố là dịch
đầy đủ ngữ pháp ngôn ngữ ký hiệu.

## Thành phần đã xác minh để tái sử dụng

| Thành phần | Hiện trạng | Cách dùng |
|---|---|---|
| `lib/services/sign_ai/speech_input.dart` | Có nhận tiếng Việt và quản lý quyền mic | Giữ engine và luồng xin quyền |
| `lib/features/speech/speech_screens.dart` | Có ghi nhận, kết quả, chỉnh sửa, lịch sử | Thêm vùng xem ký hiệu vào kết quả |
| `DictionaryEntry` và API `/api/v1/dictionary` | Có `word`, `videoUrl`, `thumbnailUrl`, `imageUrls`, trạng thái duyệt | Dùng chung kho nội dung đã xuất bản |
| Trang quản trị/từ điển | Có bản nháp, duyệt, xuất bản | Duyệt mẫu trước khi công khai |
| `E:\WorkSpace\SignVoice\datasets\SignVoice_Extended_2026-10-16` | Có `canonical_videos`, `source_metadata` | Tìm mẫu RGB, lấy nguồn/nhãn gốc |
| `E:\WorkSpace\SignVoice\dataset_pipeline` | Có manifest, checksum, bảng rà nhãn và công cụ xử lý video | Tái dùng đối chiếu và chống trùng |
| Public server/Conveyor | Đã phục vụ Flutter, API và proxy AI | Phục vụ thêm media mẫu qua HTTPS |

API từ điển được kiểm tra tại server đang chạy trả về 0 mục đã xuất bản.
Điều này không chứng minh ổ đĩa không có video. Manifest cũ có nhãn chờ duyệt;
phải đối chiếu manifest mới và video thực trước khi chọn mẫu.

## Thứ tự triển khai

### 1. Kiểm kê và chọn nội dung mẫu

- Đọc metadata/manifest của kho mở rộng, xác nhận đường dẫn video thực và hash;
  xuất bảng từ/cụm từ, nguồn, biến thể, số mẫu và tình trạng kiểm tra.
- Giữ dấu tiếng Việt; chỉ dùng alias được khai báo và duyệt. Không suy ra cùng
  động tác chỉ vì cùng tên, không nhập skeleton mã số làm hình mẫu có tên.
- Ưu tiên các câu mẫu `xin chào`, `tôi`, `là`, `bạn`, `cảm ơn` và sáu từ camera
  quen thuộc nếu kho có mẫu phù hợp. Danh sách này là mục tiêu cần kiểm kê,
  không phải tuyên bố tất cả đã có dữ liệu đúng.
- Chọn một mẫu đại diện đã kiểm tra mỗi mục; giữ biến thể khác riêng có nguồn.
  Đối chiếu điều kiện sử dụng trước khi đưa media nguồn lên public.
- Không dùng video raw TEST của người dùng làm mẫu public hoặc dữ liệu TRAIN.

Đầu ra: catalog nháp, báo cáo từ còn thiếu/chưa duyệt và danh sách mẫu có thể xuất bản.

### 2. Chuẩn bị thư viện ảnh/video nhẹ

- Tái dùng công cụ OpenCV/FFmpeg hiện có nếu phù hợp, kiểm tra bản cài trước khi dùng.
- Tạo bản sao video ngắn đúng khoảng ký hiệu; giữ tay, mặt và phần thân cần thiết.
  Tạo thumbnail để tải nhanh. Ảnh thumbnail là ảnh xem trước, không coi là hướng dẫn
  đầy đủ cho động tác; mẫu động có video hoặc chuỗi ảnh đã kiểm tra.
- Đặt tên theo ID/hash, lưu nguồn và nhãn vào metadata. Nhập từ điển ở trạng thái
  nháp, chống trùng khi chạy lại; chỉ xuất bản những mục đã duyệt.
- Lưu media tách model và backend source; cấu hình thư mục media ngoài Git, có
  HTTPS, đúng MIME và HTTP Range cho phát video. Không phục vụ cả dataset 46 GB.

Đầu ra: các mục từ điển đã duyệt có media thật; thử tải/phát bằng URL public.

### 3. Ghép văn bản với ký hiệu

- Viết bộ ghép riêng có thể kiểm thử; tái dùng API/service từ điển. Tải danh mục
  đã xuất bản đủ trang và cache; không coi 20 mục trang đầu là toàn bộ từ vựng.
- Chuẩn hóa Unicode, hoa/thường và khoảng trắng; giữ dấu, văn bản gốc và dấu câu.
  Ưu tiên cụm dài nhất có trong catalog, không ghép xuyên ranh giới câu.
- Alias như `xin chào` → `chào` chỉ được áp dụng sau khi xác minh nội dung tương ứng.
- Kết quả mỗi đoạn có nội dung gốc, mục từ điển/media nếu tìm thấy, hoặc trạng thái
  chưa có mẫu. Không âm thầm bỏ `là`, tên riêng hoặc thay từ bằng ký hiệu gần nghĩa.
- Tên riêng/từ thiếu có thể thêm chế độ đánh vần sau, chỉ khi đã có bộ mẫu chữ cái
  được duyệt; không tự bật fallback trong bản đầu.

Đầu ra: danh sách đoạn có thứ tự và trạng thái tra cứu rõ ràng, độc lập model camera.

### 4. Tích hợp Flutter

- Giữ văn bản, chỉnh sửa, sao chép và lịch sử hiện tại; thêm nút/vùng `Xem ký hiệu`.
- Mỗi thẻ hiện nhãn và ảnh hướng dẫn nếu có; video có nút phát lại. Có điều khiển
  trước/sau và phát lần lượt; chỉ một video phát tại một thời điểm.
- Kiểm tra và bổ sung trình phát video dùng được trên Web/Android vì pubspec hiện
  chưa khai báo `video_player`. Hiện trang từ điển chủ yếu mở URL ra ngoài.
- Tải ảnh khi cần, chuẩn bị video kế tiếp có giới hạn, hủy request cũ khi sửa câu;
  không khởi tạo MediaPipe, TensorFlow hay LM Studio cho chức năng này.
- Bản đầu tra cứu sau khi dừng nói/chỉnh sửa xong để tránh thẻ nhảy theo transcript
  tạm. Hiển thị theo phần nhận dạng đã chốt có thể làm ở lượt tiếp theo.

### 5. Kiểm thử và triển khai public

- Bộ ghép: cụm nhiều âm tiết, dấu tiếng Việt, Unicode, alias đã duyệt, dấu câu,
  từ lặp, tên riêng, đoạn thiếu và catalog nhiều trang.
- Flutter: nhận giọng nói → kết quả → thẻ; chỉnh sửa cập nhật đúng; không có mẫu,
  lỗi mạng/media có thông báo; không làm mất văn bản hoặc xin quyền camera.
- Media: ảnh/video tương ứng đúng nhãn, không dùng ảnh giả hoặc icon thay động tác;
  thử tua, phát lại và chuyển video; dừng phát khi rời màn hình.
- Chạy Web và Android, kiểm tra bố cục điện thoại và HTTPS public; đo thời gian tải
  bằng media thật. Chỉ cam kết hiệu năng sau khi đo.
- Build release, chạy script public hiện có, kiểm tra bản JS mới và URL media từ
  ngoài máy. Giữ model camera hiện tại; không cần train Colab cho luồng tra cứu này.

## Điều kiện hoàn thành bản đầu

Một câu kiểm thử có thể ghi bằng mic hoặc nhập/chỉnh sửa, hiển thị đúng văn bản và
thứ tự thẻ; mỗi đoạn tìm thấy mở được mẫu đã duyệt, mỗi đoạn thiếu được báo rõ.
Không mất từ khi sửa/ghi lại, không lỗi khi mạng chậm; Web và Android phát được
media. Báo cáo coverage tính từ catalog thực, không lấy 181 nhãn model làm số mẫu
hướng dẫn đã sẵn sàng. Nghiệm thu nội dung dựa vào mẫu được duyệt, không chỉ test code.

## Mở rộng sau bản đầu

Tăng coverage bằng mẫu đã rà; bộ đánh vần có kiểm soát; nhận transcript đã chốt
theo đoạn; cache offline có giới hạn. Dịch câu tự nhiên sang cấu trúc ngôn ngữ ký
hiệu là công việc riêng cần người có chuyên môn kiểm chứng.
