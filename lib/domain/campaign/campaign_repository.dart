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

  /// Persists edits to an existing Draft.
  Future<Result<Campaign>> updateDraft(String id, CampaignDraft draft);

  Future<Result<Campaign>> submitForApproval(String id, {TraceId? trace});

  /// Approve/return/reject. [reason] is mandatory for return/reject (§8.4).
  Future<Result<Campaign>> decide(
    String id, {
    required CampaignDecision decision,
    String? reason,
    TraceId? trace,
  });
}

enum CampaignDecision { approve, returnForCorrection, reject }
