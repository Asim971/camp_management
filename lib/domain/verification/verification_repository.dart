import '../../core/result/result.dart';
import '../../core/trace/trace_id.dart';
import 'verification.dart';
import 'verification_case.dart';

/// CRM verification data access. Decisions are the authoritative human outcome
/// (FR-011); the machine result is advisory only.
abstract interface class VerificationRepository {
  Future<Result<List<VerificationQueueItem>>> queue({String? assigneeId});

  Future<Result<VerificationCase>> getCase(String attendanceId);

  /// Submits the human decision. [expectedVersion] guards against a concurrent
  /// decision — the server returns 409 (→ [FailureKind.conflict]) if another
  /// reviewer already decided, so the UI can refresh instead of overwriting
  /// (§9.4). Reason is mandatory (enforced in the domain object).
  ///
  /// [trace] is the per-action correlation id; pass the same one to the audit
  /// event for this action so the two can be joined (Architecture §12).
  Future<Result<void>> decide(
    VerificationDecision decision, {
    required int expectedVersion,
    TraceId? trace,
  });
}
