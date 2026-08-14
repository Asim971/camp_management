import 'package:flutter/widgets.dart';

/// Motion durations. Kept in one place so the whole app moves at one tempo.
abstract final class MotionDur {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 400);
}

/// Easing. `emphasized` for entrances/exits; `spring` for tactile feedback.
abstract final class MotionCurve {
  static const emphasized = Curves.easeOutCubic;
  static const spring = Cubic(0.34, 1.56, 0.64, 1.0);
}

/// True when the OS "reduce motion" setting (or web prefers-reduced-motion) is on.
bool motionOff(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// A duration that collapses to zero under reduced-motion — the single guard
/// every motion primitive routes through.
Duration reduced(BuildContext context, Duration d) =>
    motionOff(context) ? Duration.zero : d;
