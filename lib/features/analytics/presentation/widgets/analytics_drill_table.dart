import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/tokens.dart';
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
    // Resolved once here rather than inside the cell/rowDetail closures:
    // those are invoked later by BmdDataTable and, for the row detail, from
    // inside a side-sheet route whose own context sits under a different
    // Navigator (mirrors `campaign_list_screen.dart`'s identical note).
    final l10n = AppL10n.of(context);
    return BmdDataTable<AnalyticsCampaignRow>(
      rows: campaigns,
      rowId: (r) => r.id,
      onRowTap: (r) => context.go('/campaigns/${r.id}'),
      // Every column below can be dropped at a narrow width (only `name` is
      // `identity`) — `rowDetailBuilder` is what BmdDataTable's own
      // assertion requires so that data stays reachable instead of silently
      // disappearing (bmd_data_table.dart's `_visible`/build-time assert).
      rowDetailTitle: (r) => r.name,
      rowDetailBuilder: (r) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusChip(label: r.status.label(l10n), tone: _toneFor(r.status)),
          const SizedBox(height: BmdSpace.s3),
          Text('Target: ${r.target}'),
          Text('Verified: ${r.verified}'),
          Text('In review: ${r.inReview}'),
        ],
      ),
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
