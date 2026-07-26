import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/sync/sync_engine.dart';

/// Live view of the offline sync queue (M-04), sourced from the engine's
/// durable table. The screen watches this; it is never a manual poll.
final syncQueueProvider = StreamProvider.autoDispose<List<SyncTaskView>>(
  (ref) => ref.watch(syncEngineProvider).statusStream(),
);

/// Count of items not yet handed off to the server (for the persistent header).
final pendingCountProvider = Provider.autoDispose<int>((ref) {
  final queue = ref.watch(syncQueueProvider).valueOrNull ?? const [];
  return queue.where((t) => t.status == 'pendingSync' || t.status == 'paused').length;
});
