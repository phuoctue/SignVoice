# SignVoice

## Kết nối landing page — 30/10/2026

- Bộ chọn chung trong quản trị (vai trò, trạng thái, danh mục và các bộ lọc dùng `AdminSelectField`) mở sát ô chọn bằng menu, không dùng hộp thoại giữa màn hình; danh sách dài vẫn tìm kiếm và cuộn được. Menu tài khoản chân sidebar vừa chiều rộng thanh, bỏ phần avatar/tên/email lặp lại; còn Hồ sơ và Đăng xuất.
- Route `/home` là landing page; `/login` và `/register` là xác thực; Tổng quan sau đăng nhập dùng `/dashboard`. Đường `/welcome` cũ chuyển về `/home`; các nút trong workspace vẫn về Tổng quan. Web hiện dùng URL dạng `/#/home`, `/#/login`, `/#/dashboard`.
- Hero ưu tiên mẫu lời chào công khai, có video lặp tắt tiếng, nút dừng và phần lời nói đầu ra; chỉ đọc thành tiếng khi bấm nghe. Chế độ văn bản có ô nhập và tìm mẫu thật. Không thay bằng từ ngẫu nhiên khi thiếu mẫu lời chào, không mở camera/microphone hay đưa tỷ lệ AI giả. Thẻ tính năng dùng ảnh chụp giao diện sản phẩm tại `assets/landing`, có ghi rõ dữ liệu minh họa; hai hàng canh đều đáy, từng công cụ mở đúng đích sau bước dùng thử.
- Tải riêng số ký hiệu, chủ đề và bộ sưu tập từ API công khai; nguồn nào lỗi hiện dấu — thay vì giả định bằng 0. Ô tra cứu gọi từ điển thật, ưu tiên kết quả trùng cụm từ trong trang trả về; chọn thẻ để xem ảnh/video và nguồn tư liệu. Video xem trước khi hover hoặc bấm phát dùng chung một chủ phát; giải phóng video cũ, tắt tiếng và dừng khi cuộn ra ngoài, chuyển nền hoặc bật giảm chuyển động. Nút điều khiển và yêu thích nằm ngoài ảnh để giữ trọn tư liệu.
- Nền hero trôi chậm theo vòng lặp và dừng khi ra khỏi màn hình; số liệu chỉ đếm khi vào vùng nhìn, có dấu phân cách nghìn tiếng Việt. Reveal loại focus/ngữ nghĩa khỏi nội dung chưa hiện; tiêu đề tăng chiều cao dòng cho dấu Việt. Header đổi bóng có chuyển tiếp, logo cuộn lên đầu, menu nhỏ có đủ tính năng/các bước/từ điển/FAQ; biểu tượng giảm chuyển động có trạng thái riêng. Tìm kiếm landing debounce 350 ms, có từ gợi ý bấm nhanh, khung xương và giữ chiều cao lưới khi tải.
- Người chưa đăng nhập có thể tra cứu và xem chi tiết công khai; thao tác lưu riêng vẫn cần tài khoản. Dùng thử chỉ tạo phiên Khách sau khi xác nhận 10 phút. Kiểm thử có các cỡ 1440/768/375 px, chữ 200%, giảm chuyển động, lỗi API và phục hồi tìm kiếm; Chrome kiểm tra thêm dữ liệu thật và điều hướng công khai. Cần dựng lại Web khi thay mã nguồn để máy chủ nhận trang mới.
- Từ điển công khai có header Đăng nhập/Đăng ký, bộ lọc chung một hàng trên desktop, thẻ 4 cột với ảnh 16:10 và cache/placeholder `SignPhoto`, số kết quả, tìm có nút xóa/phím `/`, chủ đề nhanh và nhảy trang. Mặc định mới xuất bản; A–Z/Z–A vẫn dùng thứ tự số tự nhiên trên backend. Lưu yêu thích khi chưa đăng nhập có giải thích trước. `/dictionary` giữ trung tâm học cho tài khoản đã đăng nhập và lưới công khai cho người chưa đăng nhập; `/dictionary/browse` mở lưới tra cứu rõ ràng cho cả hai, có nút từ trung tâm học.
- Đợt sửa tiếp: 52 bài Flutter đạt; Dart analysis sạch. Chrome với API thật đã kiểm tra video tắt tiếng/chỉ một chủ phát, nhập văn bản xem mẫu, giảm chuyển động, menu tablet, yêu thích có giải thích, nhảy trang 42, desktop/tablet/điện thoại và sáng/tối, không còn lỗi runtime. Đã sửa lỗi cuộn release khi bấm logo dưới chế độ giảm chuyển động (`jumpTo` thay cho `animateTo` với thời lượng 0) và không dùng lời chào thay thế kết quả tra cứu không khớp. Chrome dùng API fixture xác nhận `/dictionary` của tài khoản là trung tâm học và mở được `/dictionary/browse`. Bản release đã khởi động lại local, readiness/API/AI đều HTTP 200, JavaScript phục vụ khớp build. Log/ảnh ở `.runtime/public-polish-*`; ảnh tính năng lấy từ ứng dụng với API fixture, không ghi dữ liệu thử vào database.

## Giao diện chi tiết và tùy chọn Khách — 30/10/2026

- Chuông mở bảng thông báo neo ngay dưới nút, không làm tối toàn trang. Sidebar mở/thu bằng nút bấm, lưu lựa chọn và dành chỗ trong bố cục; bỏ hover/ghim, thêm avatar và họ tên với menu Hồ sơ/Đăng xuất ở chân thanh.
- Khách không có Hồ sơ/Lịch học; menu có Giọng nói và Giao diện & Trợ năng. Các lựa chọn này được giữ trên thiết bị, khôi phục qua tải lại và chuyển một lần vào tài khoản sau đăng nhập. Chỉ chuyển các tùy chọn hiển thị/giọng nói; không chuyển hồ sơ hay lịch sử giữa các tài khoản. Nếu đồng bộ lỗi, tài khoản vẫn mở được và lựa chọn được giữ để thử lại.
- Thu gọn chiều rộng các form và trang cài đặt; gom thao tác chi tiết hội thoại/văn bản; chủ đề học có lưới thích ứng, bộ sưu tập trống có nút thêm từ rõ ràng. Quiz dùng header chung, media được giới hạn rộng; chuỗi ảnh có nút trước/tiếp cho chuột và bàn phím. Cài đặt camera trên desktop là hộp thoại có phần nâng cao thu gọn. Hộp xác nhận dùng thử giới hạn rộng 520 px.
- Kiểm tra: các bộ kiểm thử Flutter cho cài đặt Khách, thông báo, điều hướng, học/ôn tập, hội thoại, bộ sưu tập, hồ sơ và chữ lớn đạt; Dart analysis sạch. Đã dựng Web release tại http://localhost:3002.

## Lịch học, hộp thông báo và giới hạn Khách — 30/10/2026

- Kiểm tra: Dart analysis sạch; kiểm thử Flutter cho hộp chuông, đổi tài khoản, lịch học, Khách và bố cục đạt. **32 kiểm thử backend** đạt với MongoDB cô lập; Chrome xác nhận sidebar, hộp chuông/lịch học, form quản trị và Khách hết hạn. Web release đã dựng lại tại **http://localhost:3002**.
- Chuông trên mọi trang Web mở hộp thông báo ngay tại trang hiện tại, có số chưa đọc. Menu tài khoản chỉ giữ **Lịch học**, tách khỏi thông báo. Nhắc học được lưu theo tài khoản/múi giờ/ngày trong tuần; khi tới giờ, chuông cập nhật trong tối đa khoảng 30 giây khi Web đang mở, hoặc đồng bộ khi quay lại tab. Web đóng hoàn toàn không có thông báo nền; Android tiếp tục dùng lịch nhắc cục bộ. Mỗi lần nhắc chỉ tạo một bản ghi và không làm mất trạng thái đã đọc.
- Sửa footer làm trang Lịch học trống; nút làm mới chuyển xuống thân trang, xóa tất cả hội thoại nằm dưới bảng. Sidebar mở rộng bằng cách dành chỗ trong bố cục, tránh đè nội dung. Hội thoại gần đây có thẻ cân đối; form tạo tài khoản/danh mục có hai cột trên desktop và hành động ngay dưới form.
- Trước khi vào Khách có hộp giải thích và xác nhận. Phiên 10 phút bắt đầu ngay khi vào, không có nút bắt đầu riêng trên trang công cụ. Thời hạn do backend quản lý và giữ qua tải lại/đổi trang/đăng xuất rồi vào Khách trên cùng định danh thiết bị. Hết giờ chặn công cụ, đang học, quiz và tiến độ; chỉ cho đọc từ điển công khai. Lưu hội thoại, yêu thích, bộ sưu tập và từ riêng cần tài khoản cá nhân. Camera/micro dừng khi hết giờ.

## Header tài khoản và sidebar tự thu gọn — 30/10/2026

