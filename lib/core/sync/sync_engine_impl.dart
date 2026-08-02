import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../media/evidence_store.dart';
import '../result/result.dart';
import '../storage/app_database.dart';
import 'backoff.dart';
import 'sync_engine.dart';
import 'sync_uploader.dart';

/// Concrete [SyncEngine] backing the offline attendance queue (Tasks T-2.1.1–4).
///
/// Guarantees (Architecture §9):
///  * **Durable** — the queue lives in Drift/SQLite and survives process death.
///  * **Idempotent** — `insertOrIgnore` on the client key + an `Idempotency-Key`
///    header mean an enqueue or an upload replay never double-counts.
///  * **Resilient** — retryable failures back off exponentially and are retried;
///    non-retryable failures move to a terminal `failed` state for the user to
///    see, never silently dropped.
///  * **Capture ≠ upload** — enqueue returns as soon as work is *persisted*; the
///    UI shows sync progress separately and never prompts recapture on delay.
///
/// [now] and [isOnline] are injected so the engine is deterministic under test
/// (see test/core/sync_engine_test.dart) with no real clock or network.
class SyncEngineImpl implements SyncEngine {
  SyncEngineImpl({
    required AppDatabase db,
    required SyncUploader uploader,
    required Future<bool> Function() isOnline,
    EvidenceStore? evidenceStore,
    Stream<bool>? connectivityStream,
    BackoffPolicy backoff = const BackoffPolicy(),
    DateTime Function() now = DateTime.now,
    // Field names are deliberately private (`_db`) while constructor params
    // stay public-looking (`db`) for a clean call-site API — so these can't
    // become initializing formals without renaming the public parameters.
    // ignore: prefer_initializing_formals
  })  : _db = db,
        // ignore: prefer_initializing_formals
        _uploader = uploader,
        // ignore: prefer_initializing_formals
        _isOnline = isOnline,
        _evidence = evidenceStore ?? createEvidenceStore(),
        // ignore: prefer_initializing_formals
        _backoff = backoff,
        // ignore: prefer_initializing_formals
        _now = now {
    // Drain automatically when connectivity is regained.
    _connSub = connectivityStream?.listen((online) {
      if (online) unawaited(drain());
    });
  }

  final AppDatabase _db;
  final SyncUploader _uploader;
  final Future<bool> Function() _isOnline;
  final EvidenceStore _evidence;
  final BackoffPolicy _backoff;
  final DateTime Function() _now;

  StreamSubscription<bool>? _connSub;
  bool _draining = false;

  static const _pending = 'pendingSync';
  static const _processing = 'matchProcessing';
  static const _failed = 'failed';
  static const _paused = 'paused';

  @override
  Future<Result<void>> enqueue(SyncTaskSpec spec) async {
    try {
      await _db.into(_db.syncTasks).insert(
            SyncTasksCompanion.insert(
              id: spec.idempotencyKey,
              type: spec.type,
              payloadJson: jsonEncode(spec.payload),
              createdAt: _now(),
            ),
            mode: InsertMode.insertOrIgnore, // idempotent enqueue
          );
      return const Ok(null);
    } catch (e) {
      return Err(Failure(FailureKind.unknown, message: e.toString()));
    }
  }

