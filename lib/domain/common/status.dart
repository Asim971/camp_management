/// Controlled status vocabulary — the single source of truth used identically
/// across list pages, detail pages, notifications, mobile sync and analytics
/// (UI/UX Guideline §1.1, §5.4, Appendix B). Status is NEVER a raw string.
///
/// Each enum exposes a stable [wireValue] (API contract) and a localization
/// key; the human label is resolved through l10n so bn/en stay in parity.
library;

enum CampaignStatus {
  draft,
  pendingApproval,
  returned,
  approved,
  active,
  paused,
  completed,
  cancelled;

  String get wireValue => switch (this) {
    draft => 'DRAFT',
    pendingApproval => 'PENDING_APPROVAL',
    returned => 'RETURNED',
    approved => 'APPROVED',
    active => 'ACTIVE',
    paused => 'PAUSED',
    completed => 'COMPLETED',
    cancelled => 'CANCELLED',
  };

  String get l10nKey => 'campaignStatus_$name';
}

enum RegistrationStatus {
  invited,
  registered,
  pendingProfileSync,
  ineligible,
  waitlisted,
  cancelled;

  String get l10nKey => 'registrationStatus_$name';
}

/// Same wording is used on mobile capture, CRM and analytics (§5.4).
enum AttendanceStatus {
  notCaptured,
  pendingSync,
  matchProcessing,
  crmReview,
  approved,
  rejected,
  returned;

  String get l10nKey => 'attendanceStatus_$name';
}

enum ImportStatus {
  dryRun,
  readyToCommit,
  processing,
  completed,
  partiallyCompleted,
  failed,
  cancelled;

  String get l10nKey => 'importStatus_$name';
}

/// Neutral, non-accusatory language (§2.1) — a failed check is "Review
/// required", not "Fraud detected".
enum IntegrityFlag {
  noReference,
  poorQuality,
  suspectedSpoof,
  duplicate,
  geofenceException,
  manualOverride;

  String get l10nKey => 'integrityFlag_$name';
}

/// Semantic intent for chip/badge rendering. Reserve brand red for the primary
/// action and selected nav — NOT for ordinary errors (§4.2).
enum StatusTone { neutral, info, success, warning, error }
