# Camera public: chậm khởi động trên điện thoại

Đã đối chiếu video `1792411633723_49545263168060327_3028160589505783569.mp4` (51,24 giây) và hai trace lúc 19:05–19:07 ngày 19/10/2026. Video chỉ dùng kiểm thử, không đưa vào TRAIN.

## Nguyên nhân có bằng chứng

- `20261019T120533Z_e587274d.npz`: 67 khung đều dùng CPU dự phòng; worker bị hủy ở giai đoạn `model` sau 30.002 ms.
- `20261019T120706Z_08700a3d.npz`: 20 khung CPU rồi 84 khung browser GPU; khởi tạo 15.650,6 ms. Cuối trace, detector báo 20,53 FPS và 33,2 ms xử lý. Đây là số của phiên cũ, không phải benchmark bản sửa.
- Tải model và WASM nối tiếp qua tunnel, không nén. Model 7.819.105 byte, WASM SIMD 11.453.626 byte. Deadline cũ hủy worker ngay cả khi chỉ đang tải chậm.

## Thay đổi

- Nén gzip một lần lúc máy chủ khởi động bằng zlib có sẵn; không nén lại mỗi request hay thêm package. Giữ Content-Type WASM, Vary, ETag và conditional GET. Chỉ phục vụ danh sách file detector cố định; cache 24 giờ.
- URL tài nguyên dùng phiên bản 8.2 để tách khỏi cache cũ. Nếu thay SDK hoặc hand model, phải đổi phiên bản các URL tương ứng.
- Tải model đồng thời với runtime/WASM đã chọn. WASM được làm nóng HTTP cache trước khi SDK dùng nó. Không tải cả bản SIMD và no-SIMD.
- Preload model ngay khi trang mở, trước khi người dùng mở camera; không truy cập camera hoặc xin quyền sớm.
- Chờ tải/khởi tạo tối đa 120 giây, giữ CPU dự phòng trong lúc tải. Watchdog xử lý khung hình vẫn là 10 giây lần đầu, 3 giây các lần sau. Đây là thời hạn lỗi, không phải thời gian chờ dự kiến.
- Bỏ thao tác reset kích thước canvas mã hóa mỗi khung hình nếu kích thước không đổi. Giữ cơ chế chỉ xử lý ảnh mới nhất và vẽ landmark trước JPEG/network.
- Không thay trọng số, ngưỡng nhận diện hay bộ 181 từ. LM Studio không được bật lại.

## Kiểm tra đã chạy

- Worker Node: 14/14 qua, gồm regression tải model trong khi runtime còn chờ, preview trước JPEG và cặp ảnh/landmark đúng timestamp.
- Backend: 10/10 qua (hosting + proxy HTTP/WSS); kiểm tra gzip giải nén đúng byte, cache, conditional 304 và response không gzip.
- Flutter camera/config/UI: 13/13 qua; Dart analyze file tracker không có vấn đề.
- TypeScript build và Flutter release web build thành công; SHA-256 worker source khớp file build/public.
- Qua Conveyor, WASM truyền 3.372.317 byte, giải nén khớp toàn bộ file 11.453.626 byte. Model gzip 5.825.846 byte. Tổng hai tài nguyên từ 19.272.731 xuống 9.198.163 byte (~52,3%).
- Một lượt đo qua cùng public URL: WASM cũ không nén 17,61 giây; bản nén 3,76 giây. Hai request khác thời điểm, không phải phép đo FPS hay thời gian mở camera trên điện thoại.
- Public HTTPS health và WSS gửi JPEG/nhận `frame_received`, `result` đều thành công với 181 từ. URL đang chạy: https://lastaquatree3.conveyor.cloud.

Chưa đo lại điện thoại thật sau sửa. Kiểm thử Chrome tự động bị cơ chế duyệt công cụ từ chối cho phép chạy. Vì vậy chưa khẳng định FPS hay độ chính xác đã tăng. Trên điện thoại, đóng trang cũ rồi mở lại URL; không xóa cache giữa các lượt nếu muốn kiểm tra lợi ích cache. Theo dõi thời gian khởi tạo và FPS landmark trong cài đặt camera.

