import 'dart:js_interop';

import 'package:web/web.dart' as web;

void Function() onPageVisible(void Function() callback) {
  final listener = ((web.Event event) {
    if (web.document.visibilityState == 'visible') callback();
  }).toJS;
  web.document.addEventListener('visibilitychange', listener);
  return () => web.document.removeEventListener('visibilitychange', listener);
}
