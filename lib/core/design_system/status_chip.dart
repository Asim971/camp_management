import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/common/status.dart';

/// The single renderer for controlled status vocabulary (Guideline §5.4).
/// Color is NEVER used alone — every chip carries an icon + text label so it
/// stays accessible and consistent across web, mobile and analytics.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.tone,
    this.icon,
    super.key,
  });

  /// Resolve tone + label from a typed status, then localize the label.
  factory StatusChip.attendance(AttendanceStatus s, {required String label}) {
    final tone = switch (s) {
      AttendanceStatus.approved => StatusTone.success,
      AttendanceStatus.rejected => StatusTone.error,
      AttendanceStatus.returned => StatusTone.warning,
      AttendanceStatus.crmReview ||
      AttendanceStatus.matchProcessing =>
        StatusTone.info,
      AttendanceStatus.pendingSync => StatusTone.warning,
      AttendanceStatus.notCaptured => StatusTone.neutral,
    };
    return StatusChip(label: label, tone: tone, icon: _iconFor(tone));
  }

  final String label;
  final StatusTone tone;
  final IconData? icon;

  static IconData _iconFor(StatusTone t) => switch (t) {
        StatusTone.success => Icons.check_circle_outline,
        StatusTone.warning => Icons.schedule,
        StatusTone.error => Icons.error_outline,
        StatusTone.info => Icons.autorenew,
        StatusTone.neutral => Icons.circle_outlined,
      };

  ({Color fg, Color bg}) _colors() => switch (tone) {
        StatusTone.success => (
            fg: BmdColor.success,
            bg: const Color(0x141F7A4D)
          ),
        StatusTone.warning => (
            fg: BmdColor.warning,
            bg: const Color(0x14B54708)
          ),
        StatusTone.error => (fg: BmdColor.error, bg: const Color(0x14B42318)),
        StatusTone.info => (fg: BmdColor.info, bg: const Color(0x14175CD3)),
        StatusTone.neutral => (
            fg: BmdColor.textSecondary,
            bg: const Color(0x0F2B3674),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final c = _colors();
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: c.fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: c.fg),
            ),
          ],
        ),
      ),
    );
  }
}
