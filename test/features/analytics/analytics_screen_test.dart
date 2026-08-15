import 'package:acsl_campaign/domain/analytics/analytics_summary.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:acsl_campaign/domain/session/campaign_session.dart';
import 'package:acsl_campaign/features/analytics/application/analytics_notifier.dart';
import 'package:acsl_campaign/features/analytics/presentation/analytics_screen.dart';
import 'package:acsl_campaign/features/campaign_detail/application/campaign_detail_controller.dart';
import 'package:acsl_campaign/features/campaign_detail/presentation/campaign_detail_screen.dart';
import 'package:acsl_campaign/features/campaign_list/application/campaign_list_notifier.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/harness.dart';

/// Task 6: mounting `AnalyticsPanel` at the global `/analytics` screen and on
/// the campaign-detail Analytics tab. Both mounts hold their own
/// [AnalyticsQuery] state and rebuild it through the shared `RangeChipRow`
/// (`analytics_range_d7`/`d30`/`d90`) — the global screen additionally offers
/// a campaign selector (`analytics_campaign_filter`) the detail tab does not
/// need, since its campaign is already fixed by the route.
///
/// Finds the [Semantics] node carrying a given stable test id (mirrors
/// `analytics_panel_test.dart`'s identical helper).
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

/// A full, non-empty [AnalyticsSummary] so all four zones actually render
/// (mirrors `analytics_panel_test.dart`'s `_seedSummary`).
AnalyticsSummary _seedSummary() => AnalyticsSummary(
  funnel: const AnalyticsFunnel(
    target: 100,
    registered: 80,
    captured: 60,
    inReview: 10,
    approved: 40,
    rejected: 5,
    returned: 5,
  ),
  verifiedPerDay: [DailyCount(date: DateTime.utc(2026, 8, 10), count: 4)],
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
  sample: const AnalyticsSample(totalAttendance: 60, small: false),
  range: AnalyticsRange(
    from: DateTime.utc(2026, 8, 1),
    to: DateTime.utc(2026, 8, 15),
  ),
  generatedAt: DateTime.utc(2026, 8, 15, 9),
);

/// A fixed summary for any query — the "whole family" is overridden with
/// this factory, so every distinct [AnalyticsQuery] key gets its own
/// instance of this notifier, all returning the same seeded summary.
class _FixedNotifier extends AnalyticsNotifier {
  _FixedNotifier(this.summary);
  final AnalyticsSummary summary;

  @override
  Future<AnalyticsSummary> build(AnalyticsQuery query) async => summary;
}

/// Records every query any family member was built with, into a list shared
/// across every instance via closure — so re-keying the family (a range or
/// campaign change) is provable from outside.
class _RecordingLog {
  final List<AnalyticsQuery> queriesSeen = [];
}

class _RecordingNotifier extends AnalyticsNotifier {
  _RecordingNotifier(this.log, this.summary);
  final _RecordingLog log;
  final AnalyticsSummary summary;

  @override
  Future<AnalyticsSummary> build(AnalyticsQuery query) async {
    log.queriesSeen.add(query);
    return summary;
  }
}

class _FixedCampaignListNotifier extends CampaignListNotifier {
  _FixedCampaignListNotifier(this._seed);
  final Paged<Campaign> _seed;
  @override
  Future<Paged<Campaign>> build() async => _seed;
}

class _SeededDetailController extends CampaignDetailController {
  _SeededDetailController(this.data);
  final CampaignDetailData data;
  @override
  Future<CampaignDetailData> build(String campaignId) async => data;
}

Campaign _campaign(String id, String name) => Campaign(
  id: id,
  name: name,
  type: 'seminar',
  organizationId: 'ORG_1',
  status: CampaignStatus.active,
  ownerId: 'u-1',
);

