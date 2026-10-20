# Kiểm tra khả năng cài lại — 20/10/2026

Mã nguồn được push vào `phuoctue/SignVoice`, nhánh `dev`. Model runtime được phát hành riêng ở tag `models-181-camera640-v1`, không đưa dataset TRAIN/video TEST hoặc credentials vào Git.

## Model

- ZIP: `SignVoice_Runtime_181_camera640.zip`, **71,118,814 bytes**.
- ZIP SHA256: `6858cae5dcc6e4a531837305380016dbfa1fbe3f75abb8bee473858af798cc8b`.
- Manifest SHA256: `af23aa8892a736db57dedf4ac0e688cdc22da1fbe160dfbcd937e05da2f8609b`.
- 181 từ, `stable_two_hand_v6_camera640`, dùng cả TCN và embedding qua `probability_ensemble`.
- Bộ cài giữ nguyên lựa chọn model đã có trên máy; clone mới sử dụng model của Release. Bộ train mới ngày 20/10 chưa thay model này.

## Kết quả kiểm chứng

| Kiểm tra | Kết quả |
|---|---|
| Clone mới trực tiếp từ GitHub vào thư mục khác | Qua |
| Tải model qua URL Release public, không gửi token đăng nhập | Qua |
| Kiểm tra ZIP, từng file và manifest SHA256 | Qua |
| Python 3.11 venv sạch, không kế thừa system packages | Cài thành công, `pip check` qua |
| Nạp hai model trong môi trường sạch | `ready=true`, 181 từ, `probability_ensemble` |
| Service từ clone mới trên cổng thử riêng 8107 | Qua |
| WebSocket words/digits/letters/all, xử lý ảnh đen bằng pipeline thật | 4/4 qua |
| Python unit tests trong môi trường sạch | 76 qua |
| Flutter tests | 115 qua |
| JavaScript camera worker tests | 23 qua |
| Backend proxy/web hosting tests | 10 qua |
| Backend typecheck và build | Qua |
| Clone mới: `npm ci`, backend typecheck, `flutter pub get` | Qua |
| Flutter web release build | Qua; có cảnh báo dependency chưa hỗ trợ WASM, build JS vẫn thành công |
| Flutter analyzer | Không có lỗi; còn 2 warning và 40 lint/info ở code cũ |
| Script parser Windows PowerShell mặc định | Qua sau khi lưu UTF-8 BOM cho script tiếng Việt |

Hai lỗi ảnh hưởng máy mới đã được sửa trong bộ cài: phiên bản OpenCV Contrib phải khớp **4.11.0.86** trong manifest và script PowerShell tiếng Việt phải được đọc đúng encoding. Dependencies Python được khóa cả các gói phụ trong `requirements-lock.txt`; backend có `package-lock.json` để dùng `npm ci`.

Các bài kiểm tra ảnh đen chỉ xác nhận cài đặt, model, bộ dò, OpenCV và giao thức hoạt động. Chúng **không đo accuracy nhận diện ký hiệu hoặc FPS trên webcam/điện thoại thật**. Chưa chạy Docker MongoDB trên máy sạch và chưa build/kiểm thử APK mới trong lần đóng gói này. Máy người dùng vẫn cần cài prerequisites, cấu hình backend/database riêng và cấp quyền camera; xem [SETUP_AI.md](SETUP_AI.md).