- Áp dụng `ui-ux-pro-max`: Web có sidebar mặc định 80 px, mở khi hover hoặc dùng bàn phím và có nút ghim cho thao tác cảm ứng. Phần mở dành chỗ trong bố cục để không che nội dung/form; tôn trọng giảm chuyển động. Bỏ mục Cá nhân và menu tài khoản ở chân sidebar; chi tiết hội thoại vẫn sáng đúng mục Hội thoại.
- Avatar ở header các trang Web đã đăng nhập dùng chung `UserAvatar`, dữ liệu hồ sơ và cache theo tài khoản. Menu có tên/email, Hồ sơ, Lịch học & thông báo, Thông báo, Giao diện & Trợ năng và Đăng xuất có xác nhận. Breadcrumb thêm cấp Giao tiếp, Hội thoại, Hồ sơ hoặc Quản trị theo trang con.
- Xóa toàn bộ hội thoại chuyển vào menu thao tác, khóa khi còn bộ lọc/tìm kiếm hoặc đang tải; hộp thoại nêu đúng tổng số hội thoại của mọi trang và nhãn xác nhận rõ. Bảng có hover dòng, cột nội dung thích ứng chiều rộng và thanh Hiển thị/Trang duy nhất ở dưới.
- Dashboard đưa tải/lỗi lên dưới lời chào, có skeleton mục tiêu/hoạt động, giữ hai số liệu Tổng đã nhớ/Cần ôn; nhãn trên lời chào là ngày. Biểu đồ chỉ hiện scrollbar khi tràn. Ảnh từ nổi bật giới hạn rộng 160 px. Trang Giao tiếp có nút Bắt đầu rõ; cấp quyền Web giảm viền lồng và dùng Để sau dạng văn bản.
- Đang học có tiêu đề Chủ đề đang học, hai nút phân tích/gợi ý nằm gọn theo hàng; bỏ liên kết Lịch sử học tập và Thống kê & mục tiêu trùng thanh điều hướng trên desktop. Tab Web cửa sổ hẹp cũng tạo lịch sử trình duyệt; Mobile giữ hành vi cũ, không hiện tab không tồn tại ở Tiến độ/Lịch sử.
- Form quản trị tài khoản/danh mục tối đa 800 px, từ điển/role 1040 px; nút lưu desktop giới hạn 300 px và thẳng hàng mép phải biểu mẫu. Footer được kiểm tra để không chiếm mất nội dung trên Mobile. Giữ API, database và thiết kế/animation đăng nhập, đăng ký.
- Đo token màu chữ trên các nền dùng trong workspace, cả sáng/tối: chữ phụ sáng từng đạt khoảng 3,70:1 trên nền xám; đổi `onSurfaceVariant` sáng sang `#475569` để đạt kiểm tra 4,5:1. Đây là kiểm tra các cặp token, không phải chứng nhận tương phản toàn bộ ảnh/video hoặc mọi trang ứng dụng.
- Kiểm tra đã đạt: 16 bài điều hướng/dashboard/quiz; 14 bài an toàn, avatar, skeleton, cấp quyền và tương phản. Các nhóm quản trị, hồ sơ/thông báo và tiến độ đã qua; các bài mới cũng kiểm tra menu chữ 2×, sidebar không làm đổi chiều rộng trang và xác nhận xóa tổng 42 mục khi trang chỉ có 2 dòng. Phân tích Dart sạch.
- Web release build thành công, đã chạy lại `http://localhost:3002/#/home`; Web, readiness/database, AI và library version đều HTTP 200, JavaScript phục vụ khớp release. Chrome thật dùng API fixture đã qua hover sidebar, menu tài khoản → Hồ sơ, form thêm tài khoản/từ điển/role, chuyển tab và Back/Forward, cấp quyền, bảng hội thoại yêu thích/xóa, quiz và cảnh báo thoát; không có lỗi runtime trong các luồng đó. Không ghi dữ liệu fixture vào database thật; chưa coi đây là kiểm thử tải production. Ảnh tại `.runtime/browser-{account-menu,sidebar-hover,admin-user-form,admin-dictionary-form,admin-role-form,studying}.png`.

## Chạy lại bản Web local — 30/10/2026

- Khởi động bản release đã có bằng `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-signvoice.ps1 Local -SkipBuild`, tại `http://localhost:3002/#/home`.
- Sửa lỗi script dừng khi Windows CIM không trả cổng AI dù health check thành công: theo dõi tiến trình Python thuộc wrapper vừa khởi động, kể cả interpreter con của môi trường venv. Đã kiểm tra cú pháp PowerShell và khởi động thực tế thành công.
- Web, backend/database readiness, AI health và library version đều HTTP 200; JavaScript phục vụ khớp bản release. AI tiếp tục dùng mô hình 181 từ.

## Tinh gọn Web và sửa luồng Thư viện ký hiệu — 29/10/2026

Đợt này áp dụng `ui-ux-pro-max`. Các quyết định bố cục dưới đây thay thế mô tả sidebar nhiều nhóm và nội dung căn trái ở các ghi chép trước.

- Sidebar còn **Tổng quan, Giao tiếp, Thư viện ký hiệu, Hội thoại, Cá nhân**, thêm Quản trị theo quyền. Hai công cụ camera/micro nằm trong Giao tiếp; Khám phá, Đang học, Bộ sưu tập, Tiến độ và Lịch sử học tập nằm trong thanh điều hướng của Thư viện. Giữ shell, trạng thái thu gọn, tooltip/focus và thanh cuộn; bỏ nhãn nhóm lặp.
- Sửa lỗi thật: `LearningHub` chỉ đọc tab khi khởi tạo nên đổi query trên cùng route không đổi nội dung. Hiện cập nhật tab, bộ lọc, timer và tải trang đầu trong `didUpdateWidget`; lịch sử học tập cũng nhận thay đổi entryId. Tab Web tạo lịch sử điều hướng; đã kiểm tra đúng chuỗi Khám phá → Đang học → Khám phá → Bộ sưu tập → Đang học → Khám phá và Back/Forward.
- Đồng nhất lề desktop 32 px, căn giữa nội dung và giới hạn chiều rộng theo trang; breadcrumb SignVoice bấm về Tổng quan, ẩn Back ở trang gốc. AppButton mặc định giới hạn 420 px trên desktop, có tùy chọn phủ ngang; nút xác thực giữ bố cục cũ. Camera/micro Web dùng khối tối đa 560 px với hướng dẫn và nút ngay bên dưới, lối nhập văn bản rõ hơn, hướng dẫn khi bị chặn và chuyển động nhẹ theo thiết lập trợ năng. Mobile giữ footer cấp quyền để hành động luôn tới được.
- Mục tiêu và biểu đồ lên ngay sau lời chào; bộ đếm mục tiêu căn trái, có giờ cập nhật và nhãn đúng hành động “Xem & đổi mục tiêu”. Biểu đồ có số, trạng thái ngày chọn, đường nền, chữ ngày 12 px, hướng dẫn theo thiết bị; các cột cùng đường đáy, 7 ngày vừa thẻ rộng 500 px, kỳ dài có scrollbar tương tác. Từ điển nổi bật desktop dùng lưới thay dải ngang ẩn; hội thoại gần đây có icon theo loại và nhãn “Xem lịch sử hội thoại”.
- Tab thư viện gọn, có viền/focus; tìm kiếm debounce 350 ms. Thẻ chủ đề bỏ số người bằng 0 và câu hành động lặp, ảnh contain để giữ đầu/tay, hiện tiến độ thật khi cache có dữ liệu. Bộ sưu tập phân cấp nút tạo/khám phá/mã mời, bỏ InkWell thừa, bộ rỗng có “Thêm ký hiệu đầu tiên”, tiêu đề theo tab và ẩn Trang 1/1. Không thêm lượt tải toàn bộ từ điển.
- Hội thoại Web dùng DataTable cao theo nội dung, **một bộ phân trang server** và 10/20/50 mục; bỏ lọc client chồng lên kết quả tìm kiếm server. Có yêu thích, mở, xóa màu cảnh báo và xóa tất cả có xác nhận; Mobile có menu xóa. Khi chữ lớn chuyển sang thẻ vẫn tải được trang sau. Sắp xếp được ghi rõ chỉ áp dụng trang đang tải. Lịch sử học tập chiếm đủ chiều rộng, nhãn hoạt động thống nhất, trạng thái màu, nút mở rõ và lưu số mục mỗi trang trên Web.
- Hồ sơ Web chia Tài khoản / Ứng dụng / Khác, vai trò dạng huy hiệu và đăng xuất riêng. Hộp xác nhận chung hỗ trợ thao tác nguy hiểm màu cảnh báo. Giữ thiết kế/animation đăng nhập, đăng ký, luồng xác thực, backend, schema database và dữ liệu gốc; chưa bổ sung hoàn tác sau xóa hoặc sắp xếp toàn bộ dữ liệu trên server.
- Kiểm thử: nhóm UI/bộ sưu tập/sidebar đạt 94 bài, 1 bỏ qua; nhóm auth/dữ liệu/theme đạt 55 bài; nhóm Mobile/cấp quyền/tiến độ đạt 23 bài. Nhóm hồi quy mới tab/quiz/biểu đồ/chữ lớn đạt 19 bài (các nhóm có bài trùng, không cộng thành tổng duy nhất). Dart analyze sạch. Chrome thật dùng API fixture đã qua đổi tab, Back/Forward, cấp quyền gọn, hồ sơ, yêu thích/xóa, quiz đổi query và cảnh báo rời bài; không có lỗi runtime trong các luồng này. Fixture không ghi vào database thật và không phải kiểm thử tải production. Ảnh kiểm tra nằm tại `.runtime/browser-{dashboard,library,permission,profile,history}.png`.
- Kiểm tra bổ sung: 7 bài sidebar/điều hướng đạt, 1 bài dành riêng Chrome bỏ qua trên VM; 12 bài tiến độ/biểu đồ và 4 bài lịch sử học tập đạt. Khi cả dòng mở chi tiết, bảng học tập ẩn checkbox để tránh hiểu nhầm thành chọn hàng. Có thêm ảnh Chrome `.runtime/browser-{microphone,collections,learning-history}.png`.
- Bản Web release cuối build thành công, đã khởi động lại `http://localhost:3002/#/home`. Trang, backend/database readiness, AI health và library version đều HTTP 200; JavaScript phục vụ khớp file release. Lượt Chrome cuối cũng qua toàn bộ luồng nêu trên, không có lỗi runtime. Nhấn Ctrl+F5 để nhận bản mới.

