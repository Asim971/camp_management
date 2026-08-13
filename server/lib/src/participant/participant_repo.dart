import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:uuid/uuid.dart';

import '../db/pool.dart';
import '../infra/audit.dart';
import '../infra/error_envelope.dart';

const Uuid _uuid = Uuid();

/// A carpenter as the API presents it. Holds the RAW `phone` and full
/// `displayCode` so the masking lives in exactly one place ([toWireJson]);
/// nothing outside this class may serialise a carpenter.
class CarpenterView {
  const CarpenterView({
    required this.id,
    required this.name,
    required this.displayCode,
    required this.phone,
    required this.territoryName,
    required this.dealerContext,
    required this.thumbnailUrl,
    required this.eligible,
    required this.syncStatus,
  });

  final String id;
  final String name;
  final String displayCode;
  final String phone;
  final String? territoryName;
  final String? dealerContext;
  final String? thumbnailUrl;
  final bool eligible;
  final String syncStatus;

  /// Exactly the shape `RegistrationRepositoryImpl._fromJson` parses, plus
  /// the additive `syncStatus` (spec 2a.D5). `attendanceState` is ABSENT on
  /// purpose: its vocabulary belongs to sub-project 4 (spec 2a.D4). Raw
  /// phone/NID never appear here (spec 2a.D2).
  Map<String, Object?> toWireJson() => {
    'id': id,
    'name': name,
    'displayId': 'CARP-••${_last4(displayCode)}',
    'phoneSuffix': _last4(phone),
    'territory': territoryName ?? '',
    'dealerContext': dealerContext,
    'thumbnailUrl': thumbnailUrl,
    'eligible': eligible,
    'syncStatus': syncStatus,
  };

  static String _last4(String s) =>
      s.length <= 4 ? s : s.substring(s.length - 4);
}

/// SQL for carpenters, registrations and profile requests. Every query is
/// scoped by `organization_id` inside the SQL itself (D7): a foreign row is
/// never selected, so `null` returns are the ONLY missing-vs-foreign signal
/// and the routes turn them into ordinary 404s.
class ParticipantRepo {
  ParticipantRepo(this._db) : _audit = AuditWriter(_db);

  final Db _db;
  final AuditWriter _audit;

  static const String _carpenterColumns =
      'c.id, c.full_name, c.phone, c.display_code, c.dealer_context, '
      'c.thumbnail_url, c.eligible, c.sync_status, t.name AS territory_name';

  CarpenterView _view(Map<String, Object?> r) => CarpenterView(
    id: r['id']! as String,
    name: r['full_name']! as String,
    displayCode: r['display_code']! as String,
    phone: r['phone']! as String,
    territoryName: r['territory_name'] as String?,
    dealerContext: r['dealer_context'] as String?,
    thumbnailUrl: r['thumbnail_url'] as String?,
    eligible: r['eligible']! as bool,
    syncStatus: r['sync_status']! as String,
  );

