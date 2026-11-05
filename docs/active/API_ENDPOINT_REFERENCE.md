# SignVoice API Endpoint Reference

**Base URL:** `http://localhost:3000/api/v1`

---

## 🔐 Authentication Endpoints

### Register
```
POST /auth/register
Body: { email, password, displayName }
Returns: { success, data: { user, accessToken, refreshToken } }
Access: Public
```

### Login
```
POST /auth/login
Body: { email, password }
Returns: { success, data: { user, accessToken, refreshToken } }
Access: Public
```

### Guest Login
```
POST /auth/guest
Returns: { success, data: { user, accessToken, refreshToken } }
Access: Public
```

### Convert Guest
```
POST /auth/convert-guest
Headers: Authorization: Bearer {token}
Body: { email, password }
Returns: { success, data: { user, accessToken, refreshToken } }
Access: Private (Guest only)
```

### Refresh Token
```
POST /auth/refresh
Body: { refreshToken }
Returns: { success, data: { accessToken } }
Access: Public
```

### Logout
```
POST /auth/logout
Headers: Authorization: Bearer {token}
Returns: { success }
Access: Private
```

### Logout All Devices
```
POST /auth/logout-all
Headers: Authorization: Bearer {token}
Returns: { success }
Access: Private
```

### Get Current User
```
GET /auth/me
Headers: Authorization: Bearer {token}
Returns: { success, data: { user } }
Access: Private
```

---

## 📚 Dictionary Endpoints

### Get Published Entries
```
GET /dictionary?categoryId={id}&search={query}&difficulty={level}&limit={n}&skip={n}
Returns: { success, data: [entries], pagination: { total, limit, skip } }
Access: Public (optional auth for history tracking)
```

### Get Entry By ID
```
GET /dictionary/:id
Returns: { success, data: { entry } }
Access: Public (optional auth for history tracking)
```

### Get Popular Entries
```
GET /dictionary/popular?limit={n}
Returns: { success, data: [entries] }
Access: Public
```

### Create Draft Entry
```
POST /dictionary
Headers: Authorization: Bearer {token}
Body: { word, definition, videoUrl, categoryId, thumbnailUrl?, imageUrls?, tags?, difficulty?, usageExample?, notes? }
Returns: { success, data: { entry } }
Access: Private (STAFF/ADMIN)
```

### Update Entry
```
PATCH /dictionary/:id
Headers: Authorization: Bearer {token}
Body: { word?, definition?, videoUrl?, ... }
Returns: { success, data: { entry } }
Access: Private (STAFF/ADMIN)
```

### Publish Entry
```
POST /dictionary/:id/publish
Headers: Authorization: Bearer {token}
Returns: { success, data: { entry } }
Access: Private (ADMIN)
```

### Archive Entry
```
POST /dictionary/:id/archive
Headers: Authorization: Bearer {token}
Returns: { success, data: { entry } }
Access: Private (ADMIN)
```

---

## 🗂️ Category Endpoints

### Get All Categories
```
GET /categories
Returns: { success, data: [categories] }
Access: Public
```

### Get Category By Slug
```
GET /categories/:slug
Returns: { success, data: { category } }
Access: Public
```

### Create Category
```
POST /categories
Headers: Authorization: Bearer {token}
Body: { name, slug, description?, icon?, sortOrder, parentId?, status }
Returns: { success, data: { category } }
Access: Private (ADMIN)
```

---

## ⭐ Favorites Endpoints

### Get User Favorites
```
GET /favorites
Headers: Authorization: Bearer {token}
Returns: { success, data: [favorites] }
Access: Private
```

### Add to Favorites
```
POST /favorites
Headers: Authorization: Bearer {token}
Body: { entryId }
Returns: { success, data: { favorite } }
Access: Private
```

### Remove from Favorites
```
DELETE /favorites/:entryId
Headers: Authorization: Bearer {token}
Returns: { success }
Access: Private
```

---

## 📜 History Endpoints

### Get User History
```
GET /history
Headers: Authorization: Bearer {token}
Returns: { success, data: [history] }
Access: Private
```

### Clear History
```
DELETE /history
Headers: Authorization: Bearer {token}
Returns: { success }
Access: Private
```

