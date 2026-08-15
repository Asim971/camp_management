import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/permission_gate.dart';
import '../../../core/auth/rbac.dart';
import '../../../core/design_system/bmd_data_table.dart';
import '../../../core/design_system/bmd_state_view.dart';
import '../../../core/design_system/screen_hero.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../core/motion/count_up.dart';
import '../../../domain/campaign/campaign.dart';
import '../../../domain/common/status.dart';
import '../../../domain/common/status_labels.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/campaign_list_notifier.dart';

/// Campaign List (W-02). Exemplar wiring an AsyncNotifier to the design system.
/// Every AsyncValue branch is a designed state — never a bare spinner or a
/// silent empty screen (Guideline QA checklist §13.2).
class CampaignListScreen extends ConsumerWidget {
  const CampaignListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(campaignListProvider);
    // Resolved once here rather than inside the cell/rowDetail closures: those
    // are invoked later by BmdDataTable and, for the row detail, from inside a
    // side-sheet route whose own context sits under a different Navigator.
    // Capturing the bundle keeps every chip on the locale this frame was built
    // for.
    final l10n = AppL10n.of(context);

    final paged = async.valueOrNull;
    final active = paged?.items
        .where((c) => c.status == CampaignStatus.active)
        .length;
    final pending = paged?.items
        .where((c) => c.status == CampaignStatus.pendingApproval)
        .length;

    return AppShell(
      title: 'Campaigns',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHero(
            title: 'Campaigns',
            summary: paged == null
                ? const []
                : [
                    _SummaryStat(label: 'Total', value: paged.total),
                    _SummaryStat(label: 'Active', value: active!),
                    _SummaryStat(label: 'Pending approval', value: pending!),
                  ],
            actions: [
              PermissionGate.disabled(
                Permission.campaignCreate,
                reason: 'Only a Campaign Creator can create a campaign.',
                label: 'Create campaign',
                child: IconButton(
                  tooltip: 'Create campaign',
                  icon: const Icon(Icons.add),
                  onPressed: () => context.go('/campaigns/new'),
                ),
              ),
            ],
          ),
          const SizedBox(height: BmdSpace.s4),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => BmdStateView.error(
                title: "Couldn't load campaigns",
                message: 'Check your connection and try again.',
                onRetry: () =>
                    ref.read(campaignListProvider.notifier).refresh(),
              ),
              data: (paged) => paged.items.isEmpty
                  ? const BmdStateView.empty(
                      title: 'No campaigns in scope',
                      message: 'Create one to get started.',
                    )
                  : BmdDataTable<Campaign>(
                      rows: paged.items,
                      rowId: (c) => c.id,
                      onRowTap: (c) => context.go('/campaigns/${c.id}'),
                      rowDetailTitle: (c) => c.name,
                      rowDetailBuilder: (c) => Builder(
                        builder: (context) {
                          final tone = _toneFor(c.status);
                          final bmd = Theme.of(context).bmd;
                          return Container(
                            padding: const EdgeInsets.only(left: BmdSpace.s3),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: switch (tone) {
                                    StatusTone.success => bmd.success,
                                    StatusTone.warning => bmd.warning,
                                    StatusTone.error => bmd.error,
                                    StatusTone.info => bmd.info,
                                    StatusTone.neutral => bmd.neutral,
                                  },
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StatusChip(
                                  label: c.status.label(l10n),
                                  tone: tone,
                                ),
                                const SizedBox(height: BmdSpace.s3),
                                Text('Target audience: ${c.targetAudience}'),
                                Text(
                                  'Verified attendance: '
                                  '${c.verifiedAttendance}',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      columns: [
                        BmdColumn(
                          id: 'name',
                          label: 'Campaign',
                          priority: BmdColumnPriority.identity,
                          minWidth: 200,
                          flex: 3,
                          cell: (c) => Text(c.name),
                        ),
                        BmdColumn(
                          id: 'status',
                          label: 'Status',
                          priority: BmdColumnPriority.primary,
                          minWidth: 160,
                          cell: (c) => StatusChip(
                            label: c.status.label(l10n),
                            tone: _toneFor(c.status),
                          ),
                        ),
                        BmdColumn(
                          id: 'target',
                          label: 'Target',
                          minWidth: 100,
                          numeric: true,
                          cell: (c) => Text('${c.targetAudience}'),
                        ),
                        BmdColumn(
                          id: 'verified',
                          label: 'Verified',
                          minWidth: 100,
                          numeric: true,
                          cell: (c) => Text('${c.verifiedAttendance}'),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  StatusTone _toneFor(CampaignStatus s) => switch (s) {
    CampaignStatus.approved || CampaignStatus.completed => StatusTone.success,
    CampaignStatus.returned || CampaignStatus.paused => StatusTone.warning,
    CampaignStatus.cancelled => StatusTone.error,
    CampaignStatus.active || CampaignStatus.pendingApproval => StatusTone.info,
    CampaignStatus.draft => StatusTone.neutral,
  };
}

/// A hero-summary stat: count-up number + label, in a quiet pill.
class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BmdSpace.s3,
        vertical: BmdSpace.s1,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: theme.bmd.glassBorder),
        borderRadius: BorderRadius.circular(BmdRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountUp(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontVariations: const [FontVariation('wght', 600)],
            ),
          ),
          const SizedBox(width: BmdSpace.s1),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.bmd.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
