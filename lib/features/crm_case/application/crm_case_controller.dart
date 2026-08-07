import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/result/result.dart';
import '../../../core/trace/trace_id.dart';
import '../../../domain/verification/verification.dart';
import '../../../domain/verification/verification_case.dart';

/// Outcome of submitting a decision, so the screen can react precisely:
/// refresh on a concurrent edit, show an error, or navigate on success.
enum DecisionResult { submitted, conflict, error }

/// Loads one verification case and submits the human decision with optimistic
/// locking (C-02, §9.4). Reason is mandatory; the domain object enforces it.
class CrmCaseController
    extends AutoDisposeFamilyAsyncNotifier<VerificationCase, String> {
  @override
  Future<VerificationCase> build(String attendanceId) async {
    final repo = ref.read(verificationRepositoryProvider);
    final result = await repo.getCase(attendanceId);
    // TODO(T-3.1.6): emit AuditAction.sensitiveMediaViewed on case open, via
    // AuditSink.revealAudited so the reveal cannot fail open (§10.2).
    return result.fold((c) => c, (f) => throw f);
  }

  Future<DecisionResult> decide({
    required VerificationOutcome outcome,
    required String reason,
    bool supervisorOverride = false,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return DecisionResult.error;

    final repo = ref.read(verificationRepositoryProvider);
    final verifierId = ref.read(authControllerProvider)?.userId ?? 'unknown';

    final result = await repo.decide(
      VerificationDecision(
        attendanceId: current.attendanceId,
        verifierId: verifierId,
        outcome: outcome,
        reason: reason,
        supervisorOverride: supervisorOverride,
      ),
      expectedVersion: current.version,
      trace: TraceId.generate(),
    );

    return result.fold((_) => DecisionResult.submitted, (failure) {
      if (failure.kind == FailureKind.conflict) {
        ref.invalidateSelf(); // another reviewer decided → reload fresh
        return DecisionResult.conflict;
      }
      return DecisionResult.error;
    });
  }
}

final crmCaseControllerProvider = AsyncNotifierProvider.autoDispose
    .family<CrmCaseController, VerificationCase, String>(CrmCaseController.new);
