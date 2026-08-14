/// The outcome of a verification decision (sub-project 5).
enum VerificationOutcome {
  approved,
  rejected,
  returnForRecapture,
  escalated;

  String get wireValue => switch (this) {
    approved => 'APPROVED',
    rejected => 'REJECTED',
    returnForRecapture => 'RETURN_FOR_RECAPTURE',
    escalated => 'ESCALATED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static VerificationOutcome? tryParseWire(String wire) {
    for (final o in values) {
      if (o.wireValue == wire) return o;
    }
    return null;
  }
}
