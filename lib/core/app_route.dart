import 'navigation.dart';

class AppRoute {
  const AppRoute._(this.uri, {this.screenId, this.known = false});

  final Uri uri;
  final String? screenId;
  final bool known;

  static AppRoute parse(
    String location, {
    Iterable<String> adminResources = const [],
  }) {
    try {
      final uri = Uri.parse(location);
      if (uri.hasScheme || uri.hasAuthority || uri.hasFragment) {
        return AppRoute._(uri);
      }
      final path = uri.path;
      if (screenNames.containsKey(path) ||
          const {
            'admin',
            'staff',
            'catalog',
            '/notifications',
            '/study-reminder',
          }.contains(path)) {
        return AppRoute._(uri, screenId: path, known: true);
      }
      if (path == '/oauth-complete' || path == '/reset-password') {
        return AppRoute._(uri, known: true);
      }
      final parts = uri.pathSegments;
      if (parts.any(
        (part) =>
            part.isEmpty || part.contains('/') || part == '.' || part == '..',
      )) {
        return AppRoute._(uri);
      }
      final learning =
          path == '/learn' ||
          path == '/learn/insights' ||
          path == '/learn/history' ||
          (parts.length == 3 &&
              parts[0] == 'learn' &&
              const {'topic', 'quiz'}.contains(parts[1]));
      final detail =
          parts.length == 2 &&
          const {'dictionary', 'conversations'}.contains(parts[0]);
      final admin =
          parts.length == 2 &&
          parts[0] == 'admin' &&
          adminResources.contains(parts[1]);
      final staff =
          (parts.length == 2 || parts.length == 3) &&
          parts[0] == 'staff' &&
          const {'content', 'users'}.contains(parts[1]);
      if (path.startsWith('/') && (learning || detail || admin || staff)) {
        return AppRoute._(
          uri,
          screenId: learning ? uri.toString() : path,
          known: true,
        );
      }
      return AppRoute._(uri);
    } on FormatException {
      return AppRoute._(Uri());
    }
  }
}
