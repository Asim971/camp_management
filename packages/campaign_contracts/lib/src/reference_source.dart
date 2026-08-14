/// The source and type of verification reference photo used (sub-project 5).
enum ReferenceSource {
  verifiedProfilePhoto,
  authorizedNidPhoto,
  approvedBaselinePhoto,
  unavailable;

  String get wireValue => switch (this) {
    verifiedProfilePhoto => 'VERIFIED_PROFILE_PHOTO',
    authorizedNidPhoto => 'AUTHORIZED_NID_PHOTO',
    approvedBaselinePhoto => 'APPROVED_BASELINE_PHOTO',
    unavailable => 'UNAVAILABLE',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static ReferenceSource? tryParseWire(String wire) {
    for (final r in values) {
      if (r.wireValue == wire) return r;
    }
    return null;
  }
}
