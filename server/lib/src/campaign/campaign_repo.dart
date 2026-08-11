import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:postgres/postgres.dart' show Sql, TxSession;
import 'package:uuid/uuid.dart';

import '../db/pool.dart';
import '../infra/audit.dart';
import '../infra/error_envelope.dart';
import 'campaign_model.dart';
import 'config_gate.dart';
import 'status_machine.dart';
import 'validation.dart';

const Uuid _uuid = Uuid();

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
  CampaignRepo(this._db) : _audit = AuditWriter(_db);

  final Db _db;
  final AuditWriter _audit;

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

  /// Creates a new DRAFT campaign owned by [ownerId] in [organizationId].
  ///
  /// A DRAFT is deliberately permissive: [input] is stored exactly as given,
  /// with no [validateForSubmit] gate — that gate belongs to the submit
  /// transition (D6), not to saving an in-progress wizard state. A campaign
  /// can be created with a blank name, no sessions, no approver — anything
  /// the wizard's later steps would otherwise reject on submit.
  Future<CampaignRow> create(
    CampaignDraftInput input, {
    required String organizationId,
    required String ownerId,
    String? correlationId,
  }) async {
    _throwIfFieldErrors(
      await _crossOrgErrors(input, organizationId: organizationId),
    );
    final id = _uuid.v4();
    await _db.tx((tx) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO campaigns '
          '(id, organization_id, name, type, objective, status, owner_id, '
          ' approver_id, target_audience, budget_reference, '
          ' geofence_enabled, version) '
          'VALUES (@id, @org, @name, @type, @objective, @status, @owner, '
          '        @approver, @target, @budget, @geofence, 1)',
        ),
        parameters: {
          'id': id,
          'org': organizationId,
          'name': input.name,
          'type': input.type,
          'objective': input.objective,
          'status': CampaignStatus.draft.wireValue,
          'owner': ownerId,
          'approver': input.approverId,
          'target': input.target,
          'budget': input.budgetReference,
          'geofence': input.geofenceEnabled,
        },
      );
      await _replaceTerritoriesTx(tx, id, input.territoryIds);
      await _replaceSessionsTx(tx, id, input.sessions);
      await _audit.writeTx(
        tx,
        action: 'campaign.created',
        resourceType: 'campaign',
        resourceId: id,
        actorId: ownerId,
        correlationId: correlationId,
      );
    });

    return _requireFreshRow(id, organizationId: organizationId, verb: 'create');
  }

  /// Overwrites the editable draft fields of campaign [id] in place.
  ///
  /// Only legal while the campaign is still DRAFT or RETURNED — the same two
  /// states [nextStatusForSubmit] treats as submittable (`_isEditableDraft`).
  /// Anything else (a campaign already under review, approved, or beyond) is
  /// an [ApiErrorCode.campaignInvalidTransition], not a silently-accepted
  /// edit of a row someone else is already acting on.
  Future<CampaignRow> updateDraft(
    String id,
    CampaignDraftInput input, {
    required String organizationId,
    required int expectedVersion,
    String? correlationId,
  }) async {
    final current = await findById(id, organizationId: organizationId);
    if (current == null) {
      throw ApiException(ApiErrorCode.notFound);
    }
    if (!_isEditableDraft(current.status)) {
      throw ApiException(
        ApiErrorCode.campaignInvalidTransition,
        details: {'currentStatus': current.status.wireValue},
      );
    }
    _throwIfFieldErrors(
      await _crossOrgErrors(input, organizationId: organizationId),
    );

    await _db.tx((tx) async {
      final updated = await tx.execute(
        Sql.named(
          'UPDATE campaigns SET '
          '  name = @name, type = @type, objective = @objective, '
          '  approver_id = @approver, target_audience = @target, '
          '  budget_reference = @budget, geofence_enabled = @geofence, '
          '  version = version + 1, updated_at = now() '
          'WHERE id = @id AND organization_id = @org AND version = @expected',
        ),
        parameters: {
          'id': id,
          'org': organizationId,
          'expected': expectedVersion,
          'name': input.name,
          'type': input.type,
          'objective': input.objective,
          'approver': input.approverId,
          'target': input.target,
          'budget': input.budgetReference,
          'geofence': input.geofenceEnabled,
        },
      );
      // Zero affected rows is the whole concurrency guarantee: it means the
      // row this UPDATE was aimed at, scoped to this exact version, no
      // longer exists — either a concurrent writer already moved it on, or
      // the caller's own view of it is simply stale. Either way, silently
      // overwriting whatever is there now would lose that other write.
      if (updated.affectedRows == 0) {
        throw ApiException(ApiErrorCode.conflictStaleVersion);
      }
      await _replaceTerritoriesTx(tx, id, input.territoryIds);
      await _replaceSessionsTx(tx, id, input.sessions);
      await _audit.writeTx(
        tx,
        action: 'campaign.updated',
        resourceType: 'campaign',
        resourceId: id,
        actorId: input.ownerId,
        correlationId: correlationId,
      );
    });

    return _requireFreshRow(id, organizationId: organizationId, verb: 'update');
  }

  /// Transitions campaign [id] from DRAFT/RETURNED to PENDING_APPROVAL.
  ///
  /// Revalidates server-side with [validateForSubmit] against the campaign's
  /// own stored fields (not a client-supplied body — submit takes none): the
  /// wizard is not a trust boundary, so a row written straight into the
  /// database with, say, overlapping sessions is caught here exactly as it
  /// would be caught client-side, with the same field-keyed errors (D6).
  ///
  /// On success, stores an immutable snapshot of the submitted draft
  /// (`campaign_submissions`) — without it a later resubmission has nothing
  /// to diff against — in the same transaction as the status change, so the
  /// two can never disagree about whether a submission happened.
  Future<CampaignRow> submit(
    String id, {
    required String organizationId,
    required String submittedBy,
    required int expectedVersion,
    String? correlationId,
  }) async {
    final current = await findById(id, organizationId: organizationId);
    if (current == null) {
      throw ApiException(ApiErrorCode.notFound);
    }
    final nextStatus = nextStatusForSubmit(current.status);
    if (nextStatus == null) {
      throw ApiException(
        ApiErrorCode.campaignInvalidTransition,
        details: {'currentStatus': current.status.wireValue},
      );
    }

    final draftInput = await _draftInputFor(current);
    _throwIfFieldErrors(validateForSubmit(draftInput));

    final snapshot = _snapshotOf(draftInput);

    await _db.tx((tx) async {
      final updated = await tx.execute(
        Sql.named(
          'UPDATE campaigns SET status = @status, version = version + 1, '
          '  updated_at = now() '
          'WHERE id = @id AND organization_id = @org AND version = @expected',
        ),
        parameters: {
          'id': id,
          'org': organizationId,
          'expected': expectedVersion,
          'status': nextStatus.wireValue,
        },
      );
      // See updateDraft's identical check: this is the ONLY place the
      // version invariant is enforced. Everything above ran against a
      // snapshot read moments earlier and could, in principle, already be
      // stale by the time this UPDATE runs; this WHERE clause is what turns
      // that possibility into a hard "zero rows changed" fact instead of a
      // silent overwrite.
      if (updated.affectedRows == 0) {
        throw ApiException(ApiErrorCode.conflictStaleVersion);
      }
      await tx.execute(
        Sql.named(
          'INSERT INTO campaign_submissions '
          '(id, campaign_id, version, submitted_by, snapshot) '
          'VALUES (@id, @campaign, @version, @submittedBy, @snapshot)',
        ),
        parameters: {
          'id': _uuid.v4(),
          'campaign': id,
          // The version the campaign was AT when this snapshot was taken —
          // the pre-bump value the caller believed was current, mirroring
          // campaign_decisions.version_at_decision below.
          'version': expectedVersion,
          'submittedBy': submittedBy,
          'snapshot': snapshot,
        },
      );
      await _audit.writeTx(
        tx,
        action: 'campaign.submitted',
        resourceType: 'campaign',
        resourceId: id,
        actorId: submittedBy,
        correlationId: correlationId,
      );
    });

    return _requireFreshRow(id, organizationId: organizationId, verb: 'submit');
  }

  /// Records a reviewer's decision on a PENDING_APPROVAL campaign and, on
  /// success, transitions it per [nextStatusForDecision].
  ///
  /// Every gate below runs before the transaction opens: SoD (does the
  /// reviewer also own the campaign, with SoD enforced per [sodEnforced]),
  /// a reason for RETURN_FOR_CORRECTION/REJECT, and unacknowledged critical
  /// warnings on APPROVE. Only the version invariant is enforced inside the
  /// transaction itself, via the same zero-affected-rows check [submit] and
  /// [updateDraft] use.
  Future<CampaignRow> decide(
    String id, {
    required String organizationId,
    required String reviewerId,
    required CampaignDecisionInput decision,
    String? reason,
    required List<String> acknowledgedWarnings,
    required int expectedVersion,
    String? correlationId,
  }) async {
    final current = await findById(id, organizationId: organizationId);
    if (current == null) {
      throw ApiException(ApiErrorCode.notFound);
    }
    final nextStatus = nextStatusForDecision(current.status, decision);
    if (nextStatus == null) {
      throw ApiException(
        ApiErrorCode.campaignInvalidTransition,
        details: {'currentStatus': current.status.wireValue},
      );
    }

    if (current.ownerId == reviewerId && await sodEnforced(_db)) {
      throw ApiException(ApiErrorCode.segregationOfDutiesViolation);
    }

    final reasonRequired =
        decision == CampaignDecisionInput.returnForCorrection ||
        decision == CampaignDecisionInput.reject;
    if (reasonRequired && (reason == null || reason.trim().isEmpty)) {
      throw ApiException(ApiErrorCode.decisionReasonRequired);
    }

    if (decision == CampaignDecisionInput.approve) {
      final sessions = await _loadSessions(id);
      final criticalWarnings = deriveCriticalWarnings(
        targetAudience: current.targetAudience,
        sessions: sessions,
      );
      final unacknowledged = [
        for (final w in criticalWarnings)
          if (!acknowledgedWarnings.contains(w)) w,
      ];
      if (unacknowledged.isNotEmpty) {
        throw ApiException(
          ApiErrorCode.warningsUnacknowledged,
          details: {'warnings': unacknowledged},
        );
      }
    }

    // Best-effort link back to the submission this decision is deciding on
    // — nullable in the schema, so a decision on a campaign somehow lacking
    // a submission row still records everything else correctly.
    final submissionId = await _latestSubmissionId(id);

    await _db.tx((tx) async {
      final updated = await tx.execute(
        Sql.named(
          'UPDATE campaigns SET status = @status, version = version + 1, '
          '  updated_at = now() '
          'WHERE id = @id AND organization_id = @org AND version = @expected',
        ),
        parameters: {
          'id': id,
          'org': organizationId,
          'expected': expectedVersion,
          'status': nextStatus.wireValue,
        },
      );
      if (updated.affectedRows == 0) {
        throw ApiException(ApiErrorCode.conflictStaleVersion);
      }
      await tx.execute(
        Sql.named(
          'INSERT INTO campaign_decisions '
          '(id, campaign_id, submission_id, reviewer_id, decision, reason, '
          ' acknowledged_warnings, version_at_decision, correlation_id) '
          'VALUES (@id, @campaign, @submission, @reviewer, @decision, '
          '        @reason, @acknowledged::jsonb, @version, @correlation)',
        ),
        parameters: {
          'id': _uuid.v4(),
          'campaign': id,
          'submission': submissionId,
          'reviewer': reviewerId,
          'decision': decision.wireValue,
          'reason': reason,
          // Audit finding: unlike a `Map` parameter (see `_snapshotOf`'s doc
          // and `AuditWriter.payload`, both of which the driver encodes as
          // jsonb automatically from the Dart value's own type), a `List`
          // parameter with no explicit type gets encoded as a Postgres
          // ARRAY, not JSON — Postgres then rejects it against this jsonb
          // column with `22P02: invalid input syntax for type json`. Only
          // visible by actually running it against the driver, exactly the
          // class of thing the jsonb notes elsewhere in this codebase warn
          // about. Encoding it to a JSON string ourselves and casting with
          // `::jsonb` in the SQL (this file's fallback per the brief) sends
          // Postgres text it can parse as JSON regardless of how the driver
          // would have guessed the parameter's type.
          'acknowledged': jsonEncode(acknowledgedWarnings),
          // The version the campaign was AT when decided — the pre-bump
          // value the reviewer was looking at, not the post-bump result.
          'version': expectedVersion,
          'correlation': correlationId,
        },
      );
      await _audit.writeTx(
        tx,
        action: 'campaign.decided',
        resourceType: 'campaign',
        resourceId: id,
        actorId: reviewerId,
        correlationId: correlationId,
      );
    });

    return _requireFreshRow(id, organizationId: organizationId, verb: 'decide');
  }

  /// DRAFT and RETURNED are the two states [nextStatusForSubmit] accepts —
  /// [updateDraft] reuses that exact boundary rather than defining a second,
  /// possibly-drifting notion of "editable".
  static bool _isEditableDraft(CampaignStatus status) =>
      status == CampaignStatus.draft || status == CampaignStatus.returned;

  /// [errors] as one [ApiErrorCode.campaignValidationFailed], or nothing if
  /// [errors] is empty. Shared by every write path that reports field-keyed
  /// validation failures ([create]/[updateDraft]'s cross-org check, and
  /// [submit]'s [validateForSubmit] revalidation) so the wire shape
  /// (`details: {'fields': [{field, message}, ...]}`) can't drift between
  /// them.
  void _throwIfFieldErrors(List<FieldError> errors) {
    if (errors.isEmpty) return;
    throw ApiException(
      ApiErrorCode.campaignValidationFailed,
      details: {
        'fields': [
          for (final e in errors) {'field': e.field, 'message': e.message},
        ],
      },
    );
  }

  /// Verifies [input]'s org-scoped references — every `territoryIds` entry
  /// and a non-null `approverId` — actually belong to [organizationId] (D7).
  ///
  /// [CampaignDraftInput] carries only ids; `territories`/`staff_users` FKs
  /// on the `campaigns`/`campaign_territories` columns already reject an id
  /// that doesn't exist *anywhere*, but a `campaign_create` holder in one
  /// organization can otherwise name a territory or approver that exists in
  /// a DIFFERENT organization — the FK is satisfied, the row is written, and
  /// the scope boundary this whole class enforces on every read is silently
  /// absent on write. A nonexistent id and a foreign id are reported
  /// identically here (both "not found in this organization"), which also
  /// closes the second half of the bug this method exists for: without this
  /// check, a nonexistent id doesn't even reach a clean validation error —
  /// it reaches the `INSERT`/`UPDATE` and fails there as a raw FK
  /// `PgException`, surfacing as 500.
  Future<List<FieldError>> _crossOrgErrors(
    CampaignDraftInput input, {
    required String organizationId,
  }) async {
    final errors = <FieldError>[];

    if (input.territoryIds.isNotEmpty) {
      final params = <String, Object?>{'org': organizationId};
      final placeholders = <String>[];
      for (var i = 0; i < input.territoryIds.length; i++) {
        final key = 'terr$i';
        placeholders.add('@$key');
        params[key] = input.territoryIds[i];
      }
      final res = await _db.execute(
        'SELECT id FROM territories '
        'WHERE organization_id = @org AND id IN (${placeholders.join(', ')})',
        params: params,
      );
      final found = {for (final r in res) row(r)['id']! as String};
      final missing = [
        for (final t in input.territoryIds)
          if (!found.contains(t)) t,
      ];
      if (missing.isNotEmpty) {
        errors.add(
          FieldError(
            'territoryIds',
            'Unknown territory id(s), or not in this organization: '
                '${missing.join(', ')}.',
          ),
        );
      }
    }

    final approverId = input.approverId;
    if (approverId != null && approverId.trim().isNotEmpty) {
      final res = await _db.execute(
        'SELECT id FROM staff_users '
        'WHERE id = @id AND organization_id = @org AND is_active',
        params: {'id': approverId, 'org': organizationId},
      );
      if (res.isEmpty) {
        errors.add(
          FieldError(
            'approverId',
            'Unknown approver, or approver is not an active user in this '
                'organization.',
          ),
        );
      }
    }

    return errors;
  }

  /// Re-reads [id] after a committed write. `null` here would mean the row
  /// this method's own transaction just wrote to has vanished before the
  /// transaction's own connection could read it back — not a business
  /// outcome any caller should have to handle, so it is a bug, not an
  /// [ApiException].
  Future<CampaignRow> _requireFreshRow(
    String id, {
    required String organizationId,
    required String verb,
  }) async {
    final campaign = await findById(id, organizationId: organizationId);
    if (campaign == null) {
      throw StateError(
        'campaign $id vanished immediately after its own $verb.',
      );
    }
    return campaign;
  }

  /// Deletes and reinserts every `campaign_territories` row for [campaignId]
  /// — simpler and just as correct as a diff, at this slice's scale (a
  /// handful of territories per campaign).
  Future<void> _replaceTerritoriesTx(
    TxSession tx,
    String campaignId,
    List<String> territoryIds,
  ) async {
    await tx.execute(
      Sql.named('DELETE FROM campaign_territories WHERE campaign_id = @id'),
      parameters: {'id': campaignId},
    );
    for (final territoryId in territoryIds) {
      await tx.execute(
        Sql.named(
          'INSERT INTO campaign_territories (campaign_id, territory_id) '
          'VALUES (@campaign, @territory)',
        ),
        parameters: {'campaign': campaignId, 'territory': territoryId},
      );
    }
  }

  /// Deletes and reinserts every `campaign_sessions` row for [campaignId].
  /// Sessions have no independent identity the wizard exposes across saves
  /// (Task 7's [SessionInput] carries no id), so a diff would have nothing
  /// to key on anyway — replace-in-place is not a simplification, it is the
  /// only option the model supports.
  Future<void> _replaceSessionsTx(
    TxSession tx,
    String campaignId,
    List<SessionInput> sessions,
  ) async {
    await tx.execute(
      Sql.named('DELETE FROM campaign_sessions WHERE campaign_id = @id'),
      parameters: {'id': campaignId},
    );
    for (final session in sessions) {
      await tx.execute(
        Sql.named(
          'INSERT INTO campaign_sessions '
          '(id, campaign_id, venue, capacity, start_at, end_at) '
          'VALUES (@id, @campaign, @venue, @capacity, @startAt, @endAt)',
        ),
        parameters: {
          'id': _uuid.v4(),
          'campaign': campaignId,
          'venue': session.venue,
          'capacity': session.capacity,
          'startAt': session.startAt,
          'endAt': session.endAt,
        },
      );
    }
  }

  Future<List<SessionInput>> _loadSessions(String campaignId) async {
    final res = await _db.execute(
      'SELECT venue, capacity, start_at, end_at FROM campaign_sessions '
      'WHERE campaign_id = @id ORDER BY start_at',
      params: {'id': campaignId},
    );
    return [
      for (final r in res)
        SessionInput(
          venue: row(r)['venue'] as String?,
          capacity: row(r)['capacity'] as int?,
          startAt: (row(r)['start_at'] as DateTime?)?.toUtc(),
          endAt: (row(r)['end_at'] as DateTime?)?.toUtc(),
        ),
    ];
  }

  /// `geofence_enabled` on its own tiny query rather than widening
  /// [CampaignRow]: Task 8 already carries [CampaignRow.budgetReference] and
  /// [CampaignRow.approverId] specifically so this task would not need to
  /// widen that shape further (see the class-level write-only-fields note on
  /// [CampaignRow]), and [validateForSubmit] never inspects geofencing —
  /// only the snapshot needs the real value, so only the snapshot path pays
  /// for reading it.
  ///
  /// Scoped by [organizationId] like every other query in this class (D7) —
  /// [id] alone is enough to find the right row (it's a primary key), but
  /// this class's own invariant is that scope is enforced in every `WHERE`
  /// clause, not left to the fact that the caller happens to already hold a
  /// same-org id.
  Future<bool> _loadGeofenceEnabled(
    String id, {
    required String organizationId,
  }) async {
    final res = await _db.execute(
      'SELECT geofence_enabled FROM campaigns '
      'WHERE id = @id AND organization_id = @org',
      params: {'id': id, 'org': organizationId},
    );
    if (res.isEmpty) return false;
    return row(res.single)['geofence_enabled']! as bool;
  }

  Future<String?> _latestSubmissionId(String campaignId) async {
    final res = await _db.execute(
      'SELECT id FROM campaign_submissions WHERE campaign_id = @id '
      'ORDER BY submitted_at DESC LIMIT 1',
      params: {'id': campaignId},
    );
    if (res.isEmpty) return null;
    return row(res.single)['id']! as String;
  }

  /// Reconstructs the draft shape [validateForSubmit] expects from what is
  /// actually stored for [current] right now — submit takes no body, so
  /// this (not a client-supplied payload) is what gets revalidated.
  Future<CampaignDraftInput> _draftInputFor(CampaignRow current) async {
    final sessions = await _loadSessions(current.id);
    final geofenceEnabled = await _loadGeofenceEnabled(
      current.id,
      organizationId: current.organizationId,
    );
    return CampaignDraftInput(
      name: current.name,
      type: current.type,
      objective: current.objective,
      territoryIds: current.territoryIds,
      target: current.targetAudience,
      budgetReference: current.budgetReference,
      approverId: current.approverId,
      ownerId: current.ownerId,
      geofenceEnabled: geofenceEnabled,
      sessions: sessions,
    );
  }

  /// The immutable, diffable shape stored in `campaign_submissions.snapshot`.
  /// A `Map` value, not a JSON string: with no explicit parameter type, the
  /// driver's default text-encoding fallback
  /// (`type_registry.dart:343`'s `_defaultTextEncoder`, delegating to
  /// `text_codec.dart`'s `PostgresTextEncoder.tryConvert`) special-cases a
  /// `Map` value at line 42 (`_encodeJSON`) and encodes it as JSON text —
  /// exactly what a jsonb column expects — and decodes it back to a `Map` on
  /// read. See `AuditWriter`'s `payload` column, which already relies on the
  /// same behaviour. Encoding it again here first would double-encode it.
  /// Contrast `decide`'s `acknowledged_warnings` insert below: the SAME
  /// fallback's `List` case (`text_codec.dart:54`, `_encodeList`) produces a
  /// Postgres ARRAY literal, not JSON — a `List` parameter needs the
  /// `jsonEncode` + `::jsonb` workaround a `Map` parameter does not.
  Map<String, Object?> _snapshotOf(CampaignDraftInput input) => {
    'name': input.name,
    'type': input.type,
    'objective': input.objective,
    'territoryIds': input.territoryIds,
    'target': input.target,
    'budgetReference': input.budgetReference,
    'approverId': input.approverId,
    'ownerId': input.ownerId,
    'geofenceEnabled': input.geofenceEnabled,
    'sessions': [
      for (final s in input.sessions)
        {
          'venue': s.venue,
          'capacity': s.capacity,
          'startAt': s.startAt?.toIso8601String(),
          'endAt': s.endAt?.toIso8601String(),
        },
    ],
  };

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

/// The critical warnings a reviewer must acknowledge before approving.
///
/// Derived at decision time from columns that already exist — never a
/// separate warnings table, which this slice deliberately does not add. The
/// one rule implemented: if [targetAudience] exceeds the combined `capacity`
/// of every session ([sessions] with a null capacity contributes nothing),
/// attendance cannot possibly reach the target as scheduled, and an approver
/// should have to say so explicitly rather than wave it through. A campaign
/// with no capacity figures at all (every session's capacity is null, or
/// there are no sessions) raises nothing here — there is no capacity claim
/// to contradict the target, so there is nothing to warn about.
List<String> deriveCriticalWarnings({
  required int targetAudience,
  required List<SessionInput> sessions,
}) {
  final totalCapacity = sessions.fold<int>(
    0,
    (sum, s) => sum + (s.capacity ?? 0),
  );
  if (totalCapacity > 0 && targetAudience > totalCapacity) {
    return const ['TARGET_EXCEEDS_SESSION_CAPACITY'];
  }
  return const [];
}
