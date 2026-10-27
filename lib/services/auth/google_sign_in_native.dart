import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/api_exception.dart';

class NativeGoogleSignIn {
  const NativeGoogleSignIn();
  static const _channel = MethodChannel('signvoice/google');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<String> signIn({
    required String clientId,
    required String nonce,
  }) async {
    if (!supported) {
      throw ApiException(message: 'Đăng nhập Google này chỉ hỗ trợ Android.');
    }
    try {
      final token = await _channel.invokeMethod<String>('signIn', {
        'clientId': clientId,
        'nonce': nonce,
      });
      if (token == null || token.isEmpty) {
        throw const FormatException('Missing Google proof');
      }
      return token;
    } on PlatformException catch (error) {
      throw ApiException(
        message: switch (error.code) {
          'GOOGLE_CANCELLED' => 'Đã hủy đăng nhập Google.',
          'GOOGLE_TIMEOUT' => 'Phiên Google hết thời gian. Vui lòng thử lại.',
          'GOOGLE_NO_ACCOUNT' =>
            'Hãy thêm tài khoản Google trong cài đặt điện thoại rồi thử lại.',
          _ => 'Không mở được đăng nhập Google. Kiểm tra mạng, Google Play Services và cấu hình Android OAuth.',
        },
        code: error.code,
      );
    } on MissingPluginException {
      throw ApiException(
        message: 'Hãy cài bản APK mới có hỗ trợ đăng nhập Google.',
      );
    }
  }

  Future<void> clear() async {
    if (!supported) return;
    try {
      await _channel
          .invokeMethod<void>('clear')
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Clearing the optional provider selection must not prevent local logout.
    }
  }
}
