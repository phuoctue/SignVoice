import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/services/api/api_config.dart';

void main() {
  final hash = 'a' * 64;
  test(
    'local image and video use API host even when saved with an old tunnel URL',
    () {
      final api = Uri.parse('http://localhost:3000/api/v1');
      for (final file in ['$hash-4.jpg', '$hash.mp4']) {
        expect(
          signMediaUrl('https://old.conveyor.cloud/sign-media/$file', api),
          'http://localhost:3000/sign-media/$file',
        );
      }
    },
  );
  test('Android emulator and public origin resolve their own backend', () {
    expect(
      signMediaUrl(
        'https://old.conveyor.cloud/sign-media/$hash.mp4',
        Uri.parse('http://10.0.2.2:3000/api/v1'),
      ),
      'http://10.0.2.2:3000/sign-media/$hash.mp4',
    );
    final api = Uri.parse('https://new.conveyor.cloud').resolve('/api/v1');
    expect(
      signMediaUrl('https://old.conveyor.cloud/sign-media/$hash-1.jpg', api),
      'https://new.conveyor.cloud/sign-media/$hash-1.jpg',
    );
  });
  test('external media and unrelated paths remain unchanged', () {
    final api = Uri.parse('http://localhost:3000/api/v1');
    for (final url in [
      'https://cdn.example.org/video.mp4',
      'https://example.org/sign-media/other.jpg',
      'https://example.org/sign-media/$hash.mp4?custom=1',
    ]) {
      expect(signMediaUrl(url, api), url);
    }
  });
}
