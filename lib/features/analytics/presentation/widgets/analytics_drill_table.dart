import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/bmd_data_table.dart';
import '../../../../core/design_system/status_chip.dart';
import '../../../../domain/analytics/analytics_summary.dart';
import '../../../../domain/common/status.dart';
import '../../../../domain/common/status_labels.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// The analytics drill table (spec RD3.D2): per-campaign target/verified/
/// in-review counts behind the charts above, so any number in the trend,
/// funnel or band-mix zones is always one tap away from the campaign(s)
/// that produced it.
///
/// Status tone follows the SAME mapping `CampaignListScreen._toneFor` uses,
/// copied here rather than imported because that switch is private to its
/// own screen.
class AnalyticsDrillTable extends StatelessWidget {
  const AnalyticsDrillTable({required this.campaigns, super.key});

  final List<AnalyticsCampaignRow> campaigns;

  static StatusTone _toneFor(CampaignStatus s) => switch (s) {
    CampaignStatus.approved || CampaignStatus.completed => StatusTone.success,
    CampaignStatus.returned || CampaignStatus.paused => StatusTone.warning,
    CampaignStatus.cancelled => StatusTone.error,
    CampaignStatus.active || CampaignStatus.pendingApproval => StatusTone.info,
    CampaignStatus.draft => StatusTone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return BmdDataTable<AnalyticsCampaignRow>(
      rows: campaigns,
      rowId: (r) => r.id,
      onRowTap: (r) => context.go('/campaigns/${r.id}'),
      columns: [
        BmdColumn(
          id: 'name',
          label: 'Campaign',
          priority: BmdColumnPriority.identity,
          minWidth: 200,
          flex: 3,
          cell: (r) => Text(r.name),
        ),
        BmdColumn(
          id: 'status',
          label: 'Status',
          priority: BmdColumnPriority.primary,
          minWidth: 160,
          cell: (r) =>
              StatusChip(label: r.status.label(l10n), tone: _toneFor(r.status)),
        ),
        BmdColumn(
          id: 'target',
          label: 'Target',
          minWidth: 100,
          numeric: true,
          cell: (r) => Text('${r.target}'),
        ),
        BmdColumn(
          id: 'verified',
          label: 'Verified',
          minWidth: 100,
          numeric: true,
          cell: (r) => Text('${r.verified}'),
        ),
        BmdColumn(
          id: 'inReview',
          label: 'In review',
          minWidth: 100,
          numeric: true,
          cell: (r) => Text('${r.inReview}'),
        ),
      ],
    );
  }
}
