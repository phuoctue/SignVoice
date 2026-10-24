# Rà soát danh mục và sắp xếp từ điển — 24/10/2026

Đã đối chiếu toàn bộ **152 mục** đang nằm trong “Từ vựng khác” trên database ứng dụng, chuyển **63 mục** vào chủ đề hiện có và **89 mục** vào bốn chủ đề mới. “Từ vựng khác” còn **0 mục**; bộ chọn chỉ hiện danh mục có từ. Hiện có **17 chủ đề có nội dung**, bao gồm Chữ cái và số.

Chỉ cập nhật `categoryId` của các mục được rà. Không nhập lại media hoặc ghi đè định nghĩa/nguồn/biến thể. Đã so sánh toàn bộ trường dữ liệu của 152 mục trước/sau, ngoại trừ danh mục và thời điểm cập nhật: ID, media, nội dung và bộ đếm giữ nguyên. Tại thời điểm rà, tổng số mục xuất bản trước và sau đều là **3.424** (số liệu đợt nhập trước là 3.425); đợt phân loại này không tạo/xóa mục từ.

## Chủ đề mới

| Chủ đề | Số từ chuyển vào |
| --- | ---: |
| Đặc điểm và tính chất | 36 |
| Văn hóa, tín ngưỡng và truyện kể | 19 |
| Xã hội và pháp luật | 12 |
| Khái niệm và từ nối | 22 |

## Sắp xếp

Màn Từ điển có bộ chọn **Sắp xếp từ vựng**: **Tăng dần (A–Z)** và **Giảm dần (Z–A)**. Mặc định là A–Z. Đổi thứ tự hoặc chủ đề sẽ quay về trang 1; lựa chọn thứ tự giữ khi tìm kiếm và chuyển trang.

Backend nhận `sort=word_asc` hoặc `sort=word_desc` tại `GET /api/v1/dictionary`. Dùng collation tiếng Việt, phân biệt chữ Ă/Â/Đ/Ê/Ô/Ơ/Ư; số xếp tự nhiên, ví dụ 2 trước 10. Có ID làm khóa phụ để phân trang ổn định. Sắp xếp trên toàn bộ tập kết quả trước `skip/limit`, không sắp riêng từng trang. Khi vừa tìm kiếm toàn văn vừa sắp xếp, tìm ID bằng text index trước, rồi sắp các kết quả đó bằng collation tiếng Việt vì Mongo text index yêu cầu simple collation.

API không có tham số `sort` vẫn giữ hành vi thứ tự cũ. Bộ chọn này áp dụng cho màn danh sách từ điển; không thay đổi thứ tự nhận diện camera hoặc chức năng quản trị.

## Danh sách phân loại đầy đủ

### Học tập và công việc — 30 từ

bổ trợ; bổ ích; chất lượng; chứng nhận; công nhận; công sức; cơ hội; khám phá; khả năng; lợi ích; mạch lạc; mạng lưới; nguồn gốc; nhược điểm; nhận thức; thành công; thành thạo; tiến bộ; tác dụng; tập trung; vai trò; vượt trội; vấn đề; vỡ lòng; xác định; ích lợi; đặc điểm; đối tượng; ưu tiên; ưu điểm.

### Hành động và tương tác — 15 từ

bất động; bị động; cố định; hút nước; lơ lửng; phòng chống; phấp phới; sống sót; thăng bằng; thất lạc; thập thò; đề phòng; chung kết; sân khấu; thắng lợi.

### Cơ thể và sức khỏe — 6 từ

chất độc; chất độc màu da cam; giãn cách xã hội; khát nước; mất (chết) (chỉ người); tận số.

### Cảm xúc và thái độ — 5 từ

nghênh nghênh (đầu); nguyện vọng; như hình với bóng; tưởng; vững chắc.

### Đi lại và vị trí — 5 từ

dọc; hàng dọc; hàng ngang; kia; trong khoảng.

### Thời gian — 1 từ

mới.

