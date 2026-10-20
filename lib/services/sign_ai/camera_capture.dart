import 'camera_capture_native.dart'
    if (dart.library.js_interop) 'camera_capture_web.dart'
    as platform;
import 'camera_types.dart';
export 'camera_types.dart';

SignCamera createSignCamera({required bool front}) =>
    platform.createSignCamera(front: front);
