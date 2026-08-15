import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../domain/analytics/analytics_summary.dart';

/// §8.15 centerpiece: approved attendance per day as an accent-cyan line
/// with a soft under-fill. Days without approvals render as zero (the wire
/// omits them). Sweep-in via TweenAnimationBuilder clipping the chart
/// horizontally 0→1 (reduced-motion: full line first frame — reduced()
/// collapses the duration and TweenAnimationBuilder snaps, same note as
/// CountUp).
class VerificationTrendChart extends StatelessWidget {
  const VerificationTrendChart({
    required this.perDay,
    required this.from,
    required this.to,
    required this.rangeLabel,
    super.key,
  });

  // from/to come from summary.range (the server's echoed resolved dates) —
  // NEVER from DateTime.now(); rangeLabel from the panel, e.g.
  // '01/08 – 15/08' built from the same echoed dates.
  final List<DailyCount> perDay;
  final DateTime from;
  final DateTime to;
  final String rangeLabel;

  List<FlSpot> _spots() {
    final byDay = {
      for (final d in perDay)
        DateTime.utc(d.date.year, d.date.month, d.date.day): d.count,
    };
    final days = to.difference(from).inDays + 1;
    return [
      for (var i = 0; i < days; i++)
        FlSpot(
          i.toDouble(),
          (byDay[DateTime.utc(
                    from.year,
                    from.month,
                    from.day,
                  ).add(Duration(days: i))] ??
                  0)
              .toDouble(),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final spots = _spots();
    final maxY = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verification trend', style: theme.textTheme.titleMedium),
        const SizedBox(height: BmdSpace.s3),
        SizedBox(
          height: 240,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: reduced(context, MotionDur.slow),
            curve: MotionCurve.emphasized,
            builder: (context, t, child) => ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                stops: [0, t, t],
                colors: const [Colors.white, Colors.white, Colors.transparent],
              ).createShader(rect),
              child: child,
            ),
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY == 0 ? 1 : maxY * 1.2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: theme.dividerColor, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (spots.length / 4).ceilToDouble(),
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          _dayLabel(from.add(Duration(days: v.toInt()))),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: bmd.accent,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          bmd.accent.withValues(alpha: 0.25),
                          bmd.accent.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: BmdSpace.s1),
        Text(
          'Approved attendance per day · Campaign service · $rangeLabel',
          style: theme.textTheme.bodySmall?.copyWith(color: bmd.textSecondary),
        ),
      ],
    );
  }

  String _dayLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
