import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../application/dashboard_notifier.dart';

/// The Dashboard's attendance funnel (W-01 data-viz row), drawn as a
/// horizontal bar chart via fl_chart's `rotationQuarterTurns: 1` — the
/// package's documented technique for horizontal bars: vertical bars rotated
/// 90° clockwise, with the axis titles counter-rotated automatically so they
/// stay upright (see the package's `BarChartSample7`).
///
/// [BmdTokens.funnel] is an ORDINAL ramp — one hue, monotone lightness — so
/// stage `i` always draws `bmd.funnel[i]`; the sequence itself carries the
/// meaning, never re-sorted by count.
class AttendanceFunnelChart extends StatelessWidget {
  const AttendanceFunnelChart({required this.funnel, super.key});

  final AttendanceFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final stages = funnel.stages;
    final maxValue = stages.fold<int>(0, (m, s) => s.$2 > m ? s.$2 : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attendance funnel', style: theme.textTheme.titleMedium),
        const SizedBox(height: BmdSpace.s3),
        SizedBox(
          height: 240,
          child: stages.isEmpty
              ? Center(
                  child: Text(
                    'No funnel data yet.',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : BarChart(
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
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                        ),
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
                              borderRadius: BorderRadius.circular(
                                BmdRadius.chip,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  duration: reduced(context, MotionDur.slow),
                ),
        ),
      ],
    );
  }
}
