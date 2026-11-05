# Hướng dẫn Test API với Swagger UI

**Ngày cập nhật:** 9 tháng 10, 2026  
**Phiên bản:** 1.0

---

## 📖 Giới thiệu

Swagger UI là công cụ tương tác cho phép bạn:
- Xem tất cả REST API endpoints của SignVoice
- Đọc mô tả chi tiết về request/response
- Test API trực tiếp từ trình duyệt
- Xác thực bằng JWT token
- Kiểm tra USER/STAFF/ADMIN endpoints

---

## 🚀 Khởi động Backend

### Bước 1: Khởi động MongoDB

**Windows:**
```powershell
# Nếu MongoDB đã được cài dặt như một service:
net start MongoDB

# Hoặc chạy thủ công:
mongod --dbpath="C:\data\db"
```

**Kiểm tra MongoDB đang chạy:**
```powershell
# Kết nối đến MongoDB shell
mongosh
# Nếu thành công, bạn sẽ thấy prompt: test>
```

### Bước 2: Cài đặt dependencies (lần đầu tiên)

```powershell
cd c:\Users\PC\sign_voice\backend
npm install
```

### Bước 3: Khởi động Backend

```powershell
cd c:\Users\PC\sign_voice\backend
npm run dev
```

**Kết quả mong đợi:**
```
🗄️  MongoDB connected successfully
📖 Swagger UI enabled at /api-docs
📄 OpenAPI JSON available at /api-docs/openapi.json
🚀 Server running on port 3000
```

---

## 🌐 Mở Swagger UI

### Truy cập Swagger

Mở trình duyệt và truy cập:
```
http://localhost:3000/api-docs
```

Bạn sẽ thấy giao diện Swagger UI với:
- **Tiêu đề:** SignVoice REST API
- **Các tags:** System, Authentication, Dictionary, Categories, Favorites, History, Users, Staff, Admin
- **Nút Authorize** ở góc trên bên phải

---

## 🧪 Test API cơ bản (không cần xác thực)

### Test 1: Health Check

1. Tìm tag **"System"**
2. Click vào **GET /health/live**
3. Click nút **"Try it out"**
4. Click **"Execute"**

**Kết quả mong đợi:**
```json
{
  "success": true,
  "data": {
    "status": "ok",
    "timestamp": "2026-10-09T10:30:00.000Z",
    "uptime": 123.45
  }
}
```

**Response Code:** `200 OK`

### Test 2: Lấy danh sách Categories (Public)

1. Tìm tag **"Categories"**
2. Click **GET /api/v1/categories**
3. Click **"Try it out"**
4. Click **"Execute"**

**Kết quả:**
- Nếu database chưa có data: `[]` (mảng rỗng)
- Nếu có data: danh sách categories

**Response Code:** `200 OK`

---

## 🔐 Xác thực bằng JWT

## 🔐 Xác thực bằng JWT

### Tài khoản Test có sẵn

Bạn có thể tạo tài khoản test bằng lệnh:

```powershell
cd c:\Users\PC\sign_voice\backend
npm run db:create-test-accounts
```

**Tài khoản được tạo:**

```
┌─────────────────────────────────────────────────────────┐
│ USER Account (Basic user permissions)                  │
├─────────────────────────────────────────────────────────┤
│ Email:    user@test.com                                │
│ Password: User123!                                      │
│ Role:     USER                                          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ STAFF Account (Content moderation)                     │
├─────────────────────────────────────────────────────────┤
│ Email:    staff@test.com                               │
│ Password: Staff123!                                     │
│ Role:     STAFF                                         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ ADMIN Account (Full system access)                     │
├─────────────────────────────────────────────────────────┤
│ Email:    admin@signvoice.com                          │
│ Password: Admin123!                                     │
│ Role:     ADMIN                                         │
└─────────────────────────────────────────────────────────┘
```

⚠️ **Lưu ý:** Đây là tài khoản TEST, chỉ dùng cho development!

---

### Bước 1: Đăng ký tài khoản (hoặc đăng nhập)

#### Đăng ký tài khoản mới:

1. Tìm tag **"Authentication"**
2. Click **POST /api/v1/auth/register**
3. Click **"Try it out"**
4. Nhập thông tin vào Request body:

```json
{
  "email": "test@example.com",
  "password": "Password123!",
  "displayName": "Nguyễn Văn Test"
}
```

5. Click **"Execute"**