  /// Escapes Postgres's default `LIKE`/`ILIKE` escape character (`\`) plus
  /// its two metacharacters (`%`, `_`) in a value that will be bound as a
  /// query PARAMETER and concatenated between literal `%` wildcards in the
  /// SQL text (e.g. `'%' || @q || '%'`). Without this, `q='%%'` — two
  /// characters, so it clears the route's minimum-length guard — would bind
  /// as a wildcard-only pattern and match every row, defeating the very
  /// guard the minimum exists for. Backslash MUST be escaped first, or the
  /// backslashes inserted for `%`/`_` would themselves get re-escaped.
  static String _escapeLikeMetachars(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// Org-scoped master search over name (case-insensitive contains),
  /// display code (contains) and phone (suffix). Bounded at 50 rows: the
  /// workspace renders a short list and pagination is a spec non-goal until
  /// a real dataset demands it.
  Future<List<CarpenterView>> search({
    required String organizationId,
    required String q,
  }) async {
    final escaped = _escapeLikeMetachars(q);
    final res = await _db.execute(
      'SELECT $_carpenterColumns FROM carpenters c '
      'LEFT JOIN territories t ON t.id = c.territory_id '
      'WHERE c.organization_id = @org AND ('
      "  c.full_name ILIKE '%' || @q || '%' "
      "  OR c.display_code ILIKE '%' || @q || '%' "
      "  OR c.phone LIKE '%' || @q"
      ') '
      'ORDER BY lower(c.full_name), c.id LIMIT 50',
      params: {'org': organizationId, 'q': escaped},
    );
    return res.map(row).map(_view).toList();
  }

  /// The registered carpenters of [sessionId]'s CAMPAIGN — registration is
  /// campaign-level; the client warms a per-session offline cache from it.
  /// `null` when the session (or its campaign) is not visible in
  /// [organizationId].
  Future<List<CarpenterView>?> rosterForSession(
    String sessionId, {
    required String organizationId,
  }) async {
    final scoped = await _db.execute(
      'SELECT s.campaign_id FROM campaign_sessions s '
      'JOIN campaigns cg ON cg.id = s.campaign_id '
      'WHERE s.id = @session AND cg.organization_id = @org',
      params: {'session': sessionId, 'org': organizationId},
    );
    if (scoped.isEmpty) return null;
    final campaignId = row(scoped.single)['campaign_id']! as String;

    final res = await _db.execute(
      'SELECT $_carpenterColumns FROM registrations r '
      'JOIN carpenters c ON c.id = r.carpenter_id '
      'LEFT JOIN territories t ON t.id = c.territory_id '
      'WHERE r.campaign_id = @campaign '
      'ORDER BY lower(c.full_name), c.id',
      params: {'campaign': campaignId},
    );
    return res.map(row).map(_view).toList();
  }

  /// Registers [carpenterIds] into [campaignId]. Returns `null` when the
  /// campaign is not visible in [organizationId] (route → 404). Throws
  /// [ApiException] `UNKNOWN_CARPENTER` naming ids that are unknown or
  /// cross-org — ids only, never names or phones (spec 2a.D2). All-or-
  /// nothing: a partially valid batch registers nothing.
  Future<({int registered, int alreadyRegistered})?> register({
    required String campaignId,
    required String organizationId,
    required List<String> carpenterIds,
    required String registeredBy,
    String? correlationId,
  }) async {
    final campaign = await _db.execute(
      'SELECT 1 FROM campaigns WHERE id = @id AND organization_id = @org',
      params: {'id': campaignId, 'org': organizationId},
    );
    if (campaign.isEmpty) return null;

    // Deduplicated once, up front: the INSERT's SELECT below produces one
    // row per matching carpenter ROW, not per id in the caller's list, so a
    // repeated id would otherwise inflate `alreadyRegistered` for carpenters
    // that were never actually already on the roster.
    final ids = carpenterIds.toSet().toList();

    // List<String> binds as a Postgres text[] — exactly what ANY() wants
    // (the jsonb trap from slice-1 Task 9 is the OTHER direction).
    final known = await _db.execute(
      'SELECT id FROM carpenters '
      'WHERE organization_id = @org AND id = ANY(@ids)',
      params: {'org': organizationId, 'ids': ids},
    );
    final knownIds = known.map((r) => row(r)['id']! as String).toSet();
    final unknown = ids.where((id) => !knownIds.contains(id)).toList();
    if (unknown.isNotEmpty) {
      throw ApiException(
        ApiErrorCode.unknownCarpenter,
        message: 'One or more carpenter ids are unknown.',
        details: {'carpenterIds': unknown},
      );
    }

    late int inserted;
    await _db.tx((tx) async {
      final result = await tx.execute(
        Sql.named(
          'INSERT INTO registrations '
          '(campaign_id, carpenter_id, status, registered_by) '
          'SELECT @campaign, c.id, '
          "  CASE WHEN c.sync_status = 'PENDING_PROFILE_SYNC' "
          "       THEN '${RegistrationStatus.pendingProfileSync.wireValue}' "
          "       ELSE '${RegistrationStatus.registered.wireValue}' END, "
          '  @by '
          'FROM carpenters c '
          // The org predicate is belt-and-braces with the pre-check above:
          // D7 requires org-scoping to live inside the SQL itself, so this
          // write does not depend on a guard elsewhere for its safety.
          'WHERE c.id = ANY(@ids) AND c.organization_id = @org '
          'ON CONFLICT (campaign_id, carpenter_id) DO NOTHING',
        ),
        parameters: {
          'campaign': campaignId,
          'ids': ids,
          'org': organizationId,
          'by': registeredBy,
        },
      );
      inserted = result.affectedRows;
      await _audit.writeTx(
        tx,
        action: 'registration.create',
        resourceType: 'campaign',
        resourceId: campaignId,
        actorId: registeredBy,
        correlationId: correlationId,
        payload: {'carpenterCount': ids.length, 'registered': inserted},
      );
    });
    return (registered: inserted, alreadyRegistered: ids.length - inserted);
  }

  /// Creates the provisional carpenter AND the profile request in one
  /// transaction (spec 2a.D1), returning both so the route can hand the
  /// carpenter straight back for the client's basket. `null` when the
  /// campaign is not visible (route → 404).
  Future<({String requestId, CarpenterView carpenter})?> createProfileRequest({
    required String campaignId,
    required String organizationId,
    required String name,
    required String phone,
    required String requestedBy,
    String? correlationId,
  }) async {
    final campaign = await _db.execute(
      'SELECT 1 FROM campaigns WHERE id = @id AND organization_id = @org',
      params: {'id': campaignId, 'org': organizationId},
    );
    if (campaign.isEmpty) return null;

    final carpenterId = _uuid.v4();
    final requestId = _uuid.v4();
    late CarpenterView view;
    await _db.tx((tx) async {
      final inserted = await tx.execute(
        Sql.named(
          'INSERT INTO carpenters '
          '(id, organization_id, full_name, phone, source, sync_status, '
          ' display_code) '
          "VALUES (@id, @org, @name, @phone, 'PROFILE_REQUEST', "
          "        'PENDING_PROFILE_SYNC', "
          "        'CARP-' || lpad(nextval('carpenter_display_serial')::text, 8, '0')) "
          'RETURNING id, full_name, phone, display_code, dealer_context, '
          '          thumbnail_url, eligible, sync_status, '
          '          NULL::text AS territory_name',
        ),
        parameters: {
          'id': carpenterId,
          'org': organizationId,
          'name': name,
          'phone': phone,
        },
      );
      view = _view(row(inserted.single));
      await tx.execute(
        Sql.named(
          'INSERT INTO profile_requests '
          '(id, campaign_id, carpenter_id, requested_by, name, phone) '
          'VALUES (@id, @campaign, @carpenter, @by, @name, @phone)',
        ),
        parameters: {
          'id': requestId,
          'campaign': campaignId,
          'carpenter': carpenterId,
          'by': requestedBy,
          'name': name,
          'phone': phone,
        },
      );
      await _audit.writeTx(
        tx,
        action: 'profile_request.create',
        resourceType: 'campaign',
        resourceId: campaignId,
        actorId: requestedBy,
        correlationId: correlationId,
        // The carpenter id, never the name/phone (spec 2a.D2).
        payload: {'carpenterId': carpenterId, 'requestId': requestId},
      );
    });
    return (requestId: requestId, carpenter: view);
  }
}
