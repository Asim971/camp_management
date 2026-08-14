import 'package:flutter/material.dart';

import '../../../../app/theme/bmd_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/design_system/bmd_button.dart';
import '../../../../core/responsive/breakpoints.dart';

/// The Dashboard's hero header (W-01, top of page): the expressive mesh
/// gradient (spec RD.D1) behind the [BuildContext.displayHero] headline, a
/// session/context line, and the single primary CTA (Guideline §5.1 — one
/// filled primary action per page; every other action on this screen is a
/// tap-through, never a second filled button).
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    required this.greeting,
    required this.contextLine,
    required this.ctaLabel,
    required this.onCta,
    super.key,
  });

  final String greeting;
  final String contextLine;
  final String ctaLabel;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The 72px desktop display role would clip/wrap awkwardly on a narrow
    // phone; bmd_theme.dart's own doc says the responsive step-down is this
    // layer's job, not the token's, so it happens here rather than in Task
    // 3's `displayHero`.
    final headlineStyle = Breakpoint.of(context).isMobile
        ? context.displayHero.copyWith(fontSize: 40, height: 44 / 40)
        : context.displayHero;

    return Semantics(
      identifier: 'dashboard_hero',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(BmdSpace.s7),
        decoration: BoxDecoration(
          gradient: BmdGradient.heroMesh(isDark),
          borderRadius: BorderRadius.circular(BmdRadius.hero),
        ),
        child: Stack(
          children: [
            // Ambient glow (RD.D1) — decorative only, so a screen reader
            // announces just the text and CTA beneath it.
            Positioned.fill(
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: BmdGradient.glow(isDark),
                    borderRadius: BorderRadius.circular(BmdRadius.hero),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  greeting,
                  style: headlineStyle.copyWith(color: Colors.white),
                ),
                const SizedBox(height: BmdSpace.s2),
                Text(
                  contextLine,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: BmdSpace.s6),
                BmdButton(
                  identifier: 'dashboard_cta',
                  label: ctaLabel,
                  onPressed: onCta,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
