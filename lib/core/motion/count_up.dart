import 'package:flutter/widgets.dart';

import 'motion_tokens.dart';

/// Animates from `0` to [value], for headline metrics (dashboard tiles,
/// approval counts). Formats with `.round()`, optionally suffixed (e.g. `%`).
///
/// Reduced-motion note: [reduced] collapses `duration` to [Duration.zero],
/// and [TweenAnimationBuilder] starts its internal [AnimationController]
/// synchronously in `initState` — a zero-duration `forward()` snaps the
/// controller straight to `completed` before the first frame is even built,
/// so the target value is what renders on the very first `pump()`. No
/// separate reduced-motion branch is needed here (unlike [Reveal]).
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, this.style, this.suffix});

  final num value;
  final TextStyle? style;
  final String? suffix;

  String _format(num v) {
    final rounded = v.round();
    return suffix == null ? '$rounded' : '$rounded$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: reduced(context, MotionDur.slow),
      curve: MotionCurve.emphasized,
      builder: (context, v, child) => Text(_format(v), style: style),
    );
  }
}
