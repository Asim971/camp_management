/// Controlled campaign status vocabulary. The wire value is the contract;
/// the Dart name is an implementation detail on either side.
///
/// Moved out of the app's `lib/domain/common/status.dart` so the server and
/// the client cannot disagree about it (spec D5).
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

  /// Returns `null` for anything unrecognised — deliberately not a default.
  /// A caller that wants a fallback must choose it explicitly and visibly.
  static CampaignStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
