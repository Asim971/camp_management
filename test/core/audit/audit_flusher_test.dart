import 'package:acsl_campaign/core/audit/audit.dart';
import 'package:acsl_campaign/core/audit/audit_emitter.dart';
import 'package:acsl_campaign/core/audit/audit_transport.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedTransport implements AuditTransport {
  _ScriptedTransport(this._results);

  final List<Result<void>> _results;
  final List<List<AuditEventPayload>> batches = [];

  @override
  Future<Result<void>> send(List<AuditEventPayload> events) async {
    batches.add(events);
    return _results[(batches.length - 1).clamp(0, _results.length - 1)];
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed(String id, {int attempts = 0}) => db
      .into(db.auditEvents)
      .insert(
        AuditEventsCompanion.insert(
          id: id,
          action: AuditAction.campaignApproved.name,
          entity: 'campaign',
          entityId: id,
          correlationId: 'trace-$id',
          actorId: 'user-1',
          occurredAt: DateTime.utc(2026, 8, 6, 12),
          attempts: Value(attempts),
        ),
      );

  AuditFlusher buildFlusher(
    AuditTransport transport, {
    int batchSize = 20,
    int maxAttempts = 10,
  }) => AuditFlusher(
    db: db,
    transport: transport,
    batchSize: batchSize,
    maxAttempts: maxAttempts,
  );

  test('deletes rows the server confirmed', () async {
    await seed('a');
    await seed('b');
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport).flush();

    expect(transport.batches.single, hasLength(2));
    expect(await db.select(db.auditEvents).get(), isEmpty);
  });

  test('keeps the row and advances attempts when the send is permanently '
      'rejected', () async {
    // validation is a permanent rejection: the server will reject this
    // exact payload again no matter how many times it is resent, so this
    // is the one case where `attempts` is meant to advance.
    await seed('a');
    final transport = _ScriptedTransport([
      const Err(Failure(FailureKind.validation, message: 'malformed event')),
    ]);

    await buildFlusher(transport).flush();

    final rows = await db.select(db.auditEvents).get();
    expect(rows, hasLength(1));
    expect(rows.single.attempts, 1);
    expect(rows.single.lastError, contains('malformed event'));
  });

  test('a transient failure keeps the row deliverable and never advances '
      'attempts', () async {
    // network is transient - a bad signal in the field, not evidence the
    // row itself is unacceptable. It must retry forever and must NEVER
    // count toward `_maxAttempts`: conflating the two would let a five-
    // minute outage permanently strand whichever batch was at the queue
    // head when it started.
    await seed('a');
    final flaky = _ScriptedTransport(
      List.generate(
        12,
        (_) => const Err(Failure(FailureKind.network, message: 'offline')),
      ),
    );
    final flusher = buildFlusher(flaky, maxAttempts: 10);

    // 12 failed ticks - more than `maxAttempts` - simulating an outage
    // that outlasts the poison-pill threshold.
    for (var i = 0; i < 12; i++) {
      await flusher.flush();
    }

    final rows = await db.select(db.auditEvents).get();
    expect(rows, hasLength(1));
    expect(rows.single.attempts, 0);

    // The row must still be in the flush window: once the network
    // recovers, a succeeding transport actually delivers and removes it.
    // This is the assertion that matters - `attempts == 0` alone would not
    // prove the row is still reachable.
    final recovered = _ScriptedTransport([const Ok(null)]);
    await buildFlusher(recovered, maxAttempts: 10).flush();

    expect(recovered.batches.single, hasLength(1));
    expect(await db.select(db.auditEvents).get(), isEmpty);
  });

  test(
    'repeated permanent rejection sets the row aside after maxAttempts',
    () async {
      await seed('a');
      final rejecting = _ScriptedTransport(
        List.generate(
          10,
          (_) => const Err(Failure(FailureKind.validation, message: 'bad row')),
        ),
      );
      final flusher = buildFlusher(rejecting, maxAttempts: 10);

      for (var i = 0; i < 10; i++) {
        await flusher.flush();
      }

      final rows = await db.select(db.auditEvents).get();
      expect(rows, hasLength(1));
      expect(rows.single.attempts, 10);

      // The row must now be excluded from the flush window - a later
      // succeeding transport must not see it, even though it is never
      // deleted.
      final recovered = _ScriptedTransport([const Ok(null)]);
      await buildFlusher(recovered, maxAttempts: 10).flush();

      expect(recovered.batches, isEmpty);
      expect(await db.select(db.auditEvents).get(), hasLength(1));
    },
  );

  test('never discards an event, however many attempts have failed', () async {
    // The sync engine gives up after maxRetries and tells the user. Audit must
    // not: a discarded compliance record is silent data loss.
    await seed('a', attempts: 99);
    final transport = _ScriptedTransport([
      const Err(Failure(FailureKind.server)),
    ]);

    await buildFlusher(transport).flush();

    expect(await db.select(db.auditEvents).get(), hasLength(1));
  });

  test('sends in FIFO order', () async {
    await seed('first');
    await seed('second');
    await seed('third');
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport).flush();

    expect(transport.batches.single.map((e) => e.entityId), [
      'first',
      'second',
      'third',
    ]);
  });

  test('respects the batch size', () async {
    await seed('a');
    await seed('b');
    await seed('c');
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport, batchSize: 2).flush();

    expect(transport.batches.single, hasLength(2));
    expect(await db.select(db.auditEvents).get(), hasLength(1));
  });

  test('skips a poison pill so it cannot block later events', () async {
    // A permanently rejected row must not stall the queue head forever. It is
    // skipped, NOT deleted - one bad event degrades one record, not the trail.
    await seed('poison', attempts: 10);
    await seed('healthy');
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport, maxAttempts: 10).flush();

    expect(transport.batches.single.map((e) => e.entityId), ['healthy']);
    final remaining = await db.select(db.auditEvents).get();
    expect(remaining, hasLength(1));
    expect(remaining.single.entityId, 'poison');
  });

  test('does nothing when there is nothing pending', () async {
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport).flush();

    expect(transport.batches, isEmpty);
  });

  test('flushes early once a full batch has buffered', () async {
    final transport = _ScriptedTransport([const Ok(null)]);
    final flusher = buildFlusher(transport, batchSize: 2);

    await seed('a');
    flusher.notifyBuffered();
    await seed('b');
    flusher.notifyBuffered();
    // Let the flush scheduled by the second notification settle.
    await Future<void>.delayed(Duration.zero);
    await flusher.dispose();

    expect(transport.batches, isNotEmpty);
  });

  test('a concurrent flush does not double-send the same rows', () async {
    await seed('a');
    final transport = _ScriptedTransport([const Ok(null)]);
    final flusher = buildFlusher(transport);

    await Future.wait([flusher.flush(), flusher.flush()]);

    expect(transport.batches, hasLength(1));
  });
}
