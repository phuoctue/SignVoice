# Hướng dẫn chạy SignVoice và LM Studio trên máy khác

Tài liệu dành cho Windows/PowerShell, dựa trên source SignVoice hiện tại. Các đường dẫn `D:\Projects\SignVoice` và `D:\Downloads\...` là ví dụ; thay bằng thư mục của máy nhận.

**Phương án chia sẻ LM Studio được sử dụng: hai máy cùng Wi-Fi/LAN.** Máy anh chạy LM Studio; máy khác chạy SignVoice và gọi AI qua IP nội bộ của máy anh. Cách chạy nhanh nằm ở phần 14.

## 1. Chọn cách sử dụng

| Nhu cầu | Cài trên máy nào? | Đọc phần |
| --- | --- | --- |
| Máy mới tự chạy Từ điển, tiến độ cá nhân và LM Studio | Source, Node.js, Flutter, MongoDB và LM Studio trên máy mới | 2–9 |
| Máy anh chạy LM Studio; máy khác cùng Wi-Fi tự chạy SignVoice | Máy anh cài LM Studio/model; máy khác cài dự án, dependency và cấu hình database riêng | 11.1 |
| Chạy cả nhận diện ký hiệu bằng camera và lệnh Local/Public có sẵn | Thêm Python 3.11 và bộ model camera | 10 |
| Máy anh chạy cả SignVoice và LM Studio; máy khác cùng mạng chỉ mở web | Cài dịch vụ trên máy server; máy khách chỉ cần trình duyệt | 11.2 |

Hai dịch vụ AI có mục đích riêng:

- **LM Studio / cổng 1235:** phân tích tiến độ học tập cá nhân bằng văn bản, model `qwen3-4b-instruct-2507`.
- **Dịch vụ Python / cổng 8001:** nhận diện ký hiệu camera. Chỉ cần khi dùng chức năng camera hoặc bộ script chạy gộp.

Giao diện gọi backend; backend mới gọi LM Studio. Trình duyệt không gọi trực tiếp cổng 1235. Ở phương án 11.1, backend trên máy khác gọi LM Studio trên máy anh qua LAN; ở phương án 11.2, backend và LM Studio cùng máy server.

## 2. Nhận đúng source và bộ media

### Source

Phải dùng bản source **đã nối LMS vào giao diện học mới**. Nhánh local `LMStudio` đã pull `dev` đến `390ca74` (giao diện Khám phá / Đang học / Từ của tôi và quiz camera). Thay đổi kết nối `SIGNVOICE_LM_STUDIO_*` sau khi pull vẫn chưa commit/push; lấy riêng `dev` chưa có cấu hình kết nối riêng này.

- Nếu phần LMS chưa được phát hành: nhận bản source do người phát triển cung cấp riêng.
- Nếu sau này nhánh LMS đã được push: lấy đúng nhánh/commit người phát triển thông báo. Không tự bỏ thay đổi local để chuyển nhánh.

Sau khi đặt source vào thư mục dự án, kiểm tra:

```powershell
Set-Location "D:\Projects\SignVoice"
Test-Path .\backend\src\services\learning-coach.service.ts
Test-Path .\backend\src\services\learning-analysis.service.ts
Test-Path .\lib\features\learning\learning_hub.dart
```

Cả ba phải trả `True`. Không sao chép `.env`, tài khoản tunnel, `node_modules` hoặc `.venv` của máy phát triển.

### Media

Nhận riêng **SignVoice-Media-20261024.zip** và đọc `README_VI.md` đi kèm. Git không chứa bộ ảnh/video từ điển.

Giải nén, mở terminal tại thư mục chứa `install-media.cjs` và `README_VI.md`, ví dụ:

```powershell
Set-Location "D:\Downloads\SignVoice-Media-20261024"
node .\install-media.cjs --verify-only
node .\install-media.cjs --project "D:\Projects\SignVoice"
```

Trình cài kiểm tra SHA256, giữ lại file giống nhau và từ chối ghi đè file khác nội dung. Nó chép media và metadata vào `.runtime` của dự án; chưa nhập dữ liệu vào MongoDB.

Sau đó phải có:

```powershell
Set-Location "D:\Projects\SignVoice"
Test-Path .\.runtime\sign-library-media
Test-Path .\.runtime\speech-sign-library\shared-20261024\library.json
```

Nếu có gói media khác ngày, ưu tiên đường dẫn và quy trình trong `README_VI.md` của đúng gói đó.

## 3. Cài công cụ và thư viện

Cho luồng Từ điển + LMS:

