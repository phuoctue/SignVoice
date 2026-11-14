# Phiên dùng thử của khách — 24/10/2026

> **Policy v1, 14/11/2026 — sửa review vòng 1/2:** quyết định D1/D2/C1–C6/B và quyết định Lead về B1 thay thế chính sách cấp lại lượt, giữ/xóa dữ liệu và đăng nhập bên dưới. `GUEST-POLICY-V1-DESIGN/design.md` là **artifact bàn giao riêng của Lead**, không phải file được track trong repo; coordinator lưu/tích hợp bản được duyệt. Đây là hợp đồng mục tiêu, **chưa triển khai/nghiệm thu v1**; bảng API và kết quả cũ không chứng minh source đã tuân thủ. Auth/API/schema, cleanup/vận hành cần task triển khai/review riêng.

## Căn cứ và thời hạn đã chốt

Đã đọc `E:\WorkSpace\Đồ án chuyên ngành\Mo_ta_du_an_SignVoice_Web_App.docx`. Mục 3, đoạn 66 ghi:

> Khách có thể xem kho công khai và dùng thử một phiên học hoặc phiên dịch.

Đoạn này cũng dành lưu bộ thẻ, đồng bộ tiến độ và quản lý hội thoại cho tài khoản cá nhân. Tài liệu không ấn định số phút. Trong cuộc trao đổi ngày 24/10/2026, chủ dự án chọn **10 phút kể từ khi bắt đầu phiên thử**. Cơ chế dưới đây áp dụng cho những chức năng phiên dịch đang có; không tự triển khai thêm các màn học thẻ/quiz trong tài liệu.

## Hành vi sử dụng

1. Vào Khách rồi xem từ điển, chủ đề, ảnh/video công khai: **chưa tính giờ**.
2. Mở chức năng phiên dịch: hiện lời giải thích và nút **Bắt đầu phiên thử 10 phút**. Camera/micro vẫn cần người dùng cấp quyền riêng.
3. Bấm bắt đầu: máy chủ ghi mốc bắt đầu và kết thúc cách nhau đúng **600 giây**, dùng chung cho camera và Giọng nói → Hình ảnh. Gọi lại, đổi màn hình, tải lại, làm mới token hay tạm rời ứng dụng không gia hạn.
4. Trong phiên có đồng hồ đếm ngược. Khách có thể vào từ điển rồi quay lại trong khoảng thời gian còn lại.
5. Hết hạn: tháo/dừng camera, micro và stream AI. Màn khóa vẫn mở, cho xem từ điển công khai, đăng ký/đăng nhập và lựa chọn dữ liệu. Hiện rõ thời điểm giữ dữ liệu đến và lượt mới khả dụng. Bản nháp trong bộ nhớ vẫn xem/sao chép được; không tự lưu server.
6. Sau 10 phút, một guard chung chỉ cho status metadata, chuyển thành tài khoản mới, discard và các thao tác duy trì auth: logout, refresh, /auth/me, với **session khách hợp lệ**. Chặn export/profile/settings/sessions/history/favorites/conversations và private APIs khác. Hai DELETE /users/account và /users/data bị chặn cho guest ở mọi trạng thái; UI dùng discard riêng có transaction/outbox. Install ID/deviceHash không chứng minh sở hữu. Refresh chỉ được dùng khi credential/row/chain hợp lệ; toàn bộ session hết hạn hay bị T_s từ chối không phục hồi quyền chuyển/xóa bằng định danh thiết bị.
7. **D1:** đăng ký tài khoản MỚI chuyển cùng User._id, giữ dữ liệu/tiến độ. Đăng nhập tài khoản có sẵn **không chuyển dữ liệu khách**; phải nói rõ trước đăng nhập. Đăng nhập thất bại/mất mạng không xóa dữ liệu. Xóa dữ liệu khách cần xác nhận riêng, không bao giờ xóa dữ liệu tài khoản chính thức.
8. **D2:** hết quyền truy cập/chuyển/discard sau 7 ngày từ grant; mục tiêu dọn live trong 24 giờ tiếp theo, có thể chậm do sự cố/thời gian dừng. Mở app/poll/refresh/lượt mới không gia hạn. Tới hạn chặn dữ liệu ngay cả khi job chưa dọn; **không chặn refresh, /auth/me, status** nếu User/session còn hợp lệ. User đã xóa thì token còn hạn cũng 401. Không xóa khi mở/đóng app hay vừa hết 10 phút/24 giờ. Discard xóa live và ghi outbox cùng transaction, trả thành công ngay khi DB commit, không chờ ledger bên ngoài.
9. Sau 24 giờ, chủ động chọn lượt mới 10 phút: khi còn dữ liệu và session cũ hợp lệ, phải xác nhận riêng “Xóa dữ liệu khách hiện tại và bắt đầu lượt mới”; discard+grant nguyên tử, hủy xác nhận không đổi gì. User mới trống, không gia hạn dữ liệu cũ. Mất/hết credential không cho quyền xóa dữ liệu cũ bằng device ID; lượt mới độc lập có thể để dữ liệu cũ không truy cập được chờ D2 cleanup. V1 giữ một session hiện tại, không có kho credential theo từng allowance. Mất response grant có thể tiêu lượt; không cấp lượt thứ hai hay trả lại token tự động.

