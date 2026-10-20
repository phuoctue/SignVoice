# Chữ cái có chuyển động và ký hiệu liên tiếp — worker 8.4

Video kiểm tra: `1792419391778_49545263168060327_3028160589505783569.mp4`, 33,99 giây. Giao diện trong video có nhận tư thế `a`, `e` nhưng không chốt được các chữ có dấu người dùng đang thử. Video chỉ dùng kiểm thử; không đưa vào TRAIN hay chỉnh trọng số/ngưỡng theo video này.

## Lỗi mã nguồn và giới hạn bằng chứng

- Giao diện có landmark tại điện thoại, nhưng nhận diện chuỗi chỉ nhận các khung JPEG được gửi thành công. Khi JPEG/network bỏ khung, các điểm ở giữa không đến `GestureBuffer`. Nhánh chữ động yêu cầu ít nhất sáu mẫu và đoạn chuyển động đầy đủ; tư thế tĩnh vẫn có thể nhận dù thiếu đoạn này. Không có trace của phiên 21:15 vì service sau khởi động trước đó chưa bật `AI_TRACE_DIR`, nên chưa đo được FPS phía AI của chính phiên này.
- `CompletedSignHold` trước đây chỉ xét hình dạng bàn tay, có thể tiếp tục khóa kết quả dù cổ tay đã di chuyển để bắt đầu ký hiệu mới.
- Service chống lặp theo tên chữ; một completion mới có cùng tên chữ không tạo event mới nếu tay chưa biến mất hơn 0,65 giây. Ký tự tĩnh cũng chưa được rearm sau một khoảng thật sự không nhận diện, khi tay vẫn còn trong hình.
- Lời gọi bộ lọc ở service còn truyền cứng `.055`, ghi đè mức dự phòng `.025` đã sửa ở lượt trước. Đã bỏ tham số ghi đè này để dùng đúng bộ lọc chung.

## Thay đổi

- Trong chế độ **Chữ cái/Chữ số** trên web, worker giữ tối đa 32 quan sát đo thật trong hai giây, khoảng 15 mẫu/giây. Mỗi JPEG mang thêm lịch sử XYZ/handedness với timestamp gốc. Khung cũ bị thay trong hàng đợi JPEG không làm mất toàn bộ các bước chuyển tư thế. Không nội suy hoặc tạo thêm bàn tay.
- SDK/model hand detector, 126 pose + 8 wrist, normalizer, model 181 từ và các ngưỡng phân loại giữ nguyên. Chế độ Từ/Tất cả không dùng lịch sử này vì thiếu phép đo mặt tại các ảnh trung gian; không lấy ảnh hiện tại giả làm ảnh quá khứ.
- Protocol vẫn gửi JPEG hiện tại cho OpenCV và mốc mặt. Lịch sử là quan sát landmark, không tự nhận có pixel đi kèm. Mỗi mẫu được kiểm tra model/SDK, số tay, tọa độ hữu hạn, timestamp tăng dần và tuổi tối đa hai giây. Header tối đa 128 KiB, tổng packet tối đa 4 MiB. Service bỏ mẫu đã xử lý khi lịch sử hai gói chồng lấn.
- Tracker nhận lịch sử trước frame hiện tại theo thứ tự thời gian. Context mặt của mẫu lịch sử được mask là không biết. Chỉ nhánh chữ/số sử dụng lịch sử; OpenCV vẫn xử lý pixel của ảnh hiện tại.
- Giữ chống lặp khi giữ nguyên tư thế. Cho phép ký hiệu mới giải phóng hold bằng thay đổi hình tay hoặc dịch cổ tay đủ lớn; nhiễu cổ tay nhỏ không giải phóng. Chữ tĩnh được rearm sau khi quyết định đã hết hiệu lực trong một khoảng thật sự không nhận diện.
- Service phát lại cùng nhãn khi có completion mới được xác minh, đồng thời kết quả hiện tại còn đáng tin, đúng mode và mới. Poll lặp cùng completion không phát thêm event. UI không bị tự động chèn các ký tự đoán top-2/top-3.

## Kiểm tra

- 21 worker tests qua, gồm việc giữ đủ 12 mẫu trung gian dù encoder chỉ trả các ảnh đầu/cuối.
- 54 Python tests qua; 15 tests trực tiếp policy/history/worker đã chạy lại sau giới hạn rearm chỉ cho chữ/số. Bao gồm header có lịch sử, timestamp tương lai/sai thứ tự/NaN/quá số lượng, lịch sử không xử lý trùng, giữ nguyên tư thế, dịch cổ tay để bắt đầu mới, và phát cùng chữ ở completion khác.
- 19 Flutter tests qua; Dart analyze không có vấn đề. Web release build thành công; worker source và build cùng SHA-256.
- Sau triển khai, gói WSS public có header 20.006 byte được nhận thành công; service nhận 12 mẫu lịch sử ở gói đầu và 0 mẫu trùng ở gói sau. Đây là phép thử protocol bằng dữ liệu giả lập, không phải kiểm tra accuracy; trace của phép thử đã chuyển riêng sang `.runtime/smoke-replays`.
- Kiểm tra thêm từ vùng camera trong video màn hình: re-extract được 412 mẫu, nhưng nhiều khung mất tay và nét vẽ landmark/OpenCV đã nằm trong ảnh. Chạy nhánh hiện tại ở hai mật độ cho kết quả khác nhau và vẫn có nhầm chữ. Đây chỉ là kiểm tra đường xử lý; **không phải accuracy webcam, không chứng minh đã nhận đúng chuỗi ă/â/ê/ô/ơ/ư**.
- Số template trong export cũng không đều: `ê`, `ô` có bốn; `ơ`, `ư` có ba. `â` có 160 template, trong đó 155 ghi nhận hai tay; chưa đối chiếu video nguồn để kết luận chúng đúng/sai biến thể. Không sửa/xóa template hoặc bỏ điều kiện hai tay để ép kết quả khớp video TEST.

