# Từ điển và học ký hiệu

Mục Từ điển gồm Khám phá, Đang học và Từ của tôi.

- Khám phá dùng các Category đang hoạt động có DictionaryEntry đã xuất bản.
  Số từ được đếm từ dữ liệu đã xuất bản; số người học là số tài khoản đã bắt đầu
  chủ đề, không phải số lượt xem. Bắt đầu lại không tăng số người học.
- Chi tiết chủ đề có ảnh, chuỗi ảnh theo thời gian, video, ví dụ có trong nguồn
  và ghi chú/nguồn tham khảo. Mỗi trang tối đa 10 từ.
- Sau khi Bắt đầu học, người học tự chọn Đang học, Đã nhớ hoặc Cần ôn tập.
  Chỉ việc mở hoặc xem video không tự đánh dấu đã nhớ. Từ đã nhớ đến hẹn sau
  3 ngày được tính vào Cần ôn tập; tự đánh giá lại sẽ đặt lịch mới.
- Đang học có tổng số từ theo ba trạng thái, bộ lọc và phân trang 10 chủ đề.
- Từ của tôi lưu theo tài khoản, hỗ trợ tạo/sửa/xóa, ý nghĩa, ví dụ, ghi chú,
  ảnh JPG/PNG/WebP dưới 1 MB và link video HTTPS. Mỗi trang 10 từ. Từ riêng
  không tự xuất bản vào từ điển chung hoặc đưa vào dữ liệu nhận diện camera.

## Lưu trữ

Các collection mới: `learning_enrollments` (unique userId/topicId),
`learning_word_progress` (unique userId/entryId), `learning_personal_words`.
Tất cả API `/api/v1/learning/*` yêu cầu đăng nhập; chủ sở hữu được lấy từ token,
không nhận userId do client cung cấp. Dữ liệu được khôi phục trên trình duyệt khác.
Xóa tài khoản cũng xóa cả ba loại dữ liệu này trong cùng giao dịch.

Không cần chạy seed hoặc thay dữ liệu từ điển hiện có. Collection và index được
Mongoose tạo khi backend khởi động, theo cấu hình hiện tại của ứng dụng.

## LM Studio

Gợi ý ôn tập được gọi khi người học bấm nút, qua `POST /api/v1/learning/coach`.
Backend dùng `LM_STUDIO_URL` (mặc định `http://127.0.0.1:1234/v1`),
`LM_STUDIO_MODEL` nếu đã đặt và `LM_STUDIO_API_KEY` nếu server yêu cầu.
Nếu chưa chỉ định model, backend lấy model đầu tiên từ `/models`.

Model chỉ nhận tổng tiến độ và tối đa 8 từ trong các chủ đề người học đã bắt đầu.
Nó gợi ý kế hoạch ôn và câu ví dụ, không chấm động tác hoặc thay đổi đánh giá ghi nhớ.
Khi LM Studio không kết nối, app ghi rõ và đưa kế hoạch ôn cơ bản từ tiến độ thật.
Không sửa AI camera, model nhận diện hoặc các file `ai_service`.

## Đường dẫn

`S22` mở Khám phá. `/learn?tab=1` mở Đang học, `/learn?tab=2` mở Từ của tôi.
`/learn/topic/:id` mở chủ đề; thêm `?study=1` để học. Các đường dẫn này hỗ trợ F5
sau khi khôi phục đăng nhập. Media `/sign-media` được quy về origin API hiện tại,
tránh các URL localhost hoặc Conveyor cũ trong dữ liệu nguồn.

Backend kiểm tra các tệp `/sign-media` cục bộ trước khi trả media cho màn học.
Nếu thiếu tệp, app báo chưa có ảnh/video; không phát sinh loạt yêu cầu 404.
Khôi phục đúng các tệp hash vào `.runtime/sign-library-media` sẽ tự làm ảnh/video
xuất hiện lại sau khi làm mới, không cần đổi database hoặc model AI.
