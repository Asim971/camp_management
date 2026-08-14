import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:postgres/postgres.dart';

import '../db/pool.dart';
import '../infra/audit.dart';
import 'session_machine.dart';

/// A session as the API presents it. Activity counts are 0 in 3a (3a.D6): the
/// real per-session numbers are produced by attendance (sub-project 4).
class SessionView {
  const SessionView({
    required this.id,
    required this.campaignId,
    required this.venue,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.capacity,
    required this.readinessOk,
  });

  final String id;
  final String campaignId;
  final String venue; // '' when the DB venue is null; never null on the wire
  final SessionStatus status;
  final DateTime? startAt;
  final DateTime? endAt;
  final int capacity;
  final bool readinessOk;

  Map<String, Object?> toWireJson() => {
    'id': id,
    'campaignId': campaignId,
    'venue': venue,
    'status': status.wireValue,
    'startAt': startAt?.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
    'capacity': capacity,
    'registeredCount': 0,
    'pendingSyncCount': 0,
    'reviewCount': 0,
    'approvedCount': 0,
    'readinessOk': readinessOk,
  };
}

enum SessionOutcome {
  applied,
  idempotentNoop,
  invalidTransition,
  notReady,
  notFound,
}

class SessionApplyResult {
  const SessionApplyResult(this.outcome, {this.view, this.currentStatus});
  final SessionOutcome outcome;
  final SessionView? view; // set for applied and idempotentNoop
  final SessionStatus? currentStatus; // set for invalidTransition (for message)
}

/// Owns all session SQL. Every read and write is org-scoped through the
/// campaigns join (D7: a cross-org session is indistinguishable from missing).
class SessionRepo {
  SessionRepo(this._db) : _audit = AuditWriter(_db);

  final Db _db;
  final AuditWriter _audit;

  static const _selectCols =
      's.id, s.campaign_id, s.venue, s.status, s.start_at, s.end_at, '
      's.capacity, c.status AS campaign_status';

  // Plain (unaliased) campaign_sessions columns, for the CAS UPDATE's
  // RETURNING clause: that statement has no `campaigns` join in scope (the
  // org check is a WHERE-clause subquery, not a FROM/JOIN), so it cannot
  // return `c.status` the way the SELECT queries above do. The campaign's
  // status does not change as part of this operation, so the row returned
  // here is completed with the already-loaded `campaign_status` instead.
  static const _sessionCols =
      'id, campaign_id, venue, status, start_at, end_at, capacity';

  SessionView _view(Map<String, Object?> r) {
    final campaignStatus =
        CampaignStatus.tryParseWire(r['campaign_status']! as String) ??
        CampaignStatus.draft;
    final status =
        SessionStatus.tryParseWire(r['status']! as String) ??
        SessionStatus
            .captureClosed; // unknown => non-operational, never a default
    final venue = (r['venue'] as String?) ?? '';
    final startAt = r['start_at'] as DateTime?;
    return SessionView(
      id: r['id']! as String,
      campaignId: r['campaign_id']! as String,
      venue: venue,
      status: status,
      startAt: startAt,
      endAt: r['end_at'] as DateTime?,
      capacity: (r['capacity'] as int?) ?? 0,
      readinessOk: isReady(
        campaignStatus: campaignStatus,
        venue: venue,
        startAt: startAt,
      ),
    );
  }

  /// Sessions for a campaign, or null if the campaign is not in [organizationId]
  /// (the route turns null into 404). An in-org campaign with no sessions
  /// returns an empty list.
  Future<List<SessionView>?> listForCampaign(
    String campaignId, {
    required String organizationId,
  }) async {
    final campaign = await _db.execute(
      'SELECT 1 FROM campaigns WHERE id = @id AND organization_id = @org',
      params: {'id': campaignId, 'org': organizationId},
    );
    if (campaign.isEmpty) return null;

    final res = await _db.execute(
      'SELECT $_selectCols FROM campaign_sessions s '
      'JOIN campaigns c ON c.id = s.campaign_id '
      'WHERE s.campaign_id = @id AND c.organization_id = @org '
      'ORDER BY s.start_at NULLS LAST, s.id',
      params: {'id': campaignId, 'org': organizationId},
    );
    return [for (final r in res) _view(row(r))];
  }

  Future<Map<String, Object?>?> _load(
    String sessionId,
    String organizationId,
  ) async {
    final res = await _db.execute(
      'SELECT $_selectCols FROM campaign_sessions s '
      'JOIN campaigns c ON c.id = s.campaign_id '
      'WHERE s.id = @id AND c.organization_id = @org',
      params: {'id': sessionId, 'org': organizationId},
    );
    return res.isEmpty ? null : row(res.single);
  }

