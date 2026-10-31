# Bộ sưu tập ký hiệu — phân tích và thiết kế

## Mục tiêu và phạm vi

Thay tab “Từ của tôi” bằng “Bộ sưu tập”: chọn từ đã xuất bản, gom theo tình huống,
ghi chú riêng, ôn bằng video → nhập nghĩa, chia sẻ bằng mã/link và lưu bản sao.
Từ tự tạo nằm trong từng bộ; từ cũ chưa xếp bộ có thể chọn lại từ “Thêm từ riêng đã có”. Không chuyển từ riêng thành ký hiệu chuẩn.
Không thay đổi mô hình nhận diện camera 181 từ, không build APK trong đợt này.

Tham khảo sản phẩm: [SignSchool](https://www.signschool.com/tools/dictionary/)
về thư viện cá nhân, [Quizlet](https://quizlet.com/en/features/flashcards) về bộ học,
[Anki](https://docs.ankiweb.net/getting-started.html#shared-decks) về nhận bộ được chia sẻ.
Đây là tham khảo luồng sử dụng; không nhập video/đáp án của ngôn ngữ ký hiệu khác.

## Quyết định UI/UX

- Giữ theme sáng/tối, font và icon Material của SignVoice. Kết quả design-system
  của ui-ux-pro-max thiên về trang giới thiệu, không áp dụng cấu trúc hero/marketing.
  Dùng quy tắc native trong skill và kết quả Flutter về danh sách lazy, trạng thái async.
- Ba tab: Khám phá / Đang học / Bộ sưu tập. Không thêm tab ở thanh điều hướng dưới.
- Trang bộ sưu tập: tiêu đề ngắn, tìm kiếm, Tạo bộ, Khám phá bộ công khai và
  Tôi có mã hoặc liên kết. Bỏ trang Thẻ riêng khỏi điều hướng bên ngoài.
- Thẻ bộ: tên, số từ khả dụng, số cần ôn, ảnh đại diện nhỏ; chạm mở chi tiết.
- Chi tiết: mô tả, thống kê gọn, “Ôn bộ này”, “Thêm từ”; sửa/chia sẻ/xóa ở menu.
- Thêm từ: tìm từ điển có sẵn, chọn nhiều từ trên các trang, lưu một lần. Nút thêm
  cũng có ở chi tiết từ điển. Từ đã thêm không bị nhân đôi.
- Ghi chú dùng chung theo tài khoản + từ, không gắn riêng với từng bản sao trong bộ.
- Trang chia sẻ là bản xem trước; phải đăng nhập để lưu một bản riêng. Ghi rõ ghi chú
  và tiến độ không được chia sẻ. Cho tắt mã đã phát hành.
- Vùng bấm Android ≥48dp; nhãn trường luôn thấy; giảm chuyển động theo hệ thống;
  dialog cuộn khi mở bàn phím/chữ lớn; kiểm tra 320px, 375px, ngang và tablet.
- Giữ dữ liệu hiện có khi refresh, tải theo trang, chặn bấm lặp, thông báo lỗi gần
  thao tác; cập nhật từ phản hồi ghi thành công thay vì tự gọi lại nhiều màn hình.

## Dữ liệu và giới hạn

`SignCollection`: userId, name, description, avatarImage, entryIds (ObjectId tham chiếu từ điển),
shareToken tùy chọn, timestamps. Tối đa 100 bộ/tài khoản và 200 từ/bộ.
Không sao chép ảnh/video hay định nghĩa của từ điển vào bộ. Ảnh đại diện bộ là ảnh người dùng chọn riêng.

### Ảnh đại diện và từ riêng trong bộ — bổ sung 28/10/2026

- Tạo/sửa bộ có xem trước ảnh, chọn/đổi/bỏ ảnh. Client thu nhỏ 128×128, giới hạn 72 KiB; backend kiểm tra định dạng JPEG/PNG/WebP, base64 và dung lượng. Không gửi trường ảnh khi PATCH thì giữ nguyên; chuỗi rỗng để bỏ ảnh. Ảnh đi kèm metadata nhỏ, không thêm một lượt gọi mạng khi hiện thẻ bộ; ảnh bộ được chia sẻ theo lựa chọn của chủ bộ và sao chép khi nhận bộ.
- Nút tạo bộ, khám phá, nhận mã và các nút trong hộp nhận/chia sẻ dùng một kiểu bo góc 12 dp, cao tối thiểu 48 dp, cách nhau 12 dp. Một tác vụ chính có nền, các tác vụ phụ dùng viền; thu hồi mã có màu cảnh báo. Vùng phản hồi bấm nằm gọn trong nút; thẻ bộ chỉ có một vùng bấm hoạt động, tránh nền hover lồng nhau.
- Chi tiết bộ → **Thêm từ**: chọn thư viện, tạo từ riêng, hoặc thêm từ riêng đã có. Không thêm điều hướng dưới. Route cũ `/learn/personal` mở Bộ sưu tập. Giữ API cũ để tương thích bản cài trước.
- `PersonalWord.collectionId` là tham chiếu tùy chọn, index `(userId, collectionId, word, _id)`. Từ tạo trước đây không bị tự đổi chủ, xóa hay sao chép; danh sách chưa xếp bộ cho chọn nhiều từ rồi gắn vào bộ trong một transaction. Gọi lại không tạo trùng. Xóa bộ bỏ tham chiếu này nhưng giữ từ/ảnh; xóa một từ riêng cần xác nhận rõ là xóa vĩnh viễn.
- Từ riêng chỉ thuộc tài khoản, không vào khám phá, link xem trước, bản nhập hoặc quiz thư viện. UI phân biệt “Từ riêng · chỉ bạn thấy”; có ảnh/video, ý nghĩa, ví dụ và mẹo riêng để tự luyện. Bộ chỉ có từ riêng được giải thích cần thêm từ thư viện để chia sẻ/ôn quiz. Tổng thư viện + từ riêng tối đa 200 từ/bộ, kiểm tra nguyên tử với khóa dữ liệu tài khoản.
- Danh sách bộ đếm từ riêng theo lô cho trang hiện tại. Nội dung bộ hợp nhất hai nguồn trước khi tìm/sắp xếp/phân trang, chỉ trả 10 từ; thống kê toàn bộ không thay đổi theo ô tìm. Ảnh riêng lớn hơn 100000 ký tự được đánh dấu `imageDeferred`; API riêng kiểm tra chủ bộ + chủ từ trước khi trả ảnh để xem/sửa. Client giữ tối đa 5 ảnh đầy đủ, có nút tải lại nếu lỗi. Không ghi ảnh đầy đủ vào cache các trang danh sách.
- Form chặn bấm lặp lúc lưu/chọn ảnh, giữ nội dung khi API lỗi, xác nhận khi bỏ thay đổi; không tự đóng bằng kéo sheet hoặc chạm nền. Mẫu ký hiệu có `PageStorageKey` riêng, tách trạng thái mở khỏi vị trí cuộn để tránh lỗi ép `double` thành `bool` khi thêm từ vào danh sách đã cuộn.
- API xuất dữ liệu tài khoản bao gồm các từ riêng. Dữ liệu canonical tiếp tục lấy theo ID gốc, nên thay media ZIP vẫn cập nhật xuyên suốt; ảnh riêng và avatar người dùng không bị tác động bởi việc đồng bộ từ điển.

`SignNote`: userId + entryId unique, text ≤2000 ký tự. Không trả ở API chia sẻ.

ReviewQuiz dùng thêm collectionId; câu hỏi giữ categoryId thực của từ. Tiến độ vẫn
là WordProgress(userId, entryId) duy nhất, không tạo một tiến độ mới cho mỗi bộ.
Quiz chụp tối đa 10 từ khả dụng, ưu tiên chưa nhớ/đến hạn, giữ bài dở để tiếp tục.
Khi nộp chỉ áp dụng từ còn công khai, danh mục còn hoạt động và còn trong bộ;
thay đổi tiến độ mới hơn ở màn hình khác không bị ghi đè.

## Truy vấn và index

### Kết nối và khám phá công khai (bổ sung 28/10)

- “Nhận bộ sưu tập” là hộp nhập cuộn toàn bộ, không tự đọc clipboard hay tự bật
  bàn phím. Người dùng chủ động Dán từ bộ nhớ; lỗi dán/định dạng có giải thích
  và dữ liệu đang nhập được giữ. Không có mã thì mở Khám phá bộ công khai ngay.
- Chủ bộ bật chia sẻ để dùng trình chia sẻ hệ thống hoặc hiện QR của liên kết
  xem trước. Người gửi tự chọn ứng dụng/người nhận; app không tự gửi tin nhắn.
  QR đen trên nền trắng, được dựng cục bộ. Người nhận dùng camera điện thoại
  quét; không thêm bộ quét camera vào luồng AI 181 từ.
- Native share dùng [share_plus 12.0.2](https://pub.dev/packages/share_plus/versions/12.0.2),
  QR dùng [qr_flutter](https://pub.dev/packages/qr_flutter). Bản share_plus mới hơn
  xung đột win32 với secure storage hiện có, nên giữ phiên bản tương thích và
  lockfile; không nâng cấp/thay thế phần lưu khóa. Không tự mở email khi Web Share
  không hỗ trợ; giữ nút sao chép để người dùng dán vào ứng dụng nhắn tin.
- `discoverable` mặc định false, `publishedAt` null. Chia sẻ link không đồng nghĩa
  đăng công khai. “Hiện trong khám phá công khai” cần tài khoản chính thức, từ
  khả dụng và xác nhận trước khi đăng. Tắt mục này gỡ khỏi danh sách nhưng giữ
  link; tắt mã chia sẻ gỡ danh sách và thu hồi link/QR. Bộ nhận từ người khác luôn
  riêng tư mặc định, không sao chép quyền chia sẻ/công khai.
- GET `/api/v1/shared-collections` không cần đăng nhập, tìm theo tên, 10 bộ/trang.
  Index `(discoverable, publishedAt desc, _id)`; lọc chủ bộ đang hoạt động, không
  trả tên tài khoản/email/ghi chú/tiến độ. Media và số từ khả dụng được lấy theo
  lô cho tối đa 10×200 tham chiếu; bộ có từ vừa bị gỡ có thể tạm hiện 0 từ.
- POST `/api/v1/sign-collections/:id/discovery` kiểm tra sở hữu, tài khoản chính
  thức, dữ liệu nghiêm ngặt và giới hạn tần suất. Gỡ từ cuối tự gỡ khám phá;
  không cho lưu bản sao rỗng. Không tự công khai bất cứ bộ có sẵn nào.
- Khám phá bộ theo nội dung là cách kết nối hiện tại; chưa có bạn bè, chat riêng,
  hồ sơ công khai hoặc bộ sưu tập mẫu được giả làm dữ liệu người thật.

- Index collection: (userId, updatedAt desc, _id), shareToken unique sparse.
- Index note: (userId, entryId) unique. WordProgress đã có index cùng khóa.
- Trang danh sách/chọn từ/chi tiết tối đa 10 mục; truy vấn collection theo owner
  trước; `$facet` lấy trang + tổng; batch lookup từ/progress, tránh query từng thẻ.
- Nội dung bộ tối đa 200 id để tránh document/phép lookup tăng không giới hạn.
- Snapshot xem trước JPEG có cache và giới hạn; video dùng URL/media cache hiện có.
- Cache đọc trên client theo phiên tài khoản, TTL ngắn và giới hạn số trang; gộp
  request trùng; bỏ phản hồi cũ khi tìm kiếm/đổi tài khoản. Ghi làm mất hiệu lực cache.
- Quiz theo chủ đề và bộ có hai index draft riêng. Trước khi mở dịch vụ, thay index
  legacy chỉ sau khi index mới đã tạo được; lưu định nghĩa index cũ vào .runtime.
  Không xóa document và không cần di chuyển thẻ riêng cũ.
- Nộp quiz đọc theo lô và ghi bulk trong transaction; sự kiện chỉ được ghi một lần.

## Phân quyền và tính nhất quán

- Mọi thao tác sửa/xóa/ghi chú đều theo userId từ phiên, không nhận owner từ client.
- Ghi dùng userTransaction hiện có để phối hợp với xóa tài khoản và reset dữ liệu.
- Xóa tài khoản/reset xóa collection và note; xóa bộ không xóa từ điển hoặc tiến độ.
- ShareToken ngẫu nhiên 128 bit, tắt được; endpoint có rate limit. DTO chia sẻ chỉ
  gồm tên/mô tả và từ công khai, không owner/email, ghi chú, tiến độ hoặc thẻ riêng.
- Nhập mã tạo bản độc lập và idempotent theo người nhận + bộ nguồn; lọc lại nội dung
  đã gỡ, không tự theo dõi những chỉnh sửa về sau của người chia sẻ.
- Không tự tạo ký hiệu bằng AI và không dùng tự xác nhận để tăng điểm quiz.

## Kiểm chứng

Kiểm thử quyền sở hữu, input, giới hạn, trùng từ/nhập lặp, thu hồi chia sẻ, xóa dữ
liệu cá nhân, từ ẩn/danh mục ẩn, quiz đa danh mục, tiến độ dùng chung, nộp lặp và
ghi đồng thời. Dùng database tạm cho kiểm thử ghi. Kiểm tra explain trên truy vấn
theo owner và query count không tăng theo số thẻ; số đo chỉ là kết quả đo, không
hứa độ trễ tuyệt đối qua Conveyor. Widget test sáng/tối, chữ lớn, bàn phím, lỗi
mạng, cache đổi tài khoản và vùng bấm; xem ảnh render thực tế trước bàn giao.

## Đồng bộ khi thay gói ZIP media

Nguồn chuẩn là DictionaryEntry, bộ sưu tập chỉ lưu entryId. Từ điển, chủ đề học,
quiz, bộ nhận từ chia sẻ và Văn bản → Ký hiệu đọc lại cùng nguồn chuẩn. Không
đóng gói bản sao video trong từng bộ hay trong APK.

Quy trình vận hành là `scripts/sync-sign-library.ps1 -ZipPath ...`: mặc định chỉ
giải nén vào staging và xác minh manifest/checksum; thêm `-Apply` mới cài media
và nhập danh mục trong transaction. Thay file ZIP trên đĩa **chưa** thay database;
phải chạy đồng bộ. Không tự chạy script được nhúng trong ZIP. Chỉ nhận gói media
đã xử lý, không nhận ZIP dataset huấn luyện thô.

- Media thay đổi có URL hash mới; giữ media cũ để không phá các tham chiếu đang
  đọc. Metadata của mỗi phiên bản đặt trong thư mục riêng, không ghi đè gói cũ.
- Giữ ID theo khóa từ chuẩn `svlib:`. Đổi video/ảnh của cùng từ không làm mất
  ghi chú, tiến độ, bộ sưu tập hay ID yêu thích. Đổi tên khóa từ được xem là mục
  khác; không tự suy đoán rằng hai nhãn khác nhau là cùng ký hiệu.
- Mặc định chỉ thêm/cập nhật nội dung được importer quản lý. `-SyncRemoved` dành
  cho gói đầy đủ: ẩn mục nguồn vắng mặt, đánh dấu để khôi phục đúng ID khi trở lại;
  không xóa document và không ẩn mục chỉnh tay. Không tự ghi đè chỉnh sửa thủ công.
- Chuyển danh mục cập nhật categoryId của tiến độ hiện tại và đăng ký chủ đề mới;
  không viết lại lịch sử học hoặc điểm quiz đã nộp.
- Bài ôn dở chứa từ thay đổi hết hiệu lực (`libraryChanged`), có nút bắt đầu lượt
  mới; bài đã hoàn thành giữ điểm nhưng hiển thị media công khai hiện tại.
- LibraryRevision đổi cùng transaction nhập. Endpoint `/api/v1/library/version`
  có cache ngắn 5 giây; ứng dụng kiểm tra khi mở/quay lại và mỗi 60 giây lúc đang
  hoạt động. Cache đọc theo tài khoản/phiên bản bị bỏ, phản hồi cũ bị loại. Không
  đăng xuất người dùng. Các màn hình từ điển tải lại; Văn bản → Ký hiệu giữ văn
  bản và tải lại chuỗi đang xem. Không cần build APK chỉ để đổi dữ liệu media.
  Cửa sổ video đang mở dừng bản cũ và yêu cầu mở lại mẫu mới, tránh phát tiếp
  dữ liệu cũ trong khi danh sách phía sau đã cập nhật.
- Mã chia sẻ xem bộ nguồn hiện tại; bộ đã nhập giữ danh sách riêng, nhưng media
  từng từ vẫn theo từ điển chuẩn. Ghi chú và tiến độ riêng không công khai.

Kiểm thử nhập lặp, đổi hash video, từ bị gỡ/khôi phục, draft hết hiệu lực, media
trong bài đã nộp và giữ nguyên điểm/ghi chú/tiến độ. Thử ghi chỉ trên MongoDB tạm;
không dùng gói đang chia sẻ để thay dữ liệu thật trong quá trình kiểm thử.