### Văn hóa, tín ngưỡng và truyện kể — 19 từ

cổ truyền; cổ tích; linh hồn; long vương; lạc long quân; ma; ma cà rồng; ma quỷ; màu nhiệm; mê tín; phong tục; phép mầu; thiên thần; thiên đình; thánh gióng; thần chết; thần kì; truyền thống; âu cơ.

### Xã hội và pháp luật — 12 từ

diệt chủng; hung thủ; hối lộ; kẻ cắp; kẻ thù; nô lệ; phản động; thuộc địa; tái phạm; tập thể; tự do; đạn.

### Đặc điểm và tính chất — 36 từ

bao la; bé loắt choắt; bằng phẳng; cao độ; chi tiết; chật chội; chặt chẽ; cong; dài; hỏng; khúc khuỷu; khổng lồ; lung tung; lấm lem; mềm mại; ngoằn ngoèo; nhọn; nhọn hoắt; náo động, náo nhiệt; nổi bật; phù hợp; phức tạp; riêng biệt; sinh động; siêu tốc; sâu thẳm; thích nghi; thẳng tắp; trong suốt; trống (không có gì); tĩnh lặng; vắng; vắng lặng; đặc biệt; ầm ĩ; ổn định.

### Khái niệm và từ nối — 22 từ

ba là; bốn là; cuộc sống; cuộc đời; có thể; cụ thể; hai là; hậu quả; khác; liên quan; mỗi; một là; ngược lại; năm là; phụ thuộc; suýt; thông qua; thông thường; trường hợp; tình huống; tồn tại; vẫn.

### Sinh hoạt và đồ dùng — 1 từ

cầu giao.

## Kiểm tra và sao lưu

- 124 tests backend đạt, bao gồm chuyển nhóm lặp không tạo trùng, bảo toàn media/ID/yêu thích, giữ nội dung đã chuyển thủ công, sắp xếp tiếng Việt/số, tìm kiếm và phân trang.
- Toàn bộ Flutter suite: 160 tests đạt, 1 test được đánh dấu bỏ qua sẵn trong suite. 46 widget tests từ điển/ứng dụng đạt sau kiểm tra bộ lọc, đổi thứ tự và quay về trang 1. Flutter analyze sạch.
- TypeScript build, OpenAPI, Flutter Web release và APK debug build đạt. Kiểm tra API thật duyệt hết các trang của cả hai chiều trên 3.424 mục, lọc Học tập và công việc (494 mục), tìm “bạn” (54 kết quả), ghép lọc chủ đề và tìm “học” (42 kết quả).
- Mã nguồn camera và manifest model không đổi trong đợt này; health vẫn 181 từ. JavaScript được server phục vụ khớp build mới. Không thực hiện kiểm tra trình duyệt tự động/thiết bị thật trong đợt này.
- Backup và ledger local: `.runtime/dictionary-topic-review/before-reclassification-1792816467678.json`, `reclassification-ledger.json`; kết quả đối chiếu: `verification.json`, `api-verification.json` cùng thư mục. Log: `.runtime/topic-sort-*.log`.

Cấu hình phân loại được lưu trong `backend/src/config/sign-library-categories.json`, khóa `reviewedCategories`, để import lại kho nguồn vẫn giữ chủ đề đã rà. Script `backend/scripts/reclassify-sign-library.ts` chỉ chuyển các từ đã rà đang còn ở danh mục dự phòng; chạy mặc định là dry-run, thêm `--apply` mới ghi dữ liệu bằng transaction và sao lưu trước khi ghi. Chạy lại sau khi hoàn tất không chuyển thêm mục nào; các mục đã được người quản lý chuyển sang nhóm khác được giữ nguyên.

```powershell
cd backend
npx tsx scripts/reclassify-sign-library.ts
npx tsx scripts/reclassify-sign-library.ts --apply
```

Phạm vi **Ký hiệu → Giọng nói giữ nguyên 181 từ**. Không thêm/sửa dữ liệu training hay model khi phân loại từ điển.