  /// Applies [action] to a session with a single atomic compare-and-swap on
  /// status (§6a / 3a.D7). The `status IN (@from0, @from1)` guard makes the
  /// legality check and the write one step: two concurrent starts cannot both
  /// win; the loser matches zero rows and is re-read as an idempotent no-op or
  /// an invalid transition.
  Future<SessionApplyResult> apply(
    SessionAction action, {
    required String sessionId,
    required String organizationId,
    required String actorId,
    String? correlationId,
  }) async {
    final loaded = await _load(sessionId, organizationId);
    if (loaded == null) {
      return const SessionApplyResult(SessionOutcome.notFound);
    }
    final current =
        SessionStatus.tryParseWire(loaded['status']! as String) ??
        SessionStatus.captureClosed;
    final target = targetOf(action);

    // Not a legal source state: already-there is an idempotent no-op, anything
    // else is a conflict — decided before touching the row.
    if (!allowedFrom(action).contains(current)) {
      if (current == target) {
        return SessionApplyResult(
          SessionOutcome.idempotentNoop,
          view: _view(loaded),
        );
      }
      return SessionApplyResult(
        SessionOutcome.invalidTransition,
        currentStatus: current,
      );
    }

    // Legal source state: `start` additionally requires readiness.
    if (action == SessionAction.start && !_view(loaded).readinessOk) {
      return const SessionApplyResult(SessionOutcome.notReady);
    }

    final froms = allowedFrom(action).map((s) => s.wireValue).toList();
    final from0 = froms.first;
    final from1 = froms.length > 1 ? froms[1] : froms.first;

    // Atomic CAS + audit in one transaction, so an operation and its audit
    // trail commit together (the same posture as the import commit). Every
    // statement runs on `tx`, never `_db` — `Db.tx` throws if the underlying
    // connection is asked to execute outside the transaction while one is
    // open, and `AuditWriter.write` does exactly that; `writeTx` runs on the
    // open `TxSession` instead.
    final updated = await _db.tx((tx) async {
      final res = await tx.execute(
        Sql.named(
          'UPDATE campaign_sessions '
          'SET status = @to '
          'WHERE id = @id '
          '  AND status IN (@from0, @from1) '
          '  AND campaign_id IN '
          '      (SELECT id FROM campaigns WHERE organization_id = @org) '
          'RETURNING $_sessionCols',
        ),
        parameters: {
          'to': target.wireValue,
          'id': sessionId,
          'from0': from0,
          'from1': from1,
          'org': organizationId,
        },
      );
      if (res.isEmpty) return null; // raced: someone else moved it first
      await _audit.writeTx(
        tx,
        action: _auditAction(action),
        resourceType: 'campaign_session',
        resourceId: sessionId,
        actorId: actorId,
        correlationId: correlationId,
        payload: {'to': target.wireValue},
      );
      // The campaign's status cannot change as part of this operation, so
      // the pre-transaction read of it is still accurate here.
      return {...row(res.single), 'campaign_status': loaded['campaign_status']};
    });

    if (updated != null) {
      return SessionApplyResult(SessionOutcome.applied, view: _view(updated));
    }

    // Lost the race: re-read to report the same no-op / conflict a slower
    // caller would have seen.
    final after = await _load(sessionId, organizationId);
    if (after == null) {
      return const SessionApplyResult(SessionOutcome.notFound);
    }
    final now =
        SessionStatus.tryParseWire(after['status']! as String) ??
        SessionStatus.captureClosed;
    if (now == target) {
      return SessionApplyResult(
        SessionOutcome.idempotentNoop,
        view: _view(after),
      );
    }
    return SessionApplyResult(
      SessionOutcome.invalidTransition,
      currentStatus: now,
    );
  }

  String _auditAction(SessionAction action) => switch (action) {
    SessionAction.start => 'session.started',
    SessionAction.pause => 'session.paused',
    SessionAction.close => 'session.capture_closed',
  };

  /// Dormant in 3a (3a.D3): flips every non-terminal session of [campaignId] to
  /// COMPLETED. The campaign-activation slice that drives campaign completion
  /// will call this; there is no endpoint for it here.
  Future<void> completeSessionsForCampaign(String campaignId) async {
    await _db.execute(
      "UPDATE campaign_sessions SET status = 'COMPLETED' "
      "WHERE campaign_id = @id "
      "  AND status NOT IN ('CAPTURE_CLOSED', 'COMPLETED')",
      params: {'id': campaignId},
    );
  }
}
