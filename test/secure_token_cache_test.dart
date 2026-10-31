import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/services/storage/secure_token_storage.dart';

class ControlledStore extends FlutterSecureStorage {
  final values = <String, String>{
    'access_token': 'stored',
    'refresh_token': 'refresh',
  };
  int reads = 0;
  Completer<String?>? pending;
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    return pending?.future ?? Future.value(values[key]);
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'native API requests read Keystore once and rotations remain durable',
    () async {
      final disk = ControlledStore();
      final store = SecureTokenStorage(secureStorage: disk);
      expect(
        await Future.wait(List.generate(8, (_) => store.getAccessToken())),
        everyElement('stored'),
      );
      expect(disk.reads, 1);
      await store.saveTokens(
        accessToken: 'rotated',
        refreshToken: 'rotated-refresh',
      );
      expect(await store.getAccessToken(), 'rotated');
      expect(disk.reads, 1);
      expect(
        await SecureTokenStorage(secureStorage: disk).getAccessToken(),
        'rotated',
      );
      expect(disk.values['refresh_token'], 'rotated-refresh');
      await store.clearAll();
      expect(await store.getAccessToken(), isNull);
      expect(disk.values, isEmpty);
    },
  );
  for (final clear in [true, false]) {
    test(
      'a late native read cannot undo ${clear ? 'logout' : 'token rotation'}',
      () async {
        final disk = ControlledStore()..pending = Completer<String?>();
        final store = SecureTokenStorage(secureStorage: disk);
        final old = store.getAccessToken();
        await Future<void>.delayed(Duration.zero);
        if (clear) {
          await store.clearAll();
        } else {
          await store.saveTokens(
            accessToken: 'new',
            refreshToken: 'new-refresh',
          );
        }
        disk.pending!.complete('old');
        expect(await old, clear ? isNull : 'new');
        expect(await store.getAccessToken(), clear ? isNull : 'new');
      },
    );
  }
}