Future<void> _pumpAnalyticsScreen(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final container = buildTestContainer(
    permissions: const {},
    overrides: overrides,
  );

  final router = GoRouter(
    initialLocation: '/analytics',
    routes: [
      GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetailScreen(
  WidgetTester tester, {
  required CampaignDetailData data,
  required List<Override> extraOverrides,
}) async {
  final container = buildTestContainer(
    permissions: const {},
    overrides: [
      campaignDetailProvider.overrideWith(() => _SeededDetailController(data)),
      ...extraOverrides,
    ],
  );

  final router = GoRouter(
    initialLocation: '/campaigns/c-1',
    routes: [
      GoRoute(
        path: '/campaigns/:id',
        builder: (_, state) =>
            CampaignDetailScreen(campaignId: state.pathParameters['id']!),
      ),
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '/analytics screen renders the hero title, both chip rows and the panel '
    'zones with a seeded provider',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpAnalyticsScreen(
        tester,
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _FixedNotifier(_seedSummary()),
          ),
          campaignListProvider.overrideWith(
            () => _FixedCampaignListNotifier(
              Paged(
                items: [_campaign('c1', 'Alpha Carpenter Drive')],
                total: 1,
              ),
            ),
          ),
        ],
      );

      expect(find.text('Campaign analytics'), findsWidgets);
      expect(
        find.text('Campaign-linked contribution — activity, not sales impact'),
        findsOneWidget,
      );

      expect(_byIdentifier('analytics_range_d7'), findsOneWidget);
      expect(_byIdentifier('analytics_range_d30'), findsOneWidget);
      expect(_byIdentifier('analytics_range_d90'), findsOneWidget);
      expect(_byIdentifier('analytics_campaign_filter'), findsOneWidget);

      expect(_byIdentifier('analytics_trend'), findsOneWidget);
      expect(_byIdentifier('analytics_funnel'), findsOneWidget);
      expect(_byIdentifier('analytics_band_mix'), findsOneWidget);
      expect(_byIdentifier('analytics_table'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping analytics_range_d7 re-keys the family — the fake records the '
    'second query with range d7',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final log = _RecordingLog();

      await _pumpAnalyticsScreen(
        tester,
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _RecordingNotifier(log, _seedSummary()),
          ),
          campaignListProvider.overrideWith(
            () => _FixedCampaignListNotifier(const Paged(items: [], total: 0)),
          ),
        ],
      );

      expect(log.queriesSeen, [const AnalyticsQuery()]);

      await tester.tap(_byIdentifier('analytics_range_d7'));
      await tester.pumpAndSettle();

      expect(log.queriesSeen.last.range, DateRangePreset.d7);
      expect(
        log.queriesSeen.last.campaignId,
        isNull,
        reason: 'only the range changed — the campaign filter did not',
      );
    },
  );

  testWidgets(
    'the campaign selector lists "All campaigns" + seeded campaign names; '
    'picking one re-keys the family with its id',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final log = _RecordingLog();

      await _pumpAnalyticsScreen(
        tester,
        overrides: [
          analyticsSummaryProvider.overrideWith(
            () => _RecordingNotifier(log, _seedSummary()),
          ),
          campaignListProvider.overrideWith(
            () => _FixedCampaignListNotifier(
              Paged(
                items: [
                  // Deliberately distinct from `_seedSummary()`'s drill-table
                  // row name ('Winter Carpenter Drive') so the selector's
                  // menu item and the drill table's row text can never
                  // collide into an ambiguous `findsOneWidget`.
                  _campaign('c1', 'Alpha Carpenter Drive'),
                  _campaign('c2', 'Beta Outreach'),
                ],
                total: 2,
              ),
            ),
          ),
        ],
      );

      await tester.tap(_byIdentifier('analytics_campaign_filter'));
      await tester.pumpAndSettle();

      expect(find.text('All campaigns'), findsWidgets);
      expect(find.text('Alpha Carpenter Drive'), findsOneWidget);
      expect(find.text('Beta Outreach'), findsOneWidget);

      await tester.tap(find.text('Alpha Carpenter Drive').last);
      await tester.pumpAndSettle();

      expect(log.queriesSeen.last.campaignId, 'c1');
      expect(
        log.queriesSeen.last.range,
        DateRangePreset.d30,
        reason: 'only the campaign changed — the range preset did not',
      );
    },
  );

  testWidgets(
    'detail tab: panel zones render, analytics_table is absent and the '
    'campaign selector is absent',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpDetailScreen(
        tester,
        data: CampaignDetailData(
          campaign: _campaign('c-1', 'ACSL Pilot Carpenter Drive'),
          sessions: const [],
        ),
        extraOverrides: [
          analyticsSummaryProvider.overrideWith(
            () => _FixedNotifier(_seedSummary()),
          ),
        ],
      );

      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();

      expect(_byIdentifier('analytics_range_d7'), findsOneWidget);
      expect(_byIdentifier('analytics_range_d30'), findsOneWidget);
      expect(_byIdentifier('analytics_range_d90'), findsOneWidget);

      expect(_byIdentifier('analytics_trend'), findsOneWidget);
      expect(_byIdentifier('analytics_funnel'), findsOneWidget);
      expect(_byIdentifier('analytics_band_mix'), findsOneWidget);

      expect(
        _byIdentifier('analytics_table'),
        findsNothing,
        reason: 'the detail tab passes showDrillTable: false',
      );
      expect(
        _byIdentifier('analytics_campaign_filter'),
        findsNothing,
        reason: 'the campaign is already fixed by the route',
      );
    },
  );

  testWidgets(
    'frozen contract: session_start still resolves on the Sessions tab '
    'after the Analytics tab is mounted with a real panel',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpDetailScreen(
        tester,
        data: CampaignDetailData(
          campaign: _campaign('c-1', 'ACSL Pilot Carpenter Drive'),
          sessions: const [
            CampaignSession(
              id: 's-1',
              campaignId: 'c-1',
              venue: 'Rangpur union hall',
              status: SessionStatus.upcoming,
            ),
          ],
        ),
        extraOverrides: [
          analyticsSummaryProvider.overrideWith(
            () => _FixedNotifier(_seedSummary()),
          ),
        ],
      );

      await tester.tap(find.text('Sessions'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('session_start'), findsOneWidget);
    },
  );
}
