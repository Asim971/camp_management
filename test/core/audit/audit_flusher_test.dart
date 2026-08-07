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

  test(
    'sends each row\'s id and occurredAt instant to the transport',
    () async {
      // IMPORTANT #1/#2: the wire payload must carry the persisted id
      // (server-side dedupe of a replayed batch) and occurredAt (the untrusted
      // client clock the server pairs with its own receipt time) - not just
      // whatever _toPayload happened to remember to copy.
      await seed('a');
      final transport = _ScriptedTransport([const Ok(null)]);

      await buildFlusher(transport).flush();

      final payload = transport.batches.single.single;
      expect(payload.id, 'a');
      // Drift round-trips DateTimeColumn as local-zoned under NativeDatabase
      // (see the identical note in audit_emitter_test.dart), so normalize
      // with `.toUtc()` before comparing the instant rather than depending
      // on Drift's storage representation.
      expect(payload.occurredAt.toUtc(), DateTime.utc(2026, 8, 6, 12));
    },
  );

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

  test('a 401 (unauthorized) keeps the row deliverable and never advances '
      'attempts', () async {
    // unauthorized/forbidden are a property of the SESSION, not the row -
    // recoverable by re-authenticating - so they must not count as
    // permanent. A device left at the login screen still ticks the
    // flusher every 30s regardless of session state; if 401 counted as
    // permanent, ten ticks (~5 minutes) would exclude the row forever with
    // nothing to ever reset `attempts` once the user signs back in.
    await seed('a');
    final flaky = _ScriptedTransport(
      List.generate(
        12,
        (_) =>
            const Err(Failure(FailureKind.unauthorized, message: 'no token')),
      ),
    );
    final flusher = buildFlusher(flaky, maxAttempts: 10);

    // 12 failed ticks - more than `maxAttempts` - simulating a device left
    // signed out for longer than the poison-pill threshold.
    for (var i = 0; i < 12; i++) {
      await flusher.flush();
    }

    final rows = await db.select(db.auditEvents).get();
    expect(rows, hasLength(1));
    expect(rows.single.attempts, 0);

    // The row must still be in the flush window: once the user signs back
    // in, a succeeding transport actually delivers and removes it.
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

  test('a permanent rejection of a multi-row batch does not charge an '
      'innocent batch-mate, but the actual offender still reaches exclusion '
      'on its own merits', () async {
    // IMPORTANT #4: AuditTransport.send returns one Result for the whole
    // batch, so a permanent rejection of [a, b] cannot say which row is at
    // fault. Spec §4.5 promises one bad event degrades exactly one record -
    // so rather than charge both rows an attempt, the flusher retries each
    // row alone (batch size 1) and only ever advances `attempts` for a row
    // that was rejected while alone.
    await seed('a');
    await seed('b');
    final transport = _ScriptedTransport([
      // 1: the pair is rejected as one - the offender is unknown yet.
      const Err(Failure(FailureKind.validation, message: 'bad row')),
      // 2: 'a' sent alone turns out fine.
      const Ok(null),
      // 3: 'b' sent alone is the actual offender.
      const Err(Failure(FailureKind.validation, message: 'bad row')),
      // 4, 5: 'b' rejected alone twice more, reaching maxAttempts: 3.
      const Err(Failure(FailureKind.validation, message: 'bad row')),
      const Err(Failure(FailureKind.validation, message: 'bad row')),
    ]);
    final flusher = buildFlusher(transport, maxAttempts: 3);

    await flusher.flush();

    var rows = await db.select(db.auditEvents).get();
    // 'a' was never charged an attempt for sharing a batch with 'b' - it
    // was sent alone, succeeded, and was deleted outright.
    expect(rows, hasLength(1));
    expect(rows.single.entityId, 'b');
    // 'b' is charged exactly one attempt for its OWN rejection while
    // alone - not one per batch it happened to be part of.
    expect(rows.single.attempts, 1);

    // Drive 'b' - the genuine offender - to exclusion on its own repeated
    // failures.
    await flusher.flush();
    await flusher.flush();

    rows = await db.select(db.auditEvents).get();
    expect(rows.single.attempts, 3);

    final recovered = _ScriptedTransport([const Ok(null)]);
    await buildFlusher(recovered, maxAttempts: 3).flush();

    expect(recovered.batches, isEmpty);
    expect(await db.select(db.auditEvents).get(), hasLength(1));
  });

  test('never discards a row when a send fails, even one the transport was '
      'actually asked to deliver', () async {
    // MINOR #9: the previous version of this test seeded attempts: 99
    // against maxAttempts: 10, so the row was already excluded from the
    // flush window and _flushOnce returned before ever calling the
    // transport - it would have passed against code with no failure
    // handling at all. This drives an actual send-and-fail instead.
    await seed('a', attempts: 5);
    final transport = _ScriptedTransport([
      const Err(Failure(FailureKind.server)),
    ]);

    await buildFlusher(transport, maxAttempts: 10).flush();

    expect(transport.batches, hasLength(1));
    final rows = await db.select(db.auditEvents).get();
    expect(rows, hasLength(1));
    expect(rows.single.entityId, 'a');
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
