import 'package:flutter/material.dart';

import 'app.dart';
import 'services/user/guest_preferences.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'services/notifications/notification_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(handleBackgroundPush);
  }
  await GuestPreferences.restore();
  runApp(const SignVoiceApp(enableLibraryUpdates: true));
}
