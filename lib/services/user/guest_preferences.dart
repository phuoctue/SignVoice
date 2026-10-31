import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class GuestPreferences {
  static const key = 'guest_pending_preferences_v1';
  static const fields = {
    'theme',
    'fontSize',
    'highContrast',
    'speechSpeed',
    'speechPitch',
    'autoSpeak',
  };
  static Map<String, dynamic> _pending = {};
  static Future<Map<String, dynamic>> read() async => Map.of(_pending);
  static Future<void> restore() async {
    _pending = {};
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return;
      final value = jsonDecode(raw);
      if (value is! Map) return;
      _pending = {
        for (final field in fields)
          if (value.containsKey(field)) field: value[field],
      };
    } catch (_) {
      _pending = {};
    }
  }

  static Future<void> save(Map<String, dynamic> changes) async {
    final prefs = await SharedPreferences.getInstance();
    final next = {...await read(), ...changes};
    await prefs.setString(key, jsonEncode(next));
    _pending = next;
  }

  static Future<void> consume(Map<String, dynamic> applied) async {
    final prefs = await SharedPreferences.getInstance();
    final remaining = await read();
    remaining.removeWhere((key, value) => applied[key] == value);
    if (remaining.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(remaining));
    }
    _pending = remaining;
  }
}
