# US-001-T01 — Navigation audit

## Phạm vi và phương pháp

Audit này thực hiện cho `T-AUDIT-001`, chỉ đọc các file được giao: `.agents/AGENT.md`, `docs/SPEC.md`, `docs/active/NON_AI_DELIVERY.md`, `docs/active/NON_AI_API.md`, `lib/app.dart`, `lib/core/app_route.dart`, `lib/core/navigation.dart`, `test/app_route_test.dart` và mục US-001-T01 trong `docs/TASKS.md`. Không sửa code/runtime hay backend.

## Kết luận ngắn

Quan sát tĩnh cho thấy implementation có hai đường khởi động native/web, dùng chung parser/AccessGate, chuẩn hóa legacy/web URL, xử lý callback OAuth/reset-password trước splash và có guard khi rời trang web. Chưa thấy lỗi tĩnh được xác nhận trong phạm vi đọc. Tuy nhiên, kiểm thử runtime/analyzer đã khởi chạy nhưng bị dừng vì tiến trình Dart chờ lâu; vì vậy chưa kết luận pass cho toàn bộ startup hoặc điều hướng thực tế.

## Đối chiếu yêu cầu và bằng chứng

| Kết quả | Quan sát | Bằng chứng |
|---|---|---|
| ĐÚNG theo quan sát tĩnh | Web khởi động từ `initialScreen`, `/` mặc định về `/home` khi là S01; `/welcome` được canonicalize về `/home`. | `lib/app.dart:80-99` |
| ĐÚNG theo quan sát tĩnh | Native dùng `onGenerateInitialRoutes` và `onGenerateRoute`, cùng `_route`/`AppRoute.parse`; route không hợp lệ hiển thị trang lỗi thay vì rơi vào màn hình khác. | `lib/app.dart:405-432`, `lib/app.dart:503-527` |
| ĐÚNG theo quan sát tĩnh | OAuth callback và reset-password được nhận diện trước khi lấy `screenId`; token reset chỉ được truyền vào màn hình reset, còn OAuth chỉ truyền lỗi query. | `lib/app.dart:434-446`, `lib/core/app_route.dart:31-32` |
| ĐÚNG theo quan sát tĩnh | Deep link external/scheme/authority/fragment bị từ chối; learning, dictionary/conversations, collections, admin và staff có kiểm tra hình dạng route/ID. | `lib/core/app_route.dart:15-17`, `lib/core/app_route.dart:34-82` |
| ĐÚNG theo quan sát tĩnh | Legacy ID và web path có ánh xạ hai chiều; push/replace/root chọn GoRouter trên web và Navigator trên native. | `lib/core/navigation.dart:24-81`, `lib/core/navigation.dart:126-145` |
| ĐÚNG theo quan sát tĩnh | Web redirect canonicalize URL và gọi exit guard khi đổi path; page được bọc trong `AppRouteExitScope`. | `lib/app.dart:90-99`, `lib/app.dart:114-143` |
| ĐÚNG theo quan sát tĩnh | Startup bỏ qua `auth.initialize()` khi đang ở OAuth callback; sau đó đồng bộ account vào `AppState`, unbind khi unauthenticated, và khởi động notification sau khi auth có trạng thái. | `lib/app.dart:308-335`, `lib/app.dart:337-368` |
| ĐÚNG theo test source | Test bao phủ đổi-password, collection ID, learning query/deep link, malformed/external link, admin/staff và static reset/OAuth route. | `test/app_route_test.dart:5-87` |
| THIẾU xác minh | Chưa có kết quả runtime chứng minh widget startup, native app-link/platform callback, web redirect thực tế, auth restore hoặc account-switch race trong audit này. | Kiểm thử bên dưới bị dừng; các file được giao không cung cấp bằng chứng runtime cho các luồng này. |
| THIẾU xác minh | Chưa audit backend contract, full Flutter suite, web build hoặc Android build vì ngoài kiểm tra hẹp của task và chưa chạy thành công. | `docs/SPEC.md:13-18`, `docs/active/NON_AI_DELIVERY.md:51-57` |

Không ghi nhận mục `SAI`/bug đã xác nhận từ quan sát tĩnh. Các mục “THIẾU xác minh” là giới hạn bằng chứng, không phải kết luận implementation sai.

## Kiểm thử và trạng thái bằng chứng

- Đã khởi chạy `flutter test test/app_route_test.dart`; tiến trình Dart chờ lâu không trả kết quả trong giới hạn phiên, đã dừng tiến trình do worker khởi chạy. **Chưa xác minh pass/fail**.
- Đã khởi chạy `flutter analyze lib/app.dart lib/core/app_route.dart lib/core/navigation.dart`; dùng cùng tiến trình bị chờ và đã dừng. **Chưa xác minh pass/fail**.
- Không chạy full `flutter analyze`, `flutter test`, backend checks, build, network test hoặc thay đổi setup/package.

## Phạm vi thay đổi

Chỉ cập nhật `docs/TASKS.md` để đăng ký/liên kết `US-001-T01` với `T-AUDIT-001`, và tạo file audit này. Không sửa `lib/`, `backend/`, `test/`, package files, Excel; đặc biệt không đụng `backend/src/routes/sign-collection.routes.ts`. Trạng thái: **T-AUDIT-001 DONE; review tài liệu PASS vòng 1/2 bởi reviewer session sạch [signvoice-19](ao://sessions/signvoice/signvoice-19), theo thông báo orchestrator signvoice-17 ngày 2026-11-06; Flutter/runtime US-001-T01 vẫn chưa xác minh**.