## Cách giữ hạn dùng

- Collection `guest_trials` dùng startedAt hiện có làm grant gần nhất, CAS giá trị đã quan sát cùng điều kiện đủ 24h; bổ sung lastGrantRequestHash chống replay. User.guestGrantedAt cố định để suy ra deadline dữ liệu/trial riêng, dùng User.dataVersion sẵn có; không thêm generation/currentGrantId/guestDataVersion hoặc deadline trùng lặp. Không lưu nội dung/email vào cooldown metadata.
- Tài khoản guest tham chiếu bản ghi hạn dùng qua trường không xuất ra DTO công khai `guestTrialId`.
- Trình duyệt dùng cookie HttpOnly `signvoice_guest_device`; native dùng định danh ngẫu nhiên 32 byte trong SharedPreferences. Giữ định danh qua logout/xóa session; chỉ được cấp lượt kế khi đủ 24h từ grant trước. Định danh này chỉ kiểm tra cooldown, không cho quyền xử lý dữ liệu.
- Tài khoản khách có sẵn được gắn định danh khi kiểm tra/bắt đầu phiên; thời gian không tính từ ngày tạo tài khoản cũ.
- Mốc bắt đầu được cập nhật nguyên tử, nên nhiều yêu cầu đồng thời chỉ tạo một hạn dùng. Máy chủ không nhận `expiresAt` hoặc số phút do client gửi.
- Không xóa/TTL cooldown record cùng guest data. Logout chỉ thu hồi session; discard xác nhận riêng. Source hiện có lỗi xóa GuestTrial và bypass newGuest:true: chưa sửa ở task docs. /auth/guest là sole grant issuer; /guest-trial/start cũ bị tắt mutation. Cleanup có giới hạn/idempotent, không chạm permanent/converted. Dừng trong certified all-writer stop, sau restart áp dụng D2 ngay cho real guests suốt W; không giữ lại real data để phục vụ migration. Q_guest=0/các fence giữ nguyên.
- W=169h > D2=168h: chỉ 6 synthetic canary G-L1/G-L2/M-G1/F-G1/N-G/C-G trong registry riêng được miễn physical cleanup VÀ data deadline đến T_s+30m, không miễn auth/T_s. Conversion canaries chạy trong 7 ngày. UI real guest dùng min(dataRetainedUntil, cutoff); thống kê D2 attrition riêng với migration impact.
- Đây là hạn dùng theo định danh bản cài đặt/trình duyệt, không xác minh một người duy nhất trên mọi thiết bị. Xóa toàn bộ cookie/bộ nhớ ứng dụng, dùng trình duyệt ẩn danh hay bản cài đặt khác có thể tạo định danh mới. Không sử dụng IP hoặc dấu vân tay thiết bị để tự suy đoán danh tính.

