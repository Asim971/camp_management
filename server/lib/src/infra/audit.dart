import 'package:postgres/postgres.dart' show Sql, TxSession;
import 'package:uuid/uuid.dart';

import '../db/pool.dart';

const Uuid _uuid = Uuid();

const String _insertSql =
    'INSERT INTO audit_events '
    '(id, actor_id, action, resource_type, resource_id, correlation_id, '
    ' payload) '
    'VALUES (@id, @actor, @action, @resourceType, @resourceId, '
    '        @correlationId, @payload)';

/// Writes to `audit_events`. One insert per call — no batching, no queue —
/// because an audit trail that can silently lose an event under load
/// defeats its own purpose.
class AuditWriter {
  AuditWriter(this._db);

  final Db _db;

  /// [actorId] is nullable on purpose: a failed login has no actor yet, and
  /// that attempt is exactly the kind of event worth auditing.
  Future<void> write({
    required String action,
    required String resourceType,
    String? resourceId,
    String? actorId,
    String? correlationId,
    Map<String, Object?> payload = const {},
  }) => _db.execute(
    _insertSql,
    params: _paramsFor(
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      actorId: actorId,
      correlationId: correlationId,
      payload: payload,
    ),
  );

  /// Same insert, run through an already-open [TxSession] instead of [_db].
  ///
  /// Task 9's writes (submit/decide) insert the audit event in the SAME
  /// transaction as the status-changing `UPDATE` and the snapshot/decision
  /// row: [Db.tx]'s doc is explicit that calling [Db.execute] while a
  /// transaction is active throws, so an audit write that belongs inside
  /// that transaction has no choice but to go through the [TxSession] it was
  /// given — the same split [TokenService] already uses for
  /// `_mintRefreshToken`/`_mintRefreshTokenTx` (`auth/tokens.dart`).
  Future<void> writeTx(
    TxSession tx, {
    required String action,
    required String resourceType,
    String? resourceId,
    String? actorId,
    String? correlationId,
    Map<String, Object?> payload = const {},
  }) => tx.execute(
    Sql.named(_insertSql),
    parameters: _paramsFor(
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      actorId: actorId,
      correlationId: correlationId,
      payload: payload,
    ),
  );

  Map<String, Object?> _paramsFor({
    required String action,
    required String resourceType,
    String? resourceId,
    String? actorId,
    String? correlationId,
    Map<String, Object?> payload = const {},
  }) => {
    'id': _uuid.v4(),
    'actor': actorId,
    'action': action,
    'resourceType': resourceType,
    'resourceId': resourceId,
    'correlationId': correlationId,
    'payload': payload,
  };
}
