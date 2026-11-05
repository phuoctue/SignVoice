# Batch 02 Implementation Matrix

**Generated:** October 9, 2026  
**Status:** In Progress - Full Implementation Phase

---

## Current Project State

### Backend API Coverage

| Endpoint Group | Status | File | Notes |
|---------------|--------|------|-------|
| Auth | ✅ COMPLETE | auth.routes.ts | 8 endpoints |
| Dictionary | ✅ COMPLETE | dictionary.routes.ts | 7 endpoints |
| Categories | ✅ COMPLETE | category.routes.ts | 3 endpoints |
| Favorites | ✅ COMPLETE | favorites.routes.ts | 3 endpoints |
| History | ✅ COMPLETE | history.routes.ts | 2 endpoints |
| User | ✅ COMPLETE | user.routes.ts | 4 endpoints |
| Admin | ✅ COMPLETE | admin.routes.ts | 10 endpoints |
| Staff | ✅ COMPLETE | staff.routes.ts | 10 endpoints |

**Total Backend Endpoints:** 47

### Flutter Service Layer

| Service | Status | File | Notes |
|---------|--------|------|-------|
| ApiClient | ✅ COMPLETE | services/api/api_client.dart | HTTP client with auth |
| TokenStorage | ⚠️ SECURITY ISSUE | services/storage/token_storage.dart | Using SharedPreferences - MUST FIX |
| AuthService | ✅ COMPLETE | services/auth/auth_service.dart | 8 methods |
| DictionaryService | ✅ COMPLETE | services/dictionary/dictionary_service.dart | 9 methods |
| FavoritesService | ❌ NOT_STARTED | - | Need to create |
| HistoryService | ❌ NOT_STARTED | - | Need to create |
| UserService | ❌ NOT_STARTED | - | Need to create |
| AdminService | ❌ NOT_STARTED | - | Need to create |
| StaffService | ❌ NOT_STARTED | - | Need to create |

### Flutter Models

| Model | Status | File |
|-------|--------|------|
| UserModel | ✅ COMPLETE | models/user_model.dart |
| DictionaryEntryModel | ✅ COMPLETE | models/dictionary_entry_model.dart |
| CategoryModel | ✅ COMPLETE | models/category_model.dart |
| FavoriteModel | ❌ NOT_STARTED | - |
| HistoryEntryModel | ❌ NOT_STARTED | - |
| UserSettingsModel | ❌ NOT_STARTED | - |

### Flutter Providers

| Provider | Status | File |
|----------|--------|------|
| AuthProvider | ✅ COMPLETE | providers/auth_provider.dart |
| DictionaryProvider | ❌ NOT_STARTED | - |
| CategoryProvider | ❌ NOT_STARTED | - |
| FavoritesProvider | ❌ NOT_STARTED | - |
| HistoryProvider | ❌ NOT_STARTED | - |
| ProfileProvider | ❌ NOT_STARTED | - |
| SettingsProvider | ❌ NOT_STARTED | - |
| AdminProvider | ❌ NOT_STARTED | - |
| StaffProvider | ❌ NOT_STARTED | - |

---

## Screen Implementation Matrix

### USER Screens - Android + Web