## Kiểm tra ở máy chủ và đường AI

**Bảng dưới mô tả API trước v1.** V1 cần status có deadline suy ra/nextTrialAvailableAt, sole grant 24h nguyên tử, discard riêng, post-trial guard và chặn đường DELETE guest cũ. Không thêm session selection từng lượt; không suy ra source đã tuân thủ.

| Đường gọi | Điều kiện |
| --- | --- |
| `GET /api/v1/guest-trial/status` | Phiên xác thực hợp lệ; đọc trạng thái, không bắt đầu giờ |
| `POST /api/v1/guest-trial/start` | Phiên xác thực hợp lệ; tạo hạn hoặc trả lại hạn cũ |
| `POST /api/v1/guest-trial/ai-ticket` | Khách đang trong hạn hoặc tài khoản chính thức; ticket mở stream có hiệu lực 30 giây |
| `POST /api/v1/sign-sequence` | Có xác thực; khách phải bắt đầu phiên và còn hạn |
| `POST /sign-ai/v1/compose` | Có xác thực; khách còn hạn |
| `WS /sign-ai/v1/stream?ticket=...` | Ticket ký đúng mục đích và phiên còn hợp lệ; đóng cả hai đầu kết nối ở hạn dùng của khách |
| Kho từ điển, danh mục, media, AI health | Vẫn công khai |
| Ghi hội thoại/yêu thích | Tài khoản chính thức |

Các mã lỗi trial gồm `GUEST_TRIAL_NOT_STARTED`, `GUEST_TRIAL_EXPIRED` (403). Hết trial không tự thu hồi session; guard cho status/convert/discard và logout/refresh/auth-me, trong đó data deadline chỉ chặn dữ liệu/convert/discard. TTL AuthSession 90 ngày không cho giữ dữ liệu 90 ngày. Legacy UI giới hạn giữ dữ liệu theo min(deadline dữ liệu, cutoff), không được phục hồi quyền bằng device ID.

## Sao lưu và khôi phục — quyết định B

Hết quyền dữ liệu live sau 7 ngày; dọn vật lý theo mục tiêu trên. Backup chỉ khôi phục sự cố, hạn chế truy cập, không dùng lại guest data cho sản phẩm. Lịch union 7 daily + 4 Sunday + 3 ngày-1-tháng **theo số lượng**, không phải 90 ngày: lịch đầy đủ giữ tối đa khoảng 92 ngày **từ ngày backup**, khoảng 99 ngày hoặc hơn từ grant nếu backup sát hạn/dọn chậm. Bỏ lỡ ngày 1/Chủ nhật hoặc ngừng backup có thể kéo dài; trần failure-case **không hữu hạn**. Cap 93 ngày cần review VÀ chủ dự án cho phép thực thi trước khi xóa bản sao, chưa áp dụng. Manual plaintext mã hóa ở task riêng; Atlas cũ đến khoảng 27/11 rồi owner yêu cầu chủ tài khoản xóa. Không hứa xóa hoàn toàn sau 7 ngày.

Ghi outbox discard/convert/cooldown grant (deviceHash/lastGrantedAt) cùng DB transaction rồi xuất async ra ledger ngoài backup; lag hoạt động bình thường tối đa cho phép 60s, quá hạn báo DR degraded, không chặn discard commit. Expiry suy ra từ grant+7d, không cần ledger expiry. Restore dùng watermark liên tục thật và gap rule: cô lập guest có thể đã chuyển, thu hồi session restore, chặn cấp lượt đến R+24h và xác minh/owner duyệt trước mở phần dịch vụ an toàn. Xóa mọi managed backup copy khi hết hạn chỉ trong task được owner cho phép; keys/tooling không thuộc guest data. Artifact Lead có đề xuất OPERATIONS/restore procedure; tài liệu này không cho phép chạy.

