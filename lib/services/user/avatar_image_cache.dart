import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';

final avatarImages = AvatarImageCache();

/// One owned avatar, at most 512 KB, in app-private preferences. Account changes
/// discard memory; logout also removes the persisted copy. URLs include content
/// hashes so an acknowledged replacement cannot reuse the previous image.
class AvatarImageCache {
  AvatarImageCache({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _key = 'signvoice_avatar_image_v1';
  String? _owner, _url;
  Uint8List? _bytes;
  int _generation = 0;
  final _pending = <String, Future<Uint8List>>{};
  Future<void> _writes = Future.value();

  bool accepts(String? owner, String source) {
    final uri = Uri.tryParse(ApiConfig.avatarMediaUrl(source));
    return owner != null &&
        owner == _owner &&
        uri != null &&
        uri.hasAuthority &&
        uri.origin == Uri.base.resolve(ApiConfig.baseUrl).origin &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        RegExp(
          '^/user-media/avatars/${RegExp.escape(owner)}/[a-f0-9]{64}\\.(jpg|png|webp)\$',
        ).hasMatch(uri.path);
  }

  void bind(String owner) {
    if (owner == _owner) return;
    _owner = owner;
    _generation++;
    _url = null;
    _bytes = null;
    _pending.clear();
  }

  Future<void> clear() {
    _owner = null;
    _generation++;
    _url = null;
    _bytes = null;
    _pending.clear();
    return _writes = _writes
        .then((_) async {
          await (await SharedPreferences.getInstance()).remove(_key);
        })
        .catchError((Object _) {});
  }

  Uint8List? peek(String? owner, String source) =>
      accepts(owner, source) && _url == ApiConfig.avatarMediaUrl(source)
      ? _bytes
      : null;

  void _select(String url) {
    if (_url == url) return;
    _generation++;
    _url = url;
    _bytes = null;
    _pending.clear();
  }

  Future<void> removeImage(String owner) {
    if (_owner != owner) return Future.value();
    _generation++;
    _url = null;
    _bytes = null;
    _pending.clear();
    return _writes = _writes
        .then((_) async {
          await (await SharedPreferences.getInstance()).remove(_key);
        })
        .catchError((Object _) {});
  }

  Future<void> seed(String owner, String source, Uint8List bytes) async {
    if (!accepts(owner, source) || bytes.isEmpty || bytes.length > 512 * 1024) {
      return;
    }
    final url = ApiConfig.avatarMediaUrl(source);
    _select(url);
    final generation = _generation;
    _url = url;
    _bytes = bytes;
    _writes = _writes
        .then((_) async {
          if (generation != _generation) return;
          await (await SharedPreferences.getInstance()).setString(
            _key,
            jsonEncode({
              'owner': owner,
              'url': url,
              'bytes': base64Encode(bytes),
            }),
          );
        })
        .catchError((Object _) {});
    await _writes;
  }

  Future<Uint8List> load(String owner, String source) {
    final cached = peek(owner, source);
    if (cached != null) return Future.value(cached);
    if (!accepts(owner, source)) {
      return Future.error(StateError('Avatar owner changed'));
    }
    final url = ApiConfig.avatarMediaUrl(source);
    _select(url);
    final generation = _generation;
    final key = '$owner:$url';
    return _pending.putIfAbsent(
      key,
      () => _load(owner, url, generation).whenComplete(() {
        if (generation == _generation) _pending.remove(key);
      }),
    );
  }

  Future<Uint8List> _load(String owner, String url, int generation) async {
    try {
      await _writes;
      final stored = (await SharedPreferences.getInstance()).getString(_key);
      if (stored != null && stored.length < 720000) {
        final data = jsonDecode(stored);
        if (generation == _generation &&
            data['owner'] == owner &&
            data['url'] == url) {
          final bytes = base64Decode(data['bytes'] as String);
          if (bytes.isNotEmpty && bytes.length <= 512 * 1024) {
            _url = url;
            _bytes = bytes;
            return bytes;
          }
        }
      }
    } catch (_) {
      /* A bad cache is replaced from the server. */
    }
    if (generation != _generation) throw StateError('Avatar source changed');
    final response = await _client
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > 512 * 1024) {
      await response.stream.listen((_) {}).cancel();
      throw StateError('Avatar unavailable');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      if (buffer.length + chunk.length > 512 * 1024) {
        throw StateError('Avatar too large');
      }
      buffer.add(chunk);
    }
    final bytes = buffer.takeBytes();
    if (generation != _generation ||
        bytes.isEmpty ||
        response.contentLength != null &&
            response.contentLength != bytes.length) {
      throw StateError('Avatar unavailable');
    }
    await seed(owner, url, bytes);
    return bytes;
  }
}
