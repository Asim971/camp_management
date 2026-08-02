import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/design_system/bmd_feedback.dart';
import '../../../core/design_system/lineage_rail.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../domain/common/status.dart';
import '../application/offline_queue_provider.dart';

/// Offline Queue and Capture Status (M-04).
///
/// This screen exists to protect the field user's work. Its one job is to make
/// "the photo is safe" and "the photo has reached the server" two visibly
/// different facts — and to never imply that a delayed upload should be solved
/// by photographing the participant again (§8.11).
class OfflineQueueScreen extends ConsumerWidget {
  const OfflineQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(syncQueueProvider);
    final pending = ref.watch(pendingCountProvider);
    final engine = ref.read(syncEngineProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: BmdSize.appBarMobile,
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
          // Persistent, compact: queue count, last sync, direct route to the
          // queue. Present on every screen in the field app (§3.2).
          OfflineBar(
            pendingCount: pending,
            // TODO(T-2.1.4): surface the real last-successful-sync timestamp.
            lastSyncLabel: '—',
          ),
          Expanded(
            child: queue.when(
              loading: () => const _QueueSkeleton(),
              error: (_, __) => BmdState.error(
                title: "Couldn't read the sync queue",
                body:
                    'Your captures are still saved on this device. Reopening '
                    'the app will not lose them.',
                action: FilledButton(
                  onPressed: () => ref.invalidate(syncQueueProvider),
                  child: const Text('Try again'),
                ),
                reference: 'Reference SYN-READ',
              ),
              data: (items) => items.isEmpty
                  ? const BmdState.empty(
                      title: 'Everything is synced',
                      body:
                          'Nothing is waiting to upload. Captures you take '
                          'from here will appear in this queue until they '
                          'reach the server.',
                      icon: Icons.cloud_done_outlined,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: BmdSpace.s6),
                      itemCount: items.length + 1,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => i == items.length
                          ? const _ReassuranceFooter()
                          : _QueueTile(item: items[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueSkeleton extends StatelessWidget {
  const _QueueSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(BmdSpace.s4),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: BmdSpace.s4),
      itemBuilder: (_, __) => const Row(
        children: [
          BmdSkeleton(width: 40, height: 40),
          SizedBox(width: BmdSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BmdSkeleton(width: 160),
                SizedBox(height: BmdSpace.s2),
                BmdSkeleton(width: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one message a field user most needs on this screen.
class _ReassuranceFooter extends StatelessWidget {
  const _ReassuranceFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(BmdSpace.s4),
      child: BmdBanner(
        tone: BannerTone.info,
        title: 'Every photo here is saved on this device',
        body:
            'They upload on their own when a network returns. Do not '
            'photograph anyone again.',
      ),
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({required this.item});
  final SyncTaskView item;

  ({String label, StatusTone tone}) _status(String s) => switch (s) {
    'pendingSync' => (label: 'Pending sync', tone: StatusTone.warning),
    'matchProcessing' => (label: 'Match processing', tone: StatusTone.info),
    'paused' => (label: 'Paused', tone: StatusTone.neutral),
    'failed' => (label: 'Upload failed', tone: StatusTone.error),
    _ => (label: s, tone: StatusTone.neutral),
  };

  /// The chain of custody for this record. Capture is always solid and green:
  /// the photo exists, whatever the upload is doing.
  List<LineageNode> _lineage() {
    const counted = LineageNode(label: 'Counted', state: LineageState.pending);
    const crmPending = LineageNode(
      label: 'CRM decision',
      state: LineageState.pending,
    );
    const captured = LineageNode(
      label: 'Captured',
      state: LineageState.done,
      meta: 'saved on this device',
    );

    return switch (item.status) {
      'pendingSync' => [
        captured,
        LineageNode(
          label: 'Waiting to upload',
          state: LineageState.current,
          meta: item.retryCount == 0
              ? 'no retries yet'
              : 'retry ${item.retryCount}',
        ),
        crmPending,
        counted,
      ],
      'matchProcessing' => [
        captured,
        const LineageNode(label: 'Uploaded', state: LineageState.done),
        const LineageNode(
          label: 'Matching',
          state: LineageState.current,
          meta: 'advisory only',
        ),
        crmPending,
        counted,
      ],
      'failed' => [
        captured,
        LineageNode(
          label: 'Upload failed',
          state: LineageState.failed,
          meta: '${item.retryCount} attempts · needs support, not a retake',
        ),
        crmPending,
        counted,
      ],
      'paused' => [
        captured,
        const LineageNode(
          label: 'Upload paused',
          state: LineageState.blocked,
          meta: 'resume to continue',
        ),
        crmPending,
        counted,
      ],
      _ => [captured, crmPending, counted],
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(syncEngineProvider);
    final theme = Theme.of(context);
    final st = _status(item.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BmdSpace.s4,
        BmdSpace.s3,
        BmdSpace.s4,
        BmdSpace.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A veiled thumbnail, never a face: this is a queue, and a
              // reviewer scrolling it has no need to see the evidence (§10.2).
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BmdColor.veil,
                  borderRadius: BorderRadius.circular(BmdRadius.chip),
                ),
                child: const Icon(
                  Icons.visibility_off_outlined,
                  size: 16,
                  color: BmdColor.inkOnVeilMuted,
                ),
              ),
              const SizedBox(width: BmdSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Carpenter ${item.carpenterId ?? '—'}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.bmd.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Session ${item.sessionId ?? '—'} · '
                      'captured ${item.createdAt}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BmdSpace.s2),
              StatusChip(label: st.label, tone: st.tone),
              Semantics(
                identifier: 'queue_item_menu',
                child: PopupMenuButton<String>(
                  onSelected: (action) async {
                    switch (action) {
                      case 'retry':
                        await engine.retry(item.id);
                      case 'pause':
                        await engine.pause(item.id);
                      case 'discard':
                        await _confirmDiscard(context, ref, item.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'retry', child: Text('Retry')),
                    PopupMenuItem(value: 'pause', child: Text('Pause')),
                    PopupMenuItem(value: 'discard', child: Text('Discard…')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BmdSpace.s3),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: LineageRail.vertical(nodes: _lineage()),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    // Discard is destructive and controlled (§8.11). It is deliberately
    // awkward: a queued upload almost never needs discarding, and a discarded
    // capture is a participant who has to be photographed twice.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this capture?'),
        content: const Text(
          'The photo will be deleted from this device and this attendance will '
          'show as Not captured. The carpenter would need to be photographed '
          'again.\n\n'
          'Only discard if support asked you to. This action is recorded '
          'against your name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it queued'),
          ),
          Semantics(
            identifier: 'queue_discard_confirm',
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).bmd.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard capture'),
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
