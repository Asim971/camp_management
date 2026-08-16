import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/motion/motion_tokens.dart';

/// The band-mix donut (spec RD3.D2): the machine's advisory match-confidence
/// distribution for attendance in range, coloured from the validated
/// categorical [BmdTokens.series] palette assigned by [MatchBand]'s FIXED
/// enum position — mirrors `CampaignStatusChart`'s rule that a series colour
/// never depends on count, only on identity. Zero-count bands are never
/// drawn: a wedge with no area would only crowd the direct-label legend
/// below the pie.
class BandMixChart extends StatelessWidget {
  const BandMixChart({
    required this.bandMix,
    required this.rangeLabel,
    super.key,
  });

  final Map<MatchBand, int> bandMix;
  final String rangeLabel;

  static String _label(MatchBand b) => switch (b) {
    MatchBand.high => 'High',
    MatchBand.medium => 'Medium',
    MatchBand.low => 'Low',
    MatchBand.noReference => 'No reference',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;

    final entries = [
      for (final band in MatchBand.values)
        if ((bandMix[band] ?? 0) > 0) (band, bandMix[band]!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Match band mix', style: theme.textTheme.titleMedium),
        const SizedBox(height: BmdSpace.s3),
        if (entries.isEmpty)
          Text('No matched attendance yet.', style: theme.textTheme.bodyMedium)
        else ...[
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: [
                  for (final (band, count) in entries)
                    PieChartSectionData(
                      value: count.toDouble(),
                      color: bmd.seriesAt(band.index),
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
          // (see `campaign_status_chart.dart`'s identical note) — also a
          // screen-reader-visible alternative to the canvas-painted slices.
          Wrap(
            spacing: BmdSpace.s4,
            runSpacing: BmdSpace.s2,
            children: [
              for (final (band, count) in entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: bmd.seriesAt(band.index),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: BmdSpace.s2),
                    Text(
                      '${_label(band)} · $count',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: BmdSpace.s1),
        Text(
          'Machine match bands · advisory only · $rangeLabel',
          style: theme.textTheme.bodySmall?.copyWith(color: bmd.textSecondary),
        ),
      ],
    );
  }
}
