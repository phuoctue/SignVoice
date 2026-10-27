# SignVoice

Ứng dụng hỗ trợ giao tiếp ngôn ngữ ký hiệu Việt Nam: Flutter Web/Android, backend Node.js/Express/TypeScript, MongoDB và service AI Python.

Đơn vị vận hành: **SignVoice**. Người phụ trách: **Phạm Phước Tuệ**. Liên hệ: **phuoctue0312@gmail.com**.

## Cập nhật trên máy hiện tại — 27/10/2026

- **Cá nhân → Chỉnh sửa hồ sơ → Đăng nhập & bảo mật** chứa Liên kết Google và Đổi mật khẩu. Đã kiểm tra lại luồng đổi mật khẩu cho USER/STAFF/ADMIN.
- LM Studio chạy nền bằng **llmster**, model Qwen3-4B-Instruct-2507 Q4_K_M, API nội bộ `http://127.0.0.1:1235/v1`. Bật lại sau khi khởi động máy bằng `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-learning-lmstudio.ps1`. Không cần mở Bionic, không cần build lại APK chỉ để bật AI. [Hướng dẫn LM Studio](docs/LMStudio-learning-progress.md#máy-hiện-tại-chạy-nền).
- Phân tích và gợi ý đã trả lời bằng model thật; các yêu cầu AI trùng đang chạy được gộp, không chia sẻ giữa tài khoản hoặc tiến độ đã thay đổi. 31 kiểm thử liên quan đạt; phân tích mã các file sửa đạt.
- Sửa lỗi chờ phân tích lâu qua điện thoại: APK gửi tác vụ nền và lấy trạng thái bằng yêu cầu ngắn, có thử lại khi mạng/gateway gián đoạn. Kết quả chỉ trả cho chủ tài khoản; giới hạn tác vụ và tự hết hạn sau 5 phút. Đạt 304 kiểm thử Flutter (1 bỏ qua) và 225 kiểm thử backend trên MongoDB tạm; giữ tương thích API gọi đồng bộ cũ.
- Phiên Conveyor trước đã hết hạn; phiên mới: `https://littleorangephone74.conveyor.cloud`. APK cần dùng đúng link mới. Google Android giữ nguyên client và SHA-1; nếu dùng Google trên web, thêm callback của tên miền mới trong Google Cloud.
- APK mới nhất: `E:\WorkSpace\SignVoice\SignVoice-Conveyor-ARM64-analysis-fixed-20261027.apk` (38,6 MiB), có luồng tác vụ nền sửa lỗi chờ phân tích lâu, giữ chữ ký cũ, đạt kiểm tra ABI/model tay/16 KB và không chứa Google client secret. SHA-256: `349D5AE4DE105E0D2D7166F4D52FC9D28FB55A95F60DC45BA37D006DE5134291`.

## Tối ưu API và Google Android — 26/10/2026

- API dùng lại kết nối, gộp các GET trùng đang chạy và giảm truy cập kho khóa Android; không lưu cache quyền. Thống kê dùng hai truy vấn tổng hợp thay cho mười truy vấn đếm. Dashboard tải song song; danh sách tài khoản hiển thị ngay khi có dữ liệu, không chờ danh sách role. JSON GET lớn được nén, dữ liệu cá nhân vẫn `no-store`.
- Google Android dùng Credential Manager và ID token được backend xác minh cùng nonce một lần, hết hạn sau 5 phút. Tài khoản email có sẵn cần vào **Cá nhân → Chỉnh sửa hồ sơ → Liên kết Google**, chọn cùng email, rồi dùng Google đăng nhập từ lần sau; giữ nguyên ID, mật khẩu, quyền và dữ liệu học. Liên kết Google và Đổi mật khẩu được gom trong mục Đăng nhập & bảo mật ở cuối màn hình chỉnh sửa.
- Cấu hình Google cần Web client và Android client cùng project. Android client dùng package `com.example.sign_voice` và SHA-1 của khóa ký APK; đổi Conveyor không đổi SHA-1. Thay URL Conveyor cần build lại endpoint API/AI, đồng thời cập nhật callback của luồng web. Xem [hướng dẫn OAuth](docs/OAUTH_SETUP.md).
- Kiểm tra tự động: 299 Flutter tests đạt, 1 bỏ qua; 220 backend tests đạt trên MongoDB tạm. Đo truy vấn thống kê tại máy: trung vị khoảng 334 ms trước và 41 ms sau (không bao gồm xác thực/HTTP/Conveyor). Đăng nhập Google bằng tài khoản thật cần xác nhận tiếp trên điện thoại.
- APK ARM64: `E:\WorkSpace\SignVoice\SignVoice-Conveyor-ARM64-api-google-20261026.apk` (38,6 MiB), cùng chữ ký bản trước; kiểm tra ABI, zipalign/ELF 16 KB, model tay và không chứa Google client secret đạt. SHA-256: `CFFE276435F6B4836D9CCB24CDFDAC04C8CD6EE28A779CC6ACD5F8C90A54C866`. API/AI dùng `https://lastaquatrail42.conveyor.cloud`; đường hầm vẫn có độ trễ mạng riêng.

## Trạng thái hoàn thiện ngày 24/10/2026

Đã đối chiếu `.agents/tasks/verification_note.txt` với các route đang chạy và hoàn thiện luồng USER, STAFF, ADMIN cùng dữ liệu backend. File ghi chú cũ mô tả một phiên bản trước; các màn hình hiện hành dùng lại biểu mẫu và màn hình chung thay vì tạo đủ từng tên file trong danh sách đó.

| Phần | Kết quả hiện tại |
| --- | --- |
| Đăng nhập | Email/mật khẩu, đăng ký, khách thử một phiên 10 phút, nâng cấp tài khoản khách giữ dữ liệu, refresh token, đăng xuất và bảo vệ route theo quyền. |
| Hồ sơ | Chọn ảnh đại diện từ thư viện/bộ chọn tệp, xem trước, lưu hoặc xóa; giữ hỗ trợ ảnh URL cũ. Ảnh JPEG/PNG/WebP được thu nhỏ trên client, giới hạn 512 KB; đổi email cần mật khẩu hiện tại. |
| Cài đặt | Lưu giao diện, cỡ chữ, tương phản, tốc độ/cao độ và tự đọc lên MongoDB. UI chỉ báo thành công sau khi API lưu được. |
| Hội thoại | API CRUD riêng theo tài khoản; lưu kết quả từ luồng giao tiếp, tìm kiếm có debounce, lọc nguồn/yêu thích, phân trang và chi tiết bằng ID. |
| Từ điển | Tải nội dung đã xuất bản trong danh mục hoạt động; tìm kiếm có debounce, chọn chủ đề kèm số từ, phân trang, chi tiết bằng ID. Xem ảnh nguồn và video ngay trong ứng dụng. |
| Giọng nói → Hình ảnh | Nói hoặc nhập văn bản để tra ảnh/video theo từ, cụm từ; dùng chung kho tham khảo với Từ điển. Từ chưa có mẫu riêng có thể đánh vần bằng media chữ cái, được ghi rõ là thay thế. |
| Yêu thích | Lưu/xóa trên server, kiểm tra quyền sở hữu, không tạo trùng; cập nhật lại bộ đếm từ dữ liệu thực. |
| Đồng bộ | Tải hồ sơ, cài đặt, hội thoại và yêu thích từ API; có trạng thái chờ/lỗi/thử lại. Xóa state khi đổi tài khoản. |
| Dữ liệu cá nhân | Xuất JSON dữ liệu tài khoản, xóa dữ liệu đã lưu, xem/thu hồi phiên đăng nhập, xóa tài khoản có xác nhận và mật khẩu với tài khoản local. |
| STAFF | Dashboard, danh sách/tìm kiếm/lọc/phân trang nội dung, chi tiết, thêm/sửa bản nháp, duyệt/từ chối theo quyền và xem danh sách người dùng. |
| ADMIN | Dashboard, tài khoản, role/quyền tùy chỉnh, nội dung, danh mục và phiên đăng nhập; dùng API và biểu mẫu chung. |
| An toàn dữ liệu | Validation chặt, DTO không chứa mật khẩu/token, cô lập dữ liệu người dùng, giao dịch MongoDB, bảo vệ quản trị viên hoạt động cuối cùng và phản hồi cũ khi đổi phiên. |
| Giao diện | Loading/error/empty/retry; giữ bản nhập khi lưu lỗi. Toàn bộ giao diện trên máy tính, kể cả Quản trị/STAFF và các biểu mẫu, dùng chung khung điện thoại tối đa 440 px. Điện thoại dùng hết chiều rộng màn hình. Bố cục web rộng được hoãn để phát triển sau theo yêu cầu. |
| Public information | `/privacy`, `/data-deletion` có thông tin người vận hành/email đã cung cấp trong cấu hình local. |
| OpenAPI | 91 paths, mô tả **112/112 method/route đang được mount**; script độ phủ đọc cấu hình mount thật trong `app.ts`. Bao gồm ảnh đại diện, đồng bộ khởi động và lịch sử/thống kê/mục tiêu học tập. |
| Thông báo & lịch học | Chuông hiển thị thông báo từ mới, ôn tập và push thử đã lưu trên máy chủ; đánh dấu đã đọc riêng từng tài khoản. Android hỗ trợ Firebase FCM và nhắc học theo giờ/ngày trong tuần, kể cả khi đóng app. Web hiện hỗ trợ chuông trong ứng dụng; chưa cấu hình Web Push. |

### Cập nhật media, ảnh đại diện và thông báo — 25/10/2026

- Trang chủ tải từ thật và ảnh từ API thay cho bốn mục minh họa cố định. Ảnh được giải mã theo kích thước hiển thị.
- Tra cứu quyền xem media dùng chỉ mục và nhớ cách phân giải URL cũ; mỗi yêu cầu vẫn kiểm tra trạng thái xuất bản. Web tải clip ký hiệu nhỏ bằng một GET và giữ tối đa 8 MB trong bộ nhớ; phát lại dùng dữ liệu đã tải. Không đổi chất lượng video hay model camera **181 từ**. Đường Conveyor vẫn có độ trễ mạng: video mẫu 50 KB đo được khoảng 2–3 giây tới byte đầu tiên.
- Vào **Cá nhân → Lịch học & thông báo** hoặc **Chuông → Đặt lịch & thông báo** để chọn giờ và ngày học. Android cần quyền thông báo; quyền “Báo thức và lời nhắc” giúp nhắc đúng giờ, nếu không cấp thì dùng lịch gần đúng của hệ thống. Lịch dùng múi giờ thiết bị, được phục hồi sau reboot và hủy khi đăng xuất/tắt nhận thông báo.
- Firebase Android: `android/app/google-services.json`, dự án `signvoice-143c9`, package `com.example.sign_voice`. Backend dùng `FIREBASE_PROJECT_ID` và `GOOGLE_APPLICATION_CREDENTIALS` trong `backend/.env`; khóa service account giữ ngoài source và đã thêm quy tắc bỏ qua Git. Không đưa khóa máy chủ vào ứng dụng.
- Chạy `cd backend; npx tsx scripts/verify-firebase.ts` để kiểm tra quyền FCM bằng `validate_only`, không gửi tới người dùng. Nút **Thử thông báo đẩy** trong chuông gửi riêng tới thiết bị của tài khoản, lưu bản ghi và giới hạn một lần/10 giây. Từ mới/ôn tập được kiểm tra mỗi phút khi backend chạy; nhắc học trên Android dùng lịch cục bộ và không cần backend đang bật.
- Push mang định danh người nhận, được Android kiểm tra trước khi hiện; thông báo cũ của tài khoản đã đăng xuất bị bỏ qua. Thiết bị gắn với phiên đăng nhập, không gửi cho phiên đã thu hồi; đổi token đăng nhập giữ đăng ký thiết bị.

Kiểm thử tự động gần nhất sau tích hợp LMStudio: **247 Flutter tests đạt, 1 bỏ qua**; backend **190 tests / 25 files đạt** trên MongoDB tạm, không dùng database thật cho bộ test. Khi chạy toàn bộ backend trên máy đang build Android, dùng `npm run test:isolated -- --maxWorkers=2 --minWorkers=1` để tránh quá tải và timeout khởi tạo.

### Tích hợp nhánh LMStudio vào dev — 25/10/2026

Nhận commit `d6c2201` bằng fast-forward từ `phuoctue/LMStudio`, bổ sung phân tích tiến độ, lịch sử học, thống kê/mục tiêu ngày và phản hồi quiz camera. Giữ các thay đổi local về thông báo, ảnh đại diện, bộ điều khiển phân trang và tối ưu khởi động. Routing dùng chung nhận thêm `/learn/history` (giữ `entryId`) và `/learn/insights`; xóa dữ liệu tài khoản dọn cả lịch sử học và thông báo. Bộ nhận diện camera giữ **181 từ**.

Đã push nhánh `dev` lên `phuoctue/SignVoice` và pull xác nhận tại commit `2f1a8ac`. Commit này khôi phục các cấu hình mẫu cần thiết cho MongoDB replica set/OAuth và yêu cầu tự sinh secret, đồng thời giữ cấu hình LM Studio mới; không thay file `.env` thực tế.

Bản sao trước khi ghép nằm trong Git stash `2e4aebeb7e9ccb8cbd29b875aed86b225f572cb1` và các ref `refs/codex/backup/*-before-lmstudio-*`; thông tin phục hồi và log ở `.runtime/lmstudio-*`. Các thay đổi local chưa commit được giữ trên máy. File APK/Web build trước lần tích hợp này cần build lại để có các màn hình mới.

### Tối ưu khởi động APK và Web qua Conveyor — 25/10/2026

- Bỏ thời gian chờ Splash cố định 1,4 giây; vẫn đợi khôi phục đăng nhập trước khi điều hướng.
- `GET /api/v1/users/bootstrap` gom hồ sơ, cài đặt, 20 hội thoại đầu và ID yêu thích vào một lần đồng bộ. Giữ API cũ và cơ chế dự phòng khi máy chủ chưa hỗ trợ endpoint mới. Trang chủ dùng lại lịch sử vừa đồng bộ, vẫn tải lại khi dữ liệu cũ hoặc còn bộ lọc.
- Web nén gzip JavaScript/CanvasKit, kiểm tra lại phiên bản bằng ETag; tải sớm JavaScript chính cùng bootstrap. Model bàn tay chỉ tải khi mở chức năng camera.
- Đo thực tế cùng đường Conveyor: JavaScript chính từ **4.116.569 byte xuống 1.163.116 byte truyền qua mạng** (~72%); tải riêng file từ **4,86 xuống 3,39 giây**. Đây là phép đo trước thay đổi HTML cuối, không phải thời gian mở toàn ứng dụng.
- Đồng bộ tài khoản gồm `/auth/me` và dữ liệu khởi động: trung vị 3 lần đo mỗi cách từ **4,86 xuống 2,39 giây**, số request từ **5 xuống 2** trên tài khoản QA mới. Tài khoản được xóa sau đo; không lưu token/mật khẩu trong báo cáo. Có thể đo lại bằng `node backend/scripts/measure-startup.cjs` khi backend public chạy ở cổng 3001.
- Conveyor vẫn có độ trễ: lần đo `/health/live` khoảng **1,65 giây tới byte đầu**, so với local khoảng **0,007 giây**. Máy tính, backend, AI và tunnel vẫn cần bật. Chưa đo thời gian mở trên điện thoại thật; tốc độ còn phụ thuộc mạng, thiết bị và dữ liệu tài khoản.
- Sau mỗi lần build Web, khởi động lại backend để nạp đúng các file đã nén: `scripts/start-signvoice.ps1 Public -SkipBuild` (đọc cấu hình public đã lưu). Khi chỉ build chưa xong, không dùng `-SkipBuild` để phát hành bản cũ.

Log kiểm tra và số đo: `.runtime/startup-*.log`, `.runtime/startup-api-comparison.json`. Không đổi chất lượng video, dữ liệu hoặc bộ nhận diện camera **181 từ**.

Nghiệm thu FCM ngày 25/10 trên máy ảo **Medium_Phone, Android 15, Google Play**, với token thật và tài khoản QA riêng:

| Trạng thái | Kết quả sau bản sửa kiểm tra người nhận |
| --- | --- |
| Foreground | Dart nhận thông báo, Android hiển thị và chuông có bản ghi. |
| Background | Bộ xử lý nền hiển thị thông báo, chuông có bản ghi. |
| Đóng từ đa nhiệm | Vẫn nhận thông báo và lưu bản ghi. |
| Khởi tạo nền mới | MainActivity đã đóng, bản APK dùng entry point `lib/main.dart`; FCM tạo FlutterEngine nền mới và hiển thị thành công. |

Quyền gửi HTTP v1 đã xác minh không còn 403. Bằng chứng trên máy phát triển: `.runtime/fcm-guard-foreground.json`, `.runtime/fcm-guard-background.json`, `.runtime/fcm-guard-closed_from_recents.json`, `.runtime/fcm-guard-cold_process.json`; ảnh `.runtime/fcm-foreground.png`. Ba tài khoản QA được dọn sau nghiệm thu. Android debug và Web JavaScript release build thành công; `flutter analyze` không có lỗi/cảnh báo. Web Push và iOS Push chưa cấu hình; kết quả trên là Android, không phải trình duyệt mở link Conveyor.

Màn đăng nhập đã bỏ các đoạn giải thích lặp lại về tài khoản SignVoice, đăng nhập lần đầu bằng Google/Facebook và trạng thái nhà cung cấp. Thông báo lỗi chỉ hiện khi người dùng thao tác.

Theo yêu cầu mới, cài đặt webcam đã bỏ **Ghi chẩn đoán cục bộ**, **Kèm ảnh camera để đối chiếu**, **Xuất bản ghi JSON** và **Xóa bản ghi cục bộ**, cùng các hook ghi hình/landmark phục vụ những nút này. Module phân tích offline và kiểm thử cũ được giữ lại; xuất JSON dữ liệu tài khoản là chức năng riêng trong phần quyền riêng tư.

### Từ điển và ảnh ký hiệu mở rộng

**Đợt mở rộng ban đầu đã nhập: 3.425 mục** (3.245 mục mới, cập nhật 180 mục cũ), tham chiếu **3.424 video và 17.120 ảnh**. Đợt đầu có 14 nhóm tham khảo; xem cập nhật phân loại bên dưới cho trạng thái hiện tại. ID, liên kết yêu thích và bộ đếm của 180 mục trước được bảo toàn; không có mục xuất bản trùng tên. “xin chào” dùng chung video của “chào”.

Chức năng **Giọng nói → Văn bản** đã đổi tên thành **Giọng nói → Hình ảnh**. Kho tham khảo được mở rộng từ ZIP người dùng cung cấp, độc lập với bộ nhận diện webcam. Từ điển chia theo 12 chủ đề sinh hoạt trong danh sách người dùng gửi, thêm nhóm **Chữ cái và số** và **Từ vựng khác**. Có ảnh xem trước, 5 ảnh theo thứ tự động tác và video phát trong ứng dụng.

“bạn” dùng mẫu nguồn riêng. Dataset không có nhãn riêng “là”, nên giao diện ghi **Đánh vần thay thế**, dùng media chữ L và A, giữ dấu huyền trong văn bản. Chỉ đánh vần khi có đủ media chữ cái; đây là tra cứu tham khảo, chưa phải dịch ngữ pháp ngôn ngữ ký hiệu.

**Ký hiệu → Giọng nói giữ nguyên 181 từ và model hiện tại.** Kho ảnh/video mở rộng không được dùng để train hoặc thay nhãn nhận diện. Nguồn, quy tắc lọc, phân loại, nhập dữ liệu và hướng dẫn tái tạo nằm trong [báo cáo mở rộng từ điển](docs/DICTIONARY_REFERENCE_EXPANSION_20261024.md). Media local nằm trong `.runtime/sign-library-media`, không đưa video hoặc ZIP 46 GB vào Git.

### Rà lại danh mục và sắp xếp từ điển

Đã chuyển đủ **152 từ** khỏi “Từ vựng khác”: **63 từ** vào chủ đề hiện có và **89 từ** vào bốn nhóm mới: **Đặc điểm và tính chất (36)**, **Văn hóa, tín ngưỡng và truyện kể (19)**, **Xã hội và pháp luật (12)**, **Khái niệm và từ nối (22)**. Danh mục rỗng được ẩn khỏi bộ chọn; hiện có 17 nhóm có nội dung. Tổng số mục xuất bản trước/sau lần rà này đều là **3.424**; ID, ảnh/video, nội dung và bộ đếm của 152 mục được giữ nguyên.

Có bộ chọn **Tăng dần (A–Z) / Giảm dần (Z–A)** theo thứ tự tiếng Việt. Sắp xếp toàn bộ kết quả trước phân trang, dùng chung với tìm kiếm và lọc chủ đề; đổi bộ lọc quay về trang 1. Xem [danh sách đầy đủ 152 từ đã phân loại và kết quả kiểm tra](docs/DICTIONARY_CATEGORIES_AND_SORT_20261024.md).

### Quyền khách và khóa hết hạn dùng thử

Đã đối chiếu file `Mo_ta_du_an_SignVoice_Web_App.docx` (mục 3: xem kho công khai và thử một phiên). Theo lựa chọn đã chốt của chủ dự án, phiên thử dài **10 phút từ lúc bấm Bắt đầu**, do máy chủ ghi nhận. Mở từ điển chưa tính giờ; tải lại, làm mới token, đổi chức năng hoặc vào Khách lần nữa trên cùng định danh trình duyệt/bản cài đặt không đặt lại hạn.

Hết hạn sẽ dừng camera/micro và ngắt kết nối AI, hiện đăng nhập/tạo tài khoản. Khách vẫn xem được từ điển công khai và sao chép bản nháp. Lưu hội thoại, yêu thích và đồng bộ cá nhân cần tài khoản chính thức. Đăng ký nâng cấp từ khách mở lại chức năng, giữ ID và dữ liệu cũ. Model camera **giữ nguyên 181 từ**.

Xem [chính sách dùng thử, giới hạn định danh, đường API và kết quả kiểm tra](docs/GUEST_TRIAL_POLICY_20261024.md). Gateway AI `/sign-ai` mặc định bật; client nhận ticket mở stream sau xác thực. AI tiếp tục chạy trên loopback `127.0.0.1:8001`.

### Phạm vi còn phụ thuộc bên ngoài

- **Facebook:** giữ nguyên code/nút hiện có và hoãn hoàn thiện theo yêu cầu. Không coi đăng nhập Facebook là đã nghiệm thu.
- **Google:** đã có luồng OAuth, callback, tạo/liên kết tài khoản và kiểm thử backend; chưa thực hiện lượt đăng nhập thật qua màn chấp thuận của Google trong đợt này. Cần cấu hình ứng dụng và callback đúng origin; xem [OAUTH_SETUP.md](docs/OAUTH_SETUP.md).
- **Email:** quên/reset/đổi mật khẩu đã có code và tests. Chưa gửi email thật trong đợt này; cần kiểm tra SMTP của người vận hành theo [SMTP_PASSWORD_RESET.md](docs/SMTP_PASSWORD_RESET.md).
- **Báo cáo STAFF:** endpoint cũ chưa có nghiệp vụ xử lý report, nay trả HTTP 501 `FEATURE_UNAVAILABLE`; không trả thành công giả.
- **AI/thiết bị:** không thay model/dataset hoặc tuyên bố đã giải quyết độ chính xác webcam. Camera, microphone, TTS, tốc độ và khả năng nhận diện cần đo trên thiết bị thật. Xem [SETUP_AI.md](docs/SETUP_AI.md) và các báo cáo đánh giá trong `docs/`.
- **Media:** không tạo video ký hiệu giả. Chất lượng, giấy phép và độ phủ video trong từ điển cần được người quản lý nội dung xác minh.
- Trước khi phát hành public, người vận hành cần xác nhận chính sách log/backup và thời gian lưu trữ đúng với hạ tầng triển khai.

## Kết quả kiểm tra

| Kiểm tra | Kết quả |
| --- | --- |
| `flutter analyze --no-pub` | **Không có lỗi/cảnh báo/info.** |
| Toàn bộ Flutter tests | **247 tests đạt, 1 test được đánh dấu bỏ qua trong suite**. Có test service/DTO/state, auth/STAFF, mobile layout/keyboard, routing, retry, chỉnh sửa văn bản, giọng đọc, media cache, thông báo/lịch học, khởi động và tiến độ/thống kê học tập. |
| Bố cục desktop/mobile | Kiểm tra Cá nhân của ADMIN/STAFF, Quản trị, đổi tab, biểu mẫu và quay lại đều giữ khung gọn trên desktop; viewport điện thoại 390 px vẫn vừa màn hình. |
| Flutter tests sau chỉnh giao diện | **52 tests liên quan đạt** sau chỉnh tìm kiếm; **9 tests user-data đạt** sau chỉnh STAFF/hồ sơ; **57 tests auth/widget đạt** sau thu gọn đăng nhập. |
| Backend trên replica set tạm | **190 tests / 25 files đạt**; gồm import lặp giữ ID/yêu thích, bảo toàn nội dung thủ công, nguồn dữ liệu, đánh vần, thông báo, đồng bộ khởi động, nén Web và tiến độ/thống kê học tập. |
| Bộ lọc dữ liệu tham khảo Python | **5 tests đạt**; bộ lọc TRAIN mặc định giữ nguyên, mở rộng tham khảo không nhận dữ liệu cá nhân/held-out. |
| Backend sau chỉnh bộ đếm yêu thích | **13 tests user-data đạt**, gồm sửa bộ đếm cũ, dữ liệu riêng, export/reset, phiên, STAFF và giao dịch đồng thời. |
| JavaScript hand worker | **33 tests đạt**. |
| Python worker/delivery/replay/socket | **16 tests đạt**; không phải phép đo accuracy. |
| Backend build và OpenAPI | TypeScript build đạt; OpenAPI hợp lệ, độ phủ **100%** của route đang mount. |
| Android debug | Build thành công, tạo `build/app/outputs/flutter-apk/app-debug.apk`; chưa chạy nghiệm thu trên thiết bị. |
| Android release ARM64 | Build thành công ngày 25/10, `build/app/outputs/flutter-apk/app-release.apk` khoảng 57,2 MiB; trỏ API/AI tới Conveyor hiện tại. Dùng khóa debug để cài thử; chưa đo cold start trên điện thoại thật. |
| Flutter Web release | Build JavaScript thành công ở `build/web`. Wasm dry run còn cảnh báo từ `flutter_secure_storage_web` và `flutter_tts`; chưa nghiệm thu Wasm. |
| Kiểm tra Chrome | Đã đăng nhập USER, lưu hồ sơ và tải lại giữ dữ liệu/phiên; kiểm tra cài đặt webcam và khu vực STAFF/ADMIN bằng database tạm. |

Tests dùng mock và database tạm tùy loại. Kết quả này không thay thế đăng nhập Google thật, gửi email thật, kiểm tra camera/microphone hoặc nghiệm thu Android trên thiết bị. Log đợt hoàn thiện nằm trong `.runtime/completion-*.log`; đợt mở rộng từ điển có `.runtime/dictionary-*.log` và `.runtime/dictionary-final-verification.json` trên máy phát triển. Lần sửa bố cục sau đó có log `.runtime/layout-*.log` và `.runtime/compact-layout-*.log`; kiểm tra trình duyệt tự động ở lần này bị tắt trong Work settings, nên kích thước được xác minh bằng Flutter widget tests.

## Chạy trên máy hiện tại

Mở PowerShell tại thư mục dự án:

```powershell
cd E:\WorkSpace\SignVoice\SignVoice
.\scripts\start-signvoice.ps1 Local
```

Script build Flutter/backend và chạy web + API cùng origin tại **http://localhost:3002**, kết nối service AI cổng 8001. Nếu đã build bản mới, có thể dùng `-SkipBuild`. Nếu báo AI đang chạy khác phiên bản code/model, đọc thông báo và dừng đúng service cũ trước khi chạy lại; không tắt mọi tiến trình Python/Node trên máy.

### Cấu hình backend

Backend cần MongoDB Atlas hoặc MongoDB local **replica set** để chạy các transaction. Cấu hình `backend/.env` theo `backend/.env.example`; không commit file chứa secret. Hai giá trị liên hệ public đã được điền ở máy hiện tại: `PRIVACY_OPERATOR_NAME="SignVoice — Phạm Phước Tuệ"`, `SUPPORT_EMAIL=phuoctue0312@gmail.com`. Máy khác cần điền lại để các trang thông tin không trả bản nháp HTTP 503.

### Chuyển bộ từ điển sang máy khác

Chỉ pull Git chưa tải được media/database từ điển. Gói **SignVoice-Media-20261024.zip** được gửi riêng, gồm **3.424 mục từ công khai, 3.423 video, 17.115 ảnh**, thông tin nguồn/giấy phép, danh mục và `README_VI.md`. File trên máy đóng gói nằm tại `.runtime/share/SignVoice-Media-20261024.zip`, kèm `.zip.sha256`; `.runtime` và ZIP không được đưa lên Git.

Người nhận giải nén gói, mở terminal tại thư mục có `README_VI.md` rồi chạy:

```powershell
node .\install-media.cjs --verify-only
node .\install-media.cjs --project "D:\Projects\SignVoice"
```

Trình cài kiểm tra SHA256 từng file, giữ file giống nhau và từ chối ghi đè file khác nội dung. Không chép `.env`, dữ liệu tài khoản hoặc thay source code. Mã nguồn đã pull cần có đủ bản cập nhật từ điển, kể cả cấu hình chủ đề mới.

Sau khi cấu hình database riêng, người nhận cần một ADMIN hoạt động khớp `ADMIN_EMAIL` để nhập dữ liệu. Với **database phát triển trống**, script hiện có `npm run db:create-admin` trong `backend` tạo tài khoản dev `admin@signvoice.com`; đặt `ADMIN_EMAIL` khớp email đó trong `.env` riêng và đổi mật khẩu mẫu sau khi đăng nhập. Nếu đã có ADMIN riêng thì dùng email của ADMIN đó, không cần tạo tài khoản dev.

Từ `backend`, kiểm tra trước rồi nhập (origin là backend của người nhận, không có `/api/v1`):

```powershell
npx tsx scripts/import-sign-library.ts --catalog .runtime/speech-sign-library/shared-20261024/library.json --origin http://localhost:3000
npx tsx scripts/import-sign-library.ts --catalog .runtime/speech-sign-library/shared-20261024/library.json --origin http://localhost:3000 --apply
```

Để chỉ xem từ điển không cần cài model AI; chạy backend và frontend riêng như bên dưới. Luồng `start-signvoice.ps1 Local` chạy gộp còn cần model/service AI theo hướng dẫn dự án. Các cấu hình phân loại và ảnh đại diện trong gói đã được đối chiếu với dữ liệu công khai hiện tại. Gói không chứa model, không thay bộ nhận diện 181 từ.

### Khởi động backend và frontend riêng

```powershell
cd backend
npm ci
npm run dev
```

Mở terminal khác tại gốc dự án:

```powershell
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=AI_SERVICE_URL=http://localhost:3000/sign-ai
```

Thêm origin chính xác vào `CORS_ALLOWED_ORIGINS`. Web dùng access token trong bộ nhớ và cookie refresh HttpOnly, SameSite=Strict; frontend/backend cần cùng site (ví dụ `localhost` ở hai cổng). Native dùng secure storage.

Android emulator trỏ API tới máy chủ qua `http://10.0.2.2:3000/api/v1`; gateway AI qua `http://10.0.2.2:3000/sign-ai`. Máy thật cần IP LAN có thể truy cập của máy chạy backend/AI; xem `flutter devices` rồi chọn thiết bị:

```powershell
flutter run -d <device-id> --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=AI_SERVICE_URL=http://10.0.2.2:3000/sign-ai
```

Để cài thử trên điện thoại Android ARM64 qua Conveyor, build **release** thay vì dùng bản debug:

```powershell
$signVoiceOrigin = (Get-Content -Encoding UTF8 '.runtime/public-settings.json' -Raw | ConvertFrom-Json).publicOrigin
.\scripts\build-ai-android.ps1 -SdkPath 'E:\Android\Sdk' -ApiBaseUrl "$signVoiceOrigin/api/v1" -AiServiceUrl "$signVoiceOrigin/sign-ai"
```

Kết quả ở `build/app/outputs/flutter-apk/app-release.apk`. Cài đè bản mới để nhận thay đổi; URL Conveyor đổi thì cần build lại APK với địa chỉ mới. Bản này vẫn dùng khóa debug theo cấu hình hiện có để cài thử, chưa phải bản ký để phát hành CH Play. Backend, AI và tunnel vẫn phải chạy khi dùng chức năng trực tuyến.

Nếu build Android từ terminal của công cụ tự động trên Windows gặp `Unable to establish loopback connection` tại Java Selector, lần build này đã chạy được với biến môi trường chỉ áp dụng cho terminal hiện tại:

```powershell
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:\Windows\Temp'
flutter build apk --debug --no-pub
```

Tham khảo [báo cáo lỗi Java Selector và cách xử lý trong môi trường Windows](https://github.com/openai/codex/issues/40902). Đây là điều chỉnh nơi tạo socket tạm cho tiến trình Java; không cần đổi firewall hoặc cài đặt bảo mật. Build còn cảnh báo tương thích Kotlin tương lai của `flutter_tts` và phiên bản SDK XML; APK debug hiện vẫn build được.

### AI và LM Studio

Hướng dẫn chuẩn: **[SETUP_AI.md](docs/SETUP_AI.md)**. Cần Python 3.11 x64, Flutter stable, Node.js 20+ và Git. Model tải từ GitHub Release, kiểm tra SHA256; không cần tải dataset TRAIN 46 GB.

```powershell
git clone --branch dev https://github.com/phuoctue/SignVoice.git
cd SignVoice
.\scripts\setup-ai-service.ps1
.\scripts\start-ai-service.ps1
```

Health mong đợi: `http://localhost:8001/health` có `ready: true`, `word_classes: 181`, `word_engine: probability_ensemble`. Model hiện dùng không bị thay bằng kết quả train chưa đạt yêu cầu.

Nhận diện webcam hiện dùng model Python trực tiếp, không bắt buộc LM Studio. Giao diện Từ điển gồm **Khám phá / Đang học / Từ của tôi**. Trong **Đang học**, nút **Phân tích tiến độ cá nhân** gọi `POST /api/v1/learning/analysis` để xem tỷ lệ đã nhớ, kết quả theo chủ đề và nhận xét; nút **Gợi ý ôn tập** gọi `POST /api/v1/learning/coach` để lấy kế hoạch ôn ngắn. Backend kết nối LM Studio bằng `SIGNVOICE_LM_STUDIO_URL` (mặc định cổng 1235), `SIGNVOICE_LM_STUDIO_MODEL` và API key tùy chọn. Xem [kết nối LM Studio](docs/LMStudio-learning-progress.md) và [setup máy khác/cùng Wi-Fi](docs/SETUP_MAY_KHAC_LMSTUDIO.md). Các trang thử ảnh và proxy AI cũ không được ứng dụng sử dụng đã được dọn khỏi source.

Trong **Đang học**, **Lịch sử học tập** hiển thị các lượt học/ôn đã ghi nhận; từng thẻ từ có **Lịch sử từ này**. **Thống kê & mục tiêu** có biểu đồ 7/30 ngày, từ thường chưa khớp trong quiz và mục tiêu ngày mặc định 5 từ mới/10 từ ôn, chỉnh được theo tài khoản. Xem [chi tiết học tập](docs/DICTIONARY_LEARNING.md).

Public/tunnel là luồng riêng: [CONVEYOR_PUBLISHING.md](docs/CONVEYOR_PUBLISHING.md). Không cần public ứng dụng để kiểm thử local.

## Kiểm tra bản build

```powershell
flutter analyze lib --no-pub
flutter build web --release --no-pub --no-web-resources-cdn --dart-define=API_BASE_URL=/api/v1 --dart-define=AI_SERVICE_URL=/sign-ai
cd backend
npm ci
npm run build
npm run docs:validate
npm run docs:coverage
```

Các kết quả kiểm thử trong báo cáo được chạy trên bộ kiểm thử local. Theo phạm vi phát hành lần này, những file test mới/cập nhật, môi trường QA tạm và trang thử camera AI được giữ trên máy phát triển, không đưa vào commit. Bộ test cũ có sẵn trong lịch sử Git chưa được đồng bộ với các thay đổi này. Khi kiểm thử database, dùng database riêng có replica set; không dùng database ứng dụng.

## Index MongoDB khi nâng cấp

Đã bỏ định nghĩa index trùng/xung đột trong schema: text index từ điển, TTL lịch sử/audit và một số index đơn lặp lại. Máy phát triển đã áp dụng sửa index và lần kiểm tra lại trả danh sách rỗng.

Máy khác kiểm tra trước:

```powershell
cd backend
npm run db:indexes
```

Mặc định chỉ **dry-run**. Sau khi xem danh sách, áp dụng:

```powershell
npm run db:indexes -- --apply
```

Script chỉ thay các index xung đột được nhận diện và tạo index theo schema, không xóa tài liệu. Định nghĩa index gốc được sao lưu trong `.runtime/index-backup-*.json`. Không chạy `db:clean` để sửa index.

## Phân quyền và dữ liệu

| Vai trò | Khu vực |
| --- | --- |
| USER/Guest | Giao tiếp, từ điển, hội thoại, yêu thích, hồ sơ và dữ liệu cá nhân. |
| STAFF | Quyền USER và quản lý nội dung theo quyền được cấp; tài khoản thường chỉ sửa bản nháp của mình. |
| ADMIN | Quản lý tài khoản, role/quyền, nội dung, danh mục và phiên. |

Menu quản lý xuất hiện theo quyền. Backend kiểm tra phiên, trạng thái và quyền hiện hành ở database; đăng ký công khai luôn tạo USER. Không cho xóa/khóa/hạ quyền quản trị viên hoạt động cuối cùng, kể cả khi hai yêu cầu chạy đồng thời.

Dữ liệu USER được gắn với ID tài khoản. Phản hồi từ phiên cũ không ghi đè phiên mới; đăng xuất/đổi tài khoản xóa hồ sơ, tùy chọn, hội thoại và lựa chọn cũ ở state. Hội thoại đã lưu tồn tại trên server, không chỉ trong RAM.

## API Documentation

- Swagger UI: **http://localhost:3000/api-docs**
- OpenAPI JSON: **http://localhost:3000/api-docs/openapi.json**
- Khi dùng server cùng origin cổng 3002, đổi cổng tương ứng.
- [Hướng dẫn test API](docs/SWAGGER_TESTING_GUIDE.md), [quản trị](docs/ADMIN_MANAGEMENT.md), [OAuth](docs/OAUTH_SETUP.md).

Route dữ liệu chính dưới `/api/v1`: `/users/profile`, `/users/settings`, `/users/data/export`, `/users/data`, `/users/sessions`, `/users/account`, `/conversations`, `/favorites`, `/dictionary`, `/staff`, `/admin`. Media ký hiệu được mount tại `/sign-media`; chỉ số độ phủ không tính file router chưa mount.

## Cấu trúc code

```text
lib/
  app.dart                       # khởi tạo service/provider, route và guard
  core/app_state.dart            # state USER, đồng bộ API, bảo vệ đổi tài khoản
  features/
    auth/                        # đăng nhập/đăng ký/guest/OAuth
    home/                        # trang chủ, lịch sử gần đây
    recognition/                 # camera AI, tạo câu và TTS
    speech/                      # giọng nói/văn bản/chuỗi ký hiệu
    library/                     # tìm kiếm, danh mục, từ điển, hội thoại
    learning/                    # học theo chủ đề, tiến độ, ôn tập camera
    profile/                     # hồ sơ/cài đặt/dữ liệu/phiên
  screens/admin/                 # workspace và biểu mẫu quản trị chung
  screens/staff/                 # dashboard, nội dung, duyệt, người dùng
  services/                      # API/auth/user/staff/admin/AI/media
backend/
  src/routes/                    # API và kiểm tra quyền
  src/services/                  # giao dịch dữ liệu, nội dung, quản trị
  src/validation/                # hợp đồng đầu vào
  tests/                         # auth, dữ liệu, quyền, public/media/proxy
  scripts/                       # nhập từ điển, kiểm tra API và sửa index
ai_service/                      # suy luận Python cổng 8001
docs/                            # cài đặt, vận hành và đánh giá AI
```

Danh mục màn hình nằm ở **Cá nhân → Thông tin ứng dụng → Danh mục màn hình**. Một số màn hình hệ thống/trang thử chỉ để kiểm tra, không thể hiện toàn bộ nghiệp vụ production.

Đổi mật khẩu tại **Cá nhân → Đổi mật khẩu**. Admin có quyền quản lý tài khoản có thể **Đặt lại mật khẩu** cho tài khoản email khác qua menu Thao tác; xem [hướng dẫn mật khẩu](docs/ACCOUNT_PASSWORDS.md).

### Đồng bộ và dọn source ngày 25/10/2026

Đã đồng bộ nhánh `dev` từ `phuoctue/SignVoice` đến commit `390ca74`, ghép và giữ các thay đổi local. Đã bỏ 8 test của quiz trả lời văn bản/chấm LM Studio vì luồng hiện tại dùng camera; giữ các test quyền truy cập, xóa tài khoản và camera đang dùng. Đồng thời xóa 43 file Dart/TypeScript cũ không còn được ứng dụng, kiểm thử hoặc script import, gồm màn hình/provider/service cũ và proxy thử chưa mount; dọn cache Python và file khóa npm rỗng ở gốc.

Danh sách file đã dọn và bản sao phục hồi nằm trong `.runtime/source-cleanup-*/manifest.json` và `removed-files.zip`. Sao lưu trước đồng bộ nằm trong `.runtime/git-sync-*/`; không nhập các bản ZIP này vào Git. Các tài liệu `BATCH_02_*` và `docs/plan/` là lịch sử triển khai, có thể nhắc tới đường dẫn cũ đã được thay thế bằng `lib/features/`.

Chi tiết phạm vi và kết quả kiểm tra: [báo cáo dọn source](docs/SOURCE_CLEANUP_20261025.md).

### Kiểm tra Flutter mobile ngày 25/10/2026

- Kiến trúc: dùng chung `LearningPageController` cho tải dữ liệu/phân trang của màn hình chủ đề và từ điển học; service/API giữ nguyên. Controller bỏ qua response cũ và request hoàn tất sau khi đóng màn hình.
- Layout/UX: mobile xoay ngang dùng toàn bộ chiều rộng; fallback ảnh nhỏ hỗ trợ chữ lớn và nhãn trợ năng; quiz tải lỗi có nút thử lại; tăng độ tương phản màu primary ở dark mode. Đã kiểm tra 320×640, 375×667, 844×390, chữ 200%, reduced motion và bàn phím.
- Routing: `lib/core/app_route.dart` phân tích thống nhất link khởi động và link trong app, giữ query của bài học, giới hạn route hợp lệ và hiển thị trang phục hồi khi link sai. Giữ Navigator và các guard đăng nhập/quyền hiện tại.
- GoRouter: chưa migration vì có 87 điểm điều hướng hiện hữu. Khi phát triển Web, chuyển lần lượt root sang `MaterialApp.router`, nhóm tab sang `StatefulShellRoute`, rồi thay các lời gọi Navigator; giữ tương thích ID Sxx và kiểm tra lại OAuth/reset password. Browser forward/history và Android App Links/iOS Universal Links chưa được triển khai trong đợt này; cần domain/chứng chỉ thật trước khi cấu hình liên kết đã xác minh.
- Tests: thêm 5 widget tests, 5 controller tests, 4 route tests, 1 test tương phản. Hai luồng integration dùng fake API: đăng nhập → bài học → xem mẫu/tự thực hành → đánh giá → tiến độ; lỗi mạng → thử lại → tạo/mở lại từ cá nhân. Không dùng tài khoản hoặc database thật, không kiểm chứng độ chính xác camera AI.

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter drive --no-pub --driver=test_driver/integration_test.dart --target=integration_test/mobile_learning_test.dart -d emulator-5554
```

`integration_test` là dependency SDK chỉ phục vụ phát triển; driver nằm trong `test_driver/`, binding nằm trong entry integration, không bật driver trong `lib/main.dart`. Nếu Gradle trên Windows báo lỗi loopback/UnixDomainSockets, tạo thư mục tạm ngắn hợp lệ và đặt `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=<đường dẫn thư mục đó>` cho riêng terminal build. iOS cần macOS/Xcode để xác minh trên thiết bị/simulator.

Kết quả đợt này: `flutter analyze` sạch; 195 Flutter tests đạt, 1 test cũ bỏ qua; cả 2 integration flows đạt trên Android 15/API 35 emulator; APK debug build và cài thành công. Log nằm trong `.runtime/mobile-*.log`; bản sao trước sửa nằm ở `.runtime/mobile-audit-before-20261025.zip`.

### Điều chỉnh màn hình giọng nói ngày 25/10/2026

- Hướng dẫn cấp quyền được rút gọn để vừa phía trên các nút trên điện thoại 375×812; nội dung vẫn cuộn được khi dùng chữ lớn/màn hình ngang.
- Chỉnh sửa văn bản ngay trong khung kết quả, có Lưu/Hủy và kiểm tra nội dung trống; bàn phím không bị footer chiếm chỗ.
- TTS thử `vi-VN`, `vi` và giọng Việt mà engine liệt kê. Khi thiết bị thiếu giọng Việt, nút **Cài giọng tiếng Việt** mở trình cài dữ liệu/cài đặt TTS Android; chọn tải Tiếng Việt rồi quay lại bấm Phát. Không tự tải giọng hoặc chuyển văn bản sang dịch vụ ngoài. Máy chưa có engine/giọng phù hợp vẫn cần cài dữ liệu trên thiết bị.
- 8 test mới cho hướng dẫn, sửa trực tiếp và TTS/recovery; toàn bộ 203 tests đạt, 1 test cũ bỏ qua. Log: `.runtime/speech-ui-*.log`.

### Tối ưu APK qua Conveyor ngày 26/10/2026

- Ảnh xem trước JPEG được gửi kèm trong API từ điển/chủ đề (tối đa 20 ảnh, mỗi ảnh 96 KB), giữ nguyên ảnh gốc. APK dùng chung cache media 16 MB trong RAM và tối đa 64 MB trên bộ nhớ đệm riêng, hết hạn sau một ngày. Clip ký hiệu nhỏ được tải bằng một GET, phát từ file và dùng lại khi mở lại; media bên ngoài vẫn dùng player streaming.
- Bấm Đã nhớ/Ôn tập hiển thị trạng thái đang lưu ngay; sau khi API xác nhận thì cập nhật thẻ/số đếm và báo thành công. Đối soát trang chạy nền, không làm trống danh sách và không chặn thông báo lưu thành công. Lỗi ghi không được báo thành công.
- Dừng camera giữ kết quả AI để lưu quiz; các câu có `entryId` khác nhau không dùng lại video mẫu câu trước. Bỏ ảnh mẫu lặp lại ở vị trí camera chưa mở, ghi rõ cách nhận diện/lưu. Có thể chủ động bỏ qua sau khi thử camera nhưng chưa nhận diện; câu đó nhận 0 điểm và giữ ở Ôn tập. Bộ nhận diện vẫn giữ 181 từ.
- Kiểm tra: 36 Flutter tests liên quan, 18 backend tests trên MongoDB tạm đạt. Đo qua Conveyor: từng ảnh/video trước sửa mất khoảng 1,4–2,1 giây/lượt; API mới trả danh sách kèm 6 ảnh trang chủ trong khoảng 2,3 giây, không còn lượt tải riêng cho 6 ảnh này. Đây là số đo trên máy phát triển qua tunnel, chưa phải đo lại trên điện thoại thật. Lần tải mới vẫn phụ thuộc Conveyor/mạng.
- Backend cần chạy bản đã build mới để gửi preview; client tương thích API cũ nhưng ảnh đầu tiên sẽ còn cần request riêng. Log/số đo nằm trong `.runtime/apk-optimization-*.log`, `.runtime/media-before.json` và `.runtime/media-after.json`.

- Bổ sung tối ưu từ điển: cache tối đa 8 trang trong phiên (đọc ngay tối đa 2 phút, làm mới nền sau 10 giây), gộp request trùng, xóa cache khi đổi tài khoản hoặc ghi tiến độ thành công. Tải trước danh mục từ trang chủ, tab học, trang kế tiếp và clip đầu tiên; danh sách dựng các thẻ gần vùng đang xem. Tiếp tục chủ đề đã tham gia không gọi đăng ký học lại.
- API nén gzip cho các lượt đọc từ điển/chủ đề hỗ trợ nén, giữ nguyên `no-store` cho dữ liệu riêng. Trang chủ đề đo được giảm từ 213.937 xuống 118.862 byte truyền. Kiểm thử trực tiếp bằng service Flutter qua Conveyor: danh mục/chủ đề tải mới 2.973/2.088 ms, đọc lại cache 1/0 ms; 4 lần đọc chỉ gọi 2 GET. Đây là số đo truy xuất dữ liệu trên máy phát triển, chưa phải thời gian dựng giao diện trên điện thoại; tải mới vẫn phụ thuộc mạng/tunnel.
- Bản bổ sung: 90 kiểm thử Flutter (gồm 1 lượt kiểm tra trực tiếp qua Conveyor) và 23 backend tests đạt; analyze không có vấn đề, build thành công. APK `E:\WorkSpace\SignVoice\SignVoice-Conveyor-dictionary-v2-20261026.apk` đã kiểm tra chữ ký giống bản trước và zipalign 16 KB. Log: `.runtime/dictionary-*.log`, `.runtime/dictionary-cache-live.json`, `.runtime/dictionary-perf-after.json`.

### Video, lịch nhắc và hồ sơ trên Android — 26/10/2026

- Văn bản → Ký hiệu tải trước tối đa hai clip gần vị trí xem, chỉ một lượt tải trước chạy cùng lúc. Chuyển nhanh bỏ hàng đợi cũ, giải phóng video trả về muộn; ảnh xem trước dùng chung cache và giữ trong lúc video đang tải.
- Giữ lịch Android không thay đổi khi mở lại ứng dụng, tránh hủy lời nhắc đang chờ rồi chuyển sang tuần sau. Đặt lịch trên máy độc lập với đăng ký push; kiểm tra lại các lịch đã cài. Màn hình lịch hiển thị lần nhắc tiếp theo, quyền nhắc đúng giờ, kênh bị tắt và nút thử nhắc sau một phút.
- Đọc lại giọng Việt và kết nối lại bộ đọc khi trở về từ cài đặt; tìm bộ đọc tiếng Việt trong các bộ đã cài trước khi báo không dùng được. Không tự phát tiếng sau khi quay về cài đặt.
- Avatar hiện ngay từ thông tin đăng nhập, cache riêng theo tài khoản tối đa 512 KB và xóa khi đăng xuất. Dùng hồ sơ đã đồng bộ khi mở trình sửa; đổi ảnh không gọi lưu màu không đổi hoặc lấy lại hồ sơ lần nữa.
- Kiểm tra: 278 Flutter tests đạt, 1 bỏ qua; analyze không có vấn đề. Log: `.runtime/mobile-reliability-*.log`. Chưa đo trực tiếp trên điện thoại thật; lịch nhắc vẫn cần quyền và cài đặt hoạt động nền phù hợp trên máy.
- APK đã build và kiểm tra chữ ký/zipalign 16 KB: `E:\WorkSpace\SignVoice\SignVoice-Conveyor-mobile-fixes-20261026.apk` (57,4 MB), dùng cùng chữ ký với bản trước và URL Conveyor hiện tại. SHA-256: `B651015019D6AD29F53CCA0C31B7504BC06957559B45CD956DC1AD49C187441F`.

### Rà soát trước bản APK tiếp theo — 26/10/2026

- Sửa thêm cache avatar: lượt tải ảnh cũ hoàn thành muộn không được ghi đè ảnh vừa đổi hoặc khôi phục cache sau khi xóa ảnh.
- Đạt 280 Flutter tests (1 bỏ qua), toàn bộ 205 backend tests trên MongoDB tạm và 5 Android JVM tests; phân tích mã Flutter/backend đạt. Log: `.runtime/preflight-*.log`.
- 4 kiểm thử tích hợp trên Android giả lập API 35 đạt: video phát từ file cache, avatar lưu/đọc qua plugin thật, Android phát lời nhắc hẹn một phút khi ứng dụng chạy nền, kiểm tra lại giọng Việt. Kết quả này chưa thay thế việc thử trên điện thoại thật. Chi tiết: `.runtime/preflight-android-results.json`.
- Kiểm tra release phát hiện APK ARM64 còn chứa thư viện MediaPipe của ABI khác, khiến Android x86 nhận cài nhưng thiếu Flutter engine phù hợp. Gradle hiện lọc ABI theo `target-platform`; script build chạy `scripts/verify-android-apk.ps1` để chặn ABI ngoài mục tiêu hoặc thiếu `libapp.so`/`libflutter.so`. Bản universal dùng đủ ARMv7, ARM64 và x86_64. Tham khảo [quy tắc ABI của Android](https://developer.android.com/ndk/guides/abis).
- Bản universal kiểm tra nhiều CPU, dùng phiên Conveyor trước: `E:\WorkSpace\SignVoice\SignVoice-Conveyor-preflight-20261026.apk` (95,9 MB), đã cài và mở bản release trên giả lập, kiểm tra chữ ký giống bản trước, zipalign 16 KB và URL Conveyor ở cả ba ABI. SHA-256: `652F675E7CA388E50E29C58D9E6E753D5D57D3457E892ADB95D221AF1201997D`. Ảnh mở ứng dụng: `.runtime/preflight-release-screen.png`.
- Conveyor đã hết giới hạn kết nối liên tục ở phiên cũ; kết nối lại được cấp `https://earlysparklyglass16.conveyor.cloud`. Wrapper hiện đánh dấu phiên hết hạn và dùng mã phiên để tránh tiến trình cũ ghi đè trạng thái khởi động mới. Backend/API và AI ở link mới đã trả HTTP 200. Conveyor vẫn là môi trường chạy thử có giới hạn phiên.
- APK dùng cho điện thoại ARM64: `E:\WorkSpace\SignVoice\SignVoice-Conveyor-ARM64-verified-20261026.apk` **38,0 MB**, chỉ đóng gói ARM64 và đã xác minh API/AI trỏ tới link Conveyor mới, chữ ký giữ nguyên, zipalign 16 KB đạt. SHA-256: `7E4227A05F3FF97B57CBDD8D6115537B28360C153EEFFA787C4B8B9D6A8934C9`. Bản universal lớn hơn được dùng để mở thử release trên giả lập x86_64; bản ARM64 cần kiểm tra tiếp trên điện thoại thật.
