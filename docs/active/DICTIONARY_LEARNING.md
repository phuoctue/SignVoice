# Từ điển và học ký hiệu

Mục Từ điển gồm Khám phá, Đang học và Từ của tôi.

- Khám phá dùng các Category đang hoạt động có DictionaryEntry đã xuất bản.
  Số từ được đếm từ dữ liệu đã xuất bản; số người học là số tài khoản đã bắt đầu
  chủ đề, không phải số lượt xem. Bắt đầu lại không tăng số người học.
- Chi tiết chủ đề có ảnh, chuỗi ảnh theo thời gian, video, ví dụ có trong nguồn
  và ghi chú/nguồn tham khảo. Mỗi trang tối đa 10 từ.
- Sau khi Bắt đầu học, từ chưa đánh giá nằm trong Đang học. Người học tự chọn Đã nhớ hoặc Ôn tập.
  Chỉ việc mở hoặc xem video không tự đánh dấu đã nhớ. Từ đã nhớ đến hẹn sau
  3 ngày được tính vào Ôn tập; tự đánh giá lại sẽ đặt lịch mới.
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

## Lịch sử học tập và lịch sử từ

Quiz ôn tập dùng AI camera để nhận diện ký hiệu. Khi bật camera, màn hình phân biệt **đang chờ ảnh**, **chưa thấy tay** và **đã thấy tay, đang nhận diện**; khi có từ được AI xác nhận sẽ hiện **Đúng ký hiệu** hoặc **Chưa khớp**. Kết quả được giữ để người học xem và lưu, kể cả khi kết nối mất sau đó. **Làm lại ký hiệu**, chuyển câu và quay về câu trước mở phiên nhận diện mới, tránh dùng kết quả giữ của câu cũ. Chỉ từ được AI xác nhận mới bật nút lưu; chưa đủ bằng chứng nhận diện không bị tự chấm là sai. Khi AI không trả kết quả camera trong 15 giây, màn hình báo lỗi để kết nối lại.

Trong **Đang học**, chọn **Lịch sử học tập** để mở nhật ký cá nhân. Trong một chủ đề đã bắt đầu, chọn **Lịch sử từ này** trên thẻ từ để chỉ xem từ đó. Trang lịch sử hỗ trợ tìm theo từ/chủ đề, sắp mới nhất trước và phân trang 10 bản ghi. Đường dẫn `/learn/history`, lọc từ bằng `?entryId=<id>`; tải lại trang vẫn giữ bộ lọc theo từ.

- **Bắt đầu chủ đề:** ghi một lần khi tham gia chủ đề lần đầu, không tăng khi bấm lại.
- **Tự đánh giá:** ghi từ, chủ đề, thời điểm và trạng thái mới. Gửi lại cùng trạng thái không tạo thêm lượt giả.
- **Ôn qua quiz camera:** ghi kết quả từng từ và việc kết quả có cập nhật tiến độ không. Nộp lại bài đã hoàn tất không tạo bản ghi trùng. Quiz chưa khớp vẫn là một lượt ôn, không được coi là đã nhớ.
- **Trạng thái đã lưu:** dữ liệu có trước nhật ký được hiển thị theo thời điểm đánh giá/cập nhật gần nhất trong WordProgress. Đây là ảnh chụp trạng thái cuối, không dựng lại các lần học trước đó. Khi từ đã có nhật ký mới, không hiển thị thêm ảnh chụp này để tránh trùng.

Collection mới `learning_events` lưu theo tài khoản, nhãn từ/chủ đề tại lúc ghi nhận và thời điểm server. Việc ghi nhật ký cùng giao dịch với thao tác học; lỗi ghi không để lại thay đổi tiến độ thiếu nhật ký. Xóa dữ liệu hoặc xóa tài khoản cũng xóa nhật ký của tài khoản đó. Xuất dữ liệu cá nhân bổ sung `learningHistory` và `learningProgress` để bao gồm cả nhật ký mới lẫn trạng thái cũ. Không ghi thêm lượt học chỉ vì mở ảnh/video.

API: `GET /api/v1/learning/history?page=1&search=...&entryId=...`; tất cả bộ lọc đều áp dụng trên dữ liệu của người trong token trước phân trang. Không nhận userId tùy ý. Các bản ghi không trả trường userId, media hoặc email.

## Biểu đồ, từ cần củng cố và mục tiêu ngày

Từ **Đang học → Thống kê & mục tiêu** (`/learn/insights`):