| ID | Screen Name | Platform | File Path | UI Status | Backend API | Service | Provider | Integration | AI Dependency | Remaining Work |
|----|-------------|----------|-----------|-----------|-------------|---------|----------|-------------|---------------|----------------|
| U01 | Login | Both | screens/auth/login_screen.dart | ✅ IMPLEMENTED | POST /auth/login | AuthService | AuthProvider | ✅ COMPLETE | No | Test security |
| U02 | Register | Both | screens/auth/register_screen.dart | ✅ IMPLEMENTED | POST /auth/register | AuthService | AuthProvider | ✅ COMPLETE | No | Test security |
| U03 | Guest Login | Both | screens/auth/login_screen.dart | ✅ IMPLEMENTED | POST /auth/guest | AuthService | AuthProvider | ✅ COMPLETE | No | Test security |
| U04 | Home/Dashboard | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | Multiple | Multiple | Multiple | ❌ NOT_STARTED | No | Full implementation |
| U05 | Dictionary List | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /dictionary | DictionaryService | DictionaryProvider | ❌ NOT_STARTED | No | Full implementation |
| U06 | Dictionary Detail | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /dictionary/:id | DictionaryService | DictionaryProvider | ❌ NOT_STARTED | No | Full implementation |
| U07 | Dictionary Search | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /dictionary?search= | DictionaryService | DictionaryProvider | ❌ NOT_STARTED | No | Full implementation |
| U08 | Browse Categories | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /categories | DictionaryService | CategoryProvider | ❌ NOT_STARTED | No | Full implementation |
| U09 | Category Detail | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /categories/:slug | DictionaryService | CategoryProvider | ❌ NOT_STARTED | No | Full implementation |
| U10 | Favorites | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /favorites | FavoritesService | FavoritesProvider | ❌ NOT_STARTED | No | Full implementation |
| U11 | History | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /history | HistoryService | HistoryProvider | ❌ NOT_STARTED | No | Full implementation |
| U12 | Profile View | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /users/profile | UserService | ProfileProvider | ❌ NOT_STARTED | No | Full implementation |
| U13 | Edit Profile | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | PATCH /users/profile | UserService | ProfileProvider | ❌ NOT_STARTED | No | Full implementation |
| U14 | Settings | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | GET/PATCH /users/settings | UserService | SettingsProvider | ❌ NOT_STARTED | No | Full implementation |
| U15 | Sign Recognition | Android | ❌ NOT_STARTED | ❌ NOT_STARTED | N/A | N/A | N/A | ❌ AI_DEFERRED | YES | Show "AI chưa tích hợp" |
| U16 | OCR Screen | Android | ❌ NOT_STARTED | ❌ NOT_STARTED | N/A | N/A | N/A | ❌ AI_DEFERRED | YES | Show "AI chưa tích hợp" |
| U17 | Practice Mode | Android | ❌ NOT_STARTED | ❌ NOT_STARTED | N/A | N/A | N/A | ❌ AI_DEFERRED | YES | Show "AI chưa tích hợp" |
| U18 | AI Assistant | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | N/A | N/A | N/A | ❌ AI_DEFERRED | YES | Show "AI chưa tích hợp" |
| U19 | Live Translation | Android | ❌ NOT_STARTED | ❌ NOT_STARTED | N/A | N/A | N/A | ❌ AI_DEFERRED | YES | Show "AI chưa tích hợp" |
| U20 | Notifications | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | TBD | TBD | TBD | ❌ BLOCKED | No | Backend not implemented |
| U21 | Statistics | Both | ❌ NOT_STARTED | ❌ NOT_STARTED | TBD | TBD | TBD | ❌ BLOCKED | No | Backend not implemented |

**USER Summary:**
- Total: 21 screens
- Implemented: 3 (Auth screens)
- Ready to implement: 9 (Dictionary, Favorites, History, Profile, Settings)
- AI Deferred: 5
- Blocked: 2
- Not Started: 18

### STAFF Screens - Web Only

| ID | Screen Name | File Path | UI Status | Backend API | Service | Provider | Integration | Remaining Work |
|----|-------------|-----------|-----------|-------------|---------|----------|-------------|----------------|
| S01 | Staff Dashboard | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /staff/stats | StaffService | StaffProvider | ❌ NOT_STARTED | Full implementation |
| S02 | Content List | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /staff/content | StaffService | StaffProvider | ❌ NOT_STARTED | Full implementation |
| S03 | Content Detail | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /staff/content/:id | StaffService | StaffProvider | ❌ NOT_STARTED | Full implementation |
| S04 | Create Content | ❌ NOT_STARTED | ❌ NOT_STARTED | POST /dictionary | DictionaryService | StaffProvider | ❌ NOT_STARTED | Full implementation |
| S05 | Edit Content | ❌ NOT_STARTED | ❌ NOT_STARTED | PATCH /staff/content/:id | StaffService | StaffProvider | ❌ NOT_STARTED | Full implementation |
| S06 | Approve Content | ❌ NOT_STARTED | ❌ NOT_STARTED | POST /staff/content/:id/approve | StaffService | StaffProvider | ❌ NOT_STARTED | Full implementation |
| S07 | Reject Content | ❌ NOT_STARTED | ❌ NOT_STARTED | POST /staff/content/:id/reject | StaffService | StaffProvider | ❌ NOT_STARTED | Full implementation |
| S08 | User Support | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /staff/users | StaffService | StaffProvider | ❌ NOT_STARTED | Full implementation |
| S09 | Staff Profile | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /users/profile | UserService | ProfileProvider | ❌ NOT_STARTED | Full implementation |

**STAFF Summary:**
- Total: 9 screens
- Implemented: 0
- Not Started: 9

### ADMIN Screens - Web Only

