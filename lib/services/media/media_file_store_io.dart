import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

final mediaFiles = MediaFileStore();
Future<Uint8List?> readMediaFile(Uri uri) => mediaFiles.read(uri);
Future<void> writeMediaFile(Uri uri, Uint8List bytes) =>
    mediaFiles.write(uri, bytes);

/// Only immutable, publicly served generated media. Account images/recordings
/// never enter this cache. Android's private cache directory needs no permission.
class MediaFileStore {
  MediaFileStore({
    Directory? directory,
    this.maxBytes = 64 * 1024 * 1024,
    this.maxAge = const Duration(days: 1),
  }) : directory =
           directory ??
           Directory('${Directory.systemTemp.path}/signvoice-media-v1');
  final Directory directory;
  final int maxBytes;
  final Duration maxAge;
  Future<void>? _ready, _pruning;
  DateTime? _lastPruned;
  int _written = 0;

  File? file(Uri uri) {
    if (!RegExp(r'^/sign-media/[a-f0-9]{64}(?:-[1-5])?\.(?:mp4|jpg)$')
            .hasMatch(uri.path) ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.host.length > 160) {
      return null;
    }
    final host = uri.host.replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_');
    return File(
      '${directory.path}/sv-${uri.scheme}-$host-${uri.port}-${uri.path.split('/').last}',
    );
  }

  Future<void> _initialize() =>
      _ready ??= directory.create(recursive: true).then((_) => prune());

  Future<Uint8List?> read(Uri uri) async {
    final target = file(uri);
    if (target == null) return null;
    await _initialize();
    try {
      final stat = await target.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size == 0 ||
          DateTime.now().difference(stat.modified) >= maxAge) {
        return null;
      }
      final bytes = await target.readAsBytes();
      await target.setLastAccessed(DateTime.now());
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(Uri uri, Uint8List bytes) async {
    final target = file(uri);
    if (target == null || bytes.isEmpty || bytes.length > maxBytes) return;
    await _initialize();
    final stat = await target.stat();
    if (stat.type == FileSystemEntityType.file &&
        stat.size == bytes.length &&
        DateTime.now().difference(stat.modified) < maxAge) {
      return;
    }
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    _written += bytes.length;
    if (_lastPruned == null ||
        DateTime.now().difference(_lastPruned!) > const Duration(seconds: 30) ||
        _written >= math.min(maxBytes ~/ 4, 4 * 1024 * 1024)) {
      await prune();
    }
  }

  Future<void> prune() =>
      _pruning ??= _prune().whenComplete(() => _pruning = null);
  Future<void> _prune() async {
    final entries = <(File, FileStat)>[];
    await for (final item in directory.list(followLinks: false)) {
      if (item is! File ||
          !item.uri.pathSegments.last.startsWith('sv-') ||
          !RegExp(r'[a-f0-9]{64}(?:-[1-5])?\.(?:mp4|jpg)$')
              .hasMatch(item.path)) {
        continue;
      }
      entries.add((item, await item.stat()));
    }
    entries.sort((a, b) => b.$2.accessed.compareTo(a.$2.accessed));
    var retained = 0, count = 0;
    for (final (file, stat) in entries) {
      if (retained + stat.size > maxBytes ||
          count >= 800 ||
          DateTime.now().difference(stat.modified) >= maxAge) {
        await file.delete();
      } else {
        retained += stat.size;
        count++;
      }
    }
    _written = 0;
    _lastPruned = DateTime.now();
  }
}
