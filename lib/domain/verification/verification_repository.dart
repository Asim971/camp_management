import '../../core/result/result.dart';
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
  Future<Result<void>> decide(
    VerificationDecision decision, {
    required int expectedVersion,
  });
}
