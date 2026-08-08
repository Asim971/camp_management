import '../../l10n/generated/app_localizations.dart';
import '../session/campaign_session.dart';
import 'status.dart';

/// Localized labels for the typed status vocabulary (Guideline Appendix B).
///
/// Exhaustive `switch` expressions with no `default` and no `_` wildcard, so
/// adding a value to any of these enums is a COMPILE ERROR here until it has a
/// label. That is deliberate: the previous design exposed `l10nKey` getters
/// returning a runtime String, which could not resolve against `gen-l10n`'s
/// named getters and silently advertised keys for three families the ARB never
/// contained.
extension CampaignStatusL10n on CampaignStatus {
  String label(AppL10n l) => switch (this) {
    CampaignStatus.draft => l.campaignStatus_draft,
    CampaignStatus.pendingApproval => l.campaignStatus_pendingApproval,
    CampaignStatus.returned => l.campaignStatus_returned,
    CampaignStatus.approved => l.campaignStatus_approved,
    CampaignStatus.active => l.campaignStatus_active,
    CampaignStatus.paused => l.campaignStatus_paused,
    CampaignStatus.completed => l.campaignStatus_completed,
    CampaignStatus.cancelled => l.campaignStatus_cancelled,
  };
}

/// [SessionStatus] lives in `domain/session/campaign_session.dart` rather than
/// `status.dart`, which is why it was missed when the other five families were
/// localized: it is the one status family the campaign detail screen renders
/// that `status.dart` never declared.
extension SessionStatusL10n on SessionStatus {
  String label(AppL10n l) => switch (this) {
    SessionStatus.upcoming => l.sessionStatus_upcoming,
    SessionStatus.active => l.sessionStatus_active,
    SessionStatus.captureClosed => l.sessionStatus_captureClosed,
    SessionStatus.paused => l.sessionStatus_paused,
    SessionStatus.completed => l.sessionStatus_completed,
  };
}

extension RegistrationStatusL10n on RegistrationStatus {
  String label(AppL10n l) => switch (this) {
    RegistrationStatus.invited => l.registrationStatus_invited,
    RegistrationStatus.registered => l.registrationStatus_registered,
    RegistrationStatus.pendingProfileSync =>
      l.registrationStatus_pendingProfileSync,
    RegistrationStatus.ineligible => l.registrationStatus_ineligible,
    RegistrationStatus.waitlisted => l.registrationStatus_waitlisted,
    RegistrationStatus.cancelled => l.registrationStatus_cancelled,
  };
}

extension AttendanceStatusL10n on AttendanceStatus {
  String label(AppL10n l) => switch (this) {
    AttendanceStatus.notCaptured => l.attendanceStatus_notCaptured,
    AttendanceStatus.pendingSync => l.attendanceStatus_pendingSync,
    AttendanceStatus.matchProcessing => l.attendanceStatus_matchProcessing,
    AttendanceStatus.crmReview => l.attendanceStatus_crmReview,
    AttendanceStatus.approved => l.attendanceStatus_approved,
    AttendanceStatus.rejected => l.attendanceStatus_rejected,
    AttendanceStatus.returned => l.attendanceStatus_returned,
  };
}

extension ImportStatusL10n on ImportStatus {
  String label(AppL10n l) => switch (this) {
    ImportStatus.dryRun => l.importStatus_dryRun,
    ImportStatus.readyToCommit => l.importStatus_readyToCommit,
    ImportStatus.processing => l.importStatus_processing,
    ImportStatus.completed => l.importStatus_completed,
    ImportStatus.partiallyCompleted => l.importStatus_partiallyCompleted,
    ImportStatus.failed => l.importStatus_failed,
    ImportStatus.cancelled => l.importStatus_cancelled,
  };
}

extension IntegrityFlagL10n on IntegrityFlag {
  String label(AppL10n l) => switch (this) {
    IntegrityFlag.noReference => l.integrityFlag_noReference,
    IntegrityFlag.poorQuality => l.integrityFlag_poorQuality,
    IntegrityFlag.suspectedSpoof => l.integrityFlag_suspectedSpoof,
    IntegrityFlag.duplicate => l.integrityFlag_duplicate,
    IntegrityFlag.geofenceException => l.integrityFlag_geofenceException,
    IntegrityFlag.manualOverride => l.integrityFlag_manualOverride,
  };
}
