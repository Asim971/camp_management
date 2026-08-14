import 'package:acsl_campaign/core/motion/reveal.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/features/dashboard/application/dashboard_notifier.dart';
import 'package:acsl_campaign/features/dashboard/presentation/dashboard_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/harness.dart';

/// Finds the [Semantics] node carrying a given stable test id (mirrors
/// `dashboard_screen_test.dart`'s identical helper).
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

/// A full, non-empty [DashboardView] so every animated surface this test
/// cares about — the KPI grid's counters and the exception strip's
/// [Reveal]s — actually renders instead of an empty placeholder.
DashboardView _seedView() => const DashboardView(
  exceptions: [
    DashboardException(
      key: 'overdue_verification',
      label: 'Overdue verification',
      count: 3,
      tone: StatusTone.error,
    ),
    DashboardException(
      key: 'escalated',
      label: 'Escalated',
      count: 1,
      tone: StatusTone.warning,
    ),
    DashboardException(
      key: 'suspected_spoof',
      label: 'Suspected spoof',
      count: 0,
      tone: StatusTone.neutral,
    ),
  ],
  kpis: [
    DashboardKpi(label: 'Campaigns', value: 5),
    DashboardKpi(label: 'Verification queue', value: 8),
  ],
  funnel: AttendanceFunnel(
    stages: [('Target audience', 100), ('Verified attendance', 40)],
  ),
  statusBreakdown: CampaignStatusBreakdown(
    byStatus: {CampaignStatus.active: 3, CampaignStatus.draft: 2},
  ),
);

class _SeededDashboardNotifier extends DashboardNotifier {
  @override
  Future<DashboardView> build() async => _seedView();
}

void main() {
  testWidgets(
    'dashboard_screen: under reduced motion, the composed screen shows '
    'final KPI/exception counts and every Reveal at full opacity on the '
    'FIRST frame — no pumpAndSettle, no elapsed time',
    (tester) async {
      final container = buildTestContainer(
        permissions: const {},
        overrides: [
          dashboardProvider.overrideWith(_SeededDashboardNotifier.new),
        ],
      );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
            // The OS/web "reduce motion" signal the whole motion system
            // guards on (`motionOff`/`reduced` in
            // `lib/core/motion/motion_tokens.dart`). Applied inside the
            // router's `builder`, below the app's own view-derived
            // `MediaQuery`, so it actually reaches `DashboardScreen` — an
            // ancestor `MediaQuery` placed outside `MaterialApp.router`
            // would be replaced by the one the app builds from the test
            // view, per Flutter's `WidgetsApp` wiring.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      );

      // Exactly one frame — no `pumpAndSettle`, no advanced duration. This is
      // the whole point of the assertion: reduced motion must hold on the
      // very first paint, not merely "eventually" once every timer/ticker has
      // caught up.
      await tester.pump();

      // The hero renders immediately (no loading/error branch survives).
      expect(_byIdentifier('dashboard_hero'), findsOneWidget);

      // KPI counters: `KpiGrid`'s `TweenAnimationBuilder` (the same
      // duration/curve/reduced-motion guard `CountUp` uses) collapses its
      // duration to zero under reduced motion, which snaps its controller to
      // `completed` synchronously in `initState` — so the FINAL value is
      // already what paints on this very first frame, not merely started
      // from zero.
      final seed = _seedView();
      for (var i = 0; i < seed.kpis.length; i++) {
        final kpi = seed.kpis[i];
        expect(
          find.descendant(
            of: _byIdentifier('dashboard_kpi_$i'),
            matching: find.text('${kpi.value.round()}'),
          ),
          findsOneWidget,
          reason:
              'KPI $i (${kpi.label}) must show its final value '
              '${kpi.value.round()} on the first frame under reduced motion',
        );
      }

      // Exception counts: same guard, same synchronous-completion argument,
      // applied inline in `ExceptionStrip` rather than through `CountUp`.
      for (final exception in seed.exceptions) {
        expect(
          find.descendant(
            of: _byIdentifier('dashboard_exception_${exception.key}'),
            matching: find.text('${exception.count}'),
          ),
          findsOneWidget,
          reason:
              'Exception ${exception.key} must show its final count '
              '${exception.count} on the first frame under reduced motion',
        );
      }

      // No `Reveal` (the exception strip's stagger-in primitive) leaves its
      // child below full opacity: under `motionOff`, `Reveal.build` returns
      // `Opacity(opacity: 1, child: child)` directly rather than an
      // in-flight `fadeIn` — the guardrail this test exists to pin end to
      // end across the composed screen.
      expect(find.byType(Reveal), findsNWidgets(seed.exceptions.length));
      final revealOpacities = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(Reveal),
          matching: find.byType(Opacity),
        ),
      );
      expect(revealOpacities, isNotEmpty);
      for (final opacity in revealOpacities) {
        expect(
          opacity.opacity,
          1.0,
          reason:
              'every Reveal must show its child at full opacity under '
              'reduced motion, not an in-flight fade value',
        );
      }
    },
  );
}