- **Biểu đồ 7/30 ngày:** chọn khoảng thời gian bằng danh sách sổ xuống. Mỗi ngày có hai cột Học/Ôn có hiệu ứng chuyển động; ngày không có dữ liệu hiện 0. Chạm ngày để mở danh sách từ thực tế, chuyển tab **Đã học / Đã ôn**, xem chủ đề, thời điểm gần nhất và lịch sử từng từ; 10 từ/trang. Vuốt ngang biểu đồ khi cần. Ngày được tính theo giờ Việt Nam **UTC+7**, kể cả khi server đặt ở múi giờ khác.
- **Học:** số từ khác nhau có lượt tự đánh giá trong ngày. Một từ được đánh giá nhiều lần cùng ngày vẫn tính một từ. **Ôn:** số từ khác nhau trong quiz camera đã hoàn tất, gồm cả nhận diện chưa khớp; nhiều lần ôn cùng từ vẫn tính một từ/ngày. Một từ có thể xuất hiện ở cả Học và Ôn nếu đã làm cả hai việc.
- Các quiz camera đã lưu từ trước khi có nhật ký vẫn được tính theo thời điểm hoàn tất. Quiz nháp, quiz chấm bằng LM Studio cũ, hoạt động trong tương lai và ảnh chụp trạng thái cũ không được suy thành lượt học/ôn.
- **Từ cần củng cố:** thống kê quiz camera trong 30 ngày lịch gần nhất, xếp số lượt chưa khớp giảm dần, rồi tỷ lệ chưa khớp, thời điểm gần nhất và ID để phân trang ổn định. Chỉ hiện từ còn xuất bản trong chủ đề đang hoạt động mà người học đã tham gia; có tổng lượt, số lượt chưa khớp và kết quả gần nhất. Đây là kết quả quiz đã ghi nhận, không phải thước đo độ chính xác chung của model. Có xem ký hiệu, mở chủ đề và lịch sử từ; 10 từ/trang.
- **Mục tiêu mỗi ngày:** mặc định **5 từ mới / 10 từ ôn**, hiển thị đầy đủ **Đã học 2/5 từ mới**, **Đã ôn 2/10 từ**. Khi đạt mục tiêu, thẻ và dấu tích chuyển xanh lá; có hiệu ứng số, thanh tiến độ và hoàn thành, tôn trọng cài đặt giảm chuyển động. Đổi được từ mới 1–100, từ ôn 1–200. Thanh dừng ở 100% khi vượt mục tiêu nhưng số thực tế vẫn hiển thị đầy đủ. Ôn chưa khớp vẫn là một lượt thực hành, không tự chuyển thành Đã nhớ.

**Cách tạo dữ liệu củng cố:** vào chủ đề đã tham gia → bộ lọc **Ôn tập** → **Bắt đầu quiz ôn tập** → thực hiện ký hiệu bằng camera, ghi nhận từng từ → nộp quiz. Nếu chưa có từ ôn, chọn **Ôn tập** trên thẻ từ đang học cần luyện trước. Các từ nhận diện chưa khớp được tổng hợp trong 30 ngày; chỉ mở video hoặc tự đánh dấu Đã nhớ không tạo kết quả quiz. Một lần ôn đúng không xóa những lượt chưa khớp trước đó, nên từ có thể vẫn xuất hiện với nhãn lần gần nhất đã khớp. Chọn **Xem ký hiệu**, **Mở chủ đề** hoặc **Lịch sử từ** để xem và luyện tiếp.

Từ mới chỉ tính khi server tạo bản ghi tiến độ đầu tiên của từ (`firstLearning=true`). Sự kiện cũ chưa có cờ này không được tự suy ra là từ mới. Việc đổi mục tiêu không làm thay đổi tiến độ, lịch sử hoặc kết quả quiz. Mục tiêu lưu ở `UserSettings.learningGoals`, theo tài khoản, được xuất cùng settings và trở về mặc định sau khi xóa dữ liệu cá nhân. Trang tải lại số liệu khi trở lại từ chủ đề/lịch sử hoặc khi ứng dụng hoạt động trở lại; có nút Làm mới.

Mục tiêu **không cập nhật theo chu kỳ**. Dữ liệu được tải khi mở trang, bấm **Làm mới**, lưu mục tiêu, quay lại từ chủ đề/lịch sử hoặc đưa ứng dụng hoạt động trở lại. Nếu tải lại khi trở về ứng dụng bị lỗi, giữ số liệu đã có và báo trạng thái.

API riêng: `GET /api/v1/learning/insights?days=7|30&page=1`, `GET /api/v1/learning/activity?date=2026-10-25&kind=learned|reviewed&page=1`, `PATCH /api/v1/learning/goals` với `{"newWords":5,"reviewWords":10}`. Tham số được kiểm tra chặt; chủ sở hữu lấy từ token. Các số liệu được backend tính từ dữ liệu thật, không cần gọi LM Studio và không cần đổi `.env`.