## Sửa các rủi ro UX Web sau rà soát — 29/10/2026

- Xác nhận sidebar trước đây gắn vào từng AppPage nên mất trạng thái khi đổi route; Web hiện dùng ShellRoute, giữ WebWorkspace, lưu lựa chọn thu gọn trong SharedPreferences. Có nhóm Công cụ/Học tập/Cá nhân, rail cân giữa icon, toggle cả ở 900–1279px, tooltip/ellipsis, semantics và phản hồi focus; tài khoản có avatar chữ và menu Hồ sơ/Đăng xuất. Giao diện/animation đăng nhập và đăng ký được giữ.
- Highlight lấy URI từ shell GoRouter và phân tích path/query; Bộ sưu tập vẫn sáng khi URL thêm bộ lọc. Nội dung desktop căn trái trong giới hạn đọc 1440px, header dạng breadcrumb, Title cập nhật tiêu đề tab, fade route ngắn tôn trọng giảm chuyển động. Grid tính cả khoảng cách giữa thẻ, không ép hai cột thiếu chiều rộng; AppCard bổ sung cursor/hover và viền focus rõ (ripple InkWell vốn đã có).
- Hội thoại Web khôi phục yêu thích; thêm mở/xóa có xác nhận và icon loại hội thoại, nút thao tác truy cập được bằng bàn phím, chọn 10/20 dòng, chọn trang dữ liệu backend. Cột có sortColumnIndex; sắp xếp được ghi rõ chỉ trong trang dữ liệu đã tải, không trình bày sai thành sắp xếp toàn bộ server. Điều kiện bảng dùng chung isDesktopLayout với AppPage.
- Quiz giữ controller theo path, định danh Page gồm route-stack key và path, không theo chuỗi query. Kiểm tra rời trang cả tại redirect và onExit để không bỏ qua khi hai trang cùng mẫu route; chỉ đổi query không tháo bài đang nhập. Đã kiểm tra hủy rời bài, lưu thoát, điều hướng cùng độ sâu, query và sự kiện route từ trình duyệt.
- Dashboard có skeleton, Notice/thử lại, biểu đồ LearningActivityChart tái sử dụng, nhãn ngày qua intl, màu chú giải sáng/tối, khoảng cách nhóm rõ và AppCard thống nhất. Nút học mở chủ đề còn từ đang học/cần ôn trong trang tiến độ đã tải; nếu chưa có chủ đề phù hợp dùng Khám phá bài học. Shortcut dùng URL mới. Lắng nghe visibilitychange của Web với TTL 30 giây và gỡ listener khi dispose; cập nhật thủ công bỏ qua TTL.
- Lịch sử học tập có bảng desktop, debounce 350ms, chọn 10/20/50 mục và phân trang server. Backend chỉ nhận ba kích thước trên, mặc định 10 giữ tương thích; cập nhật OpenAPI. Test API chạy MongoDB cô lập, xác nhận phân trang, dữ liệu theo chủ tài khoản và từ chối kích thước không hợp lệ. Không thay đổi schema database.
- Kiểm tra Chrome thật qua CDP với API fixture chặn trong trình duyệt, không tạo dữ liệu trên database thật: dashboard, title, đổi query quiz, hủy/lưu, browser Back/Forward và cảnh báo đều qua, không có lỗi runtime trong luồng được kiểm tra. Ảnh `.runtime/browser-dashboard.png` là Chrome thật dùng dữ liệu giả lập; không coi fixture là kiểm chứng tải dữ liệu production. Bộ kiểm thử biểu đồ 30 ngày/360px/chữ lớn cũng xác nhận không tràn sau đổi định dạng ngày.
- Bảng không chừa hàng trống khi dữ liệu ít; kiểm tra Chrome dùng thao tác chuột thật qua CDP đã xác nhận thêm yêu thích/xóa có xác nhận và cập nhật giao diện. Đợt hồi quy tổng hợp đạt 82 bài Flutter (1 bài Chrome riêng bỏ qua trên VM), 6 bài API history trên MongoDB cô lập; thêm 5 bài regression tập trung sidebar/bảng/quiz đạt. Phân tích Dart, TypeScript build và OpenAPI sạch. Bản Web release dùng chung backend/database/AI local tại `http://localhost:3002/#/home`; Ctrl+F5 để tải bản mới, không build APK ở đợt này.
- Đã khởi động lại local sau bản release cuối: trang, readiness/database, AI health và library version đều HTTP 200; JavaScript được phục vụ khớp bản build. Smoke Chrome cuối qua dashboard, yêu thích/xóa hội thoại, quiz đổi query, browser Back/Forward, title `Ôn ký hiệu · SignVoice`, không có lỗi runtime trong luồng fixture. Ảnh bảng Chrome tại `.runtime/browser-history.png`.


## Không gian Web riêng dùng chung Flutter và dữ liệu — 29/10/2026

- Áp dụng `ui-ux-pro-max`, `flutter-build-responsive-layout` và `flutter-setup-declarative-routing`. Giữ màu SignVoice và thiết kế/animation đăng nhập, đăng ký vừa hoàn thiện; chọn bố cục dashboard phẳng, khoảng cách 16/24/32 px, màu theo theme, hạn chế hiệu ứng nặng.
- Web có sidebar mở rộng/thu gọn, mục Bộ sưu tập riêng, trạng thái chọn cho trang con và menu Quản trị theo quyền. Nội dung giới hạn 1440 px, tăng khoảng đệm desktop; cửa sổ nhỏ tiếp tục dùng điều hướng gọn. APK tiếp tục dùng Navigator và giao diện hiện có.
- Thêm `WebDashboard`: tiến độ thật (từ mới/đã ôn hôm nay, đã nhớ/cần ôn), mục tiêu ngày, hoạt động 7 ngày, công cụ giao tiếp, bộ sưu tập, từ điển và hội thoại gần đây. Hai request tiến độ chạy song song, không tải toàn bộ từ điển, không gọi AI khi mở dashboard. Có loading/thử lại, chặn request trùng và kết quả của phiên tài khoản cũ; tải lại khi quay về foreground.
- Web dùng `MaterialApp.router`/GoRouter, ánh xạ mã Sxx sang `/home`, `/login`, `/register`, `/dictionary`, `/profile`, `/history`, `/sign-to-speech`, `/speech-to-sign` và giữ các route học tập/bộ sưu tập/quản trị. Giữ hash URL để tương thích cách phục vụ hiện tại, ví dụ `http://localhost:3002/#/home`; chưa bật path strategy. Các lệnh điều hướng named và thông báo đi qua adapter, giữ arguments và kết quả trả về; route cũ tiếp tục được nhận và chuyển sang alias. Đăng nhập email từ trang được bảo vệ giữ đích đến; giao diện auth không thiết kế lại.
- Đổi trang khỏi quiz chưa xong qua router có cảnh báo và lưu trước khi thoát, dùng cùng logic với nút quay lại. Quyền truy cập vẫn kiểm tra trong AccessGate và backend; dữ liệu riêng không được mở thêm cho Admin/Staff.
- Lịch sử hội thoại có bảng trên desktop và card trên Mobile/chữ lớn. Từ điển, bộ sưu tập, hồ sơ và quản trị tiếp tục sử dụng bố cục thích ứng, phân trang, tìm kiếm và cache dịch vụ sẵn có. Web/Mobile dùng chung API, MongoDB, tài khoản và ID nội dung; Web đồng bộ dữ liệu tài khoản khi trở lại foreground. Chưa bổ sung WebSocket đồng bộ thời gian thực hoặc giải quyết xung đột chỉnh sửa đồng thời.
- Kiểm tra: nhóm 132 bài (bộ sưu tập/quản trị/mobile/cache), nhóm 54 bài (auth/quiz/dashboard/router) và 9 bài desktop chuyên biệt đạt; các nhóm có bài trùng, không cộng thành số bài duy nhất. Dashboard được kiểm tra ở 1024/1440/1920 px, sáng/tối; kiểm tra riêng alias, phân quyền, kết quả push và xác nhận rời quiz. Ảnh `.runtime/dashboard-{dark,light}.png` là component harness, không phải ảnh nghiệm thu trình duyệt thật. Kiểm thử Chrome đang vướng bước nạp, chưa tính là đạt.
- Bản release cuối build thành công; phân tích `lib` và kiểm thử desktop sạch. Nhóm cuối gồm desktop/sidebar/auth/đăng ký đạt 32 bài, 1 bài riêng Chrome bỏ qua trên VM. Đã khởi động lại local tại `http://localhost:3002`, backend/database và AI nhận diện 181 từ phản hồi HTTP 200. JavaScript được phục vụ khớp bản release. Dùng `http://localhost:3002/#/home` và Ctrl+F5 để kiểm tra; chưa build APK ở đợt này.


## Hiệu ứng chuyển chế độ và đăng ký phải đăng nhập lại — 29/10/2026

