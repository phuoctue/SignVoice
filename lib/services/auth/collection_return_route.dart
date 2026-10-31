import 'collection_return_route_stub.dart'
    if (dart.library.js_interop) 'collection_return_route_web.dart'
    as platform;

String? validCollectionReturnRoute(String? value) =>
    value != null &&
        RegExp(r'^/collections/shared/[a-f0-9]{32}$').hasMatch(value)
    ? value
    : null;
void saveCollectionReturnRoute(String? value) {
  final route = validCollectionReturnRoute(value);
  if (route != null) platform.save(route);
}

String? consumeCollectionReturnRoute() =>
    validCollectionReturnRoute(platform.consume());
