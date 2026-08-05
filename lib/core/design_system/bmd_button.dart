import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../responsive/breakpoints.dart';

/// Button variants from Guideline §5.1. Rule: a single filled primary action
/// per page/step; use tonal/outlined/text for everything else, danger for
/// irreversible destructive actions.
enum BmdButtonVariant { primary, tonal, outlined, text, danger }

class BmdButton extends StatelessWidget {
  const BmdButton({
    required this.label,
    required this.onPressed,
    this.variant = BmdButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.identifier,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final BmdButtonVariant variant;
  final IconData? icon;
  final bool loading;

  /// Stable a11y identifier for automated tests (Maestro `id:`). Maps to
  /// Android resource-id / iOS accessibilityIdentifier.
  final String? identifier;

  @override
  Widget build(BuildContext context) {
    final built = _build(context);
    return identifier == null
        ? built
        : Semantics(identifier: identifier, child: built);
  }

  Widget _build(BuildContext context) {
    final height = Breakpoint.of(context).isMobile
        ? BmdSize.controlHeightMobile
        : BmdSize.controlHeightWeb;

    // Loading state preserves label width so the button does not resize (§5.1).
    final child = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : _labelRow();

    final onTap = loading ? null : onPressed;

    return SizedBox(
      height: height,
      child: switch (variant) {
        BmdButtonVariant.primary => FilledButton(
          onPressed: onTap,
          child: child,
        ),
        BmdButtonVariant.tonal => FilledButton.tonal(
          onPressed: onTap,
          child: child,
        ),
        BmdButtonVariant.outlined => OutlinedButton(
          onPressed: onTap,
          child: child,
        ),
        BmdButtonVariant.text => TextButton(onPressed: onTap, child: child),
        BmdButtonVariant.danger => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(backgroundColor: BmdColor.error),
          child: child,
        ),
      },
    );
  }

  Widget _labelRow() {
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
    );
  }
}

/// An icon-only action: search, filter, zoom, more, close (§5.1).
///
/// A separate widget rather than a sixth [BmdButtonVariant] — an icon button
/// has no label, which would make [BmdButton.label] meaningless. [tooltip] is
/// required because §5.1 demands one on web, and an unlabelled control without
/// it is unusable to a screen reader as well as to a new operator.
class BmdIconButton extends StatelessWidget {
  const BmdIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.identifier,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Stable a11y identifier for automated tests (Maestro `id:`). Maps to
  /// Android resource-id / iOS accessibilityIdentifier.
  final String? identifier;

  @override
  Widget build(BuildContext context) {
    final size = Breakpoint.of(context).isMobile
        ? BmdSize.touchTargetMin
        : BmdSize.controlHeightWeb;

    final button = SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
      ),
    );

    return identifier == null
        ? button
        : Semantics(identifier: identifier, child: button);
  }
}