| ID | Screen Name | File Path | UI Status | Backend API | Service | Provider | Integration | Remaining Work |
|----|-------------|-----------|-----------|-------------|---------|----------|-------------|----------------|
| A01 | Admin Dashboard | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /admin/stats | AdminService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A02 | User Management | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /admin/users | AdminService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A03 | User Detail | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /admin/users/:id | AdminService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A04 | Edit User | ❌ NOT_STARTED | ❌ NOT_STARTED | PATCH /admin/users/:id | AdminService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A05 | Suspend User | ❌ NOT_STARTED | ❌ NOT_STARTED | POST /admin/users/:id/suspend | AdminService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A06 | Content Moderation | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /admin/content/pending | AdminService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A07 | Approve Content | ❌ NOT_STARTED | ❌ NOT_STARTED | POST /dictionary/:id/publish | DictionaryService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A08 | Reject Content | ❌ NOT_STARTED | ❌ NOT_STARTED | POST /dictionary/:id/archive | DictionaryService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A09 | Category Management | ❌ NOT_STARTED | ❌ NOT_STARTED | GET/POST /categories | CategoryService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A10 | Session Management | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /admin/sessions | AdminService | AdminProvider | ❌ NOT_STARTED | Full implementation |
| A11 | Admin Profile | ❌ NOT_STARTED | ❌ NOT_STARTED | GET /users/profile | UserService | ProfileProvider | ❌ NOT_STARTED | Full implementation |

**ADMIN Summary:**
- Total: 11 screens
- Implemented: 0
- Not Started: 11

---

## Critical Issues Identified

### 🔴 SECURITY CRITICAL

**Issue:** Token storage using SharedPreferences  
**File:** `lib/services/storage/token_storage.dart`  
**Risk:** Refresh tokens stored insecurely in plain text  
**Required Action:**
- Android: Migrate to flutter_secure_storage (Android Keystore)
- Web: Implement HttpOnly cookie strategy for refresh tokens
- Priority: IMMEDIATE (Milestone A)

### ⚠️ HIGH PRIORITY

1. **No screens beyond auth** - Need to implement all 41 screens
2. **No providers beyond auth** - Need 8 more providers
3. **No services beyond auth/dictionary** - Need 7 more services
4. **No models beyond core** - Need 3 more models
5. **No navigation system** - Need role-based routing
6. **No responsive layouts** - Need Web-specific layouts
7. **No error boundaries** - Need global error handling
8. **No tests** - Need comprehensive test coverage

---

## Implementation Priorities

### Phase 1: Security & Foundation (Milestone A)
1. ✅ Fix token storage security
2. ✅ Verify auth flows
3. ✅ Test session restoration
4. ✅ Implement single-flight refresh

### Phase 2: Dictionary Feature (Milestone B)
1. Create DictionaryProvider
2. Create CategoryProvider  
3. Implement Dictionary List screen
4. Implement Dictionary Detail screen
5. Implement Search screen
6. Implement Category browse screen
7. Add tests

### Phase 3: User Features (Milestone C)
1. Create FavoritesService + Provider + Screens
2. Create HistoryService + Provider + Screens
3. Create UserService + ProfileProvider + Screens
4. Create SettingsProvider + Screen
5. Implement Home/Dashboard
6. Add tests

### Phase 4: Android Polish (Milestone D)
1. Implement navigation
2. Handle AI-deferred screens
3. Test responsiveness
4. Verify all screens accessible

### Phase 5: Web USER (Milestone E)
1. Responsive shell
2. Desktop navigation
3. Adapt all USER screens for Web
4. Test responsive breakpoints

### Phase 6: STAFF Website (Milestone F)
1. Dashboard layout
2. Content management
3. Workflow implementation
4. Tests

### Phase 7: ADMIN Website (Milestone G)
1. Admin shell
2. User management
3. Content moderation
4. Category management
5. Audit viewer
6. Tests

### Phase 8: Quality (Milestone H)
1. Cross-platform tests
2. Security tests
3. Flutter analyze
4. Build verification
5. E2E scenarios
6. Documentation

---

## Milestone Status

| Milestone | Description | Status | Completion |
|-----------|-------------|--------|------------|
| A | Security & Auth | 🔴 IN PROGRESS | 10% |
| B | Dictionary UI | ⚪ NOT STARTED | 0% |
| C | User Features | ⚪ NOT STARTED | 0% |
| D | Android Polish | ⚪ NOT STARTED | 0% |
| E | Web USER | ⚪ NOT STARTED | 0% |
| F | STAFF Website | ⚪ NOT STARTED | 0% |
| G | ADMIN Website | ⚪ NOT STARTED | 0% |
| H | Quality & Testing | ⚪ NOT STARTED | 0% |

---

## Overall Progress

**Backend:** 100% (47 endpoints complete)  
**Flutter Services:** 25% (2/8 complete)  
**Flutter Models:** 50% (3/6 complete)  
**Flutter Providers:** 11% (1/9 complete)  
**Screens:** 7% (3/41 complete)  
**Tests:** 0%  
**Overall:** ~15% Complete

**Next Action:** Fix token storage security (Milestone A1-A2)

---

*Last Updated: October 9, 2026 - Start of full implementation phase*
