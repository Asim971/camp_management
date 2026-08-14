import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../db/pool.dart';
import '../infra/audit.dart';
import '../media/signed_url.dart';

const Uuid _uuid = Uuid();

/// The outcome of [VerificationRepo.decide]. [finalStatus] is set only for
/// [VerificationDecisionCode.applied] — `'APPROVED'`/`'REJECTED'`/
/// `'RETURNED'`/`'CRM_REVIEW'` — so the route can answer
/// `{'status': finalStatus}` without a second [VerificationRepo.loadCase]
/// call (which would write a second, spurious audit-on-view row for the same
/// request).
enum VerificationDecisionCode {
  applied,
  notFound,
  versionConflict,
  reasonRequired,
  unsupportedOutcome,
}

class VerificationDecisionResult {
  const VerificationDecisionResult(this.code, {this.finalStatus});

  final VerificationDecisionCode code;
  final String? finalStatus;
}

/// CRM verification queue, case view, and approve/reject decision
/// (sub-project 5a). Every query is org-scoped through
/// `attendance.organization_id` — never through a join alone — so a
/// cross-org attendance id is indistinguishable from a nonexistent one
/// (same 404-hides-existence rationale as [CampaignRepo]).
class VerificationRepo {
  VerificationRepo(this._db, {required String signingKey})
    : _audit = AuditWriter(_db),
      // The param stays public (`signingKey`) while the field is private —
      // see the same pattern (and rationale) in AttendanceRepo's
      // constructor.
      // ignore: prefer_initializing_formals
      _signingKey = signingKey;

  final Db _db;
  final AuditWriter _audit;
  final String _signingKey;

  /// The CRM_REVIEW worklist for [organizationId]: escalated cases first,
  /// then worst band (`NO_REFERENCE` > `LOW` > `MEDIUM` > `HIGH`), then
  /// oldest-captured first within a band. [filter] narrows the WHERE
  /// (`mine`/`unassigned`/`escalated`); [callerUserId] is bound as `@caller`
  /// only for the `mine` clause — the postgres driver rejects a bound
  /// parameter the query text never references, so it is added to the params
  /// map conditionally rather than unconditionally as originally sketched.
  Future<List<Map<String, Object?>>> queue({
    required String organizationId,
    required QueueFilter filter,
    required String callerUserId,
  }) async {
    final filterClause = switch (filter) {
      QueueFilter.all => '',
      QueueFilter.mine => 'AND a.assignee_id = @caller ',
      QueueFilter.unassigned => 'AND a.assignee_id IS NULL ',
      QueueFilter.escalated => 'AND a.escalated_at IS NOT NULL ',
    };
    final res = await _db.execute(
      'SELECT a.id, a.machine_band, a.machine_reference_src, a.assignee_id, '
      '       a.captured_at, a.escalated_at, cr.full_name AS carpenter_name, '
      '       c.name AS campaign_name '
      'FROM attendance a '
      'JOIN campaigns c ON c.id = a.campaign_id '
      'JOIN carpenters cr ON cr.id = a.carpenter_id '
      "WHERE a.organization_id = @org AND a.status = 'CRM_REVIEW' "
      '$filterClause'
      'ORDER BY (a.escalated_at IS NOT NULL) DESC, '
      '         CASE a.machine_band '
      "           WHEN 'NO_REFERENCE' THEN 0 WHEN 'LOW' THEN 1 "
      "           WHEN 'MEDIUM' THEN 2 ELSE 3 END, "
      '         a.captured_at',
      params: {
        'org': organizationId,
        if (filter == QueueFilter.mine) 'caller': callerUserId,
      },
    );
    final now = DateTime.now().toUtc();
    return [for (final r in res) _queueItemWire(row(r), now)];
  }

  Map<String, Object?> _queueItemWire(Map<String, Object?> r, DateTime now) {
    final capturedAt = (r['captured_at']! as DateTime).toUtc();
    return {
      'attendanceId': r['id'],
      'carpenterName': r['carpenter_name'],
      'campaignName': r['campaign_name'],
      'ageSeconds': now.difference(capturedAt).inSeconds,
      'band': r['machine_band'],
      'referenceSource': r['machine_reference_src'],
      'assigneeId': r['assignee_id'],
      'escalatedAt': (r['escalated_at'] as DateTime?)
          ?.toUtc()
          .toIso8601String(),
    };
  }

