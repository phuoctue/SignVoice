import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/user/avatar_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = '0123456789abcdef01234567';
  final url = '/user-media/avatars/$owner/${'a' * 64}.jpg';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('late old download cannot replace an acknowledged new avatar', () async {
    final old = Completer<http.Response>();
    final cache = AvatarImageCache(client: MockClient((_) => old.future))
      ..bind(owner);
    final pending = cache.load(owner, url);
    final rejected = expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    final changed = url.replaceAll('a' * 64, 'b' * 64);
    await cache.seed(owner, changed, Uint8List.fromList([4, 5, 6]));
    old.complete(http.Response.bytes([1, 2, 3], 200));
    await rejected;
    expect(cache.peek(owner, changed), [4, 5, 6]);
    var gets = 0;
    final reopened = AvatarImageCache(
      client: MockClient((_) async {
        gets++;
        throw StateError('No network expected');
      }),
    )..bind(owner);
    expect(await reopened.load(owner, changed), [4, 5, 6]);
    expect(gets, 0);
  });
  test('removing an avatar cancels its late download and clears its persisted copy', () async {
    final old = Completer<http.Response>();
    final cache = AvatarImageCache(client: MockClient((_) => old.future))
      ..bind(owner);
    final pending = cache.load(owner, url);
    final rejected = expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await cache.removeImage(owner);
    old.complete(http.Response.bytes([1, 2, 3], 200));
    await rejected;
    expect(cache.peek(owner, url), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'signvoice_avatar_image_v1',
      ),
      isNull,
    );
  });
  test('owned avatar survives restart without another HTTP request and clears at logout', () async {
    var gets = 0;
    final client = MockClient((_) async {
      gets++;
      return http.Response.bytes(Uint8List.fromList([255, 216, 255, 1]), 200);
    });
    final first = AvatarImageCache(client: client)..bind(owner);
    final bytes = await first.load(owner, url);
    final reopened = AvatarImageCache(client: client)..bind(owner);
    expect(await reopened.load(owner, url), orderedEquals(bytes));
    expect(gets, 1);
    reopened.bind('other');
    expect(reopened.accepts('other', url), isFalse);
    expect(reopened.peek(owner, url), isNull);
    await reopened.clear();
    expect(
      (await SharedPreferences.getInstance()).getString(
        'signvoice_avatar_image_v1',
      ),
      isNull,
    );
  });
  test('acknowledged new avatar cannot reuse the old content hash', () async {
    final cache = AvatarImageCache()..bind(owner);
    await cache.seed(owner, url, Uint8List.fromList([1, 2, 3]));
    final changed = url.replaceAll('a' * 64, 'b' * 64);
    expect(cache.peek(owner, changed), isNull);
    expect(cache.peek(owner, url), isNotNull);
    expect(cache.accepts(owner, 'https://external.example$url'), isFalse);
  });
  test(
    'profile renders the authenticated avatar before bootstrap completes',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      state.bindAccount(owner, asGuest: false, userAvatarUrl: url);
      expect(state.avatarUrl, url);
      state.bindAccount('another', asGuest: false);
      expect(state.avatarUrl, isEmpty);
    },
  );
}
