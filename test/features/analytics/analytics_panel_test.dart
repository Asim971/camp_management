import 'package:acsl_campaign/core/design_system/bmd_button.dart';
import 'package:acsl_campaign/domain/analytics/analytics_summary.dart';
import 'package:acsl_campaign/features/analytics/application/analytics_notifier.dart';
import 'package:acsl_campaign/features/analytics/presentation/analytics_panel.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

/// Finds the [Semantics] node carrying a given stable test id (mirrors
/// `dashboard_screen_test.dart`'s identical helper).
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

/// A full, non-empty [AnalyticsSummary] so all four zones actually render
/// instead of the empty state. [captured] and [small] are the two knobs the
/// tests below flip.
AnalyticsSummary _seedSummary({int captured = 60, bool small = false}) =>
    AnalyticsSummary(
      funnel: AnalyticsFunnel(
        target: 100,
        registered: 80,
        captured: captured,
        inReview: 10,
        approved: 40,
        rejected: 5,
        returned: 5,
      ),
      verifiedPerDay: [
        DailyCount(date: DateTime.utc(2026, 8, 10), count: 4),
        DailyCount(date: DateTime.utc(2026, 8, 12), count: 6),
      ],
      bandMix: const {
        MatchBand.high: 30,
        MatchBand.medium: 10,
        MatchBand.low: 0,
        MatchBand.noReference: 0,
      },
      campaigns: const [
        AnalyticsCampaignRow(
          id: 'c1',
          name: 'Winter Carpenter Drive',
          status: CampaignStatus.active,
          target: 100,
          verified: 40,
          inReview: 10,
        ),
      ],
      sample: AnalyticsSample(totalAttendance: captured, small: small),
      range: AnalyticsRange(
        from: DateTime.utc(2026, 8, 1),
        to: DateTime.utc(2026, 8, 15),
      ),
      generatedAt: DateTime.utc(2026, 8, 15, 9),
    );

class _SeededNotifier extends AnalyticsNotifier {
  _SeededNotifier(this.summary);
  final AnalyticsSummary summary;

  @override
  Future<AnalyticsSummary> build(AnalyticsQuery query) async => summary;
}

/// Tracks how many times [build] ran, so the retry test can prove
/// `ref.invalidate` actually triggers a fresh notifier build rather than
/// merely re-rendering the same failed state.
class _RetryCounter {
  int count = 0;
}

class _CountingFailingNotifier extends AnalyticsNotifier {
  _CountingFailingNotifier(this.counter);
  final _RetryCounter counter;

  @override
  Future<AnalyticsSummary> build(AnalyticsQuery query) async {
    counter.count++;
    throw StateError('analytics source unavailable');
  }
}