**Kết quả mong đợi:**
```json
{
  "success": true,
  "data": {
    "user": {
      "_id": "...",
      "email": "test@example.com",
      "displayName": "Nguyễn Văn Test",
      "role": "USER",
      "status": "ACTIVE",
      "accountType": "PERMANENT"
    },
    "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

**Response Code:** `201 Created`

#### Đăng nhập (nếu đã có tài khoản):

1. Click **POST /api/v1/auth/login**
2. Click **"Try it out"**
3. Nhập (dùng tài khoản test hoặc tài khoản bạn đã tạo):

**Ví dụ - đăng nhập USER:**
```json
{
  "email": "user@test.com",
  "password": "User123!"
}
```

**Ví dụ - đăng nhập STAFF:**
```json
{
  "email": "staff@test.com",
  "password": "Staff123!"
}
```

**Ví dụ - đăng nhập ADMIN:**
```json
{
  "email": "admin@signvoice.com",
  "password": "Admin123!"
}
```

4. Click **"Execute"**

**⚠️ LƯU Ý QUAN TRỌNG:**
- Copy **accessToken** từ response (toàn bộ chuỗi dài)
- Bạn sẽ cần token này cho bước tiếp theo

### Bước 2: Authorize với JWT Token

1. Click nút **"Authorize"** ở góc trên bên phải (biểu tượng ổ khóa)
2. Một popup hiện ra với tiêu đề **"Available authorizations"**
3. Trong trường **"Value"**, paste JWT token bạn vừa copy
4. **KHÔNG** thêm từ "Bearer " - Swagger UI sẽ tự động thêm
5. Click **"Authorize"**
6. Click **"Close"**

**Kết quả:**
- Biểu tượng ổ khóa sẽ đổi thành màu đen (đã khóa)
- Tất cả các request tiếp theo sẽ tự động có header `Authorization: Bearer {token}`

### Bước 3: Test API yêu cầu xác thực

#### Test lấy thông tin người dùng hiện tại:

1. Tìm **GET /api/v1/auth/me**
2. Click **"Try it out"**
3. Click **"Execute"**

**Kết quả mong đợi:**
```json
{
  "success": true,
  "data": {
    "user": {
      "_id": "...",
      "email": "test@example.com",
      "displayName": "Nguyễn Văn Test",
      "role": "USER",
      ...
    }
  }
}
```

**Response Code:** `200 OK`

---

## 📚 Test Dictionary API

### Tạo từ điển mới (cần STAFF hoặc ADMIN)

**⚠️ Chú ý:** Tài khoản USER thông thường không có quyền tạo từ điển.

Nếu bạn cần test chức năng STAFF/ADMIN, bạn cần:
1. Tạo tài khoản STAFF/ADMIN qua database seed script
2. Hoặc dùng ADMIN để thay đổi role của user

#### Nếu có quyền STAFF:

1. Tìm **POST /api/v1/dictionary**
2. Click **"Try it out"**
3. Nhập:

```json
{
  "word": "Xin chào",
  "definition": "Lời chào hỏi khi gặp gỡ",
  "videoUrl": "https://example.com/videos/xin-chao.mp4",
  "categoryId": "YOUR_CATEGORY_ID_HERE",
  "difficulty": "BASIC",
  "tags": ["chào hỏi", "giao tiếp"]
}
```

4. Click **"Execute"**

**Kết quả thành công:** `201 Created`  
**Nếu không có quyền:** `403 Forbidden`

### Lấy danh sách từ điển

1. Tìm **GET /api/v1/dictionary**
2. Click **"Try it out"**
3. Có thể thêm filters:
   - `search`: "chào"
   - `difficulty`: "BASIC"
   - `limit`: 20
4. Click **"Execute"**

---

## 👤 Test USER API

### Xem profile

**GET /api/v1/users/profile**

### Cập nhật profile

**PATCH /api/v1/users/profile**

Request body:
```json
{
  "displayName": "Tên mới",
  "avatarUrl": "https://example.com/avatar.jpg"
}
```

### Lấy cài đặt

**GET /api/v1/users/settings**

### Cập nhật cài đặt

**PATCH /api/v1/users/settings**

Request body:
```json
{
  "theme": "DARK",
  "language": "vi",
  "videoAutoplay": true,
  "notifications": {
    "email": true,
    "push": true,
    "newContent": true
  }
}
```

---

## ⭐ Test Favorites & History

### Thêm vào yêu thích

**POST /api/v1/favorites**

```json
{
  "entryId": "YOUR_ENTRY_ID",
  "notes": "Từ này hay"
}
```

### Lấy danh sách yêu thích

**GET /api/v1/favorites**

### Xóa khỏi yêu thích

**DELETE /api/v1/favorites/{entryId}**

### Xem lịch sử

**GET /api/v1/history**

### Xóa lịch sử

**DELETE /api/v1/history**

---

## 🛠️ Test STAFF API

**⚠️ Yêu cầu:** Tài khoản phải có role STAFF hoặc ADMIN

### Xem nội dung cần duyệt

**GET /api/v1/staff/content**

Parameters:
- `status`: PENDING
- `page`: 1
- `limit`: 20

### Phê duyệt nội dung

**POST /api/v1/staff/content/{id}/approve**

### Từ chối nội dung

**POST /api/v1/staff/content/{id}/reject**

```json
{
  "reason": "Định nghĩa chưa rõ ràng, cần bổ sung"
}
```

### Xem thống kê STAFF

**GET /api/v1/staff/stats**

---

## 👑 Test ADMIN API

**⚠️ Yêu cầu:** Tài khoản phải có role ADMIN

### Xem tất cả người dùng

**GET /api/v1/admin/users**

Parameters:
- `page`: 1
- `limit`: 20
- `role`: USER / STAFF / ADMIN
- `status`: ACTIVE / SUSPENDED
- `search`: email hoặc tên

### Cập nhật người dùng

**PATCH /api/v1/admin/users/{id}**

```json
{
  "role": "STAFF",
  "status": "ACTIVE"
}
```

### Đình chỉ người dùng

**POST /api/v1/admin/users/{id}/suspend**

```json
{
  "reason": "Vi phạm quy tắc cộng đồng"
}
```

### Kích hoạt lại người dùng

**POST /api/v1/admin/users/{id}/activate**

### Xem thống kê hệ thống

**GET /api/v1/admin/stats**

### Xem phiên đăng nhập

**GET /api/v1/admin/sessions**

### Hủy phiên đăng nhập

**DELETE /api/v1/admin/sessions/{sessionId}**

---

## 🔄 Làm mới Token (Refresh Token)

Khi access token hết hạn (thường sau 15-60 phút), bạn sẽ nhận lỗi `401 TOKEN_EXPIRED`.

### Cách refresh:

1. Tìm **POST /api/v1/auth/refresh**
2. Click **"Try it out"**
3. Nhập **refreshToken** (bạn đã lưu từ lúc đăng nhập):

```json
{
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

4. Click **"Execute"**
5. Copy **accessToken** mới từ response
6. Click **"Authorize"** và paste token mới
7. Tiếp tục test

---

## ❌ Xử lý lỗi thường gặp

### Lỗi 401 Unauthorized

**Nguyên nhân:**
- Chưa đăng nhập
- Token hết hạn
- Token không hợp lệ

**Giải pháp:**
1. Đăng nhập lại để lấy token mới
2. Hoặc dùng refresh token
3. Click "Authorize" và nhập token

### Lỗi 403 Forbidden

**Nguyên nhân:**
- Tài khoản không có quyền truy cập endpoint này
- Ví dụ: USER cố gắng truy cập ADMIN API

**Giải pháp:**
- Đăng nhập bằng tài khoản có quyền phù hợp
- Hoặc dùng ADMIN để thay đổi role

### Lỗi 404 Not Found

**Nguyên nhân:**
- ID không tồn tại trong database
- Đường dẫn API sai

**Giải pháp:**
- Kiểm tra ID có đúng không
- Kiểm tra endpoint path

### Lỗi 400 Bad Request / 422 Validation Error

**Nguyên nhân:**
- Dữ liệu request không hợp lệ
- Thiếu trường bắt buộc
- Định dạng sai

**Giải pháp:**
- Đọc kỹ message trong response
- Kiểm tra schema trong Swagger
- Sửa request body cho đúng

### Lỗi 503 Service Unavailable

**Nguyên nhân:**
- MongoDB chưa kết nối
- Backend chưa sẵn sàng

**Giải pháp:**
1. Kiểm tra MongoDB đang chạy:
```powershell
mongosh
```
2. Khởi động lại Backend:
```powershell
npm run dev
```

---

## 🔒 Reset Authorization

Để đăng xuất khỏi Swagger UI:

1. Click nút **"Authorize"**
2. Click **"Logout"** bên cạnh bearerAuth
3. Click **"Close"**

Hoặc reload lại trang trình duyệt.

---

## 📋 Kiểm tra HTTP Status Codes

Swagger UI hiển thị status code màu sắc:

- **🟢 2xx (Green):** Thành công
  - `200 OK`: Request thành công
  - `201 Created`: Tạo resource thành công
  
- **🟡 4xx (Yellow/Orange):** Lỗi client
  - `400 Bad Request`: Dữ liệu không hợp lệ
  - `401 Unauthorized`: Chưa xác thực
  - `403 Forbidden`: Không có quyền
  - `404 Not Found`: Không tìm thấy resource
  - `422 Unprocessable Entity`: Validation failed
  
- **🔴 5xx (Red):** Lỗi server
  - `500 Internal Server Error`: Lỗi server
  - `503 Service Unavailable`: Database chưa sẵn sàng

---

## 📄 Xem OpenAPI JSON

Nếu bạn cần OpenAPI specification raw JSON:

```
http://localhost:3000/api-docs/openapi.json
```

Có thể dùng để:
- Import vào Postman
- Generate client code
- Tích hợp với công cụ khác

---

## 🧪 Test POST/PATCH/DELETE An toàn

**⚠️ CẢNH BÁO:** Các thao tác này thay đổi database!

### Môi trường development:
- Có thể test thoải mái
- Dùng `npm run db:clean` để reset database
- Dùng `npm run db:seed` để tạo data mẫu

### Môi trường production:
- **KHÔNG** dùng Swagger UI test trên production
- Swagger nên được disable: `SWAGGER_ENABLED=false`
- Test trên development trước

### Safe Testing Tips:

1. **Tạo tài khoản test riêng:**
   - Email: test1@example.com, test2@example.com
   - Không dùng tài khoản thật

2. **Tạo data test:**
   - Tạo categories test
   - Tạo từ điển test
   - Có thể xóa sau khi test

3. **Không xóa data quan trọng:**
   - Không DELETE user ADMIN duy nhất
   - Không xóa categories đang được sử dụng

4. **Kiểm tra response:**
   - Luôn đọc response message
   - Hiểu hành động sẽ làm gì trước khi Execute

---

## ⚙️ Validate OpenAPI Specification

Kiểm tra OpenAPI spec có hợp lệ không:

```powershell
cd c:\Users\PC\sign_voice\backend
npm run docs:validate
```

**Kết quả mong đợi:**
```
🔍 Validating OpenAPI specification...

✅ OpenAPI specification is valid
   Title: SignVoice REST API
   Version: 1.0.0
   Paths: 50+
```

---

## 🚫 Giới hạn và hạn chế

### Tính năng chưa tích hợp:

1. **AI Recognition:**
   - API tồn tại nhưng trả về thông báo "Tính năng AI chưa được tích hợp"
   - Không thể test video recognition thực tế

2. **OAuth Login:**
   - Google/Facebook login chưa được cấu hình
   - Chỉ test được email/password và guest login

3. **Email Verification:**
   - Email xác thực chưa được kích hoạt
   - Đăng ký không gửi email thật

4. **HttpOnly Refresh Token (Web):**
   - Backend hỗ trợ HttpOnly cookies cho Web
   - Swagger UI có thể không test được flow này đầy đủ
   - Cookies được browser tự động quản lý

### Testing Limitations:

- **File Upload:** Swagger UI có thể test file upload nhưng cần backend hỗ trợ multipart/form-data
- **Binary Response:** Không hiển thị tốt file downloads
- **WebSocket:** Không support real-time connections
- **Rate Limiting:** Chưa được implement

---

## 📞 Hỗ trợ

Nếu gặp vấn đề:

1. **Kiểm tra Backend logs:**
   - Xem terminal đang chạy `npm run dev`
   - Tìm error messages

2. **Kiểm tra MongoDB:**
   - Xem MongoDB có đang chạy không
   - Kiểm tra kết nối

3. **Browser Console:**
   - Press F12 để mở DevTools
   - Tab Console để xem JavaScript errors
   - Tab Network để xem API requests

4. **Đọc lỗi từ Response:**
   - Swagger hiển thị response body đầy đủ
   - Đọc `error.code` và `error.message`

---

## 📚 Tài liệu tham khảo

- **API Endpoint Reference:** `docs/active/API_ENDPOINT_REFERENCE.md`
- **OpenAPI Specification:** `backend/docs/openapi.yaml`
- **Swagger UI Docs:** https://swagger.io/tools/swagger-ui/

---

**Chúc bạn test API thành công! 🎉**
