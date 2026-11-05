import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/core/app_route.dart';
import 'package:sign_voice/core/navigation.dart';

void main() {
  test('change password public URL resolves to the existing screen', () {
    expect(webLocation('change-password'), '/change-password');
    expect(legacyLocation('/change-password'), 'change-password');
    final route = AppRoute.parse(legacyLocation('/change-password'));
    expect(route.known, isTrue);
    expect(route.screenId, 'change-password');
  });
  test(
    'collection links validate ids and keep the legacy private cards route',
    () {
      for (final path in [
        '/collections/discover',
        '/learn/personal',
        '/collections/${'a' * 24}',
        '/collections/${'a' * 24}/add',
        '/collections/save/${'a' * 24}',
        '/collections/shared/${'b' * 32}',
      ]) {
        expect(AppRoute.parse(path).known, isTrue, reason: path);
      }
      for (final path in [
        '/collections/nope',
        '/collections/shared/${'b' * 24}',
        '/collections/${'a' * 24}/unknown',
        '/collections/save/${'a' * 24}/extra',
      ]) {
        expect(AppRoute.parse(path).known, isFalse, reason: path);
      }
    },
  );
  test('learning insights and history links preserve filters', () {
    for (final location in [
      '/learn/insights',
      '/learn/history',
      '/learn/history?entryId=word-1',
    ]) {
      final route = AppRoute.parse(location);
      expect(route.known, isTrue, reason: location);
      expect(route.screenId, location);
    }
    expect(AppRoute.parse('/learn/history/extra').known, isFalse);
  });

  test(
    'learning deep links preserve query parameters and decoded identifiers',
    () {
      final route = AppRoute.parse('/learn/topic/chao%20hoi?study=1');
      expect(route.known, isTrue);
      expect(route.screenId, '/learn/topic/chao%20hoi?study=1');
      expect(route.uri.pathSegments.last, 'chao hoi');
      expect(route.uri.queryParameters['study'], '1');
      expect(AppRoute.parse('/learn?tab=2').screenId, '/learn?tab=2');
    },
  );

  test(
    'malformed and external links cannot fall through to another screen',
    () {
      for (final path in [
        '/learn/topic',
        '/learn/topic/',
        '/learn/topic/a/extra',
        '/learner',
        '/dictionary/',
        '/conversations/a/extra',
        'https://example.com/learn',
        '//example.com/learn',
        '/learn#topic',
        '/learn/topic/a%2Fb',
        '/learn/topic/%FF',
      ]) {
        expect(AppRoute.parse(path).known, isFalse, reason: path);
      }
    },
  );

  test(
    'admin resources are restricted and staff detail routes remain supported',
    () {
      expect(
        AppRoute.parse('/admin/users', adminResources: ['users']).known,
        isTrue,
      );
      expect(
        AppRoute.parse('/admin/unknown', adminResources: ['users']).known,
        isFalse,
      );
      expect(
        AppRoute.parse('/staff/users/user-1').screenId,
        '/staff/users/user-1',
      );
      expect(AppRoute.parse('/staff/unknown').known, isFalse);
    },
  );

  test('static screens normalize the URI path before access checks', () {
    expect(AppRoute.parse('S08').screenId, 'S08');
    expect(AppRoute.parse('S05?source=link').screenId, 'S05');
    expect(AppRoute.parse('admin?source=link').screenId, 'admin');
    expect(AppRoute.parse('catalog').screenId, 'catalog');
    expect(AppRoute.parse('/reset-password?token=abc').known, isTrue);
    expect(AppRoute.parse('/oauth-complete?error=denied').known, isTrue);
  });
}
