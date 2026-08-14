import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import '../db/pool.dart';
import '../infra/audit.dart';
import '../infra/error_envelope.dart';

enum AttendanceConfirmOutcome {
  confirmed,
  sessionNotFound,
  carpenterNotFound,
  evidenceMissing,
}

class AttendanceConfirmResult {
  const AttendanceConfirmResult(this.outcome, {this.status});
  final AttendanceConfirmOutcome outcome;
  final String? status; // set for confirmed
}

const _uuid = Uuid();

/// The confirm transaction (4a.D4). Derives campaign+org from the session,
/// requires the carpenter and the uploaded evidence, and persists the
/// attendance + consent record + audit atomically. No matching/PAD/geofence
/// here — the record lands in MATCH_PROCESSING (verification is sub-project 5).
class AttendanceRepo {
  AttendanceRepo(this._db) : _audit = AuditWriter(_db);
  final Db _db;
  final AuditWriter _audit;

  Future<AttendanceConfirmResult> confirm({
    required String attendanceId,
    required String organizationId,
    required String capturedBy,
    required Map<String, Object?> payload,
    String? correlationId,
  }) async {
    final sessionId = _requireString(payload, 'sessionId');
    final carpenterId = _requireString(payload, 'carpenterId');

    // Session must be in the actor's org; campaign_id comes from it (D7).
    final sessionRows = await _db.execute(
      'SELECT s.campaign_id FROM campaign_sessions s '
      'JOIN campaigns c ON c.id = s.campaign_id '
      'WHERE s.id = @s AND c.organization_id = @org',
      params: {'s': sessionId, 'org': organizationId},
    );
    if (sessionRows.isEmpty) {
      return const AttendanceConfirmResult(
        AttendanceConfirmOutcome.sessionNotFound,
      );
    }
    final campaignId = row(sessionRows.single)['campaign_id']! as String;

    final carpenterRows = await _db.execute(
      'SELECT 1 FROM carpenters WHERE id = @c AND organization_id = @org',
      params: {'c': carpenterId, 'org': organizationId},
    );
    if (carpenterRows.isEmpty) {
      return const AttendanceConfirmResult(
        AttendanceConfirmOutcome.carpenterNotFound,
      );
    }

    final media = await _db.execute(
      'SELECT 1 FROM media_objects WHERE id = @id',
      params: {'id': attendanceId},
    );
    if (media.isEmpty) {
      return const AttendanceConfirmResult(
        AttendanceConfirmOutcome.evidenceMissing,
      );
    }

    final capturedAt = DateTime.parse(_requireString(payload, 'capturedAt'));
    final consentVersion = _requireNum(payload, 'consentVersion').toInt();
    final consentLanguage = _requireString(payload, 'consentLanguage');
    final consentContentHash = _requireString(payload, 'consentContentHash');
    final consentShownAt = DateTime.parse(
      _requireString(payload, 'consentShownAt'),
    );

    await _db.tx((tx) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO attendance '
          '(id, organization_id, campaign_id, session_id, carpenter_id, '
          ' media_ref, status, captured_by, captured_at) '
          "VALUES (@id, @org, @camp, @s, @c, @id, 'MATCH_PROCESSING', @by, @at)",
        ),
        parameters: {
          'id': attendanceId,
          'org': organizationId,
          'camp': campaignId,
          's': sessionId,
          'c': carpenterId,
          'by': capturedBy,
          'at': capturedAt,
        },
      );
      await tx.execute(
        Sql.named(
          'INSERT INTO consent_records '
          '(id, attendance_id, notice_version, language, content_hash, shown_at) '
          'VALUES (@id, @att, @v, @lang, @hash, @shown)',
        ),
        parameters: {
          'id': _uuid.v4(),
          'att': attendanceId,
          'v': consentVersion,
          'lang': consentLanguage,
          'hash': consentContentHash,
          'shown': consentShownAt,
        },
      );
      await _audit.writeTx(
        tx,
        action: 'attendance.captured',
        resourceType: 'attendance',
        resourceId: attendanceId,
        actorId: capturedBy,
        correlationId: correlationId,
        payload: {'sessionId': sessionId, 'carpenterId': carpenterId},
      );
    });
    return const AttendanceConfirmResult(
      AttendanceConfirmOutcome.confirmed,
      status: 'MATCH_PROCESSING',
    );
  }
}

/// Reads a required string field from the confirm payload, surfacing a
/// missing/mistyped field as a clean 400 rather than a raw cast crash. The
/// client always sends every one of these; this is belt-and-suspenders.
String _requireString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! String || value.isEmpty) {
    throw ApiException(ApiErrorCode.badRequest, message: '$key is required.');
  }
  return value;
}

num _requireNum(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! num) {
    throw ApiException(ApiErrorCode.badRequest, message: '$key is required.');
  }
  return value;
}
