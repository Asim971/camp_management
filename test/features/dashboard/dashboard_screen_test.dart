import 'dart:async';

import 'package:acsl_campaign/core/design_system/bmd_button.dart';
import 'package:acsl_campaign/core/motion/shimmer.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/features/dashboard/application/dashboard_notifier.dart';
import 'package:acsl_campaign/features/dashboard/presentation/dashboard_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/harness.dart';

/// Finds the [Semantics] node carrying a given stable test id — the same
/// `Semantics(identifier: …)` convention Maestro flows key off (mirrors
/// `test/widget/verification_queue_screen_test.dart`'s `_byIdentifier`).
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

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

/// Never resolves — pins the dashboard's `loading` branch (shimmer) without
/// racing a real Future (mirrors the pattern noted in
/// `test/golden/gallery_golden_test.dart` for another animation that never
/// settles: don't `pumpAndSettle`, just `pump()` once).
class _LoadingDashboardNotifier extends DashboardNotifier {
  @override
  Future<DashboardView> build() => Completer<DashboardView>().future;
}

class _SeededDashboardNotifier extends DashboardNotifier {
  @override
  Future<DashboardView> build() async => _seedView();
}

class _FailingDashboardNotifier extends DashboardNotifier {
  @override
  Future<DashboardView> build() async =>
      throw StateError('dashboard source unavailable');
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required DashboardNotifier Function() notifier,
}) async {
  final container = buildTestContainer(
    permissions: const {},
    overrides: [dashboardProvider.overrideWith(notifier)],
  );

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, __) => const DashboardScreen())],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        // Required since Task 6b: CampaignStatusChart resolves its status
        // labels through AppL10n, which throws without the delegate
        // registered (see `campaign_list_screen_test.dart`'s identical note).
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
        // Shimmer's shimmer sweep repeats forever (`controller.repeat()`)
        // and never settles — freezing every ticker under here (mirrors
        // `gallery_golden_test.dart`'s identical note for the loading
        // BmdButton's indeterminate spinner) keeps `pumpAndSettle` finite
        // and avoids a "Timer still pending at teardown" failure from the
        // `loading` case. It does not affect any assertion below: none of
        // them reads a mid-animation numeric value, only widget presence,
        // style and position.
        builder: (context, child) => TickerMode(enabled: false, child: child!),
      ),
    ),
  );
}

void main() {
  testWidgets('dashboard_screen: loading renders Shimmer skeletons, not the '
      'real content', (tester) async {
    await _pumpDashboard(tester, notifier: _LoadingDashboardNotifier.new);
    // Not pumpAndSettle: Shimmer's shimmer sweep repeats forever. A bare
    // `pump()` (no duration) never advances the fake clock, so
    // flutter_animate's own `Future.delayed(Duration.zero, _play)` — a real
    // (fake-clock) Timer created in `Animate`'s initState — would never
    // fire and the framework's teardown invariant check ("Timer still
    // pending") would fail even though the repeat itself never schedules a
    // background Timer under `AutomatedTestWidgetsFlutterBinding` (ticking
    // there only advances on an explicit pump). Passing an explicit
    // `Duration.zero` DOES elapse the fake clock, which flushes it.
    await tester.pump(Duration.zero);

    expect(find.byType(Shimmer), findsWidgets);
    expect(_byIdentifier('dashboard_hero'), findsNothing);
  });

  testWidgets('dashboard_screen: data renders the hero (displayHero text + '
      'dashboard_cta), every exception, and every KPI — with the exception '
      'strip ABOVE the KPI grid (exception-first, Guideline §8.2)', (
    tester,
  ) async {
    await _pumpDashboard(tester, notifier: _SeededDashboardNotifier.new);
    await tester.pumpAndSettle();

    final hero = _byIdentifier('dashboard_hero');
    expect(hero, findsOneWidget);
    expect(_byIdentifier('dashboard_cta'), findsOneWidget);

    // The hero headline uses the shared `context.displayHero` style — the
    // 800-weight, 72px Inter display role (bmd_theme.dart).
    expect(
      find.descendant(
        of: hero,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.style?.fontSize == 72 &&
              w.style?.fontWeight == FontWeight.w800,
        ),
      ),
      findsOneWidget,
    );

    expect(
      _byIdentifier('dashboard_exception_overdue_verification'),
      findsOneWidget,
    );
    expect(_byIdentifier('dashboard_exception_escalated'), findsOneWidget);
    // Present even at a zero count — the taxonomy never reshuffles.
    expect(
      _byIdentifier('dashboard_exception_suspected_spoof'),
      findsOneWidget,
    );

    expect(_byIdentifier('dashboard_kpi_0'), findsOneWidget);
    expect(_byIdentifier('dashboard_kpi_1'), findsOneWidget);

    // Exception-first: the strip sits ABOVE the KPI grid in vertical
    // position, not merely earlier in some unordered widget list.
    final exceptionY = tester
        .getTopLeft(_byIdentifier('dashboard_exception_overdue_verification'))
        .dy;
    final kpiY = tester.getTopLeft(_byIdentifier('dashboard_kpi_0')).dy;
    expect(
      exceptionY,
      lessThan(kpiY),
      reason: 'the exception strip must render above the KPI grid',
    );
  });

  testWidgets(
    'dashboard_screen: an AsyncError renders the designed error state with '
    'a retry action, not a bare error or a blank screen',
    (tester) async {
      await _pumpDashboard(tester, notifier: _FailingDashboardNotifier.new);
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't load the dashboard"),
        findsOneWidget,
      );
      expect(find.widgetWithText(BmdButton, 'Retry'), findsOneWidget);
      expect(_byIdentifier('dashboard_hero'), findsNothing);
    },
  );
}
