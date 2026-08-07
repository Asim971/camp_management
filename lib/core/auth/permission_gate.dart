import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/providers.dart';
import 'rbac.dart';
import 'session_manager.dart';

enum _GateMode { hidden, disabled }

/// Gates a widget on a [Permission].
///
/// Two modes, chosen per call site because the right answer differs by
/// context:
///
///  * [PermissionGate.hidden] for whole surfaces the user has no business
///    knowing about. A disabled "Analytics" nav item is noise and leaks how
///    the organization is structured.
///  * [PermissionGate.disabled] for an action on a record the user is already
///    looking at. A missing Approve button leaves them unable to tell a
///    permission problem from a lifecycle-state problem from a bug - and
///    leaves support unable to either.
///
/// Client-side gating drives UX only; the server re-checks every call.
class PermissionGate extends ConsumerWidget {
  const PermissionGate.hidden(this.permission, {required this.child, super.key})
    : reason = null,
      label = null,
      _mode = _GateMode.hidden;

  const PermissionGate.disabled(
    this.permission, {
    required this.reason,
    required this.label,
    required this.child,
    super.key,
  }) : _mode = _GateMode.disabled;

  final Permission permission;
  final Widget child;

  /// Why the action is unavailable. Reaches the semantics tree as a `hint`,
  /// not only a hover tooltip.
  final String? reason;

  /// The accessible name for the gated control (e.g. "Approve"), required
  /// only in [_GateMode.disabled].
  ///
  /// [child]'s OWN semantics are excluded in that mode (see [build]), so
  /// without this the gate's node would carry a disabled state and a reason
  /// but no name at all - a screen reader would announce "dimmed, <reason>"
  /// rather than "Approve, dimmed, <reason>".
  final String? label;

  final _GateMode _mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final allowed = switch (auth) {
      AuthSignedIn(:final session) => session.scope.can(permission),
      _ => false,
    };

    if (allowed) return child;

    return switch (_mode) {
      _GateMode.hidden => const SizedBox.shrink(),
      _GateMode.disabled => Tooltip(
        message: reason!,
        child: Semantics(
          label: label,
          // The reason is supplementary detail, not the primary label: it
          // belongs in `hint` so a screen reader announces the label first
          // ("Approve"), then the disabled state from `enabled: false`, and
          // only then this explanation - not the reverse, which announces
          // the explanation before the user knows what it explains.
          hint: reason,
          enabled: false,
          container: true,
          child: ExcludeSemantics(
            // child's own control (e.g. a Material button) reports its own
            // `enabled: true` via its own semantics boundary, which a plain
            // ancestor Semantics node cannot override merely by also being
            // an ancestor - Flutter's merge unions flags across a merged
            // group rather than letting an outer "disabled" beat an inner
            // "enabled". Excluding child's semantics entirely, and stating
            // enabled/label/hint once on this node instead, is what makes
            // "disabled" the only answer a screen reader can reach.
            child: ExcludeFocus(
              // IgnorePointer blocks interaction without changing layout, so
              // the affordance stays exactly where the user expects to find
              // it.
              child: IgnorePointer(child: Opacity(opacity: 0.38, child: child)),
            ),
          ),
        ),
      ),
    };
  }
}
