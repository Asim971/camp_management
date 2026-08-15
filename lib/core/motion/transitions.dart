import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'motion_tokens.dart';

/// A same-elevation cross-fade for peer/tab navigation (switching between
/// dashboard, campaigns, verification, etc.): nothing implies "deeper" or
/// "shallower", so only opacity changes. Instant under reduced-motion.
Page<T> fadeThroughPage<T>({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: MotionDur.base,
    reverseTransitionDuration: MotionDur.base,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (motionOff(context)) return child;
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: MotionCurve.emphasized,
        ),
        child: child,
      );
    },
  );
}

/// A fade + horizontal slide for drill-down navigation (list → detail, e.g.
/// `/verification/cases/:id`, `/campaigns/:id`, capture): signals "deeper"
/// without a hard directional slide. Instant under reduced-motion.
Page<T> sharedAxisPage<T>({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: MotionDur.base,
    reverseTransitionDuration: MotionDur.base,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (motionOff(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: MotionCurve.emphasized,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
