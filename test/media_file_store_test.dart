import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/media/media_file_store_io.dart';
import 'package:sign_voice/services/media/video_byte_cache.dart';

void main() {
  late Directory directory;
  final first = Uri.parse('https://tunnel.example/sign-media/${'a' * 64}.mp4');
  final second = Uri.parse('https://tunnel.example/sign-media/${'b' * 64}.mp4');
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'signvoice-media-test-',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));

  test(
    'a new cache instance replays a downloaded clip without another request',
    () async {
      var calls = 0;
      final disk = MediaFileStore(directory: directory);
      final client = MockClient((_) async {
        calls++;
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      VideoByteCache fresh() => VideoByteCache(
        client: client,
        readDisk: disk.read,
        writeDisk: disk.write,
      );
      final one = fresh();
      await Future.wait([one.load(first), one.load(first)]);
      expect(calls, 1);
      expect(await fresh().load(first), orderedEquals([1, 2, 3, 4]));
      expect(calls, 1);
    },
  );

  test(
    'cache expiry and origin separation do not reuse stale or foreign media',
    () async {
      final disk = MediaFileStore(
        directory: directory,
        maxAge: const Duration(hours: 1),
      );
      await disk.write(first, Uint8List.fromList([1, 2, 3]));
      final foreign = first.replace(host: 'another.example');
      expect(await disk.read(foreign), isNull);
      await disk
          .file(first)!
          .setLastModified(DateTime.now().subtract(const Duration(hours: 2)));
      expect(await disk.read(first), isNull);
      expect(
        await disk.read(Uri.parse('https://tunnel.example/private/avatar.jpg')),
        isNull,
      );
    },
  );

  test('eviction respects a bounded disk budget', () async {
    final disk = MediaFileStore(directory: directory, maxBytes: 8);
    await disk.write(first, Uint8List(6));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await disk.write(second, Uint8List(6));
    final files = await directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    var total = 0;
    for (final file in files) {
      total += await file.length();
    }
    expect(total, lessThanOrEqualTo(8));
    expect(await disk.read(second), hasLength(6));
  });

  test(
    'failed or truncated downloads never become playable cached files',
    () async {
      final disk = MediaFileStore(directory: directory);
      final cache = VideoByteCache(
        client: MockClient((_) async => http.Response('', 503)),
        readDisk: disk.read,
        writeDisk: disk.write,
      );
      await expectLater(cache.load(first), throwsStateError);
      expect(await disk.read(first), isNull);
      expect(cache.retainedBytes, 0);
    },
  );
}