  /// A single case's full detail, including a freshly minted signed evidence
  /// URL and the reference thumbnail (if any). Returns `null` when
  /// [attendanceId] does not exist in [organizationId] — the route turns
  /// that into a 404 that reveals nothing about a cross-org id.
  ///
  /// WRITES an audit-on-view row (`verification.case_viewed`) as a side
  /// effect of a successful load — every call that returns non-null audits
  /// exactly once.
  Future<Map<String, Object?>?> loadCase({
    required String attendanceId,
    required String organizationId,
    required String viewerId,
    required String baseUrl,
    String? correlationId,
  }) async {
    final res = await _db.execute(
      'SELECT a.version, a.status, a.media_ref, a.captured_at, '
      '       a.machine_band, '
      '       a.machine_reference_src, a.machine_reasons, cr.full_name, '
      '       cr.display_code, cr.thumbnail_url, c.name AS campaign_name, '
      '       s.venue AS session_name '
      'FROM attendance a '
      'JOIN carpenters cr ON cr.id = a.carpenter_id '
      'JOIN campaigns c ON c.id = a.campaign_id '
      'JOIN campaign_sessions s ON s.id = a.session_id '
      'WHERE a.id = @id AND a.organization_id = @org',
      params: {'id': attendanceId, 'org': organizationId},
    );
    if (res.isEmpty) return null;
    final r = row(res.single);

    final capturedImageUrl = await signReadUrl(
      baseUrl: baseUrl,
      id: r['media_ref']! as String,
      signingKey: _signingKey,
      now: DateTime.now(),
    );

    // Audit-on-view: every successful load of a case is itself an access to
    // sensitive evidence and NID-adjacent data, and must be traceable
    // whether or not the viewer goes on to decide it.
    await _audit.write(
      action: 'verification.case_viewed',
      resourceType: 'attendance',
      resourceId: attendanceId,
      actorId: viewerId,
      correlationId: correlationId,
    );

    return {
      'attendanceId': attendanceId,
      'version': r['version'],
      'status': r['status'],
      'carpenterName': r['full_name'],
      'carpenterIdMasked': r['display_code'],
      'campaignName': r['campaign_name'],
      'sessionName': r['session_name'],
      'capturedAt': (r['captured_at']! as DateTime).toUtc().toIso8601String(),
      'capturedImageUrl': capturedImageUrl,
      'referenceImageUrl': r['thumbnail_url'],
      'band': r['machine_band'],
      'referenceSource': r['machine_reference_src'],
      'padReview': false,
      'lowQuality': false,
      'reasons': _decodeReasons(r['machine_reasons']),
    };
  }

  /// `machine_reasons` is JSONB; depending on the driver it arrives already
  /// decoded (a `List`) or still as its raw text (a `String`) — handled
  /// defensively either way.
  List<Object?> _decodeReasons(Object? raw) {
    if (raw is String) return (jsonDecode(raw) as List).cast<Object?>();
    if (raw is List) return raw.cast<Object?>();
    return const [];
  }

