import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/design_system/bmd_feedback.dart';
import '../../../core/design_system/bmd_state_view.dart';
import '../../../core/motion/reveal.dart';
import '../../../core/motion/shimmer.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../domain/analytics/analytics_summary.dart';
import '../application/analytics_notifier.dart';
import 'widgets/analytics_drill_table.dart';
import 'widgets/analytics_funnel_chart.dart';
import 'widgets/band_mix_chart.dart';
import 'widgets/verification_trend_chart.dart';

/// The analytics dashboard's four data zones (spec RD3.D2/D3/D4): the
/// verification trend, the attendance funnel, the match-band mix, and a
/// per-campaign drill table — composed here so Task 6 mounts a single
/// widget rather than wiring four independently.
///
/// Watches `analyticsSummaryProvider(query)` itself (rather than taking an
/// `AsyncValue` from a parent) so a caller only ever has to supply the
/// query. Every branch is a designed state (Guideline QA checklist §13.2):
/// shimmer while loading, `BmdStateView.error` with retry on failure,
/// `BmdStateView.empty` when there is no attendance at all in range, and
/// only then the four data zones.
class AnalyticsPanel extends ConsumerWidget {
  const AnalyticsPanel({
    required this.query,
    this.showDrillTable = true,
    super.key,
  });

  final AnalyticsQuery query;
  final bool showDrillTable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsSummaryProvider(query));
    return async.when(
      loading: () => const _AnalyticsSkeleton(),
      error: (_, __) => BmdStateView.error(
        title: "Couldn't load analytics",
        message: 'Check your connection and try again.',
        onRetry: () => ref.invalidate(analyticsSummaryProvider(query)),
      ),
      data: (summary) {
        if (summary.funnel.captured == 0) {
          return const BmdStateView.empty(
            title: 'No attendance in this range',
            message: 'Widen the date range or pick another campaign.',
          );
        }
        return _AnalyticsZones(
          summary: summary,
          showDrillTable: showDrillTable,
        );
      },
    );
  }
}

/// The four data zones, stacked with the trend full-width on top and the
/// funnel/band-mix pair below it — side by side on desktop+, stacked below
/// that (mirrors the Dashboard's `_DataVizRow` pattern).
class _AnalyticsZones extends StatelessWidget {
  const _AnalyticsZones({required this.summary, required this.showDrillTable});

  final AnalyticsSummary summary;
  final bool showDrillTable;

  static String _dateLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  /// Rows visible before the table scrolls internally — enough for a quiet
  /// campaign list without letting a very long one push the page out.
  static double _tableHeight(int rowCount) {
    final visibleRows = rowCount.clamp(1, 8);
    return BmdSize.rowHeight * (visibleRows + 1) + 2; // + header + divider
  }

  @override
  Widget build(BuildContext context) {
    final range = summary.range;
    final rangeLabel = '${_dateLabel(range.from)} – ${_dateLabel(range.to)}';

    final trendZone = Semantics(
      identifier: 'analytics_trend',
      child: Reveal(
        index: 0,
        child: VerificationTrendChart(
          perDay: summary.verifiedPerDay,
          from: range.from,
          to: range.to,
          rangeLabel: rangeLabel,
        ),
      ),
    );

    final funnelZone = Semantics(
      identifier: 'analytics_funnel',
      child: Reveal(
        index: 1,
        child: AnalyticsFunnelChart(
          funnel: summary.funnel,
          rangeLabel: rangeLabel,
        ),
      ),
    );

    final bandMixZone = Semantics(
      identifier: 'analytics_band_mix',
      child: Reveal(
        index: 2,
        child: BandMixChart(bandMix: summary.bandMix, rangeLabel: rangeLabel),
      ),
    );

    final vizRow = Breakpoint.of(context).isDesktopUp
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: funnelZone),
              const SizedBox(width: BmdSpace.s6),
              Expanded(child: bandMixZone),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              funnelZone,
              const SizedBox(height: BmdSpace.s6),
              bandMixZone,
            ],
          );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary.sample.small) ...[
            const BmdBanner(
              tone: BannerTone.warning,
              title:
                  'Fewer than 30 attendance records in this range — read '
                  'trends cautiously.',
            ),
            const SizedBox(height: BmdSpace.s4),
          ],
          trendZone,
          const SizedBox(height: BmdSpace.s6),
          vizRow,
          if (showDrillTable) ...[
            const SizedBox(height: BmdSpace.s6),
            Semantics(
              identifier: 'analytics_table',
              child: Reveal(
                index: 3,
                child: SizedBox(
                  height: _tableHeight(summary.campaigns.length),
                  child: AnalyticsDrillTable(campaigns: summary.campaigns),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading state: four blocks shaped like the four zones (Dashboard
/// `_DashboardSkeleton` pattern), so nothing jumps into place when the
/// summary lands.
class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final vizRow = Breakpoint.of(context).isDesktopUp
            ? Row(
                children: [
                  Expanded(child: Shimmer(width: width, height: 260)),
                  const SizedBox(width: BmdSpace.s6),
                  Expanded(child: Shimmer(width: width, height: 260)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Shimmer(width: width, height: 260),
                  const SizedBox(height: BmdSpace.s6),
                  Shimmer(width: width, height: 260),
                ],
              );
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Shimmer(width: width, height: 260),
              const SizedBox(height: BmdSpace.s6),
              vizRow,
              const SizedBox(height: BmdSpace.s6),
              Shimmer(width: width, height: 280),
            ],
          ),
        );
      },
    );
  }
}
