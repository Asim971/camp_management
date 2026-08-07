import '../result/result.dart';

/// Coordinates draining the offline queue to the server. The engine embodies
/// the guarantees in Architecture §9:
///
///  * capture success != upload success (two distinct, separately shown states);
///  * idempotency — every task carries a client key; the server dedups replays;
///  * durability — queue survives restart (backed by Drift);
///  * resilience — exponential backoff, visible retry count, manual retry/pause.
///
/// The UI observes [statusStream]; it must NEVER prompt recapture merely
/// because sync is delayed (§8.11).
abstract interface class SyncEngine {
  /// Enqueue a unit of work. Returns immediately after durable persistence.
  Future<Result<void>> enqueue(SyncTaskSpec spec);

  /// Attempt to drain the queue now (also runs on connectivity regained and
  /// via background worker).
  Future<void> drain();

  Future<void> retry(String taskId);
  Future<void> pause(String taskId);

  /// Discard is permission-gated and controlled (§8.11) — not a casual action.
  Future<Result<void>> discard(String taskId, {required String reason});

  Stream<List<SyncTaskView>> statusStream();
}

class SyncTaskSpec {
  const SyncTaskSpec({
    required this.idempotencyKey,
    required this.type,
    required this.payload,
  });

  final String idempotencyKey;
  final String type; // 'attendance' | 'import_commit' | ...
  final Map<String, Object?> payload;
}

/// Read model surfaced to the offline-queue screen (M-04).
class SyncTaskView {
  const SyncTaskView({
    required this.id,
    required this.type,
    required this.status, // mirrors AttendanceStatus wording where relevant
    required this.retryCount,
    required this.createdAt,
    this.sessionId,
    this.carpenterId,
    this.lastError,
  });

  final String id;
  final String type;
  final String status;
  final int retryCount;
  final DateTime createdAt;
  final String? sessionId;
  final String? carpenterId;
  final String? lastError;
}
