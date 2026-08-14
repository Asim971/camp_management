/// A campaign session's operational lifecycle. The wire value is the contract;
/// the Dart name is an implementation detail on either side.
///
/// Moved out of the app's `lib/domain/session/campaign_session.dart` for
/// sub-project 3a so the server and client cannot disagree — the same move
/// `CampaignStatus` and `ImportStatus` already made. `CAPTURE_CLOSED` is the
/// operational terminal a user reaches; `COMPLETED` is set only when the
/// session's campaign completes (sub-project 3a.D3), not by any client action.
enum SessionStatus {
  upcoming,
  active,
  paused,
  captureClosed,
  completed;

  String get wireValue => switch (this) {
    upcoming => 'UPCOMING',
    active => 'ACTIVE',
    paused => 'PAUSED',
    captureClosed => 'CAPTURE_CLOSED',
    completed => 'COMPLETED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static SessionStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
