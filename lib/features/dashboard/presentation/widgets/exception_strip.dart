import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/design_system/bmd_cards.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/motion/reveal.dart';
import '../../../../domain/common/status.dart';
import '../../application/dashboard_notifier.dart';

/// The Dashboard's opening block (W-01, Guideline §8.2 exception-first): a
/// horizontally-scrollable row of the full exception taxonomy, always shown
/// — including a zero count — so the taxonomy never reshuffles between
/// visits. Every card in [DashboardView.exceptions] order, staggered in with
/// [Reveal] and its count driven up with the same easing [CountUp] uses.
class ExceptionStrip extends StatelessWidget {
  const ExceptionStrip({required this.exceptions, super.key});

  final List<DashboardException> exceptions;

  /// Where tapping this exception's card takes the operator — the
  /// deep-link the count is about. `null` means no destination exists yet
  /// for this bucket (spec RD.D5 scopes this slice to existing reads only;
  /// see `dashboard_notifier.dart`'s `suspected_spoof`/`reconciliation` rows).
  static String? _routeFor(String key) => switch (key) {
    'overdue_verification' || 'escalated' || 'no_reference' => '/verification',
    'pending_sync' => '/queue',
    'rejected' => '/campaigns',
    _ => null,
  };

  static String _detailFor(String key) => switch (key) {
    'overdue_verification' => 'Waiting past the 24h review window',
    'escalated' => 'Flagged for supervisor review',
    'no_reference' => 'No reference photo available for matching',
    'pending_sync' => 'Captures on this device waiting to upload',
    'rejected' => 'Returned or rejected by an approver',
    'suspected_spoof' => 'Flagged by an integrity check',
    'reconciliation' => 'Awaiting reconciliation with Sales Eco',
    _ => 'Needs attention',
  };

  /// [ExceptionCard] only has error/warning/info tones (an exception is
  /// never "success"); [StatusTone.neutral] — a bucket that is currently at
  /// zero — reads closest to the quiet `info` tone.
  static ExceptionTone _toneFor(StatusTone tone) => switch (tone) {
    StatusTone.error => ExceptionTone.error,
    StatusTone.warning => ExceptionTone.warning,
    StatusTone.info ||
    StatusTone.neutral ||
    StatusTone.success => ExceptionTone.info,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 216,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: exceptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: BmdSpace.s3),
        itemBuilder: (context, index) {
          final exception = exceptions[index];
          final route = _routeFor(exception.key);

          return Reveal(
            index: index,
            child: Semantics(
              identifier: 'dashboard_exception_${exception.key}',
              child: SizedBox(
                width: 260,
                // Same duration/curve/reduced-motion guard as `CountUp`,
                // feeding the animated value into `ExceptionCard.count`
                // (a plain String) rather than reimplementing it.
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: exception.count.toDouble()),
                  duration: reduced(context, MotionDur.slow),
                  curve: MotionCurve.emphasized,
                  builder: (context, value, _) => ExceptionCard(
                    label: exception.label,
                    count: '${value.round()}',
                    tone: _toneFor(exception.tone),
                    detail: _detailFor(exception.key),
                    actionLabel: route == null ? null : 'Review',
                    onAction: route == null ? null : () => context.go(route),
                    glass: true,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
