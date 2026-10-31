# Quản lý bộ sưu tập công khai — 29/10/2026

## Kế hoạch thực hiện

1. Thêm quyền `collections:read`, `collections:moderate` cho ADMIN/STAFF mặc định; role tùy chỉnh phải được cấp rõ. Giữ hạn chế tài khoản, role và phiên đăng nhập chỉ ADMIN.
2. Lưu trạng thái CLEAR / HIDDEN / BLOCKED, lý do, phiên bản và bản nội dung đã công khai (tên, ảnh, mô tả, ID từ thư viện). Không đưa từ riêng, ghi chú, tiến độ hoặc thông tin chủ tài khoản vào DTO quản trị.
3. API quản trị có tìm kiếm/lọc/phân trang 10 mục, chi tiết từ thư viện phân trang, báo cáo và lịch sử tải riêng. HIDDEN gỡ khám phá; BLOCKED chặn cả khám phá, link/QR và nhập bản sao. CLEAR khôi phục theo lựa chọn chia sẻ hiện tại của chủ bộ, không tự đăng lại bộ đã rút về riêng tư.
4. Người có tài khoản chính thức báo cáo nội dung đang được chia sẻ bằng mã hợp lệ; mỗi người chỉ có một báo cáo mở mỗi bộ. Không tự chặn bộ chỉ vì nhiều báo cáo. Nhân viên giải quyết báo cáo với lý do và lưu lịch sử.
5. Kiểm duyệt và lịch sử ghi cùng transaction; kiểm tra phiên bản để tránh ghi đè thao tác mới. Bản đã công khai dùng riêng cho kiểm duyệt; khi bộ bị chặn, chủ bộ chỉnh sửa rồi chủ động gửi lại để kiểm tra. Không xóa dữ liệu gốc hoặc bản sao đã lưu khi kiểm duyệt.
6. Giao diện: mục trong tab Quản trị; danh sách gọn, trạng thái bằng chữ, bộ lọc, tìm trên server; xem trước khi xử lý. Form lý do có xác nhận, lỗi tại chỗ, chặn bấm lặp, giữ nội dung khi lỗi. Nút báo cáo ở bản xem trước; chủ bộ thấy lý do và cách gửi lại.
7. Kiểm thử backend bằng MongoDB tạm: quyền, riêng tư, vòng đời ẩn/chặn/khôi phục, chống vượt chặn, báo cáo trùng, xung đột phiên bản, lịch sử nguyên tử, phân trang và tham chiếu từ điển. Kiểm thử Flutter thao tác, lỗi, chữ 2×, bàn phím, màn hình hẹp/ngang/sáng/tối.
8. Cập nhật OpenAPI/README, build Web/backend và kiểm tra Conveyor. Không build APK, không push git trong đợt này.

## Thiết kế và giới hạn

Giữ theme, font và Material của SignVoice. Hai lần truy vấn design-system của ui-ux-pro-max trả bố cục landing không phù hợp nên không áp dụng/persist. Dùng mặc định native của skill (vùng chạm ≥48 dp, khoảng cách 12 dp, danh sách lazy, thoại cuộn, chữ lớn) và kết quả UX đã đối chiếu về xác nhận và phản hồi thành công.

Lịch sử dùng AuditLog hiện có (giữ tối đa một năm theo TTL hiện tại); tên người xử lý và vai trò được ghi tại thời điểm thao tác. Báo cáo chỉ hiện nội dung/lý do/thời gian, không hiện danh tính người báo cáo cho nhân viên. Các lựa chọn quản trị không thay đổi nhận diện AI 181 từ hay từ điển chuẩn.

## Kết quả thực hiện

Đã triển khai các bước 1–8, tài liệu API gồm 152/152 route. Bộ kiểm thử toàn hệ thống đạt 432 Flutter (1 bỏ qua) và 266 backend / 38 file; các kiểm tra backend chạy trên database tạm. Bổ sung bộ lọc chờ kiểm tra lại và kiểm tra khôi phục từng mức, không mở lại link của nội dung đã đổi khi chưa gửi bản mới. Bộ ảnh kiểm tra có 14 màn sáng/tối; kiểm thử bố cục bao gồm chữ 2×, bàn phím, 320 px, ngang và tablet. Web/backend đã cập nhật và kiểm tra qua https://longredrock50.conveyor.cloud lúc 08:55 ngày 29/10, giữ AI/LM Studio hoạt động; không thay đổi APK trong lần triển khai này.
