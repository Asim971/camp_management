import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme/tokens.dart';
import 'motion_tokens.dart';

/// A skeleton placeholder block for content still loading (queue rows,
/// dashboard tiles): a glass-tinted rectangle with a moving highlight sweep.
/// Renders as a static block under reduced-motion.
class Shimmer extends StatelessWidget {
  const Shimmer({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bmd = Theme.of(context).bmd;
    final block = SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bmd.glassFill,
          borderRadius: BorderRadius.circular(BmdRadius.field),
          border: Border.all(color: bmd.glassBorder),
        ),
      ),
    );

    if (motionOff(context)) return block;

    return block
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: MotionDur.slow * 3,
          color: bmd.accent.withValues(alpha: 0.35),
        );
  }
}
