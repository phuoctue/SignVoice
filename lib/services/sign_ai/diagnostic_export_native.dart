import 'dart:io';

Future<String> exportDiagnostic(String content) async {
  final file = File(
    '${Directory.systemTemp.path}/signvoice-camera-diagnostic-${DateTime.now().millisecondsSinceEpoch}.json',
  );
  await file.writeAsString(content, flush: true);
  return 'Đã lưu cục bộ: ${file.path}\nAndroid: dùng Device Explorer trong Android Studio để lấy file này.';
}
