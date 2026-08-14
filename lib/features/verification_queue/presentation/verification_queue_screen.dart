import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/providers.dart';
import '../../../app/shell/app_shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/rbac.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../domain/common/status.dart';
import '../../../domain/verification/verification_case.dart';
import '../application/verification_queue_notifier.dart';

/// Verification Queue (C-01). A prioritised worklist for CRM verifiers, with
/// All/Mine/Unassigned tabs and, for a supervisor holding
/// [Permission.verificationOverride], an Escalated tab (CM-FR-060, 067).
class VerificationQueueScreen extends ConsumerStatefulWidget {
  const VerificationQueueScreen({super.key});

  @override
  ConsumerState<VerificationQueueScreen> createState() =>
      _VerificationQueueScreenState();
}

class _VerificationQueueScreenState
    extends ConsumerState<VerificationQueueScreen> {
  QueueFilter _filter = QueueFilter.all;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final canEscalate = switch (auth) {
      AuthSignedIn(:final session) => session.scope.can(
        Permission.verificationOverride,
      ),
      _ => false,
    };
    final userId = switch (auth) {
      AuthSignedIn(:final session) => session.userId,
      _ => null,
    };

    // The Escalated tab disappears the instant the permission does; stay on a
    // filter the user can still see rather than rendering a hidden tab as
    // selected.
    final filter = (_filter == QueueFilter.escalated && !canEscalate)
        ? QueueFilter.all
        : _filter;

    final async = ref.watch(verificationQueueProvider(filter));

    return AppShell(
      title: 'Verification queue',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterTabs(
            selected: filter,
            canEscalate: canEscalate,
            onSelected: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: BmdSpace.s3),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _ErrorState(
                onRetry: () =>
                    ref.invalidate(verificationQueueProvider(filter)),
              ),
              data: (items) => items.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(BmdSpace.s4),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: BmdSpace.s3),
                      itemBuilder: (_, i) => _QueueTile(
                        item: items[i],
                        userId: userId,
                        filter: filter,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.selected,
    required this.canEscalate,
    required this.onSelected,
  });

  final QueueFilter selected;
  final bool canEscalate;
  final ValueChanged<QueueFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final tabs = <QueueFilter>[
      QueueFilter.all,
      QueueFilter.mine,
      QueueFilter.unassigned,
      if (canEscalate) QueueFilter.escalated,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BmdSpace.s4,
        BmdSpace.s4,
        BmdSpace.s4,
        0,
      ),
      child: Wrap(
        spacing: BmdSpace.s2,
        children: [
          for (final f in tabs)
            Semantics(
              identifier: 'queue_tab_${f.name}',
              button: true,
              selected: f == selected,
              child: ChoiceChip(
                label: Text(_label(f)),
                selected: f == selected,
                onSelected: (_) => onSelected(f),
              ),
            ),
        ],
      ),
    );
  }

  String _label(QueueFilter f) => switch (f) {
    QueueFilter.all => 'All',
    QueueFilter.mine => 'Mine',
    QueueFilter.unassigned => 'Unassigned',
    QueueFilter.escalated => 'Escalated',
  };
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({
    required this.item,
    required this.userId,
    required this.filter,
  });

  final VerificationQueueItem item;
  final String? userId;
  final QueueFilter filter;

  bool get _isUnassigned => item.assigneeId == null;
  bool get _isMine => userId != null && item.assigneeId == userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(verificationQueueProvider(filter).notifier);

    return Semantics(
      identifier: 'queue_item_${item.attendanceId}',
      child: Card(
        child: InkWell(
          onTap: () => context.go('/verification/cases/${item.attendanceId}'),
          borderRadius: BorderRadius.circular(BmdRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(BmdSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.carpenterName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (item.escalatedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(left: BmdSpace.s2),
                        child: Semantics(
                          identifier: 'queue_escalated_${item.attendanceId}',
                          child: const StatusChip(
                            label: 'Escalated',
                            tone: StatusTone.error,
                            icon: Icons.priority_high,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: BmdSpace.s1),
                Text(
                  item.campaignName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: BmdSpace.s2),
                Wrap(
                  spacing: BmdSpace.s2,
                  runSpacing: BmdSpace.s1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(label: Text('Band: ${_band(item.band)}')),
                    Text(
                      'Waiting ${_formatAge(item.age)}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      _isUnassigned
                          ? 'Unassigned'
                          : (_isMine ? 'Assigned to you' : 'Assigned'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: BmdSpace.s3),
                Align(
                  alignment: Alignment.centerRight,
                  child: _isUnassigned
                      ? BmdButton(
                          identifier: 'queue_claim_${item.attendanceId}',
                          label: 'Claim',
                          variant: BmdButtonVariant.outlined,
                          onPressed: () => _act(context, notifier.claim),
                        )
                      : (_isMine
                            ? BmdButton(
                                identifier:
                                    'queue_release_${item.attendanceId}',
                                label: 'Release',
                                variant: BmdButtonVariant.outlined,
                                onPressed: () =>
                                    _act(context, notifier.release),
                              )
                            : const SizedBox.shrink()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    Future<QueueActionResult> Function(String) action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await action(item.attendanceId);
    switch (result) {
      case QueueActionResult.done:
        break; // list refreshes itself via ref.invalidateSelf()
      case QueueActionResult.conflict:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('This case is being reviewed by someone else.'),
          ),
        );
      case QueueActionResult.error:
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Couldn't update this case. Try again."),
          ),
        );
    }
  }

  String _band(MatchBand b) => switch (b) {
    MatchBand.high => 'High',
    MatchBand.medium => 'Medium',
    MatchBand.low => 'Low',
    MatchBand.noReference => 'No reference',
  };

  String _formatAge(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('No cases in this view.'));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("Couldn't load the verification queue."),
        const SizedBox(height: BmdSpace.s2),
        BmdButton(
          variant: BmdButtonVariant.outlined,
          label: 'Retry',
          onPressed: onRetry,
        ),
      ],
    ),
  );
}
