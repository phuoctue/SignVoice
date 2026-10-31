import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/services/sign_ai/observation_pacer.dart';

void main() {
  test('20Hz observations retain 15 intervals per second', () {
    final gate = ObservationPacer();
    final sent = [
      for (var t = 1000; t <= 2000; t += 50)
        if (gate.claim(t)) t,
    ];
    expect(sent, hasLength(16));
    expect(sent.first, 1000);
    expect(sent.last, 2000);
  });
  test('48ms detector callbacks do not get halved by a minimum-gap timer', () {
    final gate = ObservationPacer();
    expect([
      for (var i = 0; i < 100; i++)
        if (gate.claim(i * 48)) i,
    ], hasLength(72));
  });
  test('stalls skip old deadlines and duplicate observations are rejected', () {
    final gate = ObservationPacer();
    expect(gate.claim(0), isTrue);
    expect(gate.claim(10000), isTrue);
    expect(gate.claim(10000), isFalse);
    expect(gate.claim(10001), isFalse);
    expect(gate.claim(10050), isFalse);
    expect(gate.claim(10100), isTrue);
    expect(gate.claim(10090), isFalse);
  });
  test(
    'invalid stamps do not advance the schedule and reset accepts new epoch',
    () {
      final gate = ObservationPacer();
      expect(gate.claim(double.nan), isFalse);
      expect(gate.claim(double.infinity), isFalse);
      expect(gate.claim(-1), isFalse);
      expect(gate.claim(1000), isTrue);
      expect(gate.claim(900), isFalse);
      gate.reset();
      expect(gate.claim(900), isTrue);
    },
  );
}
