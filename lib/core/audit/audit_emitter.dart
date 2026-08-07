import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../result/result.dart';
import '../storage/app_database.dart';
import 'audit.dart';
import 'audit_transport.dart';

const Uuid _uuid = Uuid();

DateTime _systemNow() => DateTime.now().toUtc();
String _uuidV4() => _uuid.v4();

/// Drift-backed [AuditSink]. Events are committed locally first and shipped by
/// `AuditFlusher`, so they survive process death on the way to the server.
class DurableAuditSink implements AuditSink {
  // `this._field` initializing formals still expose a PUBLIC call-site name
  // (Dart strips the leading underscore for the named-parameter label), so
  // `db:`/`transport:`/`now:`/`newId:` remain the external API.
  DurableAuditSink({
    required this._db,
    required this._transport,
    this._now = _systemNow,
    this._newId = _uuidV4,
    this.onBuffered,
  });

  final AppDatabase _db;
  final AuditTransport _transport;
  final DateTime Function() _now;
  final String Function() _newId;

  /// Called after each durable write so a full batch can flush early rather
  /// than waiting for the periodic timer.
  final void Function()? onBuffered;

  @override
  Future<void> emit(AuditEvent event) async {
    try {
      await _insert(event, _newId());
    } catch (error) {
      // An audit outage must not block a campaign approval or a capture. This
      // is the one place a lost event is tolerated, and only because the
      // alternative is blocking the user's work on a local DB fault.
      debugPrint('Audit event could not be buffered ($error): ${event.action}');
      return;
    }
    onBuffered?.call();
  }

  @override
  Future<Result<T>> revealAudited<T>(
    AuditEvent event,
    Future<T> Function() reveal,
  ) async {
    final id = _newId();

    // Write first: a crash mid-post must still leave evidence that access was
    // attempted.
    try {
      await _insert(event, id);
    } catch (error) {
      return Err(
        Failure(
          FailureKind.unknown,
          message: 'Audit event could not be recorded locally: $error',
          correlationId: event.correlationId.value,
        ),
      );
    }

    final sent = await _transport.send([AuditEventPayload.fromEvent(event)]);
    if (sent case Err(:final failure)) {
      // Fail closed. The row stays pending so the flusher still delivers the
      // attempt, but the value is not shown.
      return Err(failure);
    }

    await (_db.delete(_db.auditEvents)..where((t) => t.id.equals(id))).go();
    return Ok(await reveal());
  }

  Future<void> _insert(AuditEvent event, String id) => _db
      .into(_db.auditEvents)
      .insert(
        AuditEventsCompanion.insert(
          id: id,
          action: event.action.name,
          entity: event.entity,
          entityId: event.entityId,
          correlationId: event.correlationId.value,
          actorId: event.actorId,
          remarks: Value(event.remarks),
          occurredAt: _now(),
        ),
      );
}
