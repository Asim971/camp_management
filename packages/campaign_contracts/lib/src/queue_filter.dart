/// How the verification queue is filtered (sub-project 5c). The wire value is
/// the contract; `mine` resolves to the caller's id server-side (never a
/// client-supplied id).
enum QueueFilter {
  all,
  mine,
  unassigned,
  escalated;

  String get wireValue => switch (this) {
    all => 'ALL',
    mine => 'MINE',
    unassigned => 'UNASSIGNED',
    escalated => 'ESCALATED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static QueueFilter? tryParseWire(String wire) {
    for (final f in values) {
      if (f.wireValue == wire) return f;
    }
    return null;
  }
}
