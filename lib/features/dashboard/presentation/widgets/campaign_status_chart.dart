import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../domain/common/status_labels.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../application/dashboard_notifier.dart';

/// The Dashboard's campaign-status breakdown (W-01 data-viz row): a pie
/// chart coloured from the validated categorical [BmdTokens.series] palette,
/// assigned by each [CampaignStatus]'s FIXED enum position — never
/// re-ordered by count, so a given status always draws the same colour
/// across every render.
///
/// [BmdTokens.series]'s own doc warns several slots sit under the 3:1
/// contrast floor against their surface, "legal ONLY because every chart
/// ships visible direct labels and a table view" — the legend below the pie
/// is that direct-label/table pairing, not decoration.
class CampaignStatusChart extends StatelessWidget {
  const CampaignStatusChart({required this.breakdown, super.key});

  final CampaignStatusBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final l10n = AppL10n.of(context);

    final entries = [
      for (final status in CampaignStatus.values)
        if ((breakdown.byStatus[status] ?? 0) > 0)
          (status, breakdown.byStatus[status]!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Campaign status', style: theme.textTheme.titleMedium),
        const SizedBox(height: BmdSpace.s3),
        if (entries.isEmpty)
          Text('No campaigns yet.', style: theme.textTheme.bodyMedium)
        else ...[
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: [
                  for (final (status, count) in entries)
                    PieChartSectionData(
                      value: count.toDouble(),
                      color: bmd.seriesAt(status.index),
                      title: '$count',
                      titleStyle: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                      ),
                      radius: 56,
                    ),
                ],
              ),
              duration: reduced(context, MotionDur.slow),
            ),
          ),
          const SizedBox(height: BmdSpace.s3),
          // The direct-label legend the palette's contrast waiver requires
          // (see class doc) — also a screen-reader-visible alternative to
          // the canvas-painted slices above.
          Wrap(
            spacing: BmdSpace.s4,
            runSpacing: BmdSpace.s2,
            children: [
              for (final (status, count) in entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: bmd.seriesAt(status.index),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: BmdSpace.s2),
                    Text(
                      '${status.label(l10n)} · $count',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
