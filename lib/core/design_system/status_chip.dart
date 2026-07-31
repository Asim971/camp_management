import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/common/status.dart';

/// The single renderer for the controlled status vocabulary (Guideline §5.4).
///
/// Colour is NEVER used alone: every chip carries an icon and a text label, so
/// it stays readable in greyscale, under outdoor glare, and to a reader with
/// deuteranopia. The label is the controlled word verbatim — never abbreviated
/// to fit a column. If it does not fit, the column is too narrow.
///
/// A status chip reports state and is not interactive. It is deliberately
/// distinct from a filter chip, which is a control: different height, no
/// border, no dismiss affordance, and not in the tab order.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.tone,
    this.icon,
    this.large = false,
    super.key,
  });

  /// Resolve tone and icon from a typed campaign status. [label] is resolved
  /// through l10n by the caller so bn/en stay in parity.
  factory StatusChip.campaign(CampaignStatus s, {required String label}) {
    final tone = switch (s) {
      CampaignStatus.approved || CampaignStatus.completed => StatusTone.success,
      CampaignStatus.returned || CampaignStatus.paused => StatusTone.warning,
      CampaignStatus.cancelled => StatusTone.error,
      CampaignStatus.active || CampaignStatus.pendingApproval => StatusTone.info,
      CampaignStatus.draft => StatusTone.neutral,
    };
    final icon = switch (s) {
      CampaignStatus.returned => Icons.undo,
      CampaignStatus.paused => Icons.pause_circle_outline,
      CampaignStatus.active => Icons.circle,
      _ => _iconFor(tone),
    };
    return StatusChip(label: label, tone: tone, icon: icon);
  }

  /// Green is not spent on "Registered": registering is an intention, not an
  /// outcome, and green is reserved for verified and approved results.
  factory StatusChip.registration(
    RegistrationStatus s, {
    required String label,
  }) {
    final tone = switch (s) {
      RegistrationStatus.registered => StatusTone.info,
      RegistrationStatus.pendingProfileSync => StatusTone.warning,
      RegistrationStatus.ineligible ||
      RegistrationStatus.cancelled =>
        StatusTone.error,
      RegistrationStatus.invited ||
      RegistrationStatus.waitlisted =>
        StatusTone.neutral,
    };
    final icon = switch (s) {
      RegistrationStatus.invited => Icons.mail_outline,
      RegistrationStatus.registered => Icons.circle,
      RegistrationStatus.pendingProfileSync => Icons.sync,
      RegistrationStatus.waitlisted => Icons.schedule,
      _ => _iconFor(tone),
    };
    return StatusChip(label: label, tone: tone, icon: icon);
  }

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
    final icon = switch (s) {
      // Pending sync is an upload waiting, not a failure — the icon says so.
      AttendanceStatus.pendingSync => Icons.upload_outlined,
      AttendanceStatus.matchProcessing => Icons.autorenew,
      AttendanceStatus.crmReview => Icons.visibility_outlined,
      AttendanceStatus.returned => Icons.undo,
      _ => _iconFor(tone),
    };
    return StatusChip(label: label, tone: tone, icon: icon);
  }

  factory StatusChip.import(ImportStatus s, {required String label}) {
    final tone = switch (s) {
      ImportStatus.completed => StatusTone.success,
      ImportStatus.partiallyCompleted => StatusTone.warning,
      ImportStatus.failed => StatusTone.error,
      ImportStatus.processing || ImportStatus.readyToCommit => StatusTone.info,
      ImportStatus.dryRun || ImportStatus.cancelled => StatusTone.neutral,
    };
    final icon = switch (s) {
      ImportStatus.processing => Icons.autorenew,
      ImportStatus.partiallyCompleted => Icons.data_usage,
      ImportStatus.dryRun => Icons.science_outlined,
      ImportStatus.cancelled => Icons.close,
      _ => _iconFor(tone),
    };
    return StatusChip(label: label, tone: tone, icon: icon);
  }

  /// Integrity flags use warning and error semantics but neutral language: a
  /// failed check means "review required", never "fraud detected" (§2.1).
  factory StatusChip.integrity(IntegrityFlag f, {required String label}) {
    final tone = switch (f) {
      IntegrityFlag.suspectedSpoof || IntegrityFlag.duplicate => StatusTone.error,
      IntegrityFlag.noReference ||
      IntegrityFlag.poorQuality ||
      IntegrityFlag.geofenceException =>
        StatusTone.warning,
      IntegrityFlag.manualOverride => StatusTone.info,
    };
    final icon = switch (f) {
      IntegrityFlag.noReference => Icons.block_outlined,
      IntegrityFlag.poorQuality => Icons.blur_on,
      IntegrityFlag.suspectedSpoof => Icons.warning_amber_outlined,
      IntegrityFlag.duplicate => Icons.copy_all_outlined,
      IntegrityFlag.geofenceException => Icons.location_off_outlined,
      IntegrityFlag.manualOverride => Icons.edit_outlined,
    };
    return StatusChip(label: label, tone: tone, icon: icon);
  }

  final String label;
  final StatusTone tone;
  final IconData? icon;

  /// 28px, for use beside a page title. 24px everywhere else.
  final bool large;

  static IconData _iconFor(StatusTone t) => switch (t) {
        StatusTone.success => Icons.check_circle_outline,
        StatusTone.warning => Icons.schedule,
        StatusTone.error => Icons.error_outline,
        StatusTone.info => Icons.autorenew,
        StatusTone.neutral => Icons.circle_outlined,
      };

  ({Color fg, Color bg}) _colors(BmdTokens bmd) => switch (tone) {
        StatusTone.success => (fg: bmd.success, bg: bmd.tintSuccess),
        StatusTone.warning => (fg: bmd.warning, bg: bmd.tintWarning),
        StatusTone.error => (fg: bmd.error, bg: bmd.tintError),
        StatusTone.info => (fg: bmd.info, bg: bmd.tintInfo),
        StatusTone.neutral => (fg: bmd.textSecondary, bg: bmd.tintNeutral),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _colors(theme.bmd);
    final resolvedIcon = icon ?? _iconFor(tone);

    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        height: large ? 28 : 24,
        padding: EdgeInsets.symmetric(horizontal: large ? BmdSpace.s3 : 10),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(BmdRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(resolvedIcon, size: 14, color: c.fg),
            const SizedBox(width: BmdSpace.s1 + 2),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: c.fg),
            ),
          ],
        ),
      ),
    );
  }
}
