# Public SignVoice bằng một lệnh

Tại `E:\WorkSpace\SignVoice\SignVoice`:

```powershell
.\scripts\start-public-server.ps1
```

Script build web release với API `/api/v1` và AI `/sign-ai`, build backend, kiểm tra model đã chọn, dùng lại AI hợp lệ đang chạy hoặc mở service AI riêng, mở Conveyor nếu cần, đọc URL được cấp và khởi động server public cổng 3001. URL in cuối lệnh là URL hiện tại, có thể khác tên cũ mỗi khi tạo tunnel mới. Không cần chạy Conveyor hoặc Chay_AI_Service.bat riêng. Cần Node/npm, Flutter, database/backend đã cấu hình và môi trường Python AI đã cài như trước. Lần đầu trên máy chưa đăng nhập Conveyor, chạy `.\.tools\conveyor\conveyorcli.exe config -s` một lần.

Mở URL HTTPS được in trên điện thoại bằng Chrome → nhận diện → đồng ý màn xin quyền camera. Địa chỉ AI sẽ là `https://TEN.conveyor.cloud/sign-ai`. Chỉ khi đã build thành công bản mới và chưa đổi code mới dùng `-SkipBuild` để khởi động nhanh. `-NoTunnel` dành cho kiểm thử local; nó không tạo URL public dùng camera trên điện thoại.

Dừng các tiến trình do script quản lý:

```powershell
.\scripts\stop-public-server.ps1
```

Service AI hoặc tunnel đã bật thủ công trước đó được dùng lại và không bị dừng. Có thể dùng `-KeepServices` để giữ các service phụ khi dừng Node. Nếu một tunnel Conveyor bật thủ công mà script chưa biết URL, truyền `-PublicOrigin https://TEN.conveyor.cloud` một lần. Tắt tunnel thủ công nếu muốn script tự quản lý hoàn toàn.

## Kiến trúc

Điện thoại → HTTPS/WSS Conveyor → Node 3001 → HTTP/WebSocket loopback Python 8001. Node chỉ proxy, không nạp model. Python và backend vẫn là hai service riêng. Public proxy chỉ cho phép GET `/sign-ai/health`, POST `/sign-ai/v1/compose` và WebSocket `/sign-ai/v1/stream`; không proxy tùy ý sang host khác. Kiểm tra Origin ở edge, giữ xác thực token của AI nếu đã cấu hình. Origin của kết nối nội bộ được bỏ sau khi edge kiểm tra, nên service AI không cần thay danh sách Origin hay restart chỉ để dùng tunnel. URL public là đường dùng thử đang hoạt động, không phải APK hay triển khai server độc lập; máy tính cần bật và có mạng. Origin không thay thế đăng nhập hoặc bảo vệ URL khỏi người biết đường dẫn.

Conveyor CLI 3.10 gọi Console.Clear nên không chạy được với stdout redirect thông thường (`The handle is invalid`). Helper `scripts/conveyor-tunnel.py` dùng pywinpty 3.1.0 để cấp PTY và đọc URL; script tự cài dependency từ `scripts/requirements-public.txt` nếu thiếu. Không ghi tài khoản/mật khẩu vào mã. Trạng thái nằm trong `.runtime/public-server.json`, URL đã lưu ở `.runtime/public-settings.json`, log tunnel `.runtime/conveyor.log`, backend `public-server*.log`, AI do script mở `public-ai*.log`.

## Kiểm chứng 19/10/2026

- Build TypeScript thành công và web release thành công (148,5 giây). JS release chứa `/sign-ai`; hash model MediaPipe khớp bản nguồn.
- 10 kiểm thử Flutter qua; URL tương đối `/sign-ai` tạo WSS theo origin hiện tại, không giữ localhost của máy tính.
- 5 kiểm thử proxy qua, gồm HTTP/JSON, WebSocket đầu tiên, binary giữ nguyên, từ chối Origin lạ/host upstream ngoài loopback, và absolute-form URL do Conveyor chuyển tiếp. 4 kiểm thử web hosting qua trước đó.
- AI thật qua local proxy 3001: ready, 181 từ, ACK và result cho ảnh đen kiểm thử. Không gọi camera hoặc dùng ảnh người dùng.
- Đã kiểm tra tự khởi động AI ở cổng 8002 và dừng đúng tiến trình do script mở; AI 8001 đang chạy được giữ lại.
- Sau khi sửa absolute-form request, kiểm thử qua `https://lastaquatree3.conveyor.cloud/sign-ai/health` và WSS `/sign-ai/v1/stream` nhận ready/ACK/result thành công. URL này là tunnel của phiên thử hiện tại, không đảm bảo giữ nguyên sau khi tunnel được tạo lại.
- Đã thử khởi động lại launcher với `-SkipBuild`, dùng lại tunnel/AI và khởi động lại Node có quản lý. Chưa kiểm thử camera vật lý từ trình duyệt điện thoại; không tuyên bố FPS hay accuracy từ kiểm thử mạng.
