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

  /// Whether this button can currently be pressed. Single source of truth for
  /// both the Material button (via `onPressed`) and the identifier node's
  /// semantics, so the two cannot disagree.
  bool get _interactive => !loading && onPressed != null;

  @override
  Widget build(BuildContext context) {
    final built = _build(context);
    return identifier == null
        ? built
        : Semantics(
            identifier: identifier,
            // `enabled:` is NOT redundant with the Material button's own
            // disabled state. A bare `Semantics(identifier:)` wrapper compiles
            // to its OWN semantics node, separate from the button's: probed on
            // Flutter 3.44, `BmdButton(identifier: 'x', onPressed: null)`
            // yields node A (identifier "x", isEnabled Tristate.none, no label)
            // whose CHILD node B carries label + isEnabled false. Flutter's
            // Android AccessibilityBridge reports a node with no enabled state
            // as `enabled=true`, so `id:` is attached to a node that claims to
            // be enabled even when the control is disabled — which makes
            // Maestro's `assertVisible: {id: ..., enabled: false}` fail, and
            // makes `enabled: true` pass vacuously. Two E2E flows assert
            // exactly that (`confirm_continue`, `crm_submit`), and those
            // assertions are the whole point of their flows: the second
            // identity cue and the mandatory decision reason. Stating the state
            // on the identifier node is what makes them mean something.
            enabled: _interactive,
            child: built,
          );
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

    final onTap = _interactive ? onPressed : null;

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
