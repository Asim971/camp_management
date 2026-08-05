import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../responsive/breakpoints.dart';
import 'bmd_button.dart';
import 'bmd_feedback.dart';
import 'bmd_field.dart';

/// Dialogs, side sheets and confirmation (Guideline §5.6).

/// Identifies the side-sheet panel so a test can tell it apart from the bottom
/// sheet it degrades into on narrow surfaces.
const Key bmdSideSheetKey = Key('bmd_side_sheet');

/// What a confirmed [showBmdConfirm] returns. A record would do, but a named
/// class gives call sites a readable type and room for an acknowledgement
/// timestamp when the audit trail (§12) needs one.
class BmdConfirmResult {
  const BmdConfirmResult({this.reason});

  /// Non-null exactly when `reasonLabel` was supplied.
  final String? reason;
}

/// A right side sheet: filters, audit preview, registration quick view, import
/// row detail (§5.6).
///
/// Built on [showGeneralDialog] rather than `Scaffold.endDrawer` because it
/// must be callable from anywhere without the caller owning a Scaffold key, and
/// it must return a value — "filters applied" and "dismissed" are different
/// outcomes.
///
/// Below the tablet breakpoint it delegates to [showBmdBottomSheet]: §5.6
/// assigns side sheets to web and bottom sheets to mobile, so one call site
/// stays correct on both surfaces.
Future<T?> showBmdSideSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  List<Widget> actions = const [],
  double width = 420,
}) {
  if (!Breakpoint.of(context).isTabletUp) {
    return showBmdBottomSheet<T>(
      context: context,
      title: title,
      builder: builder,
      actions: actions,
    );
  }

  final screenWidth = MediaQuery.sizeOf(context).width;
  final panelWidth = width < screenWidth - BmdSpace.s9
      ? width
      : screenWidth - BmdSpace.s9;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss $title',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, _) {
      final theme = Theme.of(dialogContext);
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          key: bmdSideSheetKey,
          color: theme.colorScheme.surface,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OverlayHeader(title: title),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(BmdSpace.s4),
                      child: Builder(builder: builder),
                    ),
                  ),
                  if (actions.isNotEmpty) _OverlayActions(actions: actions),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// A mobile bottom sheet: carpenter selection, reason code, session switch,
/// offline queue action (§5.6).
Future<T?> showBmdBottomSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  List<Widget> actions = const [],
}) {
  return showModalBottomSheet<T>(
    context: context,
    // Reason-code sheets contain a field, so the sheet has to move with the
    // keyboard rather than hide behind it.
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DragHandle(),
            _OverlayHeader(title: title),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BmdSpace.s4),
                child: Builder(builder: builder),
              ),
            ),
            if (actions.isNotEmpty) _OverlayActions(actions: actions),
          ],
        ),
      ),
    ),
  );
}

/// A confirmation dialog for an irreversible decision, a short
/// approval/rejection, a consent notice or a session override (§5.6).
///
/// It owns three rules so no screen has to remember them:
///
///  * [reasonLabel] set → confirm is disabled until the reason is non-empty
///    (T-1.4.2, T-3.1.4).
///  * [acknowledgements] non-empty → confirm is disabled until every box is
///    checked (T-1.4.2).
///  * [effect] → rendered as a banner, so an irreversible action always states
///    its downstream consequence (T-3.1.4, §2.1).
///
/// Returns null on cancel or dismiss.
Future<BmdConfirmResult?> showBmdConfirm({
  required BuildContext context,
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool danger = false,
  String? reasonLabel,
  List<String> acknowledgements = const [],
  String? effect,
  String? confirmIdentifier,
}) {
  return showDialog<BmdConfirmResult>(
    context: context,
    builder: (_) => _BmdConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      danger: danger,
      reasonLabel: reasonLabel,
      acknowledgements: acknowledgements,
      effect: effect,
      confirmIdentifier: confirmIdentifier,
    ),
  );
}

class _BmdConfirmDialog extends StatefulWidget {
  const _BmdConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.danger,
    required this.reasonLabel,
    required this.acknowledgements,
    required this.effect,
    required this.confirmIdentifier,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;
  final String? reasonLabel;
  final List<String> acknowledgements;
  final String? effect;
  final String? confirmIdentifier;

  @override
  State<_BmdConfirmDialog> createState() => _BmdConfirmDialogState();
}

class _BmdConfirmDialogState extends State<_BmdConfirmDialog> {
  final _reason = TextEditingController();
  late final Set<int> _checked = <int>{};

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (widget.reasonLabel != null && _reason.text.trim().isEmpty) return false;
    return _checked.length == widget.acknowledgements.length;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.body),
              if (widget.effect != null) ...[
                const SizedBox(height: BmdSpace.s3),
                BmdBanner(
                  title: widget.effect!,
                  tone: widget.danger ? BannerTone.error : BannerTone.warning,
                ),
              ],
              for (var i = 0; i < widget.acknowledgements.length; i++)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _checked.contains(i),
                  title: Text(widget.acknowledgements[i]),
                  onChanged: (on) => setState(() {
                    (on ?? false) ? _checked.add(i) : _checked.remove(i);
                  }),
                ),
              if (widget.reasonLabel != null) ...[
                const SizedBox(height: BmdSpace.s3),
                BmdField.multiline(
                  label: widget.reasonLabel!,
                  required: true,
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        BmdButton(
          label: widget.cancelLabel,
          variant: BmdButtonVariant.outlined,
          onPressed: () => Navigator.pop(context),
        ),
        BmdButton(
          label: widget.confirmLabel,
          identifier: widget.confirmIdentifier,
          variant: widget.danger
              ? BmdButtonVariant.danger
              : BmdButtonVariant.primary,
          onPressed: _canConfirm
              ? () => Navigator.pop(
                  context,
                  BmdConfirmResult(
                    reason: widget.reasonLabel == null
                        ? null
                        : _reason.text.trim(),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

// ---- shared overlay chrome --------------------------------------------------

class _OverlayHeader extends StatelessWidget {
  const _OverlayHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BmdSpace.s4,
        BmdSpace.s3,
        BmdSpace.s2,
        BmdSpace.s3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _OverlayActions extends StatelessWidget {
  const _OverlayActions({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BmdSpace.s4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Index-based, not `action != actions.last`: two canonicalised const
          // widgets in the list compare equal, so identity/equality
          // comparison would treat the first of two identical actions as the
          // last one and drop its separator.
          for (var i = 0; i < actions.length; i++) ...[
            actions[i],
            if (i < actions.length - 1) const SizedBox(width: BmdSpace.s3),
          ],
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 32,
        height: 4,
        margin: const EdgeInsets.only(top: BmdSpace.s2),
        decoration: BoxDecoration(
          color: Theme.of(context).bmd.borderStrong,
          borderRadius: BorderRadius.circular(BmdRadius.pill),
        ),
      ),
    );
  }
}