Đo lại trên điện thoại sau triển khai vẫn cần thiết. Chọn **Chữ cái**, thử các chữ động khác nhau rồi lặp lại cùng một chữ có một lần bắt đầu động tác mới. Bộ lọc không biến một tư thế giữ yên thành nhiều lần nhập chữ. Service của lượt này bật trace đặc trưng giới hạn để đối chiếu lần test sau; không lưu ảnh camera vào trace và không dùng trace để train.

## Kiểm tra bổ sung với video 1792421580981 (lượt tiếp theo)

Trace phiên `20261019T145253Z_4f952957.npz` ghi nhận 516 quan sát trong khoảng 49 giây, nhưng chỉ 62 ảnh/kết quả camera. Backend có chốt `ô`, `ă`; không phải hoàn toàn không chạy phân loại. Khoảng cách giữa các JPEG trung vị khoảng 0,81 giây. Kết quả mô hình thường đã cũ khoảng 1,4 giây khi ảnh tiếp theo kéo nó ra service.

Hai lỗi giao nhận được sửa:

- `RecognitionWorker` đánh thức publisher khi hoàn tất; service gửi kết quả ngay, độc lập ảnh JPEG kế tiếp. Mỗi session vẫn có một owner executor cho MediaPipe; không chặn capture để chờ model. Số thứ tự publication ngăn kết quả cũ ghi đè kết quả mới. Không thay model/threshold, không thêm LM vào nhận diện.
- Service trước đây loại kết quả sau 1.500 ms kể cả `LiveSession` vẫn đang giữ tư thế cuối hợp lệ. Nay chỉ cho phép giữ quá thời hạn khi worker đã xử lý quan sát tay hiện tại và xác nhận hold còn hoạt động. Mất tay, hold đã nhả hoặc worker chưa bắt kịp quan sát mới không được dùng để hồi sinh kết quả cũ. Refresh trễ hơn hai giây sau khi ngừng nhận ảnh không được phát.

Trace gắn kết quả trả trễ vào đúng mẫu đo thật, không nhân đôi dữ liệu landmark. Các kiểm thử mới bao gồm WebSocket chỉ gửi một ảnh nhưng vẫn nhận được completion sau đó, giữ chữ khi tư thế cuối hợp lệ, loại hold chưa cập nhật/mất tay, chống lặp event và giữ số mẫu trace không đổi. Đây là kiểm tra logic/giao nhận; chưa chứng minh accuracy hoặc FPS của điện thoại tăng.

Xác minh sau sửa: toàn bộ 60 Python tests qua. WSS public `https://newtanboard42.conveyor.cloud/sign-ai/v1/stream` nhận một packet có 12 quan sát lịch sử, gửi kết quả ảnh rồi gửi publication mới với `observation_timestamp_ms=1200` mà không cần ảnh thứ hai. Health khớp SHA-256 mã engine/runtime trên đĩa, manifest model 181 từ giữ nguyên, trace đang bật. Gói smoke được chuyển riêng sang `.runtime/smoke-replays`; không dùng làm dữ liệu camera/accuracy. Không sửa Flutter ở lượt này nên không cần build lại giao diện.

## Tối ưu thời gian nhận diện sau phản hồi phải giữ tay 3–5 giây

- Trace mới nhất ở mode chữ ghi nhận inference trung vị khoảng 504–534 ms, P90 khoảng 748–750 ms. Dwell code chỉ 0–250 ms tùy ký hiệu; không có timer cố định bắt buộc giữ 3–5 giây. Thời gian hoàn tất trên điện thoại còn phụ thuộc mạng, mẫu chuyển động, mất tay và điều kiện kết thúc.
- Profiler xác định DTW/copy template và gom điểm theo lớp là các phần tốn thời gian. Runtime service hiện tái sử dụng bank template cùng squared norms trong session; đổi mode xóa cache. Phép max theo lớp dùng NumPy indexed reduction, giữ nguyên cả điểm âm dưới -1, lớp không có mẫu và NaN.
- Bước DTW của chữ được bỏ qua khi endpoint chưa ổn định và không có lớp động đang active nào có thể vượt chính readiness gate cũ. Điều kiện endpoint, score, margin và dwell không hạ. Mode từ vẫn giữ các kiểm tra chuyển động/coverage hiện tại.
- Thử cách tính DTW theo đường chéo band cho kết quả gần nhau nhưng chậm hơn (~403 ms so với 111 ms ở phép đo riêng), nên không áp dụng.
- Đối chiếu 9 cửa sổ từ hai trace thực tế, mỗi trường hợp đo 3 lần, so sánh với runtime trước sửa: toàn bộ vector điểm và readiness mask giống hệt từng phần tử. Trung vị các thời gian xử lý mỗi trường hợp: 652,8 ms trước, 326,0 ms sau. Một cửa sổ endpoint đang chuyển động: 733,0 ms xuống 21,8 ms. Số liệu là CPU service, không phải thời gian từ camera tới màn hình; chưa chứng minh độ chính xác hay độ trễ điện thoại theo một mục tiêu cụ thể.
- Toàn bộ 63 Python tests qua. Chi tiết phép đo ở `.runtime/letter-latency-benchmark.json`, script `.runtime/benchmark-exact-matching.py`. Trace chỉ dùng đối chiếu hành vi/tốc độ; không dùng TRAIN, chọn threshold hay chứng minh tăng accuracy. Bộ model 181 từ và hai mạng đã train giữ nguyên.
