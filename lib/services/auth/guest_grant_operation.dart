import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

// The server defines nextTrialAvailableAt = startedAt + exactly 86400000 ms.
String? expectedLastGrantAt(String? nextTrialAvailableAt) =>
    nextTrialAvailableAt == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(
        DateTime.parse(nextTrialAvailableAt).millisecondsSinceEpoch - 86400000,
        isUtc: true,
      ).toIso8601String();

class GuestGrantOperation {
  static const _pending = 'signvoice_guest_grant_pending';
  static const _observed = 'signvoice_guest_grant_next';

  static Future<void> observe(String? next) async {
    final prefs = await SharedPreferences.getInstance();
    if (next == null) {
      await prefs.remove(_observed);
    } else {
      await prefs.setString(_observed, next);
    }
  }

  static Future<Map<String, dynamic>> loadOrCreate({
    int? dataVersion,
    String? ownerId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pending);
    if (saved != null) {
      final value = Map<String, dynamic>.from(jsonDecode(saved) as Map);
      if (value['ownerId'] != ownerId ||
          value['confirmDiscard'] == true && dataVersion == null) {
        throw StateError(
          'Hãy xác minh lại phiên khách trước khi thử lại yêu cầu đang chờ.',
        );
      }
      return value;
    }
    final random = Random.secure();
    final value = <String, dynamic>{
      'requestKey': List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      'expectedLastGrantAt': expectedLastGrantAt(prefs.getString(_observed)),
      if (dataVersion != null) ...{
        'confirmDiscard': true,
        'expectedDataVersion': dataVersion,
        'ownerId': ownerId,
      },
    };
    if (!await prefs.setString(_pending, jsonEncode(value))) {
      throw StateError('Không lưu được yêu cầu dùng thử.');
    }
    return value;
  }

  // Only a separate, explicit later-grant consent may abandon an unknown operation.
  static Future<void> beginSeparateOperation() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_pending)) {
      throw StateError('Không lưu được lựa chọn yêu cầu mới.');
    }
  }

  static Future<void> finish(String requestKey) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(_pending);
    if (pending != null &&
        (jsonDecode(pending) as Map)['requestKey'] == requestKey) {
      await prefs.remove(_pending);
    }
  }
}
