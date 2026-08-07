import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/permission_gate.dart';
import '../../../core/auth/rbac.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_data_table.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../domain/campaign/campaign.dart';
import '../../../domain/common/status.dart';
import '../application/campaign_list_notifier.dart';

/// Campaign List (W-02). Exemplar wiring an AsyncNotifier to the design system.
/// Every AsyncValue branch is a designed state — never a bare spinner or a
/// silent empty screen (Guideline QA checklist §13.2).
class CampaignListScreen extends ConsumerWidget {
  const CampaignListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(campaignListProvider);

    return AppShell(
      title: 'Campaigns',
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
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorState(
          onRetry: () => ref.read(campaignListProvider.notifier).refresh(),
        ),
        data: (paged) => paged.items.isEmpty
            ? const _EmptyState()
            : BmdDataTable<Campaign>(
                rows: paged.items,
                rowId: (c) => c.id,
                onRowTap: (c) => context.go('/campaigns/${c.id}'),
                rowDetailTitle: (c) => c.name,
                rowDetailBuilder: (c) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(label: c.status.name, tone: _toneFor(c.status)),
                    const SizedBox(height: BmdSpace.s3),
                    Text('Target audience: ${c.targetAudience}'),
                    Text('Verified attendance: ${c.verifiedAttendance}'),
                  ],
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
                      label: c.status.name,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Text('No campaigns in scope. Create one to get started.'),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("Couldn't load campaigns."),
        const SizedBox(height: 8),
        BmdButton(
          variant: BmdButtonVariant.outlined,
          label: 'Retry',
          onPressed: onRetry,
        ),
      ],
    ),
  );
}
