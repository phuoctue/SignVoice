import 'dart:io';

Future<String> exportUserData(String content) async {
  final file = File(
    '${Directory.systemTemp.path}/signvoice-personal-data-${DateTime.now().millisecondsSinceEpoch}.json',
  );
  await file.writeAsString(content, flush: true);
  return 'Đã lưu file JSON tại: ${file.path}';
}
