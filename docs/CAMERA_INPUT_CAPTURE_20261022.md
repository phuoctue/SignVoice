# Đối chiếu ảnh camera và landmark

Đã thêm chế độ ghi ảnh phục vụ tìm lỗi đầu vào. Chưa có bản ghi ảnh mới từ người dùng nên chưa kết luận ảnh/landmark đúng hay sai, và chưa thay model hoặc policy trong app.

## Cách ghi

1. Chạy app web với code mới. Nếu dùng `flutter run`, dừng phiên cũ rồi chạy lại để nạp cả worker JavaScript. Với bản public đã build, chạy lại `./scripts/start-public-server.ps1` không dùng `-SkipBuild`, rồi tải lại trang trên điện thoại.
2. Mở **Nhận diện ký hiệu → Cài đặt**, chọn chế độ **Từ/cụm từ**. Bật **Ghi chẩn đoán cục bộ**, rồi bật riêng **Kèm ảnh camera để đối chiếu** và bấm **Lưu**. App kết nối lại để bắt đầu phiên ghi mới.
3. Đợi camera sẵn sàng, làm lần lượt **chào → nghe → nhìn → rau**, nghỉ nhẹ giữa các từ; quay khoảng 20–25 giây. Không cần quay màn hình để đối chiếu khung hình lần này.
4. Mở cài đặt, tắt **Ghi chẩn đoán cục bộ**, bấm **Lưu**; mở lại cài đặt và chọn **Xuất bản ghi JSON**. Kiểm tra số ảnh > 0 trước khi xuất. Đừng bật lại ghi vì thao tác đó xóa bản ghi cũ trong RAM.
5. File chứa ảnh thật, có thể thấy khuôn mặt và không gian xung quanh. Chỉ chia sẻ file này khi muốn phân tích ảnh. Không đẩy vào Git hay tập đánh giá độc lập.

Hỗ trợ Chrome/web trên máy tính và điện thoại, bao gồm trang Conveyor. APK Android vẫn ghi chẩn đoán landmark như trước; tùy chọn ảnh này chưa hỗ trợ APK và bị khóa trên native. Chế độ ảnh không được bật hoặc lưu thành tùy chọn mặc định.

## Nội dung và giới hạn

- PNG không mất dữ liệu của canvas đã resize, cùng canvas được dùng cho lần dò tay; không phải ảnh chụp màn hình hay camera preview đã lật.
- Mỗi 2 giây lấy tối đa 1 ảnh, 15 ảnh trong 30 giây, hoặc khoảng 16 MB RAM phần ảnh (ước lượng chuỗi UTF-16); dừng khi chạm giới hạn đầu tiên. Nhật ký landmark có giới hạn riêng 12 MB. Tổng đối tượng JSON và chuỗi xuất có thể cần thêm RAM.
- Ảnh gắn timestamp, kích thước, XYZ/handedness trước và sau bộ lọc, delegate/model/SDK, face anchor tham chiếu và thời gian encode PNG. Không gửi PNG qua socket AI; chỉ chuyển nội bộ worker → app → file tải về khi người dùng xuất.
- Việc chụp PNG có thể làm thay đổi tải máy. Không dùng phiên này để tuyên bố FPS hoặc độ trễ bình thường.
- Dữ liệu nguồn XYZ thực sự gửi được ghi thêm để dựng lại thứ tự tay và chuẩn hóa trước model. Thiếu nguồn, tràn hàng đợi, nhiều generation hoặc nhật ký bị cắt thì không được kết luận parity.

## Kiểm tra cục bộ

Từ thư mục `E:\WorkSpace\SignVoice\SignVoice`, thay đường dẫn JSON bằng file vừa xuất:

```powershell
.\ai_service\.venv\Scripts\python.exe -m ai_service.check_camera_input "C:\Users\Phuoc Tue\Downloads\signvoice-camera-diagnostic.json" --model-dir ".\ai_service\models\181_2026_10_19_camera640" --output ".\.runtime\camera-input-report.json" --redetect
```

Công cụ kiểm checksum model/runtime, định dạng PNG, kích thước, timestamp, và tính lại pose/wrist từ XYZ qua bộ lọc + tracker đang dùng. Dung sai tuyệt đối `2e-5`; không tự sửa ảnh, đảo slot hay đổi ngưỡng để làm kết quả khớp.

`feature_conversion.comparable=True` và `passed=True` chứng minh XYZ → feature khớp trên chuỗi ghi được. Chưa chứng minh detector đúng hoặc webcam nhận đúng từ. `comparable=False` nghĩa là thiếu lịch sử để kiểm, không có nghĩa là model sai.

`--redetect` chạy cùng file bộ dò MediaPipe 0.10.32 bằng CPU ở chế độ IMAGE, đối chiếu với landmark gốc browser VIDEO theo phép ghép cặp khoảng cách nhỏ nhất. Khác biệt là số liệu mô tả; CPU không phải nhãn chuẩn, và ảnh lấy mẫu không tái tạo được trạng thái tracking VIDEO. Face anchor được tái sử dụng từ bản ghi, chưa đo parity từ pixel → face anchor.

JSON cũ không chứa ảnh không thể khôi phục PNG. Cần một phiên ghi mới có bật tùy chọn ảnh. Đây là dữ liệu phát triển, không phải TEST độc lập.

## Kiểm tra đã thực hiện

- Flutter analyze các file thay đổi: không có issue.
- 7 kiểm thử Dart (quyền ghi ảnh, giới hạn bộ nhớ, tách dữ liệu, pacing/timing), 26 kiểm thử worker JavaScript, 9 kiểm thử Python: đạt.
- CLI chạy xuyên suốt với bộ dò CPU MediaPipe thật trên fixture tổng hợp: đọc PNG, so sánh detector và khớp 4/4 đầu vào feature. Đây là kiểm thử công cụ, không phải kết quả nhận diện webcam.
- Build Flutter web debug thành công ở `.runtime/camera-input-qa-web`, tách khỏi thư mục public đang phục vụ. Chưa triển khai lại public trong bước này.
- Chưa thử ghi PNG trên camera điện thoại thật. Chưa có dữ liệu để khẳng định độ chính xác hay độ trễ nhận diện được cải thiện. Model, policy, service và notebook không thay đổi trong bước này.
