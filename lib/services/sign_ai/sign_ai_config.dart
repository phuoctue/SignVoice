import 'package:flutter/foundation.dart';

import '../api/api_config.dart';

class SignAiConfig {
  static const configuredUrl = String.fromEnvironment('AI_SERVICE_URL');
  static const token = String.fromEnvironment('AI_SERVICE_TOKEN');
  static String get gatewayUrl =>
      Uri.base.resolve(ApiConfig.baseUrl).resolve('/sign-ai').toString();

  static String get defaultUrl {
    if (configuredUrl.isNotEmpty) {
      if (kIsWeb &&
          configuredUrl.startsWith('/') &&
          !configuredUrl.startsWith('//')) {
        return Uri.base.resolve(configuredUrl).toString();
      }
      return configuredUrl;
    }
    return gatewayUrl;
  }

  static Uri socketUri(String base, {Uri? appUri}) {
    final app = appUri ?? (kIsWeb ? Uri.base : null);
    final input = base.trim();
    final uri = input.startsWith('/') && !input.startsWith('//') && app != null
        ? app.resolve(input)
        : Uri.parse(input);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Nhập URL HTTP/HTTPS của service AI.');
    }
    const loopbacks = {'localhost', '127.0.0.1', '::1'};
    if (app != null &&
        uri.scheme == app.scheme &&
        (uri.host == app.host ||
            (loopbacks.contains(uri.host) && loopbacks.contains(app.host))) &&
        uri.port == app.port &&
        (uri.path.isEmpty || uri.path == '/')) {
      throw FormatException(
        'Địa chỉ này là giao diện Flutter, không phải service AI. '
        'Dùng ${app.scheme}://${app.host}:8001 cho service AI riêng.',
      );
    }
    if (app?.scheme == 'https' && uri.scheme != 'https') {
      throw const FormatException('Trang HTTPS cần địa chỉ service AI HTTPS.');
    }
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      path: '${uri.path.replaceFirst(RegExp(r'/$'), '')}/v1/stream',
    );
  }
}