  /// Decide [attendanceId] with optimistic-concurrency control: the caller
  /// must present the version it last saw ([ifMatchVersion]); a stale value
  /// yields [VerificationDecisionCode.versionConflict] (412) rather than
  /// silently clobbering a decision made in the meantime.
  ///
  /// Supports `approved` (-> `APPROVED`), `rejected` (-> `REJECTED`),
  /// `returnForRecapture` (-> `RETURNED`), and `escalated` (stays
  /// `CRM_REVIEW`, stamps `escalated_at`/`escalated_by` so a supervisor can
  /// pick it up). Any unrecognised outcome yields
  /// [VerificationDecisionCode.unsupportedOutcome] (422). Rejecting,
  /// returning for recapture, escalating, or overriding without a non-blank
  /// [reason] yields [VerificationDecisionCode.reasonRequired] (422).
  ///
  /// [supervisorOverride] is the caller's authority to re-decide a case that
  /// is no longer open (`status <> 'CRM_REVIEW'`): it drops the CAS's
  /// `status = 'CRM_REVIEW'` guard while keeping the `version = @ifMatch`
  /// guard, so a stale If-Match still 412s. The route enforces the
  /// `verification_override` permission before calling this — this method
  /// trusts the flag it is given.
  Future<VerificationDecisionResult> decide({
    required String attendanceId,
    required String organizationId,
    required String verifierId,
    required String outcomeWire,
    required String? reason,
    required bool supervisorOverride,
    required int ifMatchVersion,
    String? correlationId,
  }) async {
    // Existence + outcome validation happen BEFORE the transaction: a
    // malformed request should never even open one.
    final existing = await _db.execute(
      'SELECT 1 FROM attendance WHERE id = @id AND organization_id = @org',
      params: {'id': attendanceId, 'org': organizationId},
    );
    if (existing.isEmpty) {
      return const VerificationDecisionResult(
        VerificationDecisionCode.notFound,
      );
    }

    final outcome = VerificationOutcome.tryParseWire(outcomeWire);
    if (outcome == null) {
      return const VerificationDecisionResult(
        VerificationDecisionCode.unsupportedOutcome,
      );
    }

    const statusForOutcome = {
      VerificationOutcome.approved: 'APPROVED',
      VerificationOutcome.rejected: 'REJECTED',
      VerificationOutcome.returnForRecapture: 'RETURNED',
      VerificationOutcome.escalated: 'CRM_REVIEW', // stays open; marker below
    };
    final newStatus = statusForOutcome[outcome]!;

    final reasonRequired =
        supervisorOverride ||
        outcome == VerificationOutcome.rejected ||
        outcome == VerificationOutcome.returnForRecapture ||
        outcome == VerificationOutcome.escalated;
    if (reasonRequired && (reason == null || reason.trim().isEmpty)) {
      return const VerificationDecisionResult(
        VerificationDecisionCode.reasonRequired,
      );
    }

    final escalating = outcome == VerificationOutcome.escalated;

    return _db.tx((tx) async {
      // The CAS: zero affected rows means either the version the caller
      // presented is no longer current, OR the case is no longer open
      // (`status <> 'CRM_REVIEW'` — already decided). Existence was already
      // confirmed above, outside this tx; the re-check below distinguishes
      // those cases from a genuine race where the row vanished entirely
      // between the two. An already-decided case falling into the same
      // `versionConflict` (412 "decided by someone else; reload") branch is
      // deliberate: from the caller's point of view a closed case IS a
      // conflict — reloading it will show the decision that closed it —
      // and it is exactly the right shape to prevent a re-decide of a
      // closed case, without inventing a new outcome/branch for it.
      final whereOpenGuard = supervisorOverride
          ? ''
          : "  AND status = 'CRM_REVIEW' ";
      final casResult = await tx.execute(
        Sql.named(
          'UPDATE attendance SET status = @status, version = version + 1, '
          '  escalated_at = @escAt, escalated_by = @escBy '
          'WHERE id = @id AND version = @ifMatch AND organization_id = @org '
          '$whereOpenGuard'
          'RETURNING version',
        ),
        parameters: {
          'status': newStatus,
          'escAt': escalating ? DateTime.now().toUtc() : null,
          'escBy': escalating ? verifierId : null,
          'id': attendanceId,
          'ifMatch': ifMatchVersion,
          'org': organizationId,
        },
      );
      if (casResult.affectedRows == 0) {
        final recheck = await tx.execute(
          Sql.named(
            'SELECT 1 FROM attendance WHERE id = @id AND organization_id = @org',
          ),
          parameters: {'id': attendanceId, 'org': organizationId},
        );
        return VerificationDecisionResult(
          recheck.isEmpty
              ? VerificationDecisionCode.notFound
              : VerificationDecisionCode.versionConflict,
        );
      }

      await tx.execute(
        Sql.named(
          'INSERT INTO verification_decisions '
          '(id, attendance_id, verifier_id, outcome, reason, '
          ' supervisor_override, version_at_decision, correlation_id) '
          'VALUES (@id, @att, @verifier, @outcome, @reason, @override, '
          '        @versionAtDecision, @correlation)',
        ),
        parameters: {
          'id': _uuid.v4(),
          'att': attendanceId,
          'verifier': verifierId,
          'outcome': outcome.wireValue,
          'reason': reason,
          'override': supervisorOverride,
          'versionAtDecision': ifMatchVersion,
          'correlation': correlationId,
        },
      );
      await _audit.writeTx(
        tx,
        action: 'verification.decided',
        resourceType: 'attendance',
        resourceId: attendanceId,
        actorId: verifierId,
        correlationId: correlationId,
        payload: {
          'outcome': outcome.wireValue,
          'status': newStatus,
          'reason': reason,
        },
      );

      return VerificationDecisionResult(
        VerificationDecisionCode.applied,
        finalStatus: newStatus,
      );
    });
  }
}
