import 'package:flutter/material.dart';

import '../../app/theme/bmd_theme.dart';
import '../../app/theme/tokens.dart';

/// A compact expressive header band for operational screens (slice 2 RD2.D1)
/// — the Dashboard hero's little sibling. Content-hugging (~96–120px
/// typical), never full-bleed: [BmdGradient.heroMesh] painted at low opacity
/// over the surface color so it reads as a tinted band, with a faint
/// [BmdGradient.glow] in one corner.
///
/// Static by construction — the band itself never animates; only slotted
/// children (e.g. `CountUp`s in [summary]) do, and those already respect
/// `motionOff`.
class ScreenHero extends StatelessWidget {
  const ScreenHero({
    required this.title,
    this.subtitle,
    this.summary = const [],
    this.actions = const [],
    this.meter,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Live chips/labels (screens put `CountUp` numbers here). Rendered as a
  /// [Wrap] so they flow on narrow viewports.
  final List<Widget> summary;

  /// Buttons that belong to this screen's header. A [Wrap], for the same
  /// reason the campaign-detail header uses one: a Row squeezes the title to
  /// nothing once a second button appears on a narrow viewport.
  final List<Widget> actions;

  /// Optional full-width row under the title block (e.g. campaign detail's
  /// attendance progress meter).
  final Widget? meter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: bmd.glassBorder),
        borderRadius: BorderRadius.circular(BmdRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BmdRadius.card),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: theme.colorScheme.surface),
            ),
            // The mesh at band opacity — a tint, not a poster.
            Positioned.fill(
              child: Opacity(
                opacity: isDark ? 0.18 : 0.12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: BmdGradient.heroMesh(isDark),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -40,
              top: -40,
              width: 220,
              height: 220,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: BmdGradient.glow(isDark)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(BmdSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.displayTitle,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: BmdSpace.s1),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: bmd.textSecondary,
                      ),
                    ),
                  ],
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: BmdSpace.s3),
                    Wrap(
                      spacing: BmdSpace.s3,
                      runSpacing: BmdSpace.s2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: summary,
                    ),
                  ],
                  if (meter != null) ...[
                    const SizedBox(height: BmdSpace.s3),
                    meter!,
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: BmdSpace.s4),
                    Wrap(
                      spacing: BmdSpace.s2,
                      runSpacing: BmdSpace.s2,
                      children: actions,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
