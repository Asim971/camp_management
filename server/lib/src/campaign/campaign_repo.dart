import 'package:campaign_contracts/campaign_contracts.dart';

import '../db/pool.dart';
import 'campaign_model.dart';

/// Columns selected for one campaign, shared verbatim between [list] and
/// [findById] (and their `GROUP BY`) so a caller gets back the identical
/// shape whichever route reached it.
const String _campaignColumns =
    'c.id, c.name, c.type, c.organization_id, c.status, c.owner_id, '
    'c.objective, c.venue, c.budget_reference, c.approver_id, '
    'c.start_at, c.end_at, c.target_audience, c.version';

/// `array_agg` over the `campaign_territories` join, aliased for [_rowFrom].
/// `COALESCE(..., ARRAY[]::text[])` so a campaign with no territory rows
/// reads back as `[]`, not `null` — the `LEFT JOIN` means the aggregate would
/// otherwise be a single `NULL` from the one all-NULL joined row.
const String _territoryIdsSelect =
    "COALESCE(array_agg(t.territory_id) "
    "FILTER (WHERE t.territory_id IS NOT NULL), ARRAY[]::text[]) "
    'AS territory_ids';

/// Reads campaigns for the caller's own organization.
///
/// Every method scopes by `organization_id` inside its `WHERE` clause, not
/// as a check applied to a result fetched some other way (D7): a campaign
/// belonging to a different organization is simply never selected, so a
/// foreign id reads back identically to a nonexistent one. The caller
/// (`campaign_routes.dart`) turns that into the ordinary 404 — never a 403,
/// which would confirm the id exists.
class CampaignRepo {
  CampaignRepo(this._db);

  final Db _db;

  static const int _minPageSize = 1;
  static const int _maxPageSize = 100;

  /// Lists campaigns for [organizationId], optionally narrowed by a
  /// case-insensitive contains-match on `name` ([search]) and/or a set of
  /// [statuses] (empty means "no status filter" — not "match nothing").
  ///
  /// [page] is clamped to `>= 1` and [pageSize] to `1..100` here,
  /// unconditionally, regardless of what the caller passes — a request for
  /// `pageSize=10000` is capped server-side rather than served as one
  /// unbounded page.
  ///
  /// `total` is a separate `COUNT(*)` over the exact same predicate, never
  /// the length of the returned page — the mock this replaces returned
  /// `items.length` as `total`, which made paging invisible to the client.
  Future<({List<CampaignRow> items, int total})> list({
    required String organizationId,
    String? search,
    List<CampaignStatus> statuses = const [],
    required int page,
    required int pageSize,
  }) async {
    final clampedPage = page < 1 ? 1 : page;
    final clampedPageSize = pageSize < _minPageSize
        ? _minPageSize
        : (pageSize > _maxPageSize ? _maxPageSize : pageSize);

    final params = <String, Object?>{'org': organizationId};
    final where = <String>['c.organization_id = @org'];

    // A leading-wildcard LIKE cannot use the btree campaigns_name_idx (that
    // index serves equality/prefix lookups only) — this seq-scans. Fine at
    // pilot scale (hundreds of campaigns); not worth a trigram extension.
    // Noted here so the index isn't later "discovered unused" and dropped.
    if (search != null && search.isNotEmpty) {
      where.add("lower(c.name) LIKE lower('%' || @q || '%')");
      params['q'] = search;
    }

    if (statuses.isNotEmpty) {
      final placeholders = <String>[];
      for (var i = 0; i < statuses.length; i++) {
        final key = 'status$i';
        placeholders.add('@$key');
        params[key] = statuses[i].wireValue;
      }
      where.add('c.status IN (${placeholders.join(', ')})');
    }

    final whereClause = where.join(' AND ');

    final countRes = await _db.execute(
      'SELECT COUNT(*) AS total FROM campaigns c WHERE $whereClause',
      params: params,
    );
    final total = row(countRes.single)['total']! as int;

    final itemsRes = await _db.execute(
      'SELECT $_campaignColumns, $_territoryIdsSelect '
      'FROM campaigns c '
      'LEFT JOIN campaign_territories t ON t.campaign_id = c.id '
      'WHERE $whereClause '
      'GROUP BY $_campaignColumns '
      'ORDER BY c.created_at DESC, c.id '
      'LIMIT @limit OFFSET @offset',
      params: {
        ...params,
        'limit': clampedPageSize,
        'offset': (clampedPage - 1) * clampedPageSize,
      },
    );

    return (items: [for (final r in itemsRes) _rowFrom(row(r))], total: total);
  }

  /// A single campaign scoped to [organizationId], or `null` if no row
  /// matches — whether because [id] does not exist at all, or because it
  /// belongs to a different organization. The two are indistinguishable on
  /// purpose (D7); see the class doc.
  Future<CampaignRow?> findById(
    String id, {
    required String organizationId,
  }) async {
    final res = await _db.execute(
      'SELECT $_campaignColumns, $_territoryIdsSelect '
      'FROM campaigns c '
      'LEFT JOIN campaign_territories t ON t.campaign_id = c.id '
      'WHERE c.id = @id AND c.organization_id = @org '
      'GROUP BY $_campaignColumns',
      params: {'id': id, 'org': organizationId},
    );
    if (res.isEmpty) return null;
    return _rowFrom(row(res.single));
  }

  /// Maps one decoded row to [CampaignRow].
  ///
  /// `status` is stored as its wire value (see the migration and
  /// [CampaignStatus.wireValue]), so `tryParseWire` here can only fail if a
  /// row was written with a value outside the enum — a data-integrity bug
  /// upstream, not a case this read path silently tolerates.
  CampaignRow _rowFrom(Map<String, Object?> r) {
    final status = CampaignStatus.tryParseWire(r['status']! as String);
    if (status == null) {
      throw StateError(
        'campaigns row ${r['id']} has unrecognised status '
        '"${r['status']}".',
      );
    }
    return CampaignRow(
      id: r['id']! as String,
      name: r['name']! as String,
      type: r['type']! as String,
      organizationId: r['organization_id']! as String,
      status: status,
      ownerId: r['owner_id']! as String,
      objective: r['objective'] as String?,
      venue: r['venue'] as String?,
      budgetReference: r['budget_reference'] as String?,
      approverId: r['approver_id'] as String?,
      // The driver already returns a UTC DateTime for timestamptz, but
      // .toUtc() is cheap and makes that invariant explicit rather than
      // assumed — see CampaignRow.toWireJson, which relies on isUtc for the
      // trailing "Z".
      startAt: (r['start_at'] as DateTime?)?.toUtc(),
      endAt: (r['end_at'] as DateTime?)?.toUtc(),
      targetAudience: r['target_audience']! as int,
      version: r['version']! as int,
      territoryIds: (r['territory_ids']! as List).cast<String>(),
    );
  }
}
