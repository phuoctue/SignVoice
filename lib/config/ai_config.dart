import 'package:flutter/foundation.dart';

class AIConfig {
  /// IPv4 mặc định của laptop
  static String laptopIp = '10.12.58.197';
  static int port = 1234;

  /// URL tuỳ chỉnh thủ công (nếu người dùng thay đổi trên UI)
  static String? customBaseUrl;

  /// Lấy Base URL tự động hoặc tuỳ biến
  static String get baseUrl {
    if (customBaseUrl != null && customBaseUrl!.isNotEmpty) {
      return customBaseUrl!;
    }

    const envUrl = String.fromEnvironment('LM_STUDIO_URL');
    if (envUrl.isNotEmpty) return envUrl;

    if (kIsWeb) {
      // Trên Web (điện thoại hoặc máy tính), gọi qua Backend AI proxy để tránh bị chặn HTTPS/Mixed Content/Khác mạng
      final origin = Uri.base.origin;
      return '$origin/api/v1/ai';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return 'http://127.0.0.1:$port/v1';
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      default:
        // Mặc định kết nối qua mạng nội bộ đến laptop cho điện thoại thật
        return 'http://$laptopIp:$port/v1';
    }
  }

  /// URL Android Emulator
  static String get emulatorUrl => 'http://10.0.2.2:$port/v1';

  /// URL mạng LAN
  static String get lanUrl => 'http://$laptopIp:$port/v1';
}