- Xem video `Recording 2026-10-29 153038.mp4`. Phát hiện máy đặt `HKCU\Control Panel\Desktop\WindowMetrics\MinAnimate=0`; code cũ chuyển ngay khi nhận giảm chuyển động, còn AnimationController mặc định có thể rút ngắn thời lượng. Transition xác thực hiện dùng `AnimationBehavior.preserve`, giữ 650 ms theo yêu cầu; nút **Giảm chuyển động / Bật hiệu ứng trượt** ở góc trang cho phép chọn riêng trong màn hình này, không sửa thiết lập Windows. Kiểm thử đã mô phỏng cả `accessibilityFeatures.disableAnimations=true` và xác nhận panel vẫn có vị trí trung gian, không nhảy thẳng.
- Bỏ Google/Facebook khỏi đăng ký trên cả giao diện desktop và mobile; chỉ giữ ở đăng nhập. Tiêu đề đăng nhập desktop thành **Tiếp tục hành trình cùng SignVoice**, có logo và mô tả ngắn, phân cấp chữ và khoảng cách rõ hơn.
- Web và mã nguồn mobile dùng chung luồng đăng ký: tạo tài khoản thành công → trở về biểu mẫu đăng nhập, giữ email, xóa mật khẩu/xác nhận; chỉ gọi điều hướng vào ứng dụng sau đăng nhập thành công. Provider không đi qua trạng thái authenticated khi đăng ký. Nâng cấp guest giữ nguyên ID/dữ liệu, thu hồi phiên khách và cũng yêu cầu đăng nhập lại.
- Client gửi `requireLogin=true` ở `/auth/register` và `/auth/convert-guest`. Backend không lưu phiên mới, không trả tokens và xóa refresh cookie với luồng này. API giữ tương thích cho client cũ không gửi cờ; **APK đã cài trước đây cần build/cài lại để nhận luồng mới**, chưa build APK trong lượt này. OpenAPI đã mô tả hai dạng phản hồi.
- Kiểm tra: **32 kiểm thử Flutter tập trung đạt, 1 bỏ qua dành riêng Chrome**, gồm animation, auth/OAuth và luồng đăng ký mới cho cookie Web/native token storage; **17 kiểm thử backend đạt** (15 auth-security và 2 luồng đăng ký/guest), sử dụng MongoDB cô lập. TypeScript build, Dart analyze và kiểm tra OpenAPI đạt. Không tạo tài khoản thử nghiệm trên database ứng dụng thật.
- Đã build Web release và khởi động lại backend local tại **http://localhost:3002**. Trang, readiness/database, AI health và thư viện trả HTTP 200; JavaScript đang phục vụ khớp bản release mới. Nhấn Ctrl+F5 để nhận bản cập nhật; AI 181 từ tiếp tục hoạt động.

## Làm mượt đăng nhập/đăng ký Web — 29/10/2026

- Đã xem các khung hình video `Recording 2026-10-29 145903.mp4` người dùng cung cấp và áp dụng `ui-ux-pro-max`. Chuyển chế độ ngay trong cùng `AuthScreen`, dùng panel trượt 650 ms với đường cong ease-in-out và fade biểu mẫu ở giữa chuyển động; giữ màu xanh SignVoice, giá trị đã nhập và đích đến sau đăng nhập.
- Google/Facebook chuyển thành hai nút biểu tượng 52×52 đặt cạnh nhau dưới tiêu đề, có tooltip và tên trợ năng; giữ xử lý OAuth hiện có. Bỏ dòng mô tả thừa bên đăng ký và liên kết đăng ký trùng bên đăng nhập desktop. Dùng thử chuyển thành nút phụ **Khám phá bản dùng thử** có biểu tượng la bàn.
- Biểu mẫu được căn giữa, giới hạn chiều rộng, có khoảng cuộn cho cửa sổ thấp/chữ lớn; chỉ một form được gắn tại mỗi thời điểm. Trong chuyển động, tạm ngăn thao tác và focus vào biểu mẫu; panel có thể đảo chiều, chế độ giảm chuyển động chuyển ngay tới trạng thái cuối. Tách trạng thái validation đăng nhập/đăng ký để lỗi của chế độ trước không đi sang chế độ sau.
- Kiểm tra: **38 kiểm thử đạt, 1 kiểm thử Chrome bỏ qua trong môi trường VM**, gồm auth, OAuth, đặt lại mật khẩu, bố cục và mobile; kiểm thử riêng xác nhận vị trí giữa chuyển động, đảo chiều nhanh, giữ email và reduced motion. Phân tích các file thay đổi sạch. Đã render và xem hai ảnh test harness tại `.runtime/auth-polished-{login,register}.png`; đây là ảnh component mô phỏng, không phải ảnh nghiệm thu trình duyệt thật.
- Web release build thành công và đã khởi động lại **http://localhost:3002**. Trang, readiness/database, AI health và phiên bản thư viện trả HTTP 200; JavaScript đang phục vụ khớp bản release mới. Nhấn Ctrl+F5 để kiểm tra. Backend và AI nhận diện 181 từ tiếp tục hoạt động; chưa build APK trong lượt này.

## Web desktop và skill Flutter — 29/10/2026