Widget _host({
  required ProviderContainer container,
  AnalyticsQuery query = const AnalyticsQuery(),
  bool showDrillTable = true,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: AnalyticsPanel(query: query, showDrillTable: showDrillTable),
      ),
      // The OS/web "reduce motion" signal the whole motion system guards on
      // (`motionOff`/`reduced`) — applied below the app's own view-derived
      // MediaQuery, same idiom as `dashboard_reduced_motion_test.dart`.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'analytics_panel: all four zone identifiers render, with the defence '
    'lines for the trend and band-mix charts',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = buildTestContainer(
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _SeededNotifier(_seedSummary()),
          ),
        ],
      );

      await tester.pumpWidget(_host(container: container));
      await tester.pumpAndSettle();

      expect(_byIdentifier('analytics_trend'), findsOneWidget);
      expect(_byIdentifier('analytics_funnel'), findsOneWidget);
      expect(_byIdentifier('analytics_band_mix'), findsOneWidget);
      expect(_byIdentifier('analytics_table'), findsOneWidget);

      expect(
        find.textContaining('Approved attendance per day'),
        findsOneWidget,
      );
      expect(find.textContaining('advisory only'), findsOneWidget);
    },
  );

  testWidgets(
    'analytics_panel: showDrillTable:false hides analytics_table but keeps '
    'the other three zones',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = buildTestContainer(
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _SeededNotifier(_seedSummary()),
          ),
        ],
      );

      await tester.pumpWidget(
        _host(container: container, showDrillTable: false),
      );
      await tester.pumpAndSettle();

      expect(_byIdentifier('analytics_trend'), findsOneWidget);
      expect(_byIdentifier('analytics_funnel'), findsOneWidget);
      expect(_byIdentifier('analytics_band_mix'), findsOneWidget);
      expect(_byIdentifier('analytics_table'), findsNothing);
    },
  );

  // Two independent tests rather than one test mounting two trees: swapping
  // `pumpWidget` trees mid-test unmounts the first tree's autoDispose
  // provider, which merely SCHEDULES its dispose via Riverpod's scheduler
  // (a zero-duration Timer) rather than disposing synchronously —
  // `pumpAndSettle` only drains scheduled FRAMES, not that Timer, so it is
  // still pending at test teardown and trips flutter_test's
  // "Timer still pending" invariant. A single mount per test lets the
  // container's own `addTearDown(container.dispose)` (from
  // `buildTestContainer`) dispose everything synchronously instead.
  const bannerText =
      'Fewer than 30 attendance records in this range — read trends '
      'cautiously.';

  testWidgets(
    'analytics_panel: sample.small shows the small-sample banner copy '
    'verbatim',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = buildTestContainer(
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _SeededNotifier(_seedSummary(small: true)),
          ),
        ],
      );
      await tester.pumpWidget(_host(container: container));
      await tester.pumpAndSettle();
      expect(find.text(bannerText), findsOneWidget);
    },
  );

  testWidgets(
    'analytics_panel: a healthy (non-small) sample hides the banner',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = buildTestContainer(
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _SeededNotifier(_seedSummary()),
          ),
        ],
      );
      await tester.pumpWidget(_host(container: container));
      await tester.pumpAndSettle();
      expect(find.text(bannerText), findsNothing);
    },
  );

  testWidgets(
    'analytics_panel: at a 390px-wide mobile viewport, analytics_table still '
    'resolves with no exception — BmdDataTable can drop every non-identity '
    'column at that width, and its own build-time assertion requires a '
    'rowDetailBuilder so the dropped data stays reachable (regression for '
    'the Linux CI mobile golden that caught the missing one)',
    (tester) async {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = buildTestContainer(
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _SeededNotifier(_seedSummary()),
          ),
        ],
      );

      await tester.pumpWidget(_host(container: container));
      await tester.pumpAndSettle();

      expect(_byIdentifier('analytics_table'), findsOneWidget);
    },
  );

  testWidgets(
    'analytics_panel: funnel.captured == 0 renders the empty state copy, '
    'with no zone identifiers present',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = buildTestContainer(
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _SeededNotifier(_seedSummary(captured: 0)),
          ),
        ],
      );

      await tester.pumpWidget(_host(container: container));
      await tester.pumpAndSettle();

      expect(find.text('No attendance in this range'), findsOneWidget);
      expect(
        find.text('Widen the date range or pick another campaign.'),
        findsOneWidget,
      );
      expect(_byIdentifier('analytics_trend'), findsNothing);
      expect(_byIdentifier('analytics_funnel'), findsNothing);
      expect(_byIdentifier('analytics_band_mix'), findsNothing);
      expect(_byIdentifier('analytics_table'), findsNothing);
    },
  );

  testWidgets(
    'analytics_panel: an AsyncError renders BmdStateView.error, and tapping '
    'Retry invalidates the provider (a fresh notifier build runs)',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final counter = _RetryCounter();
      final container = buildTestContainer(
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _CountingFailingNotifier(counter),
          ),
        ],
      );

      await tester.pumpWidget(_host(container: container));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load analytics"), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(counter.count, 1);

      await tester.tap(find.widgetWithText(BmdButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(
        counter.count,
        2,
        reason: 'Retry must invalidate the provider and trigger a new build',
      );
    },
  );

  testWidgets(
    'analytics_panel: under reduced motion, analytics_trend renders on the '
    'FIRST pump — no pumpAndSettle, no elapsed time',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = buildTestContainer(
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _SeededNotifier(_seedSummary()),
          ),
        ],
      );

      await tester.pumpWidget(_host(container: container));
      await tester.pump();

      expect(_byIdentifier('analytics_trend'), findsOneWidget);
    },
  );
}
