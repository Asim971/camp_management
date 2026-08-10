/// Stable machine-readable error vocabulary. Clients switch on `code` and
/// never parse `message`, so a wording change is never a breaking change.
enum ApiErrorCode {
  // transport / generic
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  internal,
  // concurrency and replay
  conflictStaleVersion,
  idempotencyKeyRequired,
  idempotencyKeyReused,
  idempotencyKeyInFlight,
  // campaign lifecycle
  campaignInvalidTransition,
  campaignValidationFailed,
  decisionReasonRequired,
  warningsUnacknowledged,
  segregationOfDutiesViolation;

  String get wireValue => switch (this) {
    badRequest => 'BAD_REQUEST',
    unauthorized => 'UNAUTHORIZED',
    forbidden => 'FORBIDDEN',
    notFound => 'NOT_FOUND',
    internal => 'INTERNAL',
    conflictStaleVersion => 'CONFLICT_STALE_VERSION',
    idempotencyKeyRequired => 'IDEMPOTENCY_KEY_REQUIRED',
    idempotencyKeyReused => 'IDEMPOTENCY_KEY_REUSED',
    idempotencyKeyInFlight => 'IDEMPOTENCY_KEY_IN_FLIGHT',
    campaignInvalidTransition => 'CAMPAIGN_INVALID_TRANSITION',
    campaignValidationFailed => 'CAMPAIGN_VALIDATION_FAILED',
    decisionReasonRequired => 'DECISION_REASON_REQUIRED',
    warningsUnacknowledged => 'WARNINGS_UNACKNOWLEDGED',
    segregationOfDutiesViolation => 'SEGREGATION_OF_DUTIES_VIOLATION',
  };

  static ApiErrorCode? tryParseWire(String wire) {
    for (final c in values) {
      if (c.wireValue == wire) return c;
    }
    return null;
  }
}
