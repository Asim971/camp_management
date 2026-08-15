import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../motion/reveal.dart';
import 'bmd_button.dart';

/// Designed empty/error states (slice 2 RD2.D2), replacing bare centered
/// [Text]s. Typography, tone and spacing only — the icon circle is where a
/// later slice's illustration drops in.
class BmdStateView extends StatelessWidget {
  const BmdStateView.empty({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  }) : _error = false,
       onRetry = null;

  const BmdStateView.error({
    required this.title,
    required this.message,
    required VoidCallback this.onRetry,
    super.key,
  }) : _error = true,
       icon = Icons.error_outline,
       action = null;

  final String title;
  final String message;
  final IconData icon;

  /// Optional call-to-action for the empty variant (e.g. a create button).
  final Widget? action;

  /// The error variant always renders an outlined Retry button wired here.
  final VoidCallback? onRetry;

  final bool _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final toneColor = _error ? bmd.error : bmd.neutral;
    final tint = _error ? bmd.tintError : bmd.tintNeutral;

    return Center(
      child: Reveal(
        index: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
                child: Icon(icon, size: 48, color: toneColor),
              ),
              const SizedBox(height: BmdSpace.s4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: BmdSpace.s2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: bmd.textSecondary,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: BmdSpace.s4),
                BmdButton(
                  label: 'Retry',
                  variant: BmdButtonVariant.outlined,
                  onPressed: onRetry,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: BmdSpace.s4),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
