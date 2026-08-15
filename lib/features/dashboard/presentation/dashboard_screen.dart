import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/providers.dart';
import '../../../app/shell/app_shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_feedback.dart';
import '../../../core/motion/shimmer.dart';
import '../../../core/responsive/breakpoints.dart';
import '../application/dashboard_notifier.dart';
import 'widgets/attendance_funnel_chart.dart';
import 'widgets/campaign_status_chart.dart';
import 'widgets/exception_strip.dart';
import 'widgets/hero_header.dart';
import 'widgets/kpi_grid.dart';

/// Campaign Dashboard (W-01) — the expressive-redesign showpiece, and the
/// operator's front door.
///
/// Composed top-to-bottom (Guideline §8.2 exception-first, never reordered):
/// the hero header and its single CTA, the exception strip (what is stuck,
/// ALWAYS before any total), the KPI grid, then the funnel/status
/// data-viz row. Every source is an existing read composed client-side
/// (spec RD.D5) — see `dashboard_notifier.dart` for the exact composition
/// and its documented gaps.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    final auth = ref.watch(authStateProvider);
    final displayName = switch (auth) {
      AuthSignedIn(:final session) => session.displayName,
      _ => null,
    };
    final contextLine = displayName == null
        ? 'Your campaigns, verification queue and sync status at a glance.'
        : 'Signed in as $displayName · campaigns, verification and sync at '
              'a glance.';

    return AppShell(
      title: 'Dashboard',
      body: async.when(
        loading: () => const _DashboardSkeleton(),
        error: (_, __) =>
            _ErrorState(onRetry: () => ref.invalidate(dashboardProvider)),
        data: (view) => SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: BmdSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeroHeader(
                greeting: 'Campaign Dashboard',
                contextLine: contextLine,
                ctaLabel: 'Open verification queue',
                onCta: () => context.go('/verification'),
              ),
              const SizedBox(height: BmdSpace.s6),
              ExceptionStrip(exceptions: view.exceptions),
              const SizedBox(height: BmdSpace.s6),
              KpiGrid(kpis: view.kpis),
              const SizedBox(height: BmdSpace.s6),
              _DataVizRow(
                funnel: view.funnel,
                statusBreakdown: view.statusBreakdown,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The funnel and status charts, side by side on desktop+ and stacked below
/// that (Breakpoint per the existing responsive layer).
class _DataVizRow extends StatelessWidget {
  const _DataVizRow({required this.funnel, required this.statusBreakdown});

  final AttendanceFunnel funnel;
  final CampaignStatusBreakdown statusBreakdown;

  @override
  Widget build(BuildContext context) {
    final funnelChart = AttendanceFunnelChart(funnel: funnel);
    final statusChart = CampaignStatusChart(breakdown: statusBreakdown);

    if (Breakpoint.of(context).isDesktopUp) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: funnelChart),
          const SizedBox(width: BmdSpace.s6),
          Expanded(child: statusChart),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        funnelChart,
        const SizedBox(height: BmdSpace.s6),
        statusChart,
      ],
    );
  }
}

/// Loading state: a skeleton shaped like the real layout (hero, exception
/// strip, KPI grid, data-viz row) rather than a bare spinner, so nothing
/// jumps when the data lands.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Shimmer(width: width, height: 220),
              const SizedBox(height: BmdSpace.s6),
              SizedBox(
                height: 216,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 5,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: BmdSpace.s3),
                  itemBuilder: (_, __) =>
                      const Shimmer(width: 260, height: 216),
                ),
              ),
              const SizedBox(height: BmdSpace.s6),
              Wrap(
                spacing: BmdSpace.s4,
                runSpacing: BmdSpace.s4,
                children: List.generate(
                  4,
                  (_) => const Shimmer(width: 260, height: 140),
                ),
              ),
              const SizedBox(height: BmdSpace.s6),
              Shimmer(width: width, height: 260),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => BmdState.error(
    title: "Couldn't load the dashboard",
    body:
        'The campaign, verification and sync summaries could not be '
        'loaded. Check your connection and try again.',
    action: BmdButton(
      variant: BmdButtonVariant.outlined,
      label: 'Retry',
      onPressed: onRetry,
    ),
  );
}
