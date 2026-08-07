import 'package:acsl_campaign/core/sync/backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackoffPolicy', () {
    const policy = BackoffPolicy(
      base: Duration(seconds: 2),
      maxDelay: Duration(minutes: 5),
      maxRetries: 8,
    );

    test('grows exponentially from the base', () {
      // jitterSeed 0.5 => zero offset, so we test the pure exponential curve.
      expect(policy.delayFor(0, jitterSeed: 0.5).inSeconds, 2);
      expect(policy.delayFor(1, jitterSeed: 0.5).inSeconds, 4);
      expect(policy.delayFor(2, jitterSeed: 0.5).inSeconds, 8);
      expect(policy.delayFor(3, jitterSeed: 0.5).inSeconds, 16);
    });

    test('is capped at maxDelay', () {
      expect(policy.delayFor(20, jitterSeed: 0.5), policy.maxDelay);
    });

    test('jitter stays within the configured fraction', () {
      final low = policy.delayFor(3, jitterSeed: 0.0).inMilliseconds;
      final high = policy.delayFor(3, jitterSeed: 1.0).inMilliseconds;
      const mid = 16000; // 2 * 2^3 seconds
      expect(low, lessThan(mid));
      expect(high, greaterThan(mid));
      // 20% spread on 16s => +/-3.2s
      expect(mid - low, closeTo(3200, 1));
      expect(high - mid, closeTo(3200, 1));
    });

    test('gives up at maxRetries', () {
      expect(policy.shouldGiveUp(7), isFalse);
      expect(policy.shouldGiveUp(8), isTrue);
    });

    test('jitterSeedFor is stable per id and varies across ids', () {
      expect(jitterSeedFor('task-a'), jitterSeedFor('task-a'));
      expect(jitterSeedFor('task-a'), isNot(jitterSeedFor('task-b')));
    });
  });
}
