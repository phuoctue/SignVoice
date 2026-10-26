import 'package:flutter/material.dart';

import 'app.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'services/notifications/notification_background.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(handleBackgroundPush);
  }
  runApp(const SignVoiceApp());
}