## Lượt sửa 8.3: lần đầu và chuyển một/hai tay

Video tiếp theo: `1792413288525_49545263168060327_3028160589505783569.mp4` (45,72 giây). Trace `20261019T123137Z_773de090.npz` ghi khởi tạo 23.474,3 ms; các phiên sau ghi 508,4 ms, 2.081,3 ms và 476,9 ms. Vì vậy đã có bằng chứng về chênh lệch giữa cold/warm startup, nhưng chưa có bằng chứng đạt dưới 10 giây trên điện thoại trong lần tải đầu.

- Ưu tiên tài nguyên trực tiếp từ Google Storage (hand model float16 version 1) và jsDelivr (Tasks Vision cố định 0.10.32); bản local đã nén vẫn giữ làm dự phòng. Byte model, WASM và loader JavaScript đối chiếu trùng bản vendored, không đổi hand detector hay feature dimensions.
- Kiểm tra cache local trước để người đã tải bản 8.2 không phải tải lại. Khi chưa có cache, thử nguồn trực tiếp; sau 1,5 giây bắt đầu đường local dự phòng nếu nguồn trực tiếp chưa hoàn tất. Lấy bản hoàn tất đầu tiên và abort lượt còn lại. Nếu CDN lỗi ngay, local bắt đầu ngay. Các tài nguyên công khai được tải; ảnh camera vẫn gửi về AI service riêng qua đường public cũ.
- Preconnect Google Storage/jsDelivr và preload model từ khi trang mở. CSP cho phép loader SDK từ jsDelivr; nguồn được khóa phiên bản. Worker URL 8.3, tài nguyên local không đổi nên giữ phiên bản cache 8.2.
- Giảm phạm vi gộp quan sát gần trùng: trước đây hai bàn tay hợp lệ cách nhau 0,03 chiều rộng ảnh vẫn có thể bị gộp thành một. Vẫn loại quan sát gần như trùng hoàn toàn.
- Đồng bộ bộ lọc trình duyệt và Python: vùng ngang quanh người ký rộng hơn để giữ tay thứ hai giơ sang bên; ngưỡng kích thước dự phòng khi không có mốc mặt từ 0,055 xuống 0,025 để không làm mất tay nắm lại. Đây là thay đổi chọn quan sát, không thay tọa độ/normalizer/nhãn/trọng số model. Vùng rộng hơn cần kiểm tra thêm trong cảnh có người khác phía sau.
- Trace ghi thêm `asset_load_ms`, `detector_init_ms`, `raw_hands`, `rejected_hands` để phân biệt tải chậm, tạo detector chậm, SDK không bắt tay và bộ lọc loại tay. Không tạo landmark giả khi tay bị che.
- Sửa UI che landmark dự phòng: khi `LocalHandObservation` chỉ là trạng thái `initializing` với danh sách rỗng, giao diện được vẽ các điểm đo thật từ service. Banner khởi tạo vẫn giữ. Sau khi local tracker hoạt động, không cho kết quả service đến trễ vẽ đè hoặc hồi sinh điểm local đã cũ.
- Kiểm thử: 20 worker, 47 Python, 10 backend qua; các ca mới gồm 1→2→1 tay, hai tay ở gần nhau, tay gập khi mốc mặt hết hạn, CDN bị chặn, cache có sẵn và hủy nguồn tải chậm.
- Flutter: 19 kiểm thử camera/config/stream/UI qua; regression xác nhận điểm dự phòng hiển thị trong khi tải và vẫn xóa điểm cũ sau khi local tracker chạy. Dart analyze không có vấn đề. Web release build và health/WSS public đã kiểm tra với đúng runtime/adapter mới, bộ 181 từ không đổi.

Tài liệu API đã đối chiếu: [MediaPipe Hand Landmarker Web](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/web_js). Thời gian tải thực tế phụ thuộc mạng và thiết bị; không xem các số đo tải từ máy tính là benchmark cold startup trên điện thoại.
