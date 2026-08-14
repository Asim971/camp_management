import 'package:campaign_contracts/campaign_contracts.dart' show SessionStatus;
import 'package:freezed_annotation/freezed_annotation.dart';

// `export` alone re-exports the name to importers of this library, but does
// NOT bring it into scope for this file's own code (including the generated
// `part` below) — hence the `import` above as well.
export 'package:campaign_contracts/campaign_contracts.dart' show SessionStatus;

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
