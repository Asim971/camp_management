import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'motion_tokens.dart';

/// Fades and rises [child] into place, staggered by [index] (§ RD motion).
///
/// Used for list/grid entrances so rows read as a sequence rather than
/// popping in together. Under reduced-motion, `child` is shown at its final
/// opacity/offset on the very first frame — no delay, no animation — rather
/// than merely collapsing the duration to zero, because a zero-duration
/// [flutter_animate] effect still schedules its play through a delayed
/// future and would not have applied by the first `pump()`.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.index, required this.child});

  /// Position in the sequence this reveal belongs to; drives the stagger
  /// delay (`40ms * index`).
  final int index;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (motionOff(context)) {
      return Opacity(opacity: 1, child: child);
    }
    return child
        .animate()
        .fadeIn(
          duration: MotionDur.base,
          delay: Duration(milliseconds: 40 * index),
          curve: MotionCurve.emphasized,
        )
        .slideY(begin: 0.08, end: 0, curve: MotionCurve.emphasized);
  }
}