- Git nếu nhận source qua Git.
- Node.js **20 trở lên**, npm **10 trở lên**.
- Flutter có Dart thỏa `^3.13.2` trong `pubspec.yaml`, cùng Chrome hoặc Edge.
- LM Studio và runtime tương thích model tải về trên máy xử lý AI. Nếu dùng chung LM Studio theo phần 11.1, máy chạy SignVoice không cần cài LM Studio hoặc tải model GGUF.
- MongoDB **replica set** hoặc MongoDB Atlas riêng. MongoDB standalone không đủ cho các giao dịch của dự án.

RAM 16 GB là mức tham khảo từ máy đã kiểm tra; tốc độ AI phụ thuộc CPU/GPU, bộ nhớ và cấu hình nạp model. Máy khách chỉ mở web không cần GPU hoặc LM Studio.

Kiểm tra công cụ:

```powershell
node --version
npm.cmd --version
flutter --version
flutter doctor
```

Cài dependency tại đúng thư mục:

```powershell
Set-Location "D:\Projects\SignVoice"
flutter pub get
Push-Location .\backend
npm.cmd ci --include=dev
Pop-Location
```

## 4. Cấu hình database và backend riêng

### MongoDB

Chọn **một** trong hai cách:

**MongoDB Atlas:** dùng cluster/database của người nhận, tạo database user riêng và cho phép IP máy chạy backend. Đặt URI của người nhận trong `.env`.

**MongoDB local qua Docker Desktop:** nếu cổng 27017 đang trống, bật Docker Desktop rồi chạy cấu hình có sẵn:

```powershell
Set-Location "D:\Projects\SignVoice\backend"
docker compose up -d --wait
docker compose ps
```

Compose hiện tạo replica set `rs0`, lưu dữ liệu trong volume và chỉ mở cổng database ở `127.0.0.1:27017`. URI tương ứng:

```dotenv
MONGODB_URI=mongodb://127.0.0.1:27017/signvoice?replicaSet=rs0
```

Nếu đã có MongoDB dùng cổng này, dùng instance replica set phù hợp và URI riêng; không khởi động thêm container trùng cổng. Không chạy `docker compose down -v` khi cần giữ dữ liệu.

### File backend/.env

Tạo `backend/.env` mới. Các giá trị bên dưới dành cho luồng chạy tối thiểu ở **http://localhost:3000**:

```dotenv
NODE_ENV=development
PORT=3000
SERVE_WEB=true
PUBLIC_ORIGIN=http://localhost:3000
WEB_ORIGIN=http://localhost:3000
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

MONGODB_URI=mongodb://127.0.0.1:27017/signvoice?replicaSet=rs0
JWT_ACCESS_SECRET=THAY_BANG_CHUOI_NGAU_NHIEN_RIENG_THU_NHAT
JWT_REFRESH_SECRET=THAY_BANG_CHUOI_NGAU_NHIEN_RIENG_THU_HAI
JWT_ACCESS_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

SIGNVOICE_LM_STUDIO_URL=http://127.0.0.1:1235/v1
SIGNVOICE_LM_STUDIO_MODEL=qwen3-4b-instruct-2507
SIGNVOICE_LM_STUDIO_API_KEY=

AI_PUBLIC_PROXY=false
ADMIN_EMAIL=admin@signvoice.com
PRIVACY_OPERATOR_NAME="Ten nguoi van hanh cua may nhan"
SUPPORT_EMAIL=your-email@example.com
```

Thay URI nếu dùng Atlas. Thay tên/email liên hệ bằng thông tin của người nhận. `ADMIN_EMAIL` phải khớp ADMIN đang hoạt động dùng để import từ điển; hướng dẫn tạo tài khoản ở phần 6.

Hai JWT secret phải khác nhau, mỗi chuỗi ít nhất 32 ký tự; không dùng nguyên placeholder. Chạy lệnh sau **hai lần** rồi điền kết quả riêng vào hai biến:

```powershell
node -e "console.log(require('node:crypto').randomBytes(48).toString('hex'))"
```

SMTP và Google/Facebook OAuth là cấu hình tùy chọn, cần thông tin riêng nếu dùng. Với thiết lập ban đầu này, dùng đăng nhập email/mật khẩu. Không chép secret, SMTP hoặc tài khoản của máy phát triển sang máy nhận.

## 5. Cài và bật LM Studio

