import 'package:freezed_annotation/freezed_annotation.dart';

part 'campaign_session.freezed.dart';

/// A campaign session/event occurrence (W-05, FR-010..014). Counts drive the
/// operational view: how many are registered, awaiting sync, in review and
/// approved — attendance activity, kept distinct from commercial outcome.
@freezed
class CampaignSession with _$CampaignSession {
  const factory CampaignSession({
    required String id,
    required String campaignId,
    required String venue,
    required SessionStatus status,
    DateTime? startAt,
    DateTime? endAt,
    @Default(0) int capacity,
    @Default(0) int registeredCount,
    @Default(0) int pendingSyncCount,
    @Default(0) int reviewCount,
    @Default(0) int approvedCount,
    @Default(true) bool readinessOk,
  }) = _CampaignSession;

  const CampaignSession._();

  bool get overCapacity => capacity > 0 && registeredCount > capacity;
}

enum SessionStatus { upcoming, active, captureClosed, paused, completed }
