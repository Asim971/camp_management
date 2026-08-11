import '../../core/result/result.dart';
import '../../core/trace/trace_id.dart';
import '../common/status.dart';
import 'campaign.dart';
import 'campaign_draft.dart';

/// Query parameters for the campaign list (default sort is exception-first,
/// then upcoming date — Guideline §8.2, NOT alphabetical).
class CampaignQuery {
  const CampaignQuery({
    this.search,
    this.statuses = const {},
    this.territoryIds = const {},
    this.page = 0,
    this.pageSize = 25,
  });

  final String? search;
  final Set<CampaignStatus> statuses;
  final Set<String> territoryIds;
  final int page;
  final int pageSize;
}

class Paged<T> {
  const Paged({required this.items, required this.total});
  final List<T> items;
  final int total;
}

/// Repository interface lives in the domain layer; the Dio implementation lives
/// in data/. Features depend only on this abstraction.
abstract interface class CampaignRepository {
  Future<Result<Paged<Campaign>>> list(CampaignQuery query);
  Future<Result<Campaign>> getById(String id);

  /// Creates a new Draft campaign from wizard input. Returns the persisted
  /// campaign (with server id + Draft status).
  ///
  /// [trace] is the per-action correlation id; pass the same one to the audit
  /// event for this action so the two can be joined (Architecture §12).
  Future<Result<Campaign>> createDraft(CampaignDraft draft, {TraceId? trace});

  /// Persists edits to an existing Draft. [version] is the value the caller
  /// last saw (§9.1 optimistic concurrency) — the server 409s if it has moved.
  Future<Result<Campaign>> updateDraft(
    String id,
    CampaignDraft draft, {
    required int version,
  });

  /// [version] is the value the caller last saw; a stale value 409s rather
  /// than silently submitting over someone else's concurrent edit.
  Future<Result<Campaign>> submitForApproval(
    String id, {
    required int version,
    TraceId? trace,
  });

  /// Approve/return/reject. [reason] is mandatory for return/reject (§8.4).
  /// [acknowledgedWarnings] must name every critical warning the server
  /// derived for this campaign or an APPROVE is rejected
  /// (WARNINGS_UNACKNOWLEDGED) — silently waving one through is exactly the
  /// permission-escalation failure this migration exists to close.
  Future<Result<Campaign>> decide(
    String id, {
    required CampaignDecision decision,
    String? reason,
    required int version,
    required List<String> acknowledgedWarnings,
    TraceId? trace,
  });
}

enum CampaignDecision { approve, returnForCorrection, reject }
