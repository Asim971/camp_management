import 'dart:math' as math;

/// Pure, deterministic backoff policy — no clock or RNG dependency so it is
/// fully unit-testable (see test/core/backoff_test.dart). The engine asks
/// "given N prior attempts, how long until the next?" and "should I give up?".
class BackoffPolicy {
  const BackoffPolicy({
    this.base = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.maxRetries = 8,
    this.jitterFraction = 0.2,
  });

  final Duration base;
  final Duration maxDelay;
  final int maxRetries;

  /// Fraction of the computed delay used as deterministic jitter spread. The
  /// caller supplies the jitter seed (e.g. a hash of the task id) so behavior
  /// stays reproducible in tests while still de-synchronizing many devices.
  final double jitterFraction;

  bool shouldGiveUp(int retryCount) => retryCount >= maxRetries;

  /// Exponential: base * 2^retryCount, capped at [maxDelay], then a symmetric
  /// deterministic jitter in [-jitterFraction, +jitterFraction] applied via
  /// [jitterSeed] (0.0–1.0).
  Duration delayFor(int retryCount, {double jitterSeed = 0.5}) {
    final expMs = base.inMilliseconds * math.pow(2, retryCount);
    final cappedMs = math.min(expMs.toDouble(), maxDelay.inMilliseconds.toDouble());
    final spread = cappedMs * jitterFraction;
    final offset = (jitterSeed.clamp(0.0, 1.0) * 2 - 1) * spread; // [-spread, spread]
    final ms = (cappedMs + offset).clamp(0, maxDelay.inMilliseconds.toDouble());
    return Duration(milliseconds: ms.round());
  }
}

/// Stable 0.0–1.0 seed derived from a task id, so a given task always jitters
/// the same way but different tasks differ.
double jitterSeedFor(String taskId) {
  var hash = 0;
  for (final unit in taskId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return (hash % 1000) / 1000.0;
}