1. Cài LM Studio từ [trang chính thức](https://lmstudio.ai/).
2. Trong phần tìm model, tìm **Qwen3-4B-Instruct-2507-GGUF**.
3. Chọn bản của **lmstudio-community**, lượng tử **Q4_K_M** rồi tải về.
4. Nạp model. Có thể bắt đầu với context **4096**; điều chỉnh theo bộ nhớ máy nếu cần.
5. Vào **Developer**, đặt cổng **1235**, bật **Start Server** và giữ server chạy.
6. Kiểm tra từ chính máy đang chạy backend:

```powershell
$models = Invoke-RestMethod http://127.0.0.1:1235/v1/models
$models.data | Select-Object id
```

Phải thấy ID model SignVoice. Nếu ID trên máy nhận khác, đặt `SIGNVOICE_LM_STUDIO_MODEL` bằng **ID thực tế API trả về**, không dùng tên file GGUF thay thế tùy ý.

Nếu LM Studio bật **Require Authentication**, tạo token trên LM Studio rồi điền `SIGNVOICE_LM_STUDIO_API_KEY` trong `.env` của backend. Backend gửi Bearer token tới AI; không đưa token vào Flutter/source/chat. Để trống nếu API không yêu cầu xác thực. Ví dụ trên dùng loopback; chia sẻ trong LAN ở phần 11.1. Không mở API 1235 ra Internet.

Backend và LM Studio ở cùng máy thì giữ `127.0.0.1`; không cần bật Serve on Local Network hay CORS cho LM Studio. Phần server được mô tả trong [tài liệu chính thức LM Studio](https://lmstudio.ai/docs/developer/core/server).

**Lưu ý từ lỗi đã gặp:** tải model hoặc mở ứng dụng chưa có nghĩa là API server đã chạy. Phải kiểm tra `/v1/models` thành công. Các script chạy SignVoice hiện không tự khởi động LM Studio.

Nếu máy nhận đã có dự án lá cây: giữ nguyên model/preset/hội thoại của dự án đó, tải thêm model SignVoice. SignVoice chỉ định model và system prompt trong từng yêu cầu backend; không thay preset chung. Nạp thêm model có thể tốn bộ nhớ hoặc khiến model khác phải nạp lại khi dùng.

## 6. Chuẩn bị ADMIN và nhập từ điển

### ADMIN

Nếu đã có ADMIN riêng đang hoạt động trong database nhận: đặt `ADMIN_EMAIL` trong `.env` đúng email đó.

Nếu dùng database phát triển mới, trống, có thể tạo tài khoản khởi tạo bằng script có sẵn:

```powershell
Set-Location "D:\Projects\SignVoice\backend"
npm.cmd run db:create-admin
```

**Script hiện tạo cố định `admin@signvoice.com` với mật khẩu dev, được in trong terminal; biến `ADMIN_PASSWORD` không làm script này tạo mật khẩu tùy chọn.** Chỉ dùng để khởi tạo database riêng, đổi mật khẩu trước khi chia sẻ/public.

Đổi mật khẩu bằng API sau khi backend ở phần 7 đã chạy:

- `POST /api/v1/auth/login`: đăng nhập bằng tài khoản vừa tạo.
- `POST /api/v1/auth/change-password`: Bearer access token của phiên đăng nhập, body gồm `currentPassword` và `newPassword`.
- Có thể thao tác trong Swagger tại `http://localhost:3000/api-docs` khi chạy development. Nhập mật khẩu/token trực tiếp trên máy nhận, không lưu vào source hoặc gửi qua chat. Đăng nhập lại sau khi đổi mật khẩu.

Nếu đổi email ADMIN qua hồ sơ, cập nhật lại `ADMIN_EMAIL` trong `.env` trước lần import tiếp theo. Chỉ đăng ký tài khoản thường không tự tạo quyền ADMIN.

### Import

Tại thư mục `backend`, kiểm tra trước rồi mới nhập. `--origin` là địa chỉ gốc phục vụ web/API/media, không thêm `/api/v1`:

```powershell
Set-Location "D:\Projects\SignVoice\backend"
npx.cmd tsx scripts/import-sign-library.ts --catalog .runtime/speech-sign-library/shared-20261024/library.json --origin http://localhost:3000
```

Nếu dry-run xác nhận đúng database, ADMIN và bộ media:

```powershell
npx.cmd tsx scripts/import-sign-library.ts --catalog .runtime/speech-sign-library/shared-20261024/library.json --origin http://localhost:3000 --apply
```

Script resolve `--catalog` từ **gốc dự án**, dù terminal đang ở `backend`. Lệnh import kết nối MongoDB trực tiếp, không yêu cầu backend HTTP đang chạy. Nó giữ các mục do import quản lý theo ID ổn định và bảo toàn nội dung thủ công theo quy tắc trong source.

Nếu dùng bộ script Local cổng 3002 ở phần 10, chọn `--origin http://localhost:3002`. Nếu chuẩn bị cho truy cập LAN, chọn origin IP/port sẽ sử dụng ở phần 11. Địa chỉ media được ứng dụng chuẩn hóa theo backend đang dùng; origin vẫn nên điền đúng ngay khi import.

## 7. Chạy Từ điển + LMS, không cần Python camera

Giữ MongoDB và LM Studio đang chạy. Từ gốc dự án:

```powershell
Set-Location "D:\Projects\SignVoice"
flutter build web --release --dart-define=API_BASE_URL=/api/v1 --dart-define=AI_SERVICE_URL=/sign-ai --no-web-resources-cdn
Push-Location .\backend
npm.cmd run build
npm.cmd run start
```

Giữ terminal cuối mở. `.env` ở phần 4 cho phép backend phục vụ cùng lúc web/API tại **http://localhost:3000**. Chế độ này dùng được Từ điển và phân tích tiến độ; chức năng nhận diện camera Python chưa được khởi động.

Terminal khác kiểm tra:

```powershell
Invoke-RestMethod http://localhost:3000/health/ready
```

Mong đợi `success: true`. Chỉ `/health/live` thành công chưa chứng minh database đã sẵn sàng.

Sau khi sửa `backend/.env` hoặc backend source: Ctrl+C terminal đang chạy, build lại backend nếu sửa source, rồi `npm.cmd run start` lại. Sửa giao diện thì build lại Flutter web.

## 8. Kiểm tra chức năng trên tài khoản người nhận

1. Mở `http://localhost:3000`, đăng ký/đăng nhập bằng tài khoản của người nhận.
2. Vào **Từ điển → Khám phá**, chọn một chủ đề. Kiểm tra có từ, ảnh và video rồi bấm **Bắt đầu học**.
3. Học từng từ, tự đánh giá **Đã nhớ** hoặc **Ôn tập**. Từ chưa đánh giá nằm ở **Đang học**.
4. Vào tab **Đang học**, kiểm tra các tổng **Đang học / Đã nhớ / Ôn tập** và danh sách chủ đề đã bắt đầu.
5. Bấm **Phân tích tiến độ cá nhân** để xem tỷ lệ đã nhớ, số chủ đề và nhận xét về điểm mạnh/cần cải thiện/mục tiêu tiếp theo. Có nhãn **Phân tích từ LM Studio** hoặc **Phân tích từ số liệu** khi AI chưa sẵn sàng. Tổng tính trên toàn bộ chủ đề đã bắt đầu, không chỉ trang đang xem. Giới hạn 3 yêu cầu/phút/tài khoản.
6. Bấm **Gợi ý ôn tập** nếu cần kế hoạch ôn ngắn và ví dụ. Phản hồi có nhãn **Gợi ý từ LM Studio** hoặc **Lộ trình ôn tập cơ bản**. Giới hạn 6 yêu cầu/phút theo IP. Cả hai chức năng chờ AI tối đa 90 giây ở backend, 100 giây ở Flutter.
7. Tải lại trang và đăng nhập lại nếu cần: tiến độ vẫn còn trong MongoDB. Không có chủ đề/từ để phân tích thì bắt đầu chủ đề trước.
8. Trong **Đang học**, bấm **Lịch sử học tập** để xem các lượt đã ghi nhận. Trên thẻ từ trong chủ đề đã bắt đầu, bấm **Lịch sử từ này** để lọc riêng từ đó. Có tìm kiếm và 10 bản ghi/trang; dữ liệu cũ hiện dưới nhãn **Trạng thái đã lưu** theo lần cập nhật gần nhất.
9. Bấm **Thống kê & mục tiêu**: chọn **7/30 ngày** trong danh sách sổ xuống, bấm ngày để xem từng từ **Đã học / Đã ôn**. Mục tiêu hiển thị đầy đủ số đã làm/tổng và chuyển xanh lá khi hoàn thành. Dữ liệu cập nhật khi mở trang, quay lại từ trang học/ôn, lưu mục tiêu hoặc bấm **Làm mới**; không cập nhật định kỳ 5 giây. **Đổi mục tiêu** để lưu số từ mới/từ ôn riêng; mặc định 5/10. Muốn có dữ liệu **Cần củng cố**, vào chủ đề → Ôn tập → làm ký hiệu bằng camera → nộp quiz; các từ từng chưa khớp trong 30 ngày sẽ được tổng hợp. Quiz nháp hoặc trạng thái cũ không tự sinh thêm lượt học. Xem quy tắc đếm trong [DICTIONARY_LEARNING.md](DICTIONARY_LEARNING.md#biểu-đồ-từ-cần-củng-cố-và-mục-tiêu-ngày).

LM Studio chỉ nhận xét tiến độ và gợi ý ôn; không sửa đánh giá ghi nhớ hoặc chấm động tác. Luồng quiz camera và lịch ôn 3 ngày giữ nguyên theo `dev`, xem [DICTIONARY_LEARNING.md](../active/DICTIONARY_LEARNING.md). Chế độ tối thiểu phần 7 không khởi động camera; muốn dùng quiz camera cần phần 10.

## 9. Trình tự sử dụng hằng ngày và dừng

Với chế độ tối thiểu ở phần 7:

1. Bật database. Nếu dùng Docker local: mở Docker Desktop rồi `docker compose up -d --wait` tại `backend`.
2. Mở LM Studio, nạp model SignVoice và bật API server cổng 1235.
3. Tại `backend`, chạy `npm.cmd run start` nếu đã có bản build mới nhất.
4. Mở web đúng địa chỉ; đăng nhập bằng tài khoản của mình.

Dừng backend chạy thủ công bằng **Ctrl+C** trong đúng terminal. Script `stop-public-server.ps1` chỉ dừng server do bộ script quản lý, không quản lý lệnh `npm start` thủ công này. LM Studio và MongoDB được dừng riêng khi không dùng.

## 10. Nếu cần chạy cả camera bằng Local/Public

Cài thêm Python **3.11 x64**, tạo môi trường và tải đúng bộ model camera theo [SETUP_AI.md](../active/SETUP_AI.md):

```powershell
Set-Location "D:\Projects\SignVoice"
.\scripts\setup-ai-service.ps1 -Python (py -3.11 -c "import sys; print(sys.executable)")
```

Không sao chép `.venv` của máy khác. Model camera là gói riêng, không phải GGUF của LM Studio và không nằm trong ZIP media từ điển.

Sau khi database, model camera và `.env` sẵn sàng, vẫn phải bật LM Studio cổng 1235 nếu cần phân tích tiến độ:

```powershell
# Build lại cả giao diện/backend và chạy cùng dịch vụ camera.
.\scripts\start-signvoice.ps1 Local
```

Mở **http://localhost:3002**. Script Local ghi đè cổng/origin của lần chạy về 3002, dù `.env` đặt PORT=3000. Không chạy lệnh thủ công và bộ script đồng thời trên cùng cổng.

Public qua Conveyor cần cài Conveyor CLI ở `.tools/conveyor/conveyorcli.exe` và đăng nhập tài khoản tunnel của người nhận theo [CONVEYOR_PUBLISHING.md](../active/CONVEYOR_PUBLISHING.md). Sau đó:

```powershell
.\scripts\start-signvoice.ps1 Public
```

Mở link HTTPS do script in ra; backend vẫn gọi LM Studio trên chính máy server. Dùng `-SkipBuild` chỉ khi đã build đúng bản source hiện tại.

Các lệnh dừng:

```powershell
# Dừng server Local; giữ dịch vụ AI dùng chung.
.\scripts\stop-public-server.ps1 -Local

# Dừng backend Public, giữ các dịch vụ phụ do script quản lý, gồm tunnel/AI.
.\scripts\stop-public-server.ps1 -KeepServices

# Dừng Public và các dịch vụ phụ do phiên script đó quản lý.
.\scripts\stop-public-server.ps1
```

Các lệnh trên không tắt LM Studio. Health cần kiểm tra khi chạy gộp: `/health/ready` và `/sign-ai/health`. Không dùng một mình health thành công của Python để kết luận LM Studio đã chạy.

## 11. Dùng chung server trong cùng Wi-Fi/LAN

Hai máy phải cùng mạng nội bộ và được phép liên lạc với nhau. Dùng Wi-Fi thường hoặc Ethernet cùng router; mạng khách hay Wi-Fi có client isolation có thể chặn kết nối. Không dùng IP LAN để kết nối khi hai máy ở khác mạng.

### 11.1. Máy anh chạy LM Studio, máy khác tự chạy SignVoice

Luồng: **Trình duyệt máy khác → backend SignVoice máy khác → LM Studio máy anh:1235 → kết quả phân tích**.

Máy anh chỉ cần LM Studio, runtime và model SignVoice. Máy khác chuẩn bị source, dependency, database, tài khoản và media theo phần 2–8; bỏ bước cài LM Studio/model trên máy đó. Không chép `.env`, JWT secret hoặc tài khoản database của máy anh.

**Trên máy anh — máy chạy LM Studio:**

1. Chạy `ipconfig`, lấy IPv4 của Wi-Fi/Ethernet đang kết nối; ví dụ **192.168.1.10**. Không lấy IP adapter WSL/Hyper-V. IP có thể thay đổi khi đổi mạng hoặc router cấp lại địa chỉ.
2. Mở LM Studio, nạp `qwen3-4b-instruct-2507`, vào **Developer → Server Settings**, bật **Serve on Local Network**, đặt cổng **1235** và bật server. Kiểm tra lại địa chỉ lắng nghe sau khi đổi thiết lập.
3. Kiểm tra ngay trên máy anh:

```powershell
Invoke-RestMethod http://192.168.1.10:1235/v1/models
```

4. Nếu Windows Firewall chặn, trên mạng riêng tin cậy đã đặt profile **Private**, chạy PowerShell Administrator và thêm quy tắc giới hạn trong mạng nội bộ:

```powershell
New-NetFirewallRule -DisplayName 'SignVoice LM Studio LAN 1235' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1235 -Profile Private -RemoteAddress LocalSubnet
```

Chỉ thêm quy tắc khi cần; không tắt firewall hoặc mở cổng router ra Internet. Không chuyển mạng công cộng không tin cậy sang Private chỉ để mở API. Nếu bật **Require Authentication**, tạo token và điền `SIGNVOICE_LM_STUDIO_API_KEY` trên backend máy khác. Không cần bật CORS của LM Studio vì kết nối đến từ backend, không phải trình duyệt. Xem [Serve on Local Network](https://lmstudio.ai/docs/developer/core/server/serve-on-network).

**Trên máy khác — máy chạy SignVoice:**

1. Kết nối cùng Wi-Fi/LAN, mở PowerShell kiểm tra:

```powershell
Invoke-RestMethod http://192.168.1.10:1235/v1/models
```

Phải nhận danh sách model trước khi kiểm tra nút AI. Thay IP ví dụ bằng IPv4 thực của máy anh ở cả lệnh kiểm tra và `.env`.

2. Chỉ cập nhật hai dòng LM Studio trong `backend/.env` của máy khác; giữ nguyên cấu hình database, JWT và các thiết lập riêng:

```dotenv
SIGNVOICE_LM_STUDIO_URL=http://192.168.1.10:1235/v1
SIGNVOICE_LM_STUDIO_MODEL=qwen3-4b-instruct-2507
```

`127.0.0.1` hoặc `localhost` trên máy khác trỏ về chính máy đó, không phải máy anh. Nếu API trả ID model khác, dùng ID thực tế từ `/v1/models`.

3. Khởi động lại backend sau khi sửa `.env`: dùng phần 7 cho Từ điển/LMS tối thiểu, hoặc phần 10 nếu đã cài đủ camera và muốn dùng `start-signvoice.ps1 Local`. Với chế độ Local, mở **http://localhost:3002 trên máy khác**; chỉ đường gọi AI đi tới IP máy anh.
4. Đăng nhập, vào **Từ điển → Khám phá**, chọn chủ đề và **Bắt đầu học**, rồi vào **Đang học → Phân tích tiến độ cá nhân**. Nút **Gợi ý ôn tập** vẫn có riêng để lập kế hoạch ôn.

Giữ máy anh bật, không ngủ và LM Studio server đang chạy suốt phiên sử dụng. Chia sẻ AI không tự đồng bộ tài khoản hoặc tiến độ giữa các database; dữ liệu học tập vẫn thuộc database của backend đang chạy. Model, preset và hội thoại lá cây được giữ nguyên; tải/nạp model SignVoice không xóa dự án đó.

Riêng kết nối đến LM Studio trong LAN không cần Internet. Nếu backend dùng MongoDB Atlas, OAuth hoặc SMTP, các dịch vụ đó vẫn cần Internet.

### 11.2. Máy anh chạy cả SignVoice và LM Studio, máy khác chỉ mở web

Máy server làm toàn bộ phần 2–8. Máy khách không cần cài source, Flutter, MongoDB, Python hoặc LM Studio.

Dùng chế độ chạy tối thiểu thủ công ở cổng 3000 để cấu hình origin LAN rõ ràng:

1. Trên server chạy `ipconfig`, lấy IPv4 của Wi-Fi/Ethernet đang dùng; ví dụ **192.168.1.10**.
2. Dừng backend thủ công bằng Ctrl+C, rồi tại `backend` đặt biến cho **terminal hiện tại** và chạy lại:

```powershell
Set-Location "D:\Projects\SignVoice\backend"
$env:NODE_ENV = 'development'
$env:PORT = '3000'
$env:SERVE_WEB = 'true'
$env:PUBLIC_ORIGIN = 'http://192.168.1.10:3000'
$env:WEB_ORIGIN = 'http://192.168.1.10:3000'
$env:CORS_ALLOWED_ORIGINS = 'http://192.168.1.10:3000,http://localhost:3000'
$env:PASSWORD_RESET_ORIGIN = 'http://192.168.1.10:3000'
$env:AI_PUBLIC_PROXY = 'false'
npm.cmd run start
```

3. Nếu Windows Firewall chặn, cho phép backend cổng 3000 trên mạng **Private**. Ví dụ lệnh dưới chạy trong PowerShell Administrator trên server, chỉ khi cần:

```powershell
New-NetFirewallRule -DisplayName 'SignVoice LAN 3000' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3000 -Profile Private -RemoteAddress LocalSubnet
```

4. Trên máy khách cùng mạng, mở **http://192.168.1.10:3000**, dùng email/mật khẩu của tài khoản riêng.

Thay IP ví dụ bằng IP thật. Dùng nhất quán địa chỉ IP đó cho web/API khi kiểm tra đăng nhập; `localhost` trên máy khách trỏ về chính máy khách. Nếu Wi-Fi có client isolation, cần dùng mạng cho phép các thiết bị liên lạc.

**Không dùng trực tiếp `start-signvoice.ps1 Local` cho cấu hình origin LAN này:** script hiện ép WEB_ORIGIN/CORS/callback về localhost:3002. Truy cập trang bằng IP có thể tải giao diện nhưng thao tác đăng nhập/ghi dữ liệu cần origin phù hợp. Cách chạy thủ công phía trên đặt origin cho phiên LAN và không sửa script.

Giữ `SIGNVOICE_LM_STUDIO_URL=http://127.0.0.1:1235/v1` trên máy server; không thay bằng IP máy khách. Không cần mở firewall cho cổng LM Studio hoặc MongoDB. Đăng nhập OAuth cần callback riêng đúng địa chỉ được nhà cung cấp cho phép; HTTP LAN có thể bị trình duyệt chặn camera/micro, nên luồng này tập trung Từ điển/LMS và email/mật khẩu.

Hai máy giữ kết nối cùng Wi-Fi/LAN. Khi server tắt/ngủ hoặc đóng backend/LM Studio, máy khách không phân tích được.

Phần LAN là hướng dẫn cấu hình theo source; cần kiểm tra lại trên thiết bị/mạng người nhận, chưa được xác nhận trên mọi môi trường.

## 12. Xử lý lỗi thường gặp

| Hiện tượng | Kiểm tra và xử lý |
| --- | --- |
| “Chưa phân tích được…” | Trên máy backend gọi `/v1/models` ở cổng 1235. Bật Start Server, kiểm tra ID model, thử lại khi model sẵn sàng. Xem `.runtime/public-server.error.log` nếu chạy bằng script hoặc terminal backend nếu chạy thủ công. |
| Máy khác không gọi được LM Studio qua IP | Kiểm tra cùng Wi-Fi/LAN, IP đúng adapter, Serve on Local Network đã bật, server cổng 1235 đang chạy, firewall và client isolation. Thử `/v1/models` từ chính máy chạy backend; không dùng `localhost` để trỏ đến máy anh. |
| LM Studio trả 401 | Nếu bật Require Authentication, điền token đúng vào `SIGNVOICE_LM_STUDIO_API_KEY` rồi khởi động lại backend. Lệnh `/v1/models` cũng cần header Authorization Bearer khi API bật xác thực. |
| Hiện Lộ trình ôn tập cơ bản | Kiểm tra model, URL/API key riêng của SignVoice, log LM Studio và thời gian phản hồi; đây là gợi ý theo quy tắc khi AI không sẵn sàng hoặc chưa có từ trong chủ đề đã bắt đầu. |
| `/v1/models` trả model nhưng phân tích lỗi | Model có thể chưa nạp, nạp lỗi/thiếu bộ nhớ hoặc phản hồi quá thời gian. Xem log Developer trong LM Studio, đóng ứng dụng chiếm tài nguyên và thử nạp lại model SignVoice. Không xóa model dự án khác. |
| Backend health 503 | Kiểm tra `MONGODB_URI`, kết nối database, replica set và IP allowlist nếu dùng Atlas. |
| `Transaction numbers are only allowed...` | Database đang chạy standalone; dùng replica set hoặc Atlas. |
| Từ điển trống, không có ảnh/video | Kiểm tra đã cài ZIP media **và** import metadata vào đúng database; pull Git không làm hai việc này. |
| `Configured active admin not found` | `ADMIN_EMAIL` không khớp tài khoản ADMIN có status ACTIVE trong database đang cấu hình. |
| Thiếu `tsc` | Chạy `npm.cmd ci --include=dev` trong `backend`, sau đó build lại. |
| `AI Python environment is missing` | Đang dùng script chạy gộp; cài phần 10 hoặc chuyển sang chế độ Từ điển/LMS thủ công phần 7. |
| AI camera báo khác code/model | Dừng đúng dịch vụ camera cũ rồi chạy lại; không tắt tất cả tiến trình Python/Node. |
| Máy khách thấy web nhưng đăng nhập/ghi lỗi | Kiểm tra WEB_ORIGIN/CORS đúng IP/port, dùng cùng origin và không bị script Local ghi đè. |
| Vượt giới hạn yêu cầu AI | Chờ một phút rồi thử; phân tích giới hạn 3 yêu cầu/phút/tài khoản, gợi ý ôn giới hạn 6 yêu cầu/phút theo IP. |
| Vẫn thấy giao diện cũ | Build lại Flutter web, khởi động lại backend nếu sửa code/config và tải lại trang. |

LM Studio chạy model đã tải được khi offline, nhưng Atlas, OAuth, SMTP và Conveyor vẫn cần Internet. Nếu cần mất Internet vẫn dùng được tiến độ/từ điển, chuẩn bị MongoDB local replica set, media, source, model và dependency từ trước. Xem [tài liệu offline LM Studio](https://lmstudio.ai/docs/app/offline).

## 13. Checklist bàn giao

- [ ] Source có `learning-coach.service.ts`, `learning_hub.dart` và giao diện Khám phá / Đang học / Từ của tôi.
- [ ] `.env`, database, JWT secret và tài khoản ADMIN thuộc người nhận.
- [ ] Bộ media đã kiểm tra checksum, cài vào dự án và import từ điển thành công.
- [ ] LM Studio `/v1/models` trả ID model trùng cấu hình SignVoice.
- [ ] Backend `/health/ready` trả `success: true`.
- [ ] Đăng nhập, bắt đầu chủ đề, tự đánh giá từ, tải lại trang vẫn giữ trạng thái.
- [ ] Nút Gợi ý ôn tập trả nhận xét tiếng Việt có nhãn Gợi ý từ LM Studio; lỗi AI hiện lộ trình cơ bản.
- [ ] Nút Phân tích tiến độ cá nhân hiện tỷ lệ đã nhớ, số chủ đề và phân tích với nguồn được ghi rõ; không làm thay đổi tiến độ.
- [ ] Lịch sử học tập/lịch sử từ hiển thị đúng tài khoản, tìm kiếm và phân trang; thao tác đánh giá hoặc hoàn tất quiz tạo bản ghi mới.
- [ ] Nếu chia sẻ LM Studio qua LAN: `/v1/models` và nút AI hoạt động từ chính máy chạy backend, dùng IP nội bộ của máy anh.
- [ ] Nếu chia sẻ cả web qua LAN: kiểm tra từ trình duyệt máy khách thật bằng đúng IP/cổng của server.

## 14. Cách chạy tóm tắt — máy anh phát LM Studio cho máy khác cùng Wi-Fi

Sau khi đã hoàn tất cài đặt ban đầu và hai máy cùng Wi-Fi/LAN:

1. **Máy anh:** mở LM Studio → nạp `qwen3-4b-instruct-2507` → bật **Serve on Local Network** → bật server cổng **1235**. Lấy IPv4 bằng `ipconfig`.
2. **Máy khác:** kiểm tra `Invoke-RestMethod http://192.168.1.10:1235/v1/models`, thay IP bằng IP máy anh.
3. **Máy khác:** đặt `SIGNVOICE_LM_STUDIO_URL=http://192.168.1.10:1235/v1` và `SIGNVOICE_LM_STUDIO_MODEL=qwen3-4b-instruct-2507` trong `backend/.env`. Sửa lại URL nếu IP máy anh đổi.
4. **Máy khác:** bật database hoặc bảo đảm kết nối Atlas. Nếu đã cài đầy đủ camera theo phần 10, từ gốc dự án chạy:

```powershell
.\scripts\start-signvoice.ps1 Local
```

Lệnh build lại giao diện/backend và chạy ứng dụng tại **http://localhost:3002** trên máy khác. Nếu chỉ cài Từ điển/LMS, dùng các lệnh build/chạy tối thiểu ở phần 7 và mở **http://localhost:3000**.

5. **Máy khác:** đăng nhập → **Từ điển → Khám phá → Bắt đầu học** một chủ đề → **Đang học → Phân tích tiến độ cá nhân**. Dùng **Gợi ý ôn tập** khi cần kế hoạch ôn ngắn.
6. Dừng phiên Local trên máy khác:

```powershell
.\scripts\stop-public-server.ps1 -Local
```

Nếu chạy thủ công theo phần 7, dừng bằng **Ctrl+C** trong terminal backend. Tắt API server trong LM Studio trên máy anh khi không còn máy nào sử dụng; script dừng SignVoice không tắt LM Studio.

Tài liệu liên quan: [Chi tiết LMS](../active/LMStudio-learning-progress.md), [dịch vụ camera](../active/SETUP_AI.md), [media và import](../../README.md#chuyển-bộ-từ-điển-sang-máy-khác).
