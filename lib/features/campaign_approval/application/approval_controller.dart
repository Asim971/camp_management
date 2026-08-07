import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/result/result.dart';
import '../../../core/trace/trace_id.dart';
import '../../../domain/campaign/campaign.dart';
import '../../../domain/campaign/campaign_repository.dart';

enum ApprovalResult { done, conflict, error }

/// Loads the campaign under review and records the approver decision (W-04,
/// FR-007). Return/reject require a reason; the screen also enforces
/// segregation of duties (the creator cannot approve their own campaign).
class ApprovalController
    extends AutoDisposeFamilyAsyncNotifier<Campaign, String> {
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
          trace: TraceId.generate(),
        );
    return result.fold((_) => ApprovalResult.done, (failure) {
      if (failure.kind == FailureKind.conflict) {
        ref.invalidateSelf();
        return ApprovalResult.conflict;
      }
      return ApprovalResult.error;
    });
  }
}

final approvalControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ApprovalController, Campaign, String>(ApprovalController.new);
