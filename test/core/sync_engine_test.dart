import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:acsl_campaign/core/sync/backoff.dart';
import 'package:acsl_campaign/core/sync/sync_engine.dart';
import 'package:acsl_campaign/core/sync/sync_engine_impl.dart';
import 'package:acsl_campaign/core/sync/sync_uploader.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Offline sync integration harness (Task T-2.1.5). Exercises the engine
/// against a real in-memory Drift DB and a scriptable uploader, with an
/// injected clock and connectivity so the failure-recovery matrix (§9.4) is
/// deterministic. Extend with cases as the field flows land.

/// Uploader whose result is scripted per call and which records attempts.
class _ScriptedUploader implements SyncUploader {
  _ScriptedUploader(this._responses);
  final List<Result<void>> _responses;
  int calls = 0;

  @override
  Future<Result<void>> upload(SyncTaskSpec spec) async {
    final i = calls.clamp(0, _responses.length - 1);
    calls++;
    return _responses[i];
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  SyncTaskSpec spec(String id) =>
      SyncTaskSpec(idempotencyKey: id, type: 'attendance', payload: {'x': 1});

  test('enqueue persists exactly once even on replay (idempotent)', () async {
    final engine = SyncEngineImpl(
      db: db,
      uploader: _ScriptedUploader([const Ok(null)]),
      isOnline: () async => false, // do not drain yet
    );

    await engine.enqueue(spec('t1'));
    await engine.enqueue(spec('t1')); // replay — same key

    final rows = await db.select(db.syncTasks).get();
    expect(rows.length, 1);
    expect(rows.single.status, 'pendingSync');
  });

  test('successful drain moves the task to matchProcessing', () async {
    final engine = SyncEngineImpl(
      db: db,
      uploader: _ScriptedUploader([const Ok(null)]),
      isOnline: () async => true,
    );

    await engine.enqueue(spec('t2'));
    await engine.drain();

    final row = await (db.select(db.syncTasks)..where((t) => t.id.equals('t2')))
        .getSingle();
    expect(row.status, 'matchProcessing');
  });

  test('offline drain is a no-op; work is preserved', () async {
    final engine = SyncEngineImpl(
      db: db,
      uploader: _ScriptedUploader([const Ok(null)]),
      isOnline: () async => false,
    );

    await engine.enqueue(spec('t3'));
    await engine.drain();

    final row = await (db.select(db.syncTasks)..where((t) => t.id.equals('t3')))
        .getSingle();
    expect(row.status, 'pendingSync'); // never lost, never processed
  });

  test('retryable failure increments retry and stays pending', () async {
    final engine = SyncEngineImpl(
      db: db,
      uploader: _ScriptedUploader([const Err(Failure(FailureKind.network))]),
      isOnline: () async => true,
    );

    await engine.enqueue(spec('t4'));
    await engine.drain();

    final row = await (db.select(db.syncTasks)..where((t) => t.id.equals('t4')))
        .getSingle();
    expect(row.status, 'pendingSync');
    expect(row.retryCount, 1);
    expect(row.lastError, isNotNull);
  });

  test('non-retryable failure becomes terminal failed', () async {
    final engine = SyncEngineImpl(
      db: db,
      uploader: _ScriptedUploader([const Err(Failure(FailureKind.validation))]),
      isOnline: () async => true,
    );

    await engine.enqueue(spec('t5'));
    await engine.drain();

    final row = await (db.select(db.syncTasks)..where((t) => t.id.equals('t5')))
        .getSingle();
    expect(row.status, 'failed');
  });

  test('409 conflict is treated as already-synced success', () async {
    final engine = SyncEngineImpl(
      db: db,
      uploader: _ScriptedUploader([const Err(Failure(FailureKind.conflict))]),
      isOnline: () async => true,
    );

    await engine.enqueue(spec('t6'));
    await engine.drain();

    final row = await (db.select(db.syncTasks)..where((t) => t.id.equals('t6')))
        .getSingle();
    expect(row.status, 'matchProcessing');
  });

  test('backoff defers a just-attempted task until due', () async {
    var clock = DateTime(2026, 7, 26, 10);
    final engine = SyncEngineImpl(
      db: db,
      uploader: _ScriptedUploader([
        const Err(Failure(FailureKind.network)), // attempt 1 fails
        const Ok(null), // would succeed if attempted
      ]),
      isOnline: () async => true,
      backoff: const BackoffPolicy(base: Duration(seconds: 2)),
      now: () => clock,
    );

    await engine.enqueue(spec('t7'));
    await engine.drain(); // attempt 1 → fail, retryCount 1, lastAttempt=now

    // Immediately drain again: not yet due (needs ~2s), so no second attempt.
    await engine.drain();
    var row = await (db.select(db.syncTasks)..where((t) => t.id.equals('t7')))
        .getSingle();
    expect(
      row.retryCount,
      1,
      reason: 'should not retry before backoff elapses',
    );

    // Advance the clock past the backoff window and drain again → succeeds.
    clock = clock.add(const Duration(seconds: 10));
    await engine.drain();
    row = await (db.select(db.syncTasks)..where((t) => t.id.equals('t7')))
        .getSingle();
    expect(row.status, 'matchProcessing');
  });
}
