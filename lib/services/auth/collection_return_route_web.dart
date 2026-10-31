import 'package:web/web.dart' as web;

const key = 'signvoice.collection-return';
void save(String value) {
  try {
    web.window.sessionStorage.setItem(key, value);
  } catch (_) {}
}

String? consume() {
  try {
    final value = web.window.sessionStorage.getItem(key);
    web.window.sessionStorage.removeItem(key);
    return value;
  } catch (_) {
    return null;
  }
}
