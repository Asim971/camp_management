/// Attendance lifecycle status. The wire value is the contract; the Dart name
/// is an implementation detail on either side. Moved out of the app's
/// `lib/domain/common/status.dart` so the server and client cannot disagree
/// about it (spec 5a.D1, delivered in 5b when the client first parses it).
enum AttendanceStatus {
  notCaptured,
  pendingSync,
  matchProcessing,
  crmReview,
  approved,
  rejected,
  returned;

  String get wireValue => switch (this) {
    notCaptured => 'NOT_CAPTURED',
    pendingSync => 'PENDING_SYNC',
    matchProcessing => 'MATCH_PROCESSING',
    crmReview => 'CRM_REVIEW',
    approved => 'APPROVED',
    rejected => 'REJECTED',
    returned => 'RETURNED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static AttendanceStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
