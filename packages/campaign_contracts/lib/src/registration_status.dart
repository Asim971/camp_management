/// Controlled registration-status vocabulary — moved out of the app's
/// `lib/domain/common/status.dart` now that sub-project 2a defines its
/// server contract (the foundation spec's D5 rule: enums move only when
/// their wire contract lands, never before).
///
/// `pendingProfileSync` changed meaning with D1: it now means "this
/// registration's carpenter exists only as a locally captured provisional
/// profile, not yet ratified into the master" — no longer "awaiting an
/// authoritative Sales Eco identity".
enum RegistrationStatus {
  invited,
  registered,
  pendingProfileSync,
  ineligible,
  waitlisted,
  cancelled;

  String get wireValue => switch (this) {
    invited => 'INVITED',
    registered => 'REGISTERED',
    pendingProfileSync => 'PENDING_PROFILE_SYNC',
    ineligible => 'INELIGIBLE',
    waitlisted => 'WAITLISTED',
    cancelled => 'CANCELLED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static RegistrationStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