---

## 👤 User Endpoints

### Get Profile
```
GET /users/profile
Headers: Authorization: Bearer {token}
Returns: { success, data: { user } }
Access: Private
```

### Update Profile
```
PATCH /users/profile
Headers: Authorization: Bearer {token}
Body: { displayName?, avatarUrl? }
Returns: { success, data: { user } }
Access: Private
```

### Get Settings
```
GET /users/settings
Headers: Authorization: Bearer {token}
Returns: { success, data: { settings } }
Access: Private
```

### Update Settings
```
PATCH /users/settings
Headers: Authorization: Bearer {token}
Body: { theme?, language?, notifications? }
Returns: { success, data: { settings } }
Access: Private
```

---

## 🛠️ Staff Endpoints

### Get Content for Moderation
```
GET /staff/content?status={status}&category={id}&sortBy={field}&order={asc|desc}&page={n}&limit={n}&search={query}
Headers: Authorization: Bearer {token}
Returns: { success, data: { items: [entries], pagination: { page, limit, total, pages } } }
Access: Private (STAFF/ADMIN)
```

### Get Content By ID
```
GET /staff/content/:id
Headers: Authorization: Bearer {token}
Returns: { success, data: { entry } }
Access: Private (STAFF/ADMIN)
```

### Update Content
```
PATCH /staff/content/:id
Headers: Authorization: Bearer {token}
Body: { word?, definition?, ... }
Returns: { success, data: { entry } }
Access: Private (STAFF/ADMIN)
```

### Approve Content
```
POST /staff/content/:id/approve
Headers: Authorization: Bearer {token}
Returns: { success, data: { entry }, message }
Access: Private (STAFF/ADMIN)
```

### Reject Content
```
POST /staff/content/:id/reject
Headers: Authorization: Bearer {token}
Body: { reason }
Returns: { success, data: { entry }, message }
Access: Private (STAFF/ADMIN)
```

### Get Users (Support)
```
GET /staff/users?page={n}&limit={n}&search={query}&role={role}&status={status}
Headers: Authorization: Bearer {token}
Returns: { success, data: { users: [users], pagination } }
Access: Private (STAFF/ADMIN)
```

### Get User Details
```
GET /staff/users/:id
Headers: Authorization: Bearer {token}
Returns: { success, data: { user } }
Access: Private (STAFF/ADMIN)
```

### Get Reports
```
GET /staff/reports
Headers: Authorization: Bearer {token}
Returns: { success, data: { reports: [] } }
Access: Private (STAFF/ADMIN)
Note: Placeholder - implement based on Report model
```

### Update Report
```
PATCH /staff/reports/:id
Headers: Authorization: Bearer {token}
Body: { status }
Returns: { success, message }
Access: Private (STAFF/ADMIN)
Note: Placeholder - implement based on Report model
```

### Get Staff Stats
```
GET /staff/stats
Headers: Authorization: Bearer {token}
Returns: { success, data: { content: { pending, published }, users: { total, recentWeek } } }
Access: Private (STAFF/ADMIN)
```

---

## 👑 Admin Endpoints

### Get All Users
```
GET /admin/users?page={n}&limit={n}&search={query}&role={role}&status={status}&accountType={type}&sortBy={field}&order={asc|desc}
Headers: Authorization: Bearer {token}
Returns: { success, data: { users: [users], pagination } }
Access: Private (ADMIN)
```

### Get User By ID
```
GET /admin/users/:id
Headers: Authorization: Bearer {token}
Returns: { success, data: { user, stats: { activeSessions, favorites } } }
Access: Private (ADMIN)
```

### Update User
```
PATCH /admin/users/:id
Headers: Authorization: Bearer {token}
Body: { displayName?, role?, status?, avatarUrl? }
Returns: { success, data: { user }, message }
Access: Private (ADMIN)
```

### Delete User
```
DELETE /admin/users/:id
Headers: Authorization: Bearer {token}
Returns: { success, data: { user }, message }
Access: Private (ADMIN)
Note: Soft delete (sets status to DELETED)
```

