/// The machine's advisory match-confidence band (sub-project 5). Advisory only —
/// the human sees the band + reasons, never a raw score.
enum MatchBand {
  high,
  medium,
  low,
  noReference;

  String get wireValue => switch (this) {
    high => 'HIGH',
    medium => 'MEDIUM',
    low => 'LOW',
    noReference => 'NO_REFERENCE',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static MatchBand? tryParseWire(String wire) {
    for (final b in values) {
      if (b.wireValue == wire) return b;
    }
    return null;
  }
}
