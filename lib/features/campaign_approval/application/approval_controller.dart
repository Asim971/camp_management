import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/result/result.dart';
import '../../../core/trace/trace_id.dart';
import '../../../domain/campaign/campaign.dart';
import '../../../domain/campaign/campaign_repository.dart';

// `validation` is distinct from `error`: it means the server understood the
// request and refused it FOR A SPECIFIC, NAMEABLE REASON (missing reason,
// unacknowledged warnings) — [ApprovalController.lastFailureMessage] carries
// that reason. `error` covers everything else (network/timeout/unknown),
// where there is nothing more specific to say.
enum ApprovalResult { done, conflict, validation, error }

/// Loads the campaign under review and records the approver decision (W-04,
/// FR-007). Return/reject require a reason; the screen also enforces
/// segregation of duties (the creator cannot approve their own campaign).
class ApprovalController
    extends AutoDisposeFamilyAsyncNotifier<Campaign, String> {
  /// The server's own explanation for the most recent [ApprovalResult.
  /// validation] outcome (e.g. "A reason is required to return or reject a
  /// campaign.", or which warning codes are unacknowledged) — read by the
  /// screen right after `decide()` returns. `null` until the first
  /// validation failure; stale content is harmless since the screen only
  /// reads it when the result it just got back IS `.validation`.
  String? lastFailureMessage;

  @override
  Future<Campaign> build(String campaignId) async {
    final repo = ref.read(campaignRepositoryProvider);
    final result = await repo.getById(campaignId);
    return result.fold((c) => c, (f) => throw f);
  }

  /// True when the signed-in approver also created the campaign — approval
  /// must be blocked (segregation of duties, §8.4/§9.1).
  bool get sodViolation {
    final campaign = state.valueOrNull;
    final userId = switch (ref.read(authStateProvider)) {
      AuthSignedIn(:final session) => session.userId,
      _ => null,
    };
    return campaign != null && userId != null && campaign.ownerId == userId;
  }

  Future<ApprovalResult> decide({
    required CampaignDecision decision,
    String? reason,
    required List<String> acknowledgedWarnings,
  }) async {
    final campaign = state.valueOrNull;
    if (campaign == null) return ApprovalResult.error;
    if (decision == CampaignDecision.approve && sodViolation) {
      return ApprovalResult.error;
    }

    final result = await ref
        .read(campaignRepositoryProvider)
        .decide(
          campaign.id,
          decision: decision,
          reason: reason,
          version: campaign.version,
          acknowledgedWarnings: acknowledgedWarnings,
          trace: TraceId.generate(),
        );
    return result.fold((_) => ApprovalResult.done, (failure) {
      switch (failure.kind) {
        case FailureKind.conflict:
          ref.invalidateSelf();
          return ApprovalResult.conflict;
        case FailureKind.validation:
          // The server's message names the specific problem (missing reason,
          // unacknowledged warnings) — carry it verbatim rather than
          // collapsing it into the same dead-end text as every other error.
          lastFailureMessage = failure.message;
          return ApprovalResult.validation;
        default:
          return ApprovalResult.error;
      }
    });
  }
}

final approvalControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ApprovalController, Campaign, String>(ApprovalController.new);
