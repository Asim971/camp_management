import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../domain/common/status.dart';
import '../application/offline_queue_provider.dart';

/// Offline Queue and Capture Status (M-04). Makes sync unambiguous: a persistent
/// header shows what is still pending, and each item shows its state, retry
/// count and available action. Delayed sync is never framed as a reason to
/// recapture (§8.11).
class OfflineQueueScreen extends ConsumerWidget {
  const OfflineQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(syncQueueProvider);
    final pending = ref.watch(pendingCountProvider);
    final engine = ref.read(syncEngineProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        title: const Text('Sync queue'),
        actions: [
          IconButton(
            tooltip: 'Retry all',
            icon: const Icon(Icons.sync),
            onPressed: engine.drain,
          ),
        ],
      ),
      body: Column(
        children: [
          _PendingHeader(pending: pending),
          Expanded(
            child: queue.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Queue unavailable')),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('Everything is synced.'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _QueueTile(item: items[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingHeader extends StatelessWidget {
  const _PendingHeader({required this.pending});
  final int pending;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 18),
          const SizedBox(width: 8),
          Text(
            pending == 0 ? 'All items synced' : '$pending pending',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const Spacer(),
          // TODO(T-2.1.4): show last successful sync timestamp.
          Text('Last sync —', style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({required this.item});
  final dynamic item; // SyncTaskView

  ({String label, StatusTone tone}) _status(String s) => switch (s) {
        'pendingSync' => (label: 'Pending sync', tone: StatusTone.warning),
        'matchProcessing' => (label: 'Match processing', tone: StatusTone.info),
        'paused' => (label: 'Paused', tone: StatusTone.neutral),
        'failed' => (label: 'Failed', tone: StatusTone.error),
        _ => (label: s, tone: StatusTone.neutral),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(syncEngineProvider);
    final st = _status(item.status as String);

    return ListTile(
      title: Text('Carpenter ${item.carpenterId ?? '—'}'),
      subtitle: Text(
        'Session ${item.sessionId ?? '—'} · '
        'captured ${item.createdAt} · retries ${item.retryCount}',
      ),
      leading: StatusChip(label: st.label, tone: st.tone),
      trailing: Semantics(
        identifier: 'queue_item_menu',
        child: PopupMenuButton<String>(
          onSelected: (action) async {
            switch (action) {
              case 'retry':
                await engine.retry(item.id as String);
              case 'pause':
                await engine.pause(item.id as String);
              case 'discard':
                await _confirmDiscard(context, ref, item.id as String);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'retry', child: Text('Retry')),
            PopupMenuItem(value: 'pause', child: Text('Pause')),
            PopupMenuItem(value: 'discard', child: Text('Discard…')),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    // Discard is destructive + controlled (§8.11) — always confirm.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard captured attendance?'),
        content: const Text(
          'This permanently removes the captured evidence from this device. '
          'It cannot be recovered. Discard only when instructed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          Semantics(
            identifier: 'queue_discard_confirm',
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard'),
            ),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref
          .read(syncEngineProvider)
          .discard(id, reason: 'Field user discard (confirmed)');
    }
  }
}
