import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/features/auth/landing_motion.dart';

void main() {
  testWidgets(
    'ambient motion repeats while visible and stops off screen and on disposal',
    (tester) async {
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  LandingBackdrop(
                    scroll: scroll,
                    child: const SizedBox(height: 300, width: 800),
                  ),
                  const SizedBox(height: 1400),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, true);
      scroll.jumpTo(600);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, false);
      scroll.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, true);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      scroll.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unrevealed content cannot take keyboard focus and announces visibility only once',
    (tester) async {
      final scroll = ScrollController(), focus = FocusNode();
      var visible = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 1000),
                  LandingReveal(
                    scroll: scroll,
                    onVisible: () => visible++,
                    child: TextButton(
                      focusNode: focus,
                      onPressed: () {},
                      child: const Text('Nội dung phía dưới'),
                    ),
                  ),
                  const SizedBox(height: 700),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(focus.canRequestFocus, false);
      expect(visible, 0);
      scroll.jumpTo(700);
      await tester.pumpAndSettle();
      expect(focus.canRequestFocus, true);
      expect(visible, 1);
      scroll.jumpTo(0);
      scroll.jumpTo(700);
      await tester.pumpAndSettle();
      expect(visible, 1);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      scroll.dispose();
    },
  );
}