### Suspend User
```
POST /admin/users/:id/suspend
Headers: Authorization: Bearer {token}
Body: { reason }
Returns: { success, data: { user }, message }
Access: Private (ADMIN)
```

### Activate User
```
POST /admin/users/:id/activate
Headers: Authorization: Bearer {token}
Returns: { success, data: { user }, message }
Access: Private (ADMIN)
```

### Get System Stats
```
GET /admin/stats
Headers: Authorization: Bearer {token}
Returns: { success, data: { users: {...}, content: {...}, sessions: {...}, timestamp } }
Access: Private (ADMIN)
```

### Get Pending Content
```
GET /admin/content/pending?page={n}&limit={n}
Headers: Authorization: Bearer {token}
Returns: { success, data: { items: [entries], pagination } }
Access: Private (ADMIN)
```

### Get Active Sessions
```
GET /admin/sessions?page={n}&limit={n}
Headers: Authorization: Bearer {token}
Returns: { success, data: { sessions: [sessions], pagination } }
Access: Private (ADMIN)
```

### Terminate Session
```
DELETE /admin/sessions/:sessionId
Headers: Authorization: Bearer {token}
Returns: { success, message }
Access: Private (ADMIN)
```

---

## 📋 Response Format

### Success Response
```json
{
  "success": true,
  "data": { ... },
  "message": "Optional success message"
}
```

### Error Response
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": { ... }
  }
}
```

### Paginated Response
```json
{
  "success": true,
  "data": {
    "items": [...],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total": 150,
      "pages": 8
    }
  }
}
```

---

## 🔑 Authentication

**Header Format:**
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Token Refresh Flow:**
1. Access token expires (401 with TOKEN_EXPIRED code)
2. Client calls POST /auth/refresh with refreshToken
3. Receive new accessToken
4. Retry original request with new token

**Flutter Implementation:**
```dart
// ApiClient handles this automatically
final response = await ApiClient.instance.get('/dictionary');
```

---

## 🚨 Error Codes

### Authentication Errors
- `AUTH_REQUIRED` - No token provided
- `AUTH_TOKEN_INVALID` - Malformed or invalid token
- `AUTH_TOKEN_EXPIRED` - Token expired, refresh needed
- `AUTH_SESSION_INVALID` - Session not found or expired
- `AUTH_USER_NOT_FOUND` - User not found or inactive
- `AUTH_FORBIDDEN` - Insufficient permissions
- `AUTH_GUEST_RESTRICTED` - Action requires permanent account

### Validation Errors
- `VALIDATION_ERROR` - Request validation failed
- `VALIDATION_MISSING_FIELD` - Required field missing
- `VALIDATION_INVALID_FORMAT` - Invalid field format

### Resource Errors
- `NOT_FOUND` - Resource not found
- `USER_NOT_FOUND` - User not found
- `DICT_ENTRY_NOT_FOUND` - Dictionary entry not found
- `CATEGORY_NOT_FOUND` - Category not found
- `FAVORITE_NOT_FOUND` - Favorite not found
- `HISTORY_NOT_FOUND` - History entry not found

### Server Errors
- `INTERNAL_SERVER_ERROR` - Unexpected server error
- `SERVICE_UNAVAILABLE` - Service temporarily unavailable

---

## 🔄 Rate Limiting

**Current:** No rate limiting implemented

**Recommendation for Production:**
- Anonymous: 100 requests/15 minutes
- Authenticated: 1000 requests/15 minutes
- Admin: Unlimited

---

## 🧪 Testing with cURL

### Register
```bash
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password123","displayName":"Test User"}'
```

### Login
```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password123"}'
```

### Get Dictionary (with auth)
```bash
curl -X GET http://localhost:3000/api/v1/dictionary \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

### Create Entry (STAFF)
```bash
curl -X POST http://localhost:3000/api/v1/dictionary \
  -H "Authorization: Bearer YOUR_STAFF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "word": "Hello",
    "definition": "A greeting",
    "videoUrl": "https://example.com/video.mp4",
    "categoryId": "60d5ec49f1b2c8b1f8c4e123"
  }'
```

---

**Last Updated:** October 9, 2026  
**Version:** 1.0 (Foundation)
