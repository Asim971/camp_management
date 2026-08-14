/// Per-row dry-run classification. Committable in 2b: VALID and NEEDS_PROFILE.
/// WARNING ships in the vocabulary but is not produced this slice (2c's
/// eligibility rule). DUPLICATE/UNAUTHORIZED/ERROR are never committable.
enum ImportRowOutcome {
  valid,
  warning,
  duplicate,
  needsProfile,
  unauthorized,
  error;

  String get wireValue => switch (this) {
    valid => 'VALID',
    warning => 'WARNING',
    duplicate => 'DUPLICATE',
    needsProfile => 'NEEDS_PROFILE',
    unauthorized => 'UNAUTHORIZED',
    error => 'ERROR',
  };

  static ImportRowOutcome? tryParseWire(String wire) {
    for (final o in values) {
      if (o.wireValue == wire) return o;
    }
    return null;
  }
}