Ticket được bỏ khỏi URL trước khi chuyển tới AI và không ghi vào log; định danh bản cài đặt cũng được che trong log API. Gateway không phân tích hoặc sửa frame, landmark, ngưỡng nhận diện hay model. AI vẫn chạy trên loopback, giữ **181 từ / probability_ensemble**.

## Chạy web và Android

Gateway `/sign-ai` mặc định được gắn trong backend, trước JSON parser và sau CORS. Service AI giữ loopback `127.0.0.1:8001`; truy cập từ app qua gateway có xác thực. Cấu hình `AI_PUBLIC_PROXY=false` sẽ tắt gateway.

Web cùng origin dùng cấu hình build hiện tại:

```powershell
flutter build web --release --no-pub --no-web-resources-cdn --dart-define=API_BASE_URL=/api/v1 --dart-define=AI_SERVICE_URL=/sign-ai
```

Khi chạy riêng frontend/backend hoặc Android emulator, trỏ AI tới gateway của backend:

```powershell
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=AI_SERVICE_URL=http://localhost:3000/sign-ai
flutter run -d <android-device> --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=AI_SERVICE_URL=http://10.0.2.2:3000/sign-ai
```

Máy thật thay `10.0.2.2` bằng IP LAN của máy chạy backend. Khách sử dụng gateway của API hiện tại, kể cả khi còn lưu URL AI cũ ở thiết bị. Không public trực tiếp service loopback để tránh đi vòng kiểm tra hạn dùng.

## Kết quả kiểm tra

**Lịch sử 24/10/2026, không phải nghiệm thu policy v1 hoặc bằng chứng lỗi F1/bypass đã sửa.** Task thiết kế 14/11 chỉ kiểm tra tài liệu/phạm vi, không chạy backend/Flutter/DB.

- **133 backend tests đạt / 16 files**: hạn đúng 600 giây; bắt đầu đồng thời, refresh và vào lại khách không gia hạn; từ chối sửa hạn bằng payload; vẫn xem kho sau khi hết hạn; nâng cấp tài khoản mở lại chức năng; ticket đúng mục đích; kết nối khách và kết nối AI phía sau đều được đóng.
- **165 Flutter tests đạt, 1 test có cờ cấu hình được bỏ qua**; kiểm tra riêng dừng micro, đóng camera đang khởi tạo, giữ văn bản đang nhận trước khi kết thúc, màn yêu cầu tài khoản và thử lại khi mạng lỗi. Flutter analyze sạch.
- TypeScript, OpenAPI 66 paths / 85 method-route, Flutter Web release và APK debug build đạt.
- Đã kiểm tra API và WebSocket với AI thật bằng tài khoản QA riêng: handshake 181 từ, hạn ban đầu 600 giây, đóng stream theo deadline, sau hết hạn trả 403, từ điển trả 200, vào lại Khách vẫn hết hạn, nâng cấp tài khoản trở thành `unlimited`.
- Để kiểm tra ngắt stream ngay mà không thay hạn dùng của người dùng thật, chỉ deadline của tài khoản QA được rút ngắn trong bước mô phỏng; các tài khoản QA và bản ghi hạn dùng QA được dọn sau kiểm tra.
- Model manifest và bốn file runtime camera giữ nguyên. Không nghiệm thu camera/micro trên điện thoại vật lý hoặc bằng trình duyệt tự động trong đợt này; dùng widget tests và kiểm tra API/AI thật.

Log: `.runtime/guest-trial-*.log`. Bằng chứng API thật: `.runtime/guest-trial-live-verification.json`; mốc bảo toàn model: `.runtime/guest-trial-model-baseline.json`. Các file local này không được đưa vào Git.
