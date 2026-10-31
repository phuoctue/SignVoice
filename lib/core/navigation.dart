import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppRouteExitController {
  Future<bool> Function()? handler;
  Future<bool> allowExit() async => await handler?.call() ?? true;
}

class AppRouteExitScope extends InheritedWidget {
  const AppRouteExitScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final AppRouteExitController controller;
  static AppRouteExitController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppRouteExitScope>()
      ?.controller;
  @override
  bool updateShouldNotify(AppRouteExitScope oldWidget) =>
      controller != oldWidget.controller;
}

const webPaths = <String, String>{
  'S01': '/home',
  'S05': '/login',
  'S06': '/register',
  'S07': '/forgot-password',
  'S08': '/dashboard',
  'S10': '/sign-to-speech',
  'S15': '/speech-to-sign',
  'S20': '/history',
  'S22': '/dictionary',
  'S24': '/favorites',
  'S25': '/profile',
  'S26': '/profile/edit',
  'admin': '/admin',
  'staff': '/staff',
};

String webLocation(String id) {
  final uri = Uri.parse(id);
  final path =
      webPaths[uri.path] ??
      (uri.path.startsWith('/') ? uri.path : '/${uri.path}');
  return uri.replace(path: path).toString();
}

String legacyLocation(String location) {
  final uri = Uri.parse(location);
  final match = webPaths.entries.where((entry) => entry.value == uri.path);
  final path = match.isNotEmpty
      ? match.first.key
      : (uri.path.startsWith('/S') ? uri.path.substring(1) : uri.path);
  return uri.replace(path: path).toString();
}

Future<T?> pushAppRoute<T extends Object?>(
  BuildContext context,
  String id, {
  Object? arguments,
}) {
  final router = GoRouter.maybeOf(context);
  return router != null
      ? router.push<T>(webLocation(id), extra: arguments)
      : Navigator.of(context).pushNamed<T>(id, arguments: arguments);
}

Future<T?> replaceAppRoute<T extends Object?, TO extends Object?>(
  BuildContext context,
  String id, {
  Object? arguments,
  TO? result,
}) {
  final router = GoRouter.maybeOf(context);
  return router != null
      ? router.pushReplacement<T>(webLocation(id), extra: arguments)
      : Navigator.of(
          context,
        ).pushReplacementNamed<T, TO>(id, arguments: arguments, result: result);
}

const screenNames = <String, String>{
  'S01': 'Giới thiệu SignVoice',
  'S02': 'Onboarding 1',
  'S03': 'Onboarding 2',
  'S04': 'Onboarding 3',
  'S05': 'Đăng nhập',
  'S06': 'Đăng ký',
  'S07': 'Quên mật khẩu',
  'S08': 'Trang chủ',
  'S09': 'Cấp quyền Camera',
  'S10': 'Camera sẵn sàng',
  'S11': 'Nhận diện thành công',
  'S12': 'Nhận diện thất bại',
  'S13': 'Tạo câu',
  'S14': 'Phát giọng nói',
  'S15': 'Cấp quyền Micro',
  'S16': 'Microphone sẵn sàng',
  'S17': 'Đang lắng nghe',
  'S18': 'Kết quả văn bản',
  'S19': 'Văn bản toàn màn hình',
  'S20': 'Lịch sử hội thoại',
  'S21': 'Chi tiết lịch sử',
  'S22': 'Từ điển ký hiệu',
  'S23': 'Chi tiết ký hiệu',
  'S24': 'Yêu thích',
  'S25': 'Cá nhân',
  'S26': 'Chỉnh sửa hồ sơ',
  'change-password': 'Đổi mật khẩu',
  'S27': 'Cài đặt giọng nói',
  'S28': 'Giao diện & Trợ năng',
  'S29': 'Đồng bộ dữ liệu',
  'S30': 'Quyền riêng tư',
  'S31': 'Thông tin ứng dụng',
  'SS01': 'Loading',
  'SS02': 'Empty State',
  'SS03': 'Success',
  'SS04': 'Error',
  'SS05': 'Offline',
  'SS06': 'Quyền bị từ chối',
  'ai_vision': 'Camera ký hiệu',
};

void openScreen(BuildContext context, String id, {bool replace = false}) {
  if (replace) {
    replaceAppRoute(context, id);
  } else {
    pushAppRoute(context, id);
  }
}

void openRoot(BuildContext context, String id) {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    router.go(webLocation(id));
  } else {
    Navigator.of(context).pushNamedAndRemoveUntil(id, (route) => false);
  }
}

void backOrHome(BuildContext context) {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  } else {
    openRoot(context, 'S08');
  }
}
