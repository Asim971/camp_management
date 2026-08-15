import 'package:flutter/material.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/design_system/bmd_cards.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../application/dashboard_notifier.dart';

/// Per-KPI defence text (label, formula, source, freshness — Guideline
/// §6.3: no bare numbers). [DashboardKpi] only carries a label and a value —
/// composed purely from existing reads (spec RD.D5) with no separate
/// metadata read — so this is a fixed lookup by the notifier's own labels,
/// with a generic fallback for any future KPI this lookup has not been
/// taught about yet.
({String definition, String source, String freshness}) _metaFor(String label) =>
    switch (label) {
      'Campaigns' => (
        definition: 'All campaigns visible to your organisation.',
        source: 'Campaign service',
        freshness: 'Live',
      ),
      'Active campaigns' => (
        definition: 'Campaigns currently in ACTIVE status.',
        source: 'Campaign service',
        freshness: 'Live',
      ),
      'Verification queue' => (
        definition: 'Attendance records awaiting CRM verification.',
        source: 'Verification queue',
        freshness: 'Live',
      ),
      'Pending sync' => (
        definition: 'Captures on this device waiting to upload.',
        source: 'Offline queue',
        freshness: 'Live (device-local)',
      ),
      _ => (definition: label, source: 'Dashboard', freshness: 'Live'),
    };

/// The Dashboard's at-a-glance metrics (W-01), below the exception strip —
/// never above it (Guideline §8.2). A responsive grid of glass [KpiCard]s,
/// each counting up from zero the same way [CountUp] does.
class KpiGrid extends StatelessWidget {
  const KpiGrid({required this.kpis, super.key});

  final List<DashboardKpi> kpis;

  int _columnsFor(Breakpoint bp) {
    if (bp.isDesktopUp) return 4;
    if (bp.isTabletUp) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final bp = Breakpoint.of(context);
    final columns = _columnsFor(bp);

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: BmdSpace.s4,
      crossAxisSpacing: BmdSpace.s4,
      // Card height is derived from column width by this ratio, so the more
      // columns, the shorter (and narrower) each card. At 4-up desktop widths
      // a card is ~200px wide, which wraps the "<source> · <freshness>"
      // defence line (e.g. "Offline queue · Live (device-local)") onto a
      // second line — content the 1.7 ratio's height could not fit (a 4.5px
      // bottom overflow, caught by dashboard_golden_test). The 4-column case
      // gets a taller card; 1- and 2-up are wide enough that the line stays
      // single and keep their original proportions.
      childAspectRatio: switch (columns) {
        1 => 2.6,
        2 => 1.7,
        _ => 1.5,
      },
      children: [
        for (var i = 0; i < kpis.length; i++) _KpiTile(index: i, kpi: kpis[i]),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.index, required this.kpi});

  final int index;
  final DashboardKpi kpi;

  @override
  Widget build(BuildContext context) {
    final meta = _metaFor(kpi.label);

    return Semantics(
      identifier: 'dashboard_kpi_$index',
      // Same duration/curve/reduced-motion guard as `CountUp`, feeding the
      // animated value into `KpiCard.value` (a plain String) rather than
      // reimplementing it — see `ExceptionStrip` for the same pattern.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: kpi.value.toDouble()),
        duration: reduced(context, MotionDur.slow),
        curve: MotionCurve.emphasized,
        builder: (context, value, _) => KpiCard(
          label: kpi.label,
          value: '${value.round()}',
          definition: meta.definition,
          source: meta.source,
          freshness: meta.freshness,
          glass: true,
        ),
      ),
    );
  }
}
