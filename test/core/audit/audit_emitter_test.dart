import 'package:acsl_campaign/core/audit/audit.dart';
import 'package:acsl_campaign/core/audit/audit_emitter.dart';
import 'package:acsl_campaign/core/audit/audit_transport.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Transport whose result is scripted per call, recording what it was asked to
/// send and how many rows existed at that moment.
class _ScriptedTransport implements AuditTransport {
  _ScriptedTransport(this._results, {this.onSend});

  final List<Result<void>> _results;

  /// Async on purpose: the ordering test inspects the DB from here, and a
  /// `void Function()` would let that inspection fire-and-forget, so the
  /// assertion could run before the read completed.
  final Future<void> Function()? onSend;

  final List<List<AuditEventPayload>> batches = [];

  @override
  Future<Result<void>> send(List<AuditEventPayload> events) async {
    batches.add(events);
    await onSend?.call();
    return _results[(batches.length - 1).clamp(0, _results.length - 1)];
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  var counter = 0;
  DurableAuditSink buildSink(
    AuditTransport transport, {
    void Function()? onBuffered,
  }) {
    counter = 0;
    return DurableAuditSink(
      db: db,
      transport: transport,
      now: () => DateTime.utc(2026, 8, 6, 12),
      newId: () => 'id-${++counter}',
      onBuffered: onBuffered,
    );
  }

  AuditEvent event({
    AuditAction action = AuditAction.campaignApproved,
    String entityId = 'CMP-1',
  }) => AuditEvent(
    action: action,
    entity: 'campaign',
    entityId: entityId,
    correlationId: const TraceId.of('trace-1'),
    actorId: 'user-1',
  );

  group('emit', () {
    test(
      'persists the event and returns without contacting the transport',
      () async {
        // emit() must be durable-and-async: it returns on local commit so an
        // audit outage never blocks a campaign approval.
        final transport = _ScriptedTransport([const Ok(null)]);
        final sink = buildSink(transport);

        await sink.emit(event());

        final rows = await db.select(db.auditEvents).get();
        expect(rows, hasLength(1));
        expect(rows.single.id, 'id-1');
        expect(rows.single.action, 'campaignApproved');
        expect(rows.single.actorId, 'user-1');
        expect(rows.single.correlationId, 'trace-1');
        // Drift's default NativeDatabase config stores DateTime as a unix-second
        // integer and reads it back via `DateTime.fromMillisecondsSinceEpoch`
        // with no `isUtc: true`, so the round-tripped value is always
        // local-zoned. Dart's `DateTime.==` requires matching `isUtc` flags in
        // addition to the instant, so comparing directly to a `DateTime.utc(..)`
        // literal would fail on any machine regardless of local timezone.
        // Normalizing with `.toUtc()` verifies the same instant was persisted
        // without depending on Drift's storage representation.
        expect(rows.single.occurredAt.toUtc(), DateTime.utc(2026, 8, 6, 12));
        expect(rows.single.attempts, 0);
        expect(transport.batches, isEmpty);
      },
    );

    test(
      'notifies the buffer callback so a full batch can flush early',
      () async {
        var notifications = 0;
        final sink = buildSink(
          _ScriptedTransport([const Ok(null)]),
          onBuffered: () => notifications++,
        );

        await sink.emit(event());
        await sink.emit(event(entityId: 'CMP-2'));

        expect(notifications, 2);
      },
    );

    test('assigns increasing seq values so flush order is FIFO', () async {
      final sink = buildSink(_ScriptedTransport([const Ok(null)]));

      await sink.emit(event(entityId: 'first'));
      await sink.emit(event(entityId: 'second'));

      final rows = await (db.select(
        db.auditEvents,
      )..orderBy([(t) => OrderingTerm(expression: t.seq)])).get();
      expect(rows.map((r) => r.entityId), ['first', 'second']);
      expect(rows.first.seq, lessThan(rows.last.seq));
    });
  });

  group('revealAudited', () {
    test('writes the row BEFORE calling the transport', () async {
      // Ordering is the whole control: if the transport were called first, a
      // crash mid-post would leave no record that access was attempted.
      var rowsWhenSent = -1;
      final transport = _ScriptedTransport(
        [const Ok(null)],
        onSend: () async {
          rowsWhenSent = (await db.select(db.auditEvents).get()).length;
        },
      );
      final sink = buildSink(transport);

      await sink.revealAudited(
        event(action: AuditAction.sensitiveMediaViewed),
        () async => 'photo-bytes',
      );

      expect(rowsWhenSent, 1);
    });

    test(
      'invokes the reveal and clears the row once the server acks',
      () async {
        final sink = buildSink(_ScriptedTransport([const Ok(null)]));
        var revealed = false;

        final result = await sink.revealAudited(
          event(action: AuditAction.nidRevealed),
          () async {
            revealed = true;
            return 'NID-1234';
          },
        );

        expect(revealed, isTrue);
        expect(result.isOk, isTrue);
        expect(result.fold((v) => v, (_) => null), 'NID-1234');
        // Confirmed sent, so nothing is left for the flusher.
        expect(await db.select(db.auditEvents).get(), isEmpty);
      },
    );

    test('does NOT invoke the reveal when the ack fails', () async {
      // Fails closed. This is the assertion that makes audit-on-view a real
      // control rather than a best-effort log line.
      final sink = buildSink(
        _ScriptedTransport([const Err(Failure(FailureKind.network))]),
      );
      var revealed = false;

      final result = await sink.revealAudited(
        event(action: AuditAction.sensitiveMediaViewed),
        () async {
          revealed = true;
          return 'photo-bytes';
        },
      );

      expect(revealed, isFalse);
      expect(result.isOk, isFalse);
      expect(result.fold((_) => null, (f) => f.kind), FailureKind.network);
    });

    test('leaves the row buffered when the ack fails', () async {
      // The reveal was blocked, but the attempt must still reach the server
      // eventually - the flusher picks this up.
      final sink = buildSink(
        _ScriptedTransport([const Err(Failure(FailureKind.timeout))]),
      );

      await sink.revealAudited(
        event(action: AuditAction.sensitiveMediaViewed),
        () async => 'photo-bytes',
      );

      final rows = await db.select(db.auditEvents).get();
      expect(rows, hasLength(1));
      expect(rows.single.action, 'sensitiveMediaViewed');
    });

    test('carries the correlation id on the failure', () async {
      final sink = buildSink(
        _ScriptedTransport([
          const Err(Failure(FailureKind.forbidden, correlationId: 'srv-1')),
        ]),
      );

      final result = await sink.revealAudited(
        event(action: AuditAction.nidRevealed),
        () async => 'NID-1234',
      );

      // A 403 on the audit endpoint is a permissions problem and must not read
      // the same as a dropped connection.
      expect(result.fold((_) => null, (f) => f.kind), FailureKind.forbidden);
      expect(result.fold((_) => null, (f) => f.correlationId), 'srv-1');
    });
  });
}
