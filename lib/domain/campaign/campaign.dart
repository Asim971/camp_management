import 'package:freezed_annotation/freezed_annotation.dart';

import '../common/status.dart';

part 'campaign.freezed.dart';

/// Campaign/seminar header (PRD Appendix B "Campaign", FR-001).
@freezed
class Campaign with _$Campaign {
  const factory Campaign({
    required String id,
    required String name,
    required String type,
    required String organizationId,
    required CampaignStatus status,
    required String ownerId,
    DateTime? startAt,
    DateTime? endAt,
    String? venue,
    String? objective,
    @Default(<String>[]) List<String> territoryIds,
    @Default(0) int targetAudience,
    @Default(0) int verifiedAttendance,
    // Optimistic-concurrency token echoed back on every mutation
    // (submitForApproval/decide/updateDraft) so the server can reject a
    // write against a row someone else already changed. Defaults to 0 for
    // legacy/test call sites that construct a Campaign without a server
    // round-trip; a real wire payload always carries the server's value.
    @Default(0) int version,
  }) = _Campaign;

  const Campaign._();

  /// Lifecycle guard — the client mirrors the server's allowed transitions
  /// (§9.1) so illegal actions are disabled, not merely rejected on submit.
  bool canTransitionTo(CampaignStatus next) => switch (status) {
    CampaignStatus.draft => next == CampaignStatus.pendingApproval,
    CampaignStatus.pendingApproval => {
      CampaignStatus.approved,
      CampaignStatus.returned,
      CampaignStatus.cancelled,
    }.contains(next),
    CampaignStatus.returned => next == CampaignStatus.pendingApproval,
    CampaignStatus.approved => next == CampaignStatus.active,
    CampaignStatus.active => {
      CampaignStatus.paused,
      CampaignStatus.completed,
    }.contains(next),
    CampaignStatus.paused => next == CampaignStatus.active,
    CampaignStatus.completed || CampaignStatus.cancelled => false,
  };
}
