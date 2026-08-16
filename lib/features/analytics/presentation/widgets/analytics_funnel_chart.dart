import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../domain/analytics/analytics_summary.dart';

/// The analytics funnel zone (spec RD3.D2): attendance progression from
/// campaign target through approved, drawn the same way as the Dashboard's
/// `AttendanceFunnelChart` — a horizontal BarChart via fl_chart's
/// `rotationQuarterTurns: 1` idiom over the ordinal [BmdTokens.funnel] ramp.
///
/// Rejected/returned are NEVER bars here: both are terminal exits from the
/// funnel rather than a step forward through it, so they render as a muted
/// annotation line beneath the chart instead of a bar that would visually
/// claim they belong to the same progression.
class AnalyticsFunnelChart extends StatelessWidget {
  const AnalyticsFunnelChart({
    required this.funnel,
    required this.rangeLabel,
    super.key,
  });

  final AnalyticsFunnel funnel;
  final String rangeLabel;

  List<(String, int)> get _stages => [
    ('Target', funnel.target),
    ('Registered', funnel.registered),
    ('Captured', funnel.captured),
    ('In review', funnel.inReview),
    ('Approved', funnel.approved),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final stages = _stages;
    final maxValue = stages.fold<int>(0, (m, s) => s.$2 > m ? s.$2 : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attendance funnel', style: theme.textTheme.titleMedium),
        const SizedBox(height: BmdSpace.s3),
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              rotationQuarterTurns: 1,
              alignment: BarChartAlignment.spaceAround,
              maxY: maxValue == 0 ? 1 : maxValue * 1.15,
              barTouchData: BarTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(
                        '${stages[group.x].$1}\n${rod.toY.round()}',
                        theme.textTheme.bodySmall!.copyWith(
                          color: Colors.white,
                        ),
                      ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 96,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= stages.length) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: SizedBox(
                          width: 88,
                          child: Text(
                            stages[i].$1,
                            style: theme.textTheme.labelSmall,
                            softWrap: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < stages.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: stages[i].$2.toDouble(),
                        color: bmd.funnel[i % bmd.funnel.length],
                        width: 18,
                        borderRadius: BorderRadius.circular(BmdRadius.chip),
                      ),
                    ],
                  ),
              ],
            ),
            duration: reduced(context, MotionDur.slow),
          ),
        ),
        const SizedBox(height: BmdSpace.s2),
        Text(
          'Rejected ${funnel.rejected} · Returned ${funnel.returned}',
          style: theme.textTheme.bodySmall?.copyWith(color: bmd.textSecondary),
        ),
        const SizedBox(height: BmdSpace.s1),
        Text(
          'Attendance progression · Campaign service · $rangeLabel '
          '(target/registered are campaign totals)',
          style: theme.textTheme.bodySmall?.copyWith(color: bmd.textSecondary),
        ),
      ],
    );
  }
}
