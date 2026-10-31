import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/user/guest_preferences.dart';
import 'package:http/http.dart' as http;

import 'user_data_integration_test.dart' show UserDataFixture;

class RetryPreferencesFixture extends UserDataFixture {
  bool offline = true;
  @override
  Future<http.Response> handle(http.Request request) async {
    if (offline &&
        request.method == 'PATCH' &&
        request.url.path.endsWith('/users/settings'))
      return http.Response('{}', 503);
    return super.handle(request);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GuestPreferences.restore();
  });
  test('failed preference transfer keeps the account usable and retries without losing choices', () async {
    await GuestPreferences.save({'theme': 'DARK'});
    final fixture = RetryPreferencesFixture();
    final state = AppState(service: fixture.service)
      ..bindAccount('owner', asGuest: false);
    expect(await state.synchronize(), true);
    expect(state.ready, true);
    expect(await GuestPreferences.read(), {'theme': 'DARK'});
    fixture.offline = false;
    expect(await state.synchronize(), true);
    expect(fixture.settings['theme'], 'DARK');
    expect(await GuestPreferences.read(), isEmpty);
    state.dispose();
    fixture.api.dispose();
  });
  test('guest choices survive recreation and transfer once to the next signed-in account', () async {
    final guest = AppState()..guest = true;
    expect(
      await guest.saveSettings({
        'speechSpeed': 1.4,
        'speechPitch': .8,
        'fontSize': 20,
        'theme': 'DARK',
      }),
      true,
    );
    expect(guest.speechSpeed, 1.4);
    expect(guest.fontScale, 1.25);
    guest.dispose();
    await GuestPreferences.restore();
    final fixture = UserDataFixture();
    final state = AppState(service: fixture.service)
      ..bindAccount('owner', asGuest: false);
    expect(await state.synchronize(), true);
    expect(state.speechSpeed, 1.4);
    expect(fixture.settings['theme'], 'DARK');
    expect(await GuestPreferences.read(), isEmpty);
    state.unbindAccount();
    fixture.settings = {'speechSpeed': 1.0, 'theme': 'LIGHT'};
    state.bindAccount('other', asGuest: false);
    await state.synchronize();
    expect(state.speechSpeed, 1);
    expect(fixture.settings['theme'], 'LIGHT');
    state.dispose();
    fixture.api.dispose();
  });
}