- Web sử dụng toàn bộ cửa sổ trình duyệt. Từ 900 px, tài khoản đã đăng nhập có sidebar riêng; từ 1280 px sidebar hiện nhãn đầy đủ. APK giữ điều hướng mobile. Trang tổng quan chia hai thẻ giao tiếp, học tập/bộ sưu tập/cá nhân chia cột theo không gian, từ điển tự tăng số cột, quản trị có hàng thông tin theo cột ở desktop. Chữ lớn ưu tiên một cột để giữ khả năng đọc.
- Đăng nhập/đăng ký desktop có hai panel tham khảo bố cục [Modern Login](https://github.com/AsmrProg-YT/Modern-Login), dựng bằng Flutter và màu xanh SignVoice. Panel đổi phía theo chế độ; giữ biểu mẫu, OAuth và xử lý guest hiện có. Trang cuộn được khi cửa sổ thấp/chữ 2×; hiệu ứng tôn trọng giảm chuyển động.
- Dùng chung service/API/database với APK. Chưa bổ sung cơ chế giải quyết xung đột chỉnh sửa đồng thời giữa hai thiết bị; dữ liệu học tập vẫn đi qua API hiện có. Không coi đây là đồng bộ thời gian thực.
- Kiểm tra: 104 kiểm thử auth/học tập/bộ sưu tập/quản trị/khởi động đạt; thêm 24 kiểm thử quản trị/mobile đạt; 6 kiểm thử mới cho panel sáng/tối, chữ 2× và phân quyền/điều hướng sidebar đạt. Kiểm thử Chrome tích hợp chưa chạy xong ở bước nạp và đã dừng, không tính là đạt. Chưa nghiệm thu bằng ảnh chụp trình duyệt. Phân tích các file thay đổi sạch; Web release build thành công với API `/api/v1` và AI `/sign-ai` cùng origin. Đã khởi động lại local tại **http://localhost:3002**, AI 181 từ được giữ chạy.
- Đã đối chiếu danh sách [flutter/agent-plugins](https://github.com/flutter/agent-plugins): đủ 10 skill Flutter đã có `SKILL.md` trong `C:\Users\Phuoc Tue\.codex-plus2\skills`, gồm `flutter-setup-declarative-routing`; không cài trùng hoặc ghi đè skill hiện có.

### Bước chuyển sang GoRouter đã xác định

Đây là kế hoạch ban đầu trước đợt triển khai Web ở đầu README. Hiện Web đã dùng GoRouter và adapter tương thích; Mobile giữ Navigator/MaterialApp. Path URL strategy và nghiệm thu đầy đủ Back/Forward trên trình duyệt thật vẫn cần theo dõi như ghi chú phía trên.

1. Tạo bộ ánh xạ URL rõ nghĩa (`/home`, `/login`, `/register`, `/dictionary`, `/collections`, `/history`, `/profile`) và alias cho các mã `Sxx`/liên kết chia sẻ cũ; giữ nguyên query và ID từ/bộ/quiz.
2. Chuyển sang `MaterialApp.router`, GoRouter và shell phù hợp desktop/mobile. Chuyển đồng bộ helper điều hướng, các lệnh Navigator named trực tiếp và điều hướng từ thông báo; không chỉ đổi sidebar.
3. Chờ khôi phục xác thực trước redirect; giữ đích đến sau đăng nhập. Kiểm tra role tại giao diện và tiếp tục dựa vào backend cho quyền dữ liệu. Không đặt query reset-password/token vào log.
4. Kiểm tra refresh, deep link, URL không hợp lệ, Back/Forward, OAuth callback, xác nhận rời quiz và kết quả trả về sau hộp/form trước khi bật router mới.
5. Chỉ chuyển sang path URL sau khi xác nhận backend trả `index.html` cho đường dẫn UI và không nuốt `/api`, `/sign-ai`, media hoặc asset bị thiếu; nghiệm thu local và Conveyor cùng APK. Hash URL hiện tại tiếp tục hoạt động trong lúc chuyển đổi.

Ứng dụng hỗ trợ giao tiếp ngôn ngữ ký hiệu Việt Nam: Flutter Web/Android, backend Node.js/Express/TypeScript, MongoDB và service AI Python.

Đơn vị vận hành: **SignVoice**. Người phụ trách: **Phạm Phước Tuệ**. Liên hệ: **phuoctue0312@gmail.com**.

## Kế hoạch tính phí và giới hạn tính năng — 29/10/2026

Đây là **đề xuất thiết kế**, chưa thay đổi mã nguồn, giá bán hoặc dữ liệu hiện tại. Mục tiêu là có doanh thu nhưng vẫn giữ các chức năng cốt lõi của SignVoice hữu ích cho người học và người cần hỗ trợ giao tiếp. Không khóa quyền truy cập từ điển công khai, nội dung trợ năng cơ bản hoặc dữ liệu người dùng chỉ vì tài khoản hết hạn.

### 1. Cấu trúc gói đề xuất

| Gói | Phù hợp | Giới hạn thử nghiệm ban đầu |
|---|---|---|
| Dùng thử/Khách | Xem nhanh trước khi đăng ký | Không đồng bộ; tối đa 20 từ hoặc 1 phiên học; AI giới hạn 5 lượt/ngày; không tạo bộ riêng |
| Miễn phí | Người học cá nhân | Xem toàn bộ từ điển công khai, quiz cơ bản, 3 bộ sưu tập riêng, 20 từ tự tạo, 100 lượt nhận diện AI/ngày, 5 gợi ý AI/ngày, lịch sử 30 ngày |
| Plus | Người học thường xuyên | 30 bộ sưu tập, 500 từ tự tạo, nhận diện/gợi ý AI ở hạn mức cao hơn, đồng bộ đầy đủ, lịch sử không giới hạn, thống kê nâng cao, xuất dữ liệu cá nhân và chia sẻ bộ sưu tập |
| Giáo dục/nhóm | Lớp học hoặc đơn vị hỗ trợ | Quản lý thành viên, hạn mức theo nhóm, bộ dùng chung, báo cáo tiến độ tổng hợp và hóa đơn theo số lượng tài khoản |

Các con số trên chỉ là mốc để A/B test. Phải đặt trong cấu hình máy chủ/feature flag, không hard-code trong APK. Có thể thêm gói Pro sau khi đo được chi phí AI, tỷ lệ giữ chân và nhu cầu xuất hiện trong thực tế.

Người dùng bị hạ gói không mất dữ liệu: các bộ/từ vượt hạn mức chuyển sang chỉ đọc, không cho tạo thêm cho đến khi giảm số lượng hoặc nâng cấp. Hủy gói có thời gian gia hạn ngắn; hết thời gian vẫn giữ dữ liệu riêng, ghi chú và tiến độ, chỉ tắt quyền ghi mới hoặc tính năng nâng cao.

### 2. Tách quyền gói khỏi quyền vai trò

- `plan`/`entitlement` quyết định quyền thương mại của người dùng cuối.
- `role` (`USER`, `STAFF`, `ADMIN`) quyết định quyền vận hành; quản lý tài khoản, role, phiên đăng nhập và kiểm duyệt không được mở khóa bằng gói trả phí.
- ADMIN/STAFF vẫn bị kiểm tra quyền ở backend. Không dùng trường role trong client để cấp quyền.
- Việc giới hạn AI chỉ giới hạn số lượt/thời gian sử dụng; không thay đổi dữ liệu media, ZIP, từ điển nguồn hoặc model 181 từ.

### 3. Mô hình dữ liệu và quota phía backend

Nên bổ sung các thực thể độc lập với dữ liệu học tập hiện có:

- `plans`: mã gói, phiên bản, giá, tiền tệ, chu kỳ, danh sách entitlement và trạng thái phát hành.
- `subscriptions`: `userId`, `planId`, nhà cung cấp, mã khách hàng/gói bên ngoài, trạng thái, kỳ hiện tại, thời điểm hết hạn, hủy/gia hạn và thời gian ân hạn.
- `entitlement_snapshots`: bản quyền có hiệu lực để đọc nhanh; có `sourceVersion` và thời điểm đồng bộ.
- `usage_counters`: `userId`, `feature`, cửa sổ đo (UTC), số đã dùng, hạn mức, `resetAt`; cập nhật nguyên tử trong transaction để tránh vượt hạn mức khi gửi song song.
- `billing_events` và `audit_logs`: mã sự kiện duy nhất, payload tối thiểu cần đối soát, người/thành phần thực hiện, thời điểm và kết quả. Webhook lặp lại phải idempotent.

Các feature nên dùng mã ổn định, ví dụ `ai_recognition`, `ai_suggestion`, `private_collection_create`, `custom_word_create`, `advanced_analytics`, `export_data`. Khi đổi giá hoặc hạn mức, tạo phiên bản cấu hình mới, không sửa ngược lịch sử giao dịch.

### 4. API và luồng thanh toán

Đề xuất API:

- `GET /api/v1/billing/plans`: trả các gói đang bán và entitlement công khai.
- `GET /api/v1/billing/me`: trả gói hiện tại, trạng thái, hạn mức còn lại và `resetAt`.
- `GET /api/v1/billing/usage`: trả số liệu sử dụng đã tổng hợp, không trả dữ liệu nhạy cảm.
- `POST /api/v1/billing/checkout` và `POST /api/v1/billing/portal`: tạo phiên mua/quản lý theo adapter nhà cung cấp.
- `POST /api/v1/billing/webhooks/:provider`: xác minh chữ ký, chống replay, lưu mã sự kiện và cập nhật subscription trong transaction.
- `POST /api/v1/billing/restore`: đồng bộ lại giao dịch khi đổi máy hoặc cài lại APK.

Backend phải là nguồn quyết định cuối cùng. Khi bị giới hạn, trả lỗi có mã máy đọc được (ví dụ `QUOTA_EXCEEDED`, `FEATURE_NOT_INCLUDED`), `remaining`, `limit` và `resetAt` để app hiển thị đúng; không dùng lỗi 500 cho trường hợp hết quota.

Nhà cung cấp thanh toán nên được bọc sau một interface chung. Mobile dùng cơ chế thanh toán được cửa hàng ứng dụng cho phép đối với nội dung số; web có thể dùng nhà cung cấp riêng nếu cần. Chưa chốt nhà cung cấp cho đến khi xác định thị trường, phí, thuế, hoàn tiền và chính sách cửa hàng.

### 5. UI/UX cần triển khai

- Thêm mục **Gói & sử dụng** trong Cá nhân, hiển thị gói hiện tại, thanh quota, ngày reset, trạng thái gia hạn và nút nâng cấp rõ ràng.
- Khi chạm giới hạn, giải thích tính năng nào bị giới hạn, còn bao nhiêu, mở lại lúc nào và đưa lựa chọn chờ reset/giảm dữ liệu/nâng cấp. Không xóa nội dung đang có.
- Cho phép dùng app ở chế độ offline với snapshot entitlement có thời hạn ngắn; khi chưa xác minh được thì không tự động khóa dữ liệu cũ, nhưng tạm dừng thao tác tốn quota cho đến khi đồng bộ.
- Không hiển thị giá trị nội bộ, role quản trị hoặc thông tin webhook. Hỗ trợ chữ lớn, trạng thái tải, lỗi mạng, hoàn tác và màn hình xác nhận trước mua.

### 6. Bảo mật, hoàn tiền và hạ cấp

- Không lưu số thẻ hoặc bí mật thanh toán trong SignVoice; chỉ lưu mã tham chiếu do nhà cung cấp cấp.
- Xác minh chữ ký webhook, timestamp/chống replay, idempotency key và kiểm tra trạng thái giao dịch từ máy chủ nhà cung cấp trước khi cấp quyền.
- Khi hoàn tiền, chargeback hoặc hết thời gian ân hạn, thu hồi entitlement mới nhưng giữ dữ liệu người dùng và ghi audit log.
- Giới hạn rate cho checkout, restore, webhook và endpoint usage; log lỗi không chứa token, mật khẩu hoặc payload thanh toán nhạy cảm.
- Hỗ trợ xuất/xóa dữ liệu theo chính sách hiện có; dữ liệu hóa đơn cần giữ theo yêu cầu pháp lý áp dụng.

### 7. Lộ trình triển khai an toàn

1. **Đo lường (shadow mode):** thêm bảng entitlement/usage và log chi phí AI, chưa chặn người dùng; kiểm tra race condition và dữ liệu cũ.
2. **Quota miễn phí:** bật giới hạn server-side cho AI, bộ riêng và từ tự tạo; UI hiển thị quota nhưng vẫn giữ dữ liệu khi hạ gói.
3. **Thanh toán thử nghiệm:** adapter nhà cung cấp, webhook idempotent, sandbox, restore, hoàn tiền và đối soát thủ công.
4. **Ra mắt hạn chế:** feature flag theo nhóm nhỏ, theo dõi chuyển đổi, lỗi thanh toán, chi phí mỗi người dùng và tỷ lệ bị chặn nhầm.
5. **Mở rộng:** gói Plus/giáo dục, khuyến mãi, hóa đơn và bảng điều khiển doanh thu; mọi thay đổi hạn mức đều có phiên bản và audit.

### 8. Tiêu chí nghiệm thu trước khi bật tính phí

- Không thể vượt quota bằng gọi API song song, đổi thiết bị, sửa clock hoặc sửa request từ client.
- Webhook lặp/mất thứ tự không làm nhân đôi hoặc mất entitlement; restore khôi phục đúng giao dịch.
- Hạ gói không xóa bộ sưu tập, từ tự tạo, ghi chú, tiến độ hoặc dữ liệu media.
- ADMIN/STAFF và USER được phân quyền độc lập; endpoint billing không làm lộ dữ liệu riêng.
- Có kiểm thử cho hết quota, reset kỳ, offline, timeout, hoàn tiền, hủy giữa kỳ, nâng/hạ gói và lỗi nhà cung cấp.
- Đo được chi phí AI theo feature trước khi chốt giá chính thức.

Các quyết định còn cần chốt với sản phẩm: giá và chu kỳ, nhà cung cấp thanh toán, quota AI tính theo lượt hay thời gian, có trial bao nhiêu ngày, gói gia đình/giáo dục, chính sách hoàn tiền và thị trường phát hành.

## Xây dựng và ổn định bản Web trước khi tính phí — 29/10/2026

Đã thực hiện vòng kiểm tra nền tảng đầu tiên, chưa bật giới hạn thương mại hay thanh toán:

- `flutter analyze`: **không có vấn đề**.
- `npm run build` trong `backend`: **thành công**.
- `flutter build web --release`: **thành công**, tạo bản phát hành tại `build/web`.
- Kiểm thử Flutter khởi động, điều hướng và hiệu năng API: **11 kiểm thử đạt**.
- Kiểm thử backend với MongoDB cô lập: **3 file / 9 kiểm thử đạt**, gồm asset khởi động Web, hiệu quả `auth/me` và đồng bộ thư viện media.
- Build Web có cảnh báo Wasm từ dependency bên thứ ba (`flutter_secure_storage_web`, `flutter_tts`). Đây không chặn bản Web JavaScript hiện tại; chỉ cần xử lý khi chủ động chuyển sang Wasm.

Phạm vi ổn định tiếp theo:

1. Kiểm tra smoke trên môi trường Conveyor: đăng nhập/guest, tải từ điển, video/ảnh, quiz, bộ sưu tập, AI và quản trị theo đúng quyền.
2. Ghi số đo khởi động, thời gian điều hướng, lỗi API, lỗi media và chi phí AI; không đưa giới hạn tính phí vào client.
3. Sửa các lỗi thực tế phát hiện trên Web và kiểm tra lại mobile responsive, offline, refresh và phiên đăng nhập hết hạn.
4. Khi Web đạt tiêu chí nghiệm thu mới bật entitlement/quota ở chế độ shadow, sau đó mới thử nghiệm thanh toán.

Tiêu chí chuyển sang bước tính phí: release Web build lặp lại được; backend build/typecheck sạch; smoke flow chính không có lỗi chặn; dữ liệu media đồng bộ đúng revision; quota có thể kiểm tra phía server; và không còn lỗi mất dữ liệu khi refresh, hạ quyền hoặc mất mạng.


## Tối ưu giao diện quản trị — 29/10/2026

- Áp dụng `ui-ux-pro-max` cho quản trị Admin/STAFF: thay menu thả xuống phủ màn hình bằng hộp chọn bo góc, cao tối đa 520 dp, có nút đóng và dấu chọn rõ. Danh sách dài (danh mục/role) có tìm kiếm; nhãn dài xuống dòng trong hộp chọn. Dùng chung cho lọc tài khoản, từ điển, kiểm duyệt bộ/báo cáo và các trường trong biểu mẫu.
- Chia biểu mẫu thành nhóm thông tin, media, phân loại/trạng thái và thông tin bổ sung. Nút **Lưu thay đổi** cố định, vùng bấm tối thiểu 56 dp, nằm phía trên bàn phím; chặn bấm lặp và tự cuộn đến trường lỗi đầu tiên. Thêm hiện/ẩn mật khẩu ban đầu; giữ nội dung khi lưu lỗi và cho nhập các trường văn bản trong lúc tải danh mục/role.
- Gom bộ quyền thành 6 nhóm thu gọn, có số quyền đã chọn và chọn/bỏ chọn cả nhóm trong phạm vi người quản trị được cấp. Hộp xem role dùng cùng bố cục nhóm ở chế độ chỉ đọc. Không đổi quyền backend, API hoặc dữ liệu người dùng.
- Đồng bộ thẻ danh sách và tổng quan với theme ứng dụng, phân cấp chữ/khoảng cách, trạng thái trống có hướng dẫn/xóa bộ lọc. Tìm kiếm, bộ lọc và phân trang cuộn cùng danh sách để dùng được trên màn hình thấp/chữ lớn; giữ dữ liệu cũ trong khi tải lại. Thống kê tự chia cột theo chiều rộng và cỡ chữ. Không thêm package hoặc API request khi mở hộp chọn.
- Kiểm tra riêng: **45 kiểm thử quản trị/hộp chọn/bố cục đạt**, cùng **21 kiểm thử kiểm duyệt**; đã xem ảnh render sáng/tối. Các trường hợp gồm chữ 2×, 320×640, 375 px, màn hình ngang, tablet, bàn phím, giảm chuyển động, đóng bằng Escape, tìm/chọn danh mục, cấp role và giữ biểu mẫu khi API lỗi. Thao tác trên Android thật vẫn cần nghiệm thu; chưa build APK trong đợt này.
- Kiểm thử toàn bộ Flutter sau hoàn thiện: **458 đạt, 1 bỏ qua**; 14 ảnh render quản trị sáng/tối đạt. `flutter analyze` không có vấn đề, TypeScript build thành công; thay đổi đợt này chỉ ở giao diện quản trị và kiểm thử.
- Đã build Web release/backend và cập nhật **môi trường kiểm thử** lúc **10:12 ngày 29/10**. Trang/API/readiness/AI trả HTTP 200; JavaScript public khớp bản build mới (`0bbc23fece2cb87934698046bfd7139505bc493b2de9af34e2f3da2477b91fd8`). API kiểm duyệt tiếp tục trả 401 khi chưa đăng nhập. AI 181 từ và LM Studio nền vẫn hoạt động. Link Conveyor là phiên tạm; không coi kiểm tra HTTP/render mô phỏng là nghiệm thu trên điện thoại thật.

## Quản lý bộ sưu tập công khai — 29/10/2026

- Đã triển khai **Quản trị → Bộ sưu tập công khai** cho ADMIN và STAFF: tìm theo tên trên server, lọc trạng thái, báo cáo mở hoặc yêu cầu kiểm tra lại, phân trang 10 bộ. Mở chi tiết mới tải từ thư viện; báo cáo và lịch sử tải riêng khi chọn mục tương ứng. Avatar/mô tả có trong bản xem trước, số từ lấy theo trạng thái từ điển hiện tại.
- Kiểm duyệt có **Ẩn khỏi khám phá**, **Chặn chia sẻ**, **Khôi phục quyền chia sẻ**; mọi thao tác cần lý do và xác nhận. Ẩn vẫn cho người có link xem; chặn còn vô hiệu xem trước/link/QR và nhập bản sao mới. Không xóa bộ gốc, từ riêng, ghi chú, tiến độ hoặc bản sao đã lưu. Khôi phục tôn trọng lựa chọn chia sẻ hiện tại, không tự đăng lại bộ chủ đã rút khỏi khám phá.
- Lưu bản tên/ảnh/mô tả/ID từ thư viện đã công khai để kiểm duyệt. Không liệt kê bộ riêng hoặc bộ chỉ gửi link chưa bị báo cáo; không trả danh tính chủ bộ/người báo cáo hay từ riêng/ghi chú/tiến độ qua API quản trị. Sau khi rút về riêng tư, chỉnh sửa mới không tự xuất hiện trong quản trị. Chủ bộ bị hạn chế thấy lý do và có thể chủ động **Gửi lại để kiểm tra**; việc gửi lại không tự khôi phục chia sẻ.
- Người dùng mở bản xem trước → biểu tượng cờ **Báo cáo bộ sưu tập**, chọn loại và mô tả. Cần tài khoản chính thức, tối đa 10 request/giờ/tài khoản, một báo cáo mở/người/bộ; gửi lại không tạo trùng. Báo cáo không tự khóa nội dung. Nhân viên đánh dấu đã xử lý hoặc không ghi nhận vi phạm kèm lý do; trạng thái bộ được xử lý riêng sau khi kiểm tra.
- Backend thêm quyền `collections:read`, `collections:moderate` cho ADMIN/STAFF mặc định; role tùy chỉnh được cấp riêng. Tài khoản, role/phân quyền và phiên đăng nhập tiếp tục chỉ ADMIN quản lý. Trạng thái và AuditLog được ghi cùng transaction, kiểm tra phiên bản chống ghi đè và ngăn mở lại nội dung đã đổi mà chưa gửi kiểm tra. Lịch sử ghi tên/vai trò nhân viên tại thời điểm xử lý, lý do, thời gian; dùng TTL AuditLog một năm hiện có.
- Không thêm package. Có index kiểm duyệt, yêu cầu gửi lại và báo cáo; đếm báo cáo/từ theo lô cho trang hiện tại, không gọi API theo từng thẻ. Ảnh/video và tên từ vẫn tra từ điển chuẩn bằng ID, tiếp tục theo các lần đồng bộ media ZIP.
- Kiểm chứng: **432 Flutter tests đạt, 1 bỏ qua; 266 backend tests / 38 file đạt** trên MongoDB tạm. Kiểm thử mới bao gồm quyền, dữ liệu riêng, chặn nhập qua link, khôi phục, rút bộ về riêng tư, gửi lại, báo cáo trùng, phiên bản cũ và rollback khi ghi lịch sử lỗi. Kiểm tra UI chữ 2×/bàn phím/320 px/ngang/tablet/sáng/tối; chạy lại 35 kiểm thử chức năng/render và 6 backend kiểm duyệt sau hoàn thiện. OpenAPI hợp lệ, **152/152 API có tài liệu**. Có 14 ảnh render sáng/tối để xem lại; thao tác trên điện thoại thật cần nghiệm thu sau khi build APK.
- [Kế hoạch và quyết định thiết kế](docs/COLLECTION_MODERATION_PLAN.md). Không build APK hoặc push git trong đợt này.
- Đã build Web/backend và cập nhật **môi trường kiểm thử** lúc 08:55 ngày 29/10. JavaScript public trùng bản local (`7b7ea4a29d8169d679054332fe9c1b86b2adc5a1caeecb1c21f03f0eeada987f`); trang/API công khai, readiness và AI đều hoạt động, API kiểm duyệt từ chối request chưa đăng nhập (401). AI 181 từ và LM Studio nền tiếp tục chạy. Dart analyze/TypeScript sạch; kiểm tra lại 21 widget và 6 backend kiểm duyệt đều đạt sau hoàn thiện. Thêm partial index cho các bản đã gửi kiểm duyệt để truy vấn không phải duyệt toàn bộ bộ riêng.

## Hoàn thiện Bộ sưu tập, avatar và từ riêng — 28/10/2026

- Áp dụng `ui-ux-pro-max` cho các nút trang Bộ sưu tập, hộp nhận mã và chia sẻ: cùng hình dạng, vùng bấm ≥48 dp, cách nhau 12 dp, phân biệt tác vụ chính/phụ và trạng thái không bấm được. Thẻ bộ chỉ có một vùng phản hồi bấm; bỏ nền hover lồng nhau. QR, mã chia sẻ, sao chép và thu hồi mã có khoảng cách riêng, hộp thoại vẫn cuộn được.
- **Tạo bộ / Quản lý bộ → Chỉnh sửa bộ** cho thêm, đổi hoặc bỏ ảnh đại diện. Ảnh được thu nhỏ 128×128, tối đa 72 KiB, kiểm tra JPEG/PNG/WebP và base64 trên backend. Ảnh hiện ở danh sách/chi tiết/xem trước và đi theo bản sao khi nhận bộ; không thêm request tải avatar cho từng thẻ bộ.
- Bỏ trang **Thẻ riêng** khỏi điều hướng ngoài. Trong mỗi bộ chọn **Thêm từ → Chọn từ thư viện / Tạo từ riêng / Thêm từ riêng đã có**. Từ riêng có ý nghĩa, ảnh, liên kết video HTTPS, ví dụ và mẹo; sửa/xóa ngay trong bộ. Form giữ nội dung khi API lỗi, chặn bấm lặp, cảnh báo bỏ thay đổi chưa lưu.
- Các từ riêng cũ được giữ nguyên và xuất hiện trong danh sách chưa xếp bộ. Gắn nhiều từ trong một transaction, không sao chép nội dung/ảnh, không tạo trùng. Xóa bộ vẫn giữ từ riêng để thêm vào bộ khác; xóa riêng một từ cần xác nhận. Xuất dữ liệu tài khoản bao gồm từ riêng.
- Từ riêng **chỉ bạn nhìn thấy**, không xuất hiện trong khám phá, link chia sẻ, bản sao nhận bộ hay quiz thư viện. Quiz tiếp tục dùng các ký hiệu đã xuất bản; UI giải thích rõ với bộ chỉ có từ riêng. Tổng từ riêng + thư viện tối đa 200/bộ, kiểm tra nguyên tử trên server.
- Thêm index `(userId, collectionId, word, _id)`; đếm từ riêng theo lô, hợp nhất/tìm/phân trang 10 từ ở database. Ảnh riêng lớn được tải khi mở/sửa, chỉ cache tối đa 5 ảnh đầy đủ; có nút tải lại nếu lỗi. Sửa lỗi trạng thái mở mẫu dùng nhầm vị trí cuộn (`double` thành `bool`) khi thêm từ sau khi cuộn danh sách.
- Kiểm chứng: **411 Flutter tests đạt, 1 bỏ qua; 260 backend tests / 37 file đạt** trên MongoDB tạm. Dart analyze/TypeScript sạch; OpenAPI hợp lệ, **144/144 API được mô tả**. Kiểm tra UI sáng/tối, chữ 2×, 320 px, ngang, tablet và bàn phím; tạo/sửa avatar qua picker giả lập, tạo/sửa/xóa từ riêng, giữ form lỗi, nhập từ cũ và cảnh báo khi đóng. Có 10 ảnh render sáng/tối để xem lại bố cục; chọn ảnh/chia sẻ qua ứng dụng thật vẫn cần nghiệm thu trên điện thoại.
- [Chi tiết thiết kế và phạm vi quyền riêng tư](docs/SIGN_COLLECTIONS_DESIGN.md#ảnh-đại-diện-và-từ-riêng-trong-bộ--bổ-sung-28102026). Chưa build APK trong đợt này.
- Đã build Web release/backend và cập nhật **môi trường kiểm thử** lúc 23:46 ngày 28/10. Kiểm tra qua Internet: trang, API từ điển/khám phá/phiên bản media và AI đều HTTP 200; JavaScript public trùng bản mới (`fcf79e18c9509da8daad4fa1c63201308d82f05fd32450ecaac7c935f250799b`). Sau chỉnh màu nút vô hiệu hóa, chạy lại **76 kiểm thử Bộ sưu tập/render** đều đạt. AI 181 từ và LM Studio tiếp tục phản hồi. Đo hai lượt API khám phá: nội bộ 99–109 ms, qua Conveyor 1129–1166 ms; đường hầm vẫn có độ trễ mạng, không cam kết tải tức thì trên mọi kết nối.

## Nhận bộ và kết nối cộng đồng — 28/10/2026

- Thiết kế lại hộp **Nhận bộ sưu tập**: rộng, tiêu đề ngắn, nút đóng rõ, ô liên kết/mã nhiều dòng, nút **Dán từ bộ nhớ** và lỗi nhập tại chỗ. Không tự đọc clipboard hoặc tự bật bàn phím; toàn bộ hộp cuộn khi màn hình nhỏ/chữ lớn/bàn phím mở.
- Người chưa có mã chọn **Khám phá bộ công khai** để tìm theo tên, xem trước và lưu bản riêng. Chủ bộ vào **Quản lý bộ → Chia sẻ bộ → Hiện trong khám phá công khai**, xác nhận rồi bộ mới xuất hiện cho người khác. Tài khoản chính thức và ít nhất một từ khả dụng mới được đăng. Không tự công khai các bộ có sẵn, không tạo bộ người dùng giả.
- Trong **Chia sẻ bộ**, có **Chia sẻ qua ứng dụng**, sao chép liên kết/mã và **Hiện mã QR**. Người gửi tự chọn ứng dụng/người nhận; QR mở liên kết xem trước bằng camera điện thoại. Trình duyệt/ứng dụng không hỗ trợ chia sẻ hệ thống có hướng dẫn dùng sao chép liên kết. Không thêm chức năng bạn bè/chat hoặc bộ quét vào camera AI.
- Chia sẻ riêng bằng link và đăng khám phá là hai lựa chọn riêng. Gỡ khỏi khám phá vẫn giữ link; tắt mã chia sẻ thu hồi cả link/QR và gỡ khỏi khám phá. Bản người nhận lưu vẫn độc lập, riêng tư mặc định. API công khai chỉ trả thông tin bộ/từ công khai, không trả danh tính tác giả, ghi chú hoặc tiến độ.
- Thêm index khám phá, phân trang 10 bộ và lấy media theo lô, giới hạn 200 từ/bộ. Bộ có media vừa bị gỡ có trạng thái chờ cập nhật; không cho lưu bộ rỗng. Bản app/backend vẫn dùng một từ điển chuẩn để cập nhật media.
- Dùng `share_plus 12.0.2` và `qr_flutter 4.1.0`; chọn bản chia sẻ tương thích để giữ nguyên secure storage/đăng nhập. [Phân tích thiết kế và nguồn kỹ thuật](docs/SIGN_COLLECTIONS_DESIGN.md#kết-nối-và-khám-phá-công-khai-bổ-sung-2810).
- Kiểm chứng: **401 Flutter tests đạt, 1 bỏ qua; 256 backend tests / 36 file đạt** trên MongoDB tạm; 6 kiểm thử QR/công khai với chữ 2× qua sau khi tăng khoảng trắng QR. Dart analyze/TypeScript và OpenAPI đạt (**138/138 API có tài liệu**). Đã xem ảnh sáng/tối của hộp nhận bộ, khám phá và QR; giải mã QR mẫu đúng URL xem trước. Chia sẻ hệ thống được kiểm thử qua mock, chưa nghiệm thu gửi qua từng ứng dụng trên điện thoại thật.
- Đã build lại Web/backend và kiểm tra trang/API khám phá/AI trên **môi trường kiểm thử**; JavaScript public trùng bản mới. AI 181 từ và LM Studio nền tiếp tục chạy. Chưa build APK mới; APK cũ cần build/cài bản mới để có các nút này.

## Công việc phiên 27–28/10/2026 — Bộ sưu tập ký hiệu

- Đã viết [phân tích thiết kế](docs/SIGN_COLLECTIONS_DESIGN.md) và thay tab **Từ của tôi** bằng **Bộ sưu tập**. Tạo/sửa/xóa bộ theo tình huống, chọn nhiều ký hiệu có sẵn, tìm kiếm/phân trang, lưu từ màn hình chi tiết từ điển và viết ghi chú riêng. Thẻ riêng cũ vẫn nằm trong menu **Thẻ riêng đã tạo**.
- Ôn bộ bằng quiz xem ký hiệu rồi nhập nghĩa, tối đa 10 từ nhiều chủ đề; dùng chung tiến độ theo từ, tiếp tục bài dở và giữ cảnh báo khi thoát. Chỉ tự nhớ đúng mới được ghi nhận độc lập; gợi ý/tự đối chiếu được tách riêng. Bỏ mô tả dataset chung ở phần đối chiếu; tải trước media có giới hạn và dùng lại phản hồi bắt đầu bài, giảm yêu cầu lặp. Bộ nhận diện camera **181 từ giữ nguyên**.
- Chia sẻ bằng mã/liên kết có thể thu hồi; xem trước công khai và lưu bản độc lập vào tài khoản. Không chia sẻ email, ghi chú, tiến độ hoặc thẻ riêng. Nhập cùng bộ nhiều lần không tạo trùng; đăng nhập từ liên kết giữ trang quay lại.
- Backend lưu ID từ chuẩn thay vì nhân bản video. Thêm index theo chủ tài khoản, mã chia sẻ và ghi chú; truy vấn theo lô, giới hạn 10 mục/trang, 100 bộ/tài khoản, 200 từ/bộ. Ghi trong transaction, chấm quiz theo lô và không ghi đè tiến độ mới hơn. Xuất/xóa dữ liệu tài khoản bao gồm bộ sưu tập và ghi chú. Cache client ngắn hạn, giới hạn số trang, gộp yêu cầu đang chạy, tách tài khoản và loại phản hồi cũ.
- Đồng bộ media bằng [sync-sign-library.ps1](scripts/sync-sign-library.ps1): xác minh ZIP/checksum trước, giữ ID từ, URL media theo hash và metadata từng phiên bản. Bài ôn dở bị ảnh hưởng được yêu cầu bắt đầu lại; điểm bài đã nộp, ghi chú và tiến độ vẫn giữ. Các màn hình dùng cùng từ điển chuẩn, kiểm tra phiên bản khi mở/quay lại và mỗi 60 giây khi đang hoạt động. Văn bản → Ký hiệu giữ văn bản khi tải lại media.
- Đã kiểm tra gói media hiện có: **3.424 mục, 3.423 video, 17.115 ảnh**, checksum đạt. Chưa áp dụng gói này vào database thật trong phiên làm việc này.
- Kiểm chứng: **378 kiểm thử Flutter đạt, 1 bỏ qua**; **255 kiểm thử backend / 36 file đạt** trên MongoDB tạm, kèm **29 kiểm thử hồi quy đạt** sau chỉnh sửa backend cuối; **5 kiểm thử installer đạt**. OpenAPI hợp lệ, **136/136 API được ghi nhận có tài liệu**; phân tích mã Dart và TypeScript đạt. Đã xem 8 ảnh render sáng/tối; kiểm tra bố cục 320×640, 844×390 và 800×1024 với chữ 2×, bàn phím, lỗi mạng, lựa chọn qua nhiều trang và phản hồi cũ. Không xem kiểm thử mô phỏng là đo tốc độ trên điện thoại thật.
- Mốc trước khi mở Web lại ngày **28/10**: đã tắt tunnel kiểm thử và AI theo yêu cầu; lúc đó mới hoàn thành mã nguồn/kiểm thử, chưa phát hành lại Web/APK. Sau yêu cầu chạy Conveyor và bật AI mới, trạng thái được cập nhật ở mục **Mở lại bản Web kiểm tra** phía trên. Các ghi chép bên dưới là thông tin lịch sử.


## Cập nhật trên máy hiện tại — 27/10/2026

- **Cá nhân → Chỉnh sửa hồ sơ → Đăng nhập & bảo mật** chứa Liên kết Google và Đổi mật khẩu. Đã kiểm tra lại luồng đổi mật khẩu cho USER/STAFF/ADMIN.
- LM Studio chạy nền bằng **llmster**, model Qwen3-4B-Instruct-2507 Q4_K_M, API nội bộ `http://127.0.0.1:1235/v1`. Bật lại sau khi khởi động máy bằng `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-learning-lmstudio.ps1`. Không cần mở Bionic, không cần build lại APK chỉ để bật AI. [Hướng dẫn LM Studio](docs/LMStudio-learning-progress.md#máy-hiện-tại-chạy-nền).
- Phân tích và gợi ý đã trả lời bằng model thật; các yêu cầu AI trùng đang chạy được gộp, không chia sẻ giữa tài khoản hoặc tiến độ đã thay đổi. 31 kiểm thử liên quan đạt; phân tích mã các file sửa đạt.
- Sửa lỗi chờ phân tích lâu qua điện thoại: APK gửi tác vụ nền và lấy trạng thái bằng yêu cầu ngắn, có thử lại khi mạng/gateway gián đoạn. Kết quả chỉ trả cho chủ tài khoản; giới hạn tác vụ và tự hết hạn sau 5 phút. Đạt 304 kiểm thử Flutter (1 bỏ qua) và 225 kiểm thử backend trên MongoDB tạm; giữ tương thích API gọi đồng bộ cũ.
- Phiên kiểm thử trước đã hết hạn và đã được mở lại. Ứng dụng cần dùng cấu hình môi trường hiện hành. Google Android giữ nguyên client và SHA-1; nếu dùng Google trên web, thêm callback của tên miền mới trong Google Cloud.

## Tối ưu API và Google Android — 26/10/2026

- API dùng lại kết nối, gộp các GET trùng đang chạy và giảm truy cập kho khóa Android; không lưu cache quyền. Thống kê dùng hai truy vấn tổng hợp thay cho mười truy vấn đếm. Dashboard tải song song; danh sách tài khoản hiển thị ngay khi có dữ liệu, không chờ danh sách role. JSON GET lớn được nén, dữ liệu cá nhân vẫn `no-store`.
- Google Android dùng Credential Manager và ID token được backend xác minh cùng nonce một lần, hết hạn sau 5 phút. Tài khoản email có sẵn cần vào **Cá nhân → Chỉnh sửa hồ sơ → Liên kết Google**, chọn cùng email, rồi dùng Google đăng nhập từ lần sau; giữ nguyên ID, mật khẩu, quyền và dữ liệu học. Liên kết Google và Đổi mật khẩu được gom trong mục Đăng nhập & bảo mật ở cuối màn hình chỉnh sửa.
- Cấu hình Google cần Web client và Android client cùng project. Android client dùng package `com.example.sign_voice` và SHA-1 của khóa ký APK; đổi Conveyor không đổi SHA-1. Thay URL Conveyor cần build lại endpoint API/AI, đồng thời cập nhật callback của luồng web. Xem [hướng dẫn OAuth](docs/OAUTH_SETUP.md).
- Kiểm tra tự động: 299 Flutter tests đạt, 1 bỏ qua; 220 backend tests đạt trên MongoDB tạm. Đo truy vấn thống kê tại máy: trung vị khoảng 334 ms trước và 41 ms sau (không bao gồm xác thực/HTTP/Conveyor). Đăng nhập Google bằng tài khoản thật cần xác nhận tiếp trên điện thoại.

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

### Điều chỉnh màn hình giọng nói ngày 25/10/2026

- Hướng dẫn cấp quyền được rút gọn để vừa phía trên các nút trên điện thoại 375×812; nội dung vẫn cuộn được khi dùng chữ lớn/màn hình ngang.
- Chỉnh sửa văn bản ngay trong khung kết quả, có Lưu/Hủy và kiểm tra nội dung trống; bàn phím không bị footer chiếm chỗ.
- TTS thử `vi-VN`, `vi` và giọng Việt mà engine liệt kê. Khi thiết bị thiếu giọng Việt, nút **Cài giọng tiếng Việt** mở trình cài dữ liệu/cài đặt TTS Android; chọn tải Tiếng Việt rồi quay lại bấm Phát. Không tự tải giọng hoặc chuyển văn bản sang dịch vụ ngoài. Máy chưa có engine/giọng phù hợp vẫn cần cài dữ liệu trên thiết bị.
- 8 test mới cho hướng dẫn, sửa trực tiếp và TTS/recovery; toàn bộ 203 tests đạt, 1 test cũ bỏ qua. Log: `.runtime/speech-ui-*.log`.

### Video, lịch nhắc và hồ sơ trên Android — 26/10/2026

- Văn bản → Ký hiệu tải trước tối đa hai clip gần vị trí xem, chỉ một lượt tải trước chạy cùng lúc. Chuyển nhanh bỏ hàng đợi cũ, giải phóng video trả về muộn; ảnh xem trước dùng chung cache và giữ trong lúc video đang tải.
- Giữ lịch Android không thay đổi khi mở lại ứng dụng, tránh hủy lời nhắc đang chờ rồi chuyển sang tuần sau. Đặt lịch trên máy độc lập với đăng ký push; kiểm tra lại các lịch đã cài. Màn hình lịch hiển thị lần nhắc tiếp theo, quyền nhắc đúng giờ, kênh bị tắt và nút thử nhắc sau một phút.
- Đọc lại giọng Việt và kết nối lại bộ đọc khi trở về từ cài đặt; tìm bộ đọc tiếng Việt trong các bộ đã cài trước khi báo không dùng được. Không tự phát tiếng sau khi quay về cài đặt.
- Avatar hiện ngay từ thông tin đăng nhập, cache riêng theo tài khoản tối đa 512 KB và xóa khi đăng xuất. Dùng hồ sơ đã đồng bộ khi mở trình sửa; đổi ảnh không gọi lưu màu không đổi hoặc lấy lại hồ sơ lần nữa.
- Kiểm tra: 278 Flutter tests đạt, 1 bỏ qua; analyze không có vấn đề. Log: `.runtime/mobile-reliability-*.log`. Chưa đo trực tiếp trên điện thoại thật; lịch nhắc vẫn cần quyền và cài đặt hoạt động nền phù hợp trên máy.
