import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';

Future<void> dismissTestToasts(WidgetTester tester) async {
  toastification.dismissAll(delayForAnimation: false);
  // Toastification schedules overlay removal even when no frames are pending.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}
