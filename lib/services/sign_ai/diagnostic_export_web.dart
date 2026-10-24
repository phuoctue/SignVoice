import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<String> exportDiagnostic(String content) async {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = 'signvoice-camera-diagnostic.json';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
  return 'Đã tải file chẩn đoán JSON xuống thiết bị.';
}