## LM Studio

**Phân tích tiến độ cá nhân** là nút riêng trong tab Đang học, gọi `POST /api/v1/learning/analysis` với body `{}`. Backend tổng hợp toàn bộ chủ đề đang hoạt động mà tài khoản đã bắt đầu, loại từ nháp/ẩn, áp dụng lịch ôn giống thống kê hiện có. Kết quả gồm tỷ lệ đã nhớ, tổng số theo trạng thái, số chủ đề, tối đa 40 chủ đề cần chú ý và nhận xét từ AI về điểm mạnh/cần cải thiện/mục tiêu tiếp theo. Giao diện hiển thị tối đa 5 chủ đề trong khung phân tích.

Số liệu do backend tính, không lấy số AI tự sinh. Nguồn được ghi rõ **Phân tích từ LM Studio** hoặc **Phân tích từ số liệu** nếu AI không sẵn sàng. Chưa bắt đầu chủ đề thì hướng dẫn bắt đầu trước. Phân tích không sửa tiến độ; không suy đoán thời lượng, chuỗi ngày học hoặc xu hướng tăng/giảm khi chưa có lịch sử. Giới hạn 3 yêu cầu/phút/tài khoản, không nhận userId hay prompt từ client.

Gợi ý ôn tập được gọi khi người học bấm nút, qua `POST /api/v1/learning/coach`.
Backend dùng `SIGNVOICE_LM_STUDIO_URL` (mặc định `http://127.0.0.1:1235/v1`),
`SIGNVOICE_LM_STUDIO_MODEL` (mặc định `qwen3-4b-instruct-2507`) và
`SIGNVOICE_LM_STUDIO_API_KEY` nếu server yêu cầu. Không lấy model đầu tiên từ
`/models`, không dùng các biến `LM_STUDIO_*` của dự án khác. Xem
[hướng dẫn setup cùng Wi-Fi](SETUP_MAY_KHAC_LMSTUDIO.md#111-máy-anh-chạy-lm-studio-máy-khác-tự-chạy-signvoice).

Model chỉ nhận tổng tiến độ và tối đa 8 từ đã xuất bản trong các chủ đề đang hoạt động mà người học đã bắt đầu. Không gửi ID tài khoản, email, ảnh hoặc video.
Nó gợi ý kế hoạch ôn và câu ví dụ, không chấm động tác hoặc thay đổi đánh giá ghi nhớ.
Khi LM Studio không kết nối, app ghi rõ và đưa kế hoạch ôn cơ bản từ tiến độ thật.
Backend chờ AI tối đa 90 giây; hai yêu cầu coach/analysis của Flutter chờ 100 giây.
Phản hồi trống, sai cấu trúc hoặc bị cắt do hết token cũng dùng lộ trình cơ bản;
không ghi nhận đó là phản hồi thành công của LM Studio.
Không sửa AI camera, model nhận diện hoặc các file `ai_service`.

## Đường dẫn

S22 mở Khám phá. /learn?tab=1 mở Đang học, /learn?tab=2 mở Từ của tôi. /learn/topic/:id mở chủ đề; thêm ?study=1 để học. Các đường dẫn hỗ trợ F5 sau khi khôi phục đăng nhập.

Tiếp tục học chỉ đưa ra các từ chưa nhớ và các từ đến hạn ôn. Danh sách trong chủ đề phân trang 10 từ. Bộ lọc tiến độ hiển thị từng trạng thái; mục Ôn tập mở quiz camera.

## Quiz ôn tập bằng camera

Quiz tạo tối đa 10 câu từ cần ôn. Mỗi câu hiển thị từ đích, camera nhận diện ký hiệu và phần mở rộng để xem ảnh/video mẫu. Kết quả nhận diện được lưu theo tài khoản khi chuyển câu; bài nháp được khôi phục khi tải lại trang.

Khi nộp bài, backend đối chiếu nhãn camera với từ và bí danh trong từ điển. Nhận diện khớp được 10 điểm và chuyển từ sang Đã nhớ, nhắc ôn lại sau 3 ngày. Câu chưa khớp giữ ở Ôn tập. Quiz không cần kết nối LM Studio. Các lượt quiz tiếp theo lấy nhóm từ kế tiếp trước khi quay lại từ chưa nhớ.

Collection learning_review_quizzes lưu câu hỏi, nhãn camera và kết quả. Chỉ chủ tài khoản truy cập; xóa tài khoản cũng xóa quiz. Logger không ghi nội dung quiz. File AI camera/model/dataset không bị sửa.
