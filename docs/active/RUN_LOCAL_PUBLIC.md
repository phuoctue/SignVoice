# Chạy SignVoice local và public

Mở PowerShell tại `E:\WorkSpace\SignVoice\SignVoice`. Yêu cầu đã cài dependencies
backend/Flutter và model AI bằng hướng dẫn setup hiện có.

## Một lệnh mỗi chế độ

```powershell
.\scripts\start-signvoice.ps1 Local
```

Mở `http://localhost:3002`: giao diện release + backend và media cùng origin,
AI chạy riêng cổng8001. Không cần Conveyor hoặc mở thêm terminal. Vẫn cần mạng
cho MongoDB cloud và dịch vụ nhận giọng nói khi thiết bị yêu cầu.

```powershell
.\scripts\start-signvoice.ps1 Public
```

Script build giao diện release và backend, chạy server3001, AI8001, Conveyor,
in link HTTPS để mở trên điện thoại. Reuse AI đang đúng model; không chạy hai model.
Giữ máy chủ hoạt động khi dùng link public. Lệnh public cũ vẫn dùng được:
`.\scripts\start-public-server.ps1`.

Đã có build và chỉ muốn bật lại server, không lấy thay đổi source mới:

```powershell
.\scripts\start-signvoice.ps1 Local -SkipBuild
.\scripts\start-signvoice.ps1 Public -SkipBuild
```

Hai dòng là hai lựa chọn, không phải bắt buộc chạy cả hai. Bản build dùng chung
`build/web` với `/api/v1` và `/sign-ai`, nên dùng được ở cả local3002 và public.
Muốn cập nhật source, chạy lại lệnh không có `-SkipBuild`, rồi tải lại trang.
Nếu đồng thời build cả hai chế độ, hãy chạy tuần tự để tránh ghi cùng thư mục build.

## Dừng

```powershell
.\scripts\stop-public-server.ps1 -Local
```

Dừng server local3002, giữ AI để không ảnh hưởng chế độ khác.

```powershell
.\scripts\stop-public-server.ps1 -KeepServices
```

Dừng backend public3001, giữ AI và tunnel. Muốn dừng cả các dịch vụ do script
public quản lý, dùng `.\scripts\stop-public-server.ps1` khi không có app khác dùng AI.
Script không tự dừng AI/tunnel do người dùng mở riêng.

## Flutter debug để sửa code, r/R

Chạy riêng ba terminal khi cần debugger/hot restart:

Terminal 1, tại thư mục dự án:

```powershell
cd backend
npm run dev
```

Terminal 2, tại thư mục dự án:

```powershell
.\scripts\start-ai-service.ps1
```

Nếu AI8001 đã sẵn sàng, không cần mở thêm bản thứ hai.

Terminal 3, tại thư mục dự án:

```powershell
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3000/api/v1 --dart-define=AI_SERVICE_URL=http://localhost:8001
```

Không chạy lại Flutter nếu8080 đang dùng; nhấn `R` trong terminal Flutter hiện tại
để hot restart. Giao diện release từ lệnh gộp không có r/R.

## Ảnh/video mẫu

Giữ `.runtime/sign-library-media` trên máy backend. Flutter resolve URL media nội bộ
theo API đang cấu hình, nên luồng văn bản → ký hiệu không phụ thuộc link Conveyor
cũ đã lưu trong từ điển. Máy khác phải có kho media này, không chỉ model AI.
URL từ điển cũ dùng trực tiếp ngoài luồng này có thể vẫn cần chạy lại importer
nếu muốn thay hostname đã lưu. Không cần import lại để chuyển local/public ở màn
văn bản → ký hiệu.
