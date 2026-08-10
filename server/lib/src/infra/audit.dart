import 'package:uuid/uuid.dart';

import '../db/pool.dart';

const Uuid _uuid = Uuid();

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
  }) async {
    await _db.execute(
      'INSERT INTO audit_events '
      '(id, actor_id, action, resource_type, resource_id, correlation_id, '
      ' payload) '
      'VALUES (@id, @actor, @action, @resourceType, @resourceId, '
      '        @correlationId, @payload)',
      params: {
        'id': _uuid.v4(),
        'actor': actorId,
        'action': action,
        'resourceType': resourceType,
        'resourceId': resourceId,
        'correlationId': correlationId,
        'payload': payload,
      },
    );
  }
}
