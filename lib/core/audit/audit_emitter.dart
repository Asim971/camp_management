import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../result/result.dart';
import '../storage/app_database.dart';
import '../sync/backoff.dart';
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

/// Retry schedule for the audit buffer.
///
/// `maxRetries` is unused - the flusher has no give-up path - so the effective
/// behaviour is exponential growth to a five-minute plateau, retried forever.
const BackoffPolicy auditFlushPolicy = BackoffPolicy(
  base: Duration(seconds: 2),
  maxDelay: Duration(minutes: 5),
);

/// Drains the durable audit buffer to the server.
///
/// Deliberately NOT built on [SyncEngine]: that discards a task after
/// `maxRetries: 8` and surfaces a user-visible failure, which for a compliance
/// record would be silent data loss. This shares the *policy* object, not the
/// queue.
class AuditFlusher {
  AuditFlusher({
    required this._db,
    required this._transport,
    this._connectivity,
    this._policy = auditFlushPolicy,
    this._interval = const Duration(seconds: 30),
    this._batchSize = 20,
    this._maxAttempts = 10,
    this._highWaterMark = 20000,
  });

  final AppDatabase _db;
  final AuditTransport _transport;
  final Stream<bool>? _connectivity;
  final BackoffPolicy _policy;
  final Duration _interval;
  final int _batchSize;

  /// Attempts after which a row is set aside. It is skipped, never deleted: a
  /// permanently rejected event would otherwise stall every later event, since
  /// the queue is strictly FIFO by `seq`.
  final int _maxAttempts;

  final int _highWaterMark;

  Timer? _timer;
  StreamSubscription<bool>? _connectivitySub;
  Future<void>? _inFlight;
  int _buffered = 0;
  bool _warnedHighWater = false;
  bool _disposed = false;

  void start() {
    // The configured interval never outlives the policy's plateau: if a
    // caller passes an interval longer than `_policy.maxDelay`, an offline
    // stretch would otherwise wait past the point the backoff schedule
    // itself considers "as slow as this ever gets".
    final effectiveInterval = _interval < _policy.maxDelay
        ? _interval
        : _policy.maxDelay;
    _timer ??= Timer.periodic(effectiveInterval, (_) => unawaited(flush()));
    _connectivitySub ??= _connectivity?.listen((online) {
      if (online) unawaited(flush());
    });
  }

  /// Called by [DurableAuditSink] after each durable write. Flushes early once
  /// a full batch has accumulated rather than waiting for the timer.
  void notifyBuffered() {
    _buffered++;
    if (_buffered >= _batchSize) {
      _buffered = 0;
      unawaited(flush());
    }
  }

  /// Sends one batch. Concurrent calls share the in-flight future so two
  /// triggers cannot double-send the same rows.
  Future<void> flush() {
    if (_disposed) return Future<void>.value();
    return _inFlight ??= _flushOnce().whenComplete(() => _inFlight = null);
  }

  Future<void> _flushOnce() async {
    final rows =
        await (_db.select(_db.auditEvents)
              ..where((t) => t.attempts.isSmallerThanValue(_maxAttempts))
              ..orderBy([(t) => OrderingTerm(expression: t.seq)])
              ..limit(_batchSize))
            .get();
    if (rows.isEmpty) return;

    final result = await _transport.send(rows.map(_toPayload).toList());

    if (result case Err(:final failure)) {
      await _db.batch((b) {
        for (final row in rows) {
          b.update(
            _db.auditEvents,
            AuditEventsCompanion(
              attempts: Value(row.attempts + 1),
              lastError: Value(failure.message ?? failure.kind.name),
            ),
            where: (t) => t.seq.equals(row.seq),
          );
        }
      });
      await _checkHighWaterMark();
      return;
    }

    await _db.batch((b) {
      b.deleteWhere(
        _db.auditEvents,
        (t) => t.seq.isIn(rows.map((r) => r.seq).toList()),
      );
    });
  }

  /// Nothing is ever dropped, so an indefinitely offline device grows this
  /// table. Rows are ~200 bytes, so weeks offline costs single-digit MB; past
  /// the mark that stops being negligible and is worth a signal.
  Future<void> _checkHighWaterMark() async {
    if (_warnedHighWater) return;
    // selectOnly + a count expression rather than loading rows: at the mark
    // this table holds 20k rows and `select(...).get().length` would read them
    // all into memory just to size them.
    final total = _db.auditEvents.seq.count();
    final row = await (_db.selectOnly(
      _db.auditEvents,
    )..addColumns([total])).getSingle();
    final count = row.read(total) ?? 0;
    if (count < _highWaterMark) return;
    _warnedHighWater = true;
    debugPrint(
      'Audit buffer holds $count events (>= $_highWaterMark) and cannot reach '
      'the server. Events are retained, not dropped.',
    );
  }

  /// The action string passes through verbatim - never round-tripped through
  /// [AuditAction]. A row written by a build with actions this one lacks (an
  /// Android downgrade) must reach the server labelled with what actually
  /// happened, not with whatever enum value happened to be the fallback.
  AuditEventPayload _toPayload(AuditEventRow row) => AuditEventPayload(
    action: row.action,
    entity: row.entity,
    entityId: row.entityId,
    correlationId: row.correlationId,
    actorId: row.actorId,
    remarks: row.remarks,
  );

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _inFlight;
  }
}
