import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';
import 'package:sign_voice/services/sign_ai/speech_input.dart';

class PendingPermissionEngine extends SpeechToTextPlatform {
  bool deny = false;
  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async {
    onStatus?.call('notListening'); // Initialization is not a microphone grant.
    return true;
  }

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    if (deny) {
      onError?.call(
        jsonEncode({'errorMsg': 'error_permission', 'permanent': true}),
      );
    }
    return true;
  }

  @override
  Future<void> stop() async {
    onStatus?.call('notListening');
  }

  @override
  Future<void> cancel() async {
    onStatus?.call('notListening');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual engine waits for listening event; rejection cannot fabricate microphone grant', () async {
    final original = SpeechToTextPlatform.instance;
    final engine = PendingPermissionEngine();
    SpeechToTextPlatform.instance = engine;
    final input = DeviceSpeechInput.instance;
    try {
      var completed = false;
      final request = input.start().then((_) {
        completed = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(input.busy, isTrue);
      expect(input.permissionGranted, isFalse);
      expect(completed, isFalse);
      engine.onStatus?.call('listening');
      await request;
      expect(input.permissionGranted, isTrue);
      expect(input.listening, isTrue);
      await input.cancel();
      engine.deny = true;
      await input.start();
      expect(input.permissionGranted, isFalse);
      expect(input.error, contains('microphone'));
      expect(input.text, isEmpty);
    } finally {
      await input.cancel();
      SpeechToTextPlatform.instance = original;
    }
  });
}
