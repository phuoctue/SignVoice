// Local camera harness. The normal app entrypoint and authentication stay intact.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:sign_voice/app.dart' show screenFor;
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/core/theme.dart';
import 'package:sign_voice/features/recognition/live_camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    AppScope(
      state: AppState(),
      child: MaterialApp(
        title: 'SignVoice TCN180 camera test',
        debugShowCheckedModeBanner: false,
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: makeTheme(dark: false, highContrast: false),
        home: const LiveCameraScreen(),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => screenFor(settings.name ?? 'S10'),
        ),
      ),
    ),
  );
}
