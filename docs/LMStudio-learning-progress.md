# LM Studio: phân tích tiến độ cá nhân cho SignVoice

SignVoice dùng giao diện học từ nhánh `dev`: **Từ điển → Khám phá / Đang học / Từ của tôi**. Tab **Đang học** có hai chức năng riêng:

- **Phân tích tiến độ cá nhân:** tỷ lệ đã nhớ, số từ đang học/cần ôn, kết quả theo chủ đề và nhận xét về điểm mạnh, điểm cần cải thiện, mục tiêu tiếp theo.
- **Gợi ý ôn tập:** kế hoạch ôn ngắn và ví dụ sử dụng từ, giữ nguyên chức năng đã có.

Nút **Lịch sử học tập** trong Đang học mở nhật ký cá nhân; mỗi thẻ từ trong chủ đề đã bắt đầu có **Lịch sử từ này**. Xem [chi tiết lịch sử và cách lưu dữ liệu](DICTIONARY_LEARNING.md#lịch-sử-học-tập-và-lịch-sử-từ). Không dùng lại màn hình hai tab hoặc API `/learning-progress` của bản LMS cũ.

## Cấu hình

Trong `backend/.env` trên máy chạy backend:

```dotenv
SIGNVOICE_LM_STUDIO_URL=http://127.0.0.1:1235/v1
SIGNVOICE_LM_STUDIO_MODEL=qwen3-4b-instruct-2507
# Chỉ điền nếu LM Studio bật Require Authentication.
SIGNVOICE_LM_STUDIO_API_KEY=
```

Giữ nguyên các biến cấu hình dự án khác. SignVoice chỉ dùng các biến có tiền tố `SIGNVOICE_LM_STUDIO_`, chỉ định model/system prompt trong từng yêu cầu và không thay preset, hội thoại hoặc model dự án lá cây. Không tự chọn model đầu tiên từ `/v1/models`.

Model ID phải trùng kết quả API. Tải bản **lmstudio-community/Qwen3-4B-Instruct-2507-GGUF**, lượng tử **Q4_K_M**, nạp model rồi bật **Developer → Start Server** ở cổng **1235**. Có thể bắt đầu với context 4096, điều chỉnh theo bộ nhớ máy.

```powershell
Invoke-RestMethod http://127.0.0.1:1235/v1/models
```

Backend và LM Studio cùng máy thì giữ `127.0.0.1`. Nếu backend ở máy khác cùng Wi-Fi/LAN, bật **Serve on Local Network** trên máy LM Studio và thay URL bằng `http://<IPv4 máy LM Studio>:1235/v1`. Cấu hình firewall/máy khách theo [setup máy khác, phần 11.1](SETUP_MAY_KHAC_LMSTUDIO.md#111-máy-anh-chạy-lm-studio-máy-khác-tự-chạy-signvoice). Không mở cổng AI ra Internet.

Nếu bật Require Authentication, tạo token trong LM Studio rồi điền vào `SIGNVOICE_LM_STUDIO_API_KEY` trên backend. Token chỉ nằm ở backend, không đưa vào Flutter, source hoặc chat. Sau khi đổi `.env`, khởi động lại backend.

## Cách chạy và sử dụng

Sau khi chuẩn bị database, media và các công cụ theo [setup](SETUP_MAY_KHAC_LMSTUDIO.md):

1. Bật LM Studio API và bảo đảm model SignVoice sẵn sàng.
2. Nếu đã cài đủ dịch vụ camera, chạy từ gốc dự án:

```powershell
.\scripts\start-signvoice.ps1 Local
```

3. Mở **http://localhost:3002** trên máy chạy SignVoice, đăng nhập tài khoản của mình.
4. Vào **Từ điển → Khám phá**, chọn một chủ đề và **Bắt đầu học**. Xem ảnh/video, tự đánh giá **Đã nhớ** hoặc **Ôn tập**. Các từ chưa đánh giá nằm ở **Đang học**.
5. Vào tab **Đang học**, bấm **Phân tích tiến độ cá nhân**. Xem tỷ lệ đã nhớ, số chủ đề đã bắt đầu, nhận xét và các chủ đề cần chú ý. Kết quả AI có nhãn **Phân tích từ LM Studio**; nếu AI chưa sẵn sàng, vẫn có **Phân tích từ số liệu**.
6. Bấm **Gợi ý ôn tập** nếu cần kế hoạch ôn ngắn. Phản hồi có nhãn **Gợi ý từ LM Studio** hoặc **Lộ trình ôn tập cơ bản** khi dùng quy tắc.
7. Dừng Local trên máy chạy SignVoice:

```powershell
.\scripts\stop-public-server.ps1 -Local
```

LM Studio được tắt riêng khi không còn máy nào dùng. Chỉ cài Từ điển/LMS, không cần camera: dùng cách chạy tối thiểu ở phần 7 trong setup, cổng 3000. Public qua Conveyor vẫn là chức năng riêng; không cần Public để chia sẻ LM Studio trong cùng Wi-Fi.

## Luồng dữ liệu và giới hạn

- `LearningService.coach()` → `POST /api/v1/learning/coach` → `learningAdvice(userId)` → LM Studio `/chat/completions`.
- `LearningService.analyzeProgress()` → `POST /api/v1/learning/analysis` → `analyzeLearningProgress(userId)` → LM Studio. Body chỉ nhận `{}`, người dùng lấy từ token; giới hạn 3 yêu cầu/phút/tài khoản.
- Tiến độ lấy từ `learning_enrollments` và `learning_word_progress` của tài khoản trong token. Các trạng thái là `LEARNING`, `REMEMBERED`, `REVIEW`; từ đã nhớ đến lịch ôn được tính là cần ôn.
- Gợi ý ôn nhận bốn tổng số tiến độ và tối đa 8 từ đã xuất bản. Phân tích nhận tổng trên **toàn bộ** chủ đề đang hoạt động đã bắt đầu, cùng tối đa 40 chủ đề cần chú ý; giao diện hiển thị tối đa 5 chủ đề trong khung kết quả. Tổng không bị giới hạn theo trang 10 chủ đề đang xem.
- Tỷ lệ đã nhớ được backend tính bằng số từ đang ghi nhận nhớ/chưa đến lịch ôn chia tổng từ đã xuất bản trong các chủ đề đã bắt đầu. Các từ chưa đánh giá nằm ở đang học. Không gửi ID tài khoản, email, ảnh/video, token đăng nhập hoặc lịch sử hội thoại đến AI.
- AI chỉ nhận xét tiến độ và gợi ý ôn. Nó không ghi thay đổi tiến độ, không thay kết quả quiz và không chấm động tác camera. Quiz camera giữ nguyên luồng của `dev`, xem [DICTIONARY_LEARNING.md](DICTIONARY_LEARNING.md).
- Backend chờ model tối đa **90 giây**; hai yêu cầu phân tích/gợi ý ở Flutter chờ **100 giây**. Các API thường vẫn giữ timeout 30 giây.
- Phản hồi trống, sai cấu trúc, bị cắt do hết token hoặc lỗi kết nối dùng phân tích từ số liệu/lộ trình cơ bản với nhãn rõ ràng. Tiến độ vẫn được lưu trong MongoDB. Phân tích AI hiện dùng ảnh chụp tiến độ hiện tại, chưa tổng hợp nhật ký để so sánh xu hướng theo ngày.
- Bản giao diện LMS cũ đã được lưu trong stash trước khi pull; không tự chuyển dữ liệu collection cũ sang các collection học của `dev` và không xóa dữ liệu MongoDB trong quá trình ghép code.

Các script SignVoice không tự khởi động hay tắt LM Studio. Nạp nhiều model cùng lúc có thể thiếu bộ nhớ; giữ các model/preset của dự án lá cây và chỉ nạp theo nhu cầu.