  @override
  Future<void> drain() async {
    if (_draining) return; // never overlap drains
    _draining = true;
    try {
      if (!await _isOnline()) return;
      final tasks = await (_db.select(_db.syncTasks)
            ..where((t) => t.status.equals(_pending))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

      for (final task in tasks) {
        if (!_isDue(task)) continue;
        await _attempt(task);
      }
    } finally {
      _draining = false;
    }
  }

  bool _isDue(SyncTask task) {
    final last = task.lastAttemptAt;
    if (last == null) return true;
    final wait = _backoff.delayFor(
      task.retryCount,
      jitterSeed: jitterSeedFor(task.id),
    );
    return _now().difference(last) >= wait;
  }

  Future<void> _attempt(SyncTask task) async {
    final spec = SyncTaskSpec(
      idempotencyKey: task.id,
      type: task.type,
      payload: jsonDecode(task.payloadJson) as Map<String, Object?>,
    );

    final result = await _uploader.upload(spec);
    await result.fold(
      (_) => _onSuccess(task),
      (failure) => _onFailure(task, failure),
    );
  }

  Future<void> _onSuccess(SyncTask task) async {
    // Server now owns the record (quality/PAD/1:1 → CRM). Hand off to the
    // processing state and purge the local encrypted evidence to minimize
    // sensitive-data retention on the device (§10.2).
    await _setStatus(task.id, _processing, clearError: true);
    await _purgeEvidence(task);
  }

  Future<void> _onFailure(SyncTask task, Failure failure) async {
    // A 409 means the server already has this record — treat as success.
    if (failure.kind == FailureKind.conflict) {
      await _onSuccess(task);
      return;
    }

    final retryable = switch (failure.kind) {
      FailureKind.network ||
      FailureKind.timeout ||
      FailureKind.server ||
      FailureKind.offlineQueued =>
        true,
      _ => false, // validation/forbidden/unauthorized → terminal
    };

    final nextRetry = task.retryCount + 1;
    final giveUp = !retryable || _backoff.shouldGiveUp(nextRetry);

    await (_db.update(_db.syncTasks)..where((t) => t.id.equals(task.id))).write(
      SyncTasksCompanion(
        status: Value(giveUp ? _failed : _pending),
        retryCount: Value(nextRetry),
        lastAttemptAt: Value(_now()),
        lastError: Value(failure.toString()),
      ),
    );
  }

  Future<void> _purgeEvidence(SyncTask task) async {
    try {
      final payload = jsonDecode(task.payloadJson) as Map<String, Object?>;
      final path = payload['encryptedMediaPath'] as String?;
      if (path != null) await _evidence.deleteIfExists(path);
    } catch (_) {
      // Non-fatal: a leftover encrypted blob is cleaned by a retention sweep.
    }
  }

  Future<void> _setStatus(String id, String status, {bool clearError = false}) {
    return (_db.update(_db.syncTasks)..where((t) => t.id.equals(id))).write(
      SyncTasksCompanion(
        status: Value(status),
        lastError: clearError ? const Value(null) : const Value.absent(),
      ),
    );
  }

  @override
  Future<void> retry(String taskId) async {
    // Reset to pending and clear the attempt clock so it is immediately due.
    await (_db.update(_db.syncTasks)..where((t) => t.id.equals(taskId))).write(
      const SyncTasksCompanion(
        status: Value(_pending),
        lastAttemptAt: Value(null),
      ),
    );
    await drain();
  }

  @override
  Future<void> pause(String taskId) => _setStatus(taskId, _paused);

  @override
  Future<Result<void>> discard(String taskId, {required String reason}) async {
    // Permission-gated + controlled at the call site (§8.11). Purge evidence.
    final task = await (_db.select(_db.syncTasks)
          ..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    if (task != null) await _purgeEvidence(task);
    await (_db.delete(_db.syncTasks)..where((t) => t.id.equals(taskId))).go();
    return const Ok(null);
  }

  @override
  Stream<List<SyncTaskView>> statusStream() {
    final query = _db.select(_db.syncTasks)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
          (rows) => rows.map(_toView).toList(),
        );
  }

  SyncTaskView _toView(SyncTask t) {
    String? sessionId;
    String? carpenterId;
    try {
      final payload = jsonDecode(t.payloadJson) as Map<String, Object?>;
      sessionId = payload['sessionId'] as String?;
      carpenterId = payload['carpenterId'] as String?;
    } catch (_) {/* payload without those keys */}
    return SyncTaskView(
      id: t.id,
      type: t.type,
      status: t.status,
      retryCount: t.retryCount,
      createdAt: t.createdAt,
      sessionId: sessionId,
      carpenterId: carpenterId,
      lastError: t.lastError,
    );
  }

  void dispose() => _connSub?.cancel();
}
