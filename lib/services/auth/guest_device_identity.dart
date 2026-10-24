import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

// A quota identifier, never an authentication credential. Logout keeps it.
Future<String> guestDeviceKey() async {
  final prefs = await SharedPreferences.getInstance();
  const name = 'signvoice_guest_trial_device';
  final existing = prefs.getString(name);
  if (existing != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(existing)) {
    return existing;
  }
  final random = Random.secure();
  final key = List.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  await prefs.setString(name, key);
  return key;
}
