/// Bulk-import job lifecycle. Moved out of the app's
/// `lib/domain/common/status.dart` now that sub-project 2b defines its server
/// contract (the D5 rule: enums move only when their wire contract lands).
///
/// 2b implements PROCESSING → READY_TO_COMMIT → COMPLETED, plus FAILED. DRY_RUN,
/// PARTIALLY_COMPLETED and CANCELLED ship in the vocabulary but are produced by
/// a later slice (2c) — shipping them now means 2c needs no contract change.
enum ImportStatus {
  dryRun,
  readyToCommit,
  processing,
  completed,
  partiallyCompleted,
  failed,
  cancelled;

  String get wireValue => switch (this) {
    dryRun => 'DRY_RUN',
    readyToCommit => 'READY_TO_COMMIT',
    processing => 'PROCESSING',
    completed => 'COMPLETED',
    partiallyCompleted => 'PARTIALLY_COMPLETED',
    failed => 'FAILED',
    cancelled => 'CANCELLED',
  };

  static ImportStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
