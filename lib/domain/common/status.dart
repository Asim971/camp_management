/// Controlled status vocabulary — the single source of truth used identically
/// across list pages, detail pages, notifications, mobile sync and analytics
/// (UI/UX Guideline §1.1, §5.4, Appendix B). Status is NEVER a raw string.
///
/// [CampaignStatus] now lives in `package:campaign_contracts` so the server
/// cannot disagree with the client about it (spec D5). It is re-exported here
/// rather than moved-and-reimported because 28 files import this path and the
/// enum name is unchanged: a shim keeps that diff at one file instead of 28.
///
/// The other enums below have NO wire value yet — their server contracts are
/// blocked — so they stay here until the sub-project that defines them lands.
/// Do not invent wire values for them to make this file look symmetrical.
library;

export 'package:campaign_contracts/campaign_contracts.dart' show CampaignStatus;

enum RegistrationStatus {
  invited,
  registered,
  pendingProfileSync,
  ineligible,
  waitlisted,
  cancelled,
}

/// Same wording is used on mobile capture, CRM and analytics (§5.4).
enum AttendanceStatus {
  notCaptured,
  pendingSync,
  matchProcessing,
  crmReview,
  approved,
  rejected,
  returned,
}

enum ImportStatus {
  dryRun,
  readyToCommit,
  processing,
  completed,
  partiallyCompleted,
  failed,
  cancelled,
}

/// Neutral, non-accusatory language (§2.1) — a failed check is "Review
/// required", not "Fraud detected".
enum IntegrityFlag {
  noReference,
  poorQuality,
  suspectedSpoof,
  duplicate,
  geofenceException,
  manualOverride,
}

/// Semantic intent for chip/badge rendering. Reserve brand red for the primary
/// action and selected nav — NOT for ordinary errors (§4.2).
enum StatusTone { neutral, info, success, warning, error }
