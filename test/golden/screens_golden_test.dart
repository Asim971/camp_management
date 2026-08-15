import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/domain/analytics/analytics_summary.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/session/campaign_session.dart';
import 'package:acsl_campaign/domain/verification/verification.dart';
import 'package:acsl_campaign/domain/verification/verification_case.dart';
import 'package:acsl_campaign/features/analytics/application/analytics_notifier.dart';
import 'package:acsl_campaign/features/analytics/presentation/analytics_screen.dart';
import 'package:acsl_campaign/features/campaign_detail/application/campaign_detail_controller.dart';
import 'package:acsl_campaign/features/campaign_detail/presentation/campaign_detail_screen.dart';
import 'package:acsl_campaign/features/campaign_list/application/campaign_list_notifier.dart';
import 'package:acsl_campaign/features/campaign_list/presentation/campaign_list_screen.dart';
import 'package:acsl_campaign/features/crm_case/application/crm_case_controller.dart';
import 'package:acsl_campaign/features/crm_case/presentation/crm_case_screen.dart';
import 'package:acsl_campaign/features/verification_queue/application/verification_queue_notifier.dart';
import 'package:acsl_campaign/features/verification_queue/presentation/verification_queue_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:campaign_contracts/campaign_contracts.dart' show QueueFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/golden.dart';
import '../support/harness.dart';

/// Slice-2 screen baselines (Task 7): Verification Queue, CRM Case, Campaign
/// List and Campaign Detail — Linux only (`goldenTest` skips elsewhere; see
/// `test/support/golden.dart`). NOT generated in this task: `--update-goldens`
/// is a no-op on Windows, so these `.png`s must be produced on Linux CI and
/// committed from there (mirrors `test/golden/dashboard_golden_test.dart`).
///
/// Only two of the four viewport×brightness combinations per screen — desktop
/// dark and mobile light — rather than the dashboard's full cross product:
/// eight screens' worth of baselines is already a lot to review, and these
/// two corners exercise both the wide multi-column layouts (CRM case's three
/// zones) and the narrow stacked ones, in both themes, without doubling the
/// file count for marginal extra coverage.
const _variants = <(String suffix, Size size, Brightness brightness)>[
  ('desktop-dark', Size(1280, 2600), Brightness.dark),
  ('mobile-light', Size(390, 2600), Brightness.light),
];

/// Sets the test binding's *physical* view directly (mirrors
/// `dashboard_golden_test.dart`'s `_setViewport`: `setSurfaceSize` does not
/// drive `MediaQuery.sizeOf` on this toolchain, which several widgets size
/// themselves from via `Breakpoint.of`).
void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Queue: three tiles exercising every S1 state — one overdue+escalated
/// (error ramp + glow), one fresh medium unassigned (Claim button), one
/// fresh high assigned-to-me (Release button; harness userId is 'u-1').
class _SeededQueue extends VerificationQueueNotifier {
  @override
  Future<List<VerificationQueueItem>> build(QueueFilter filter) async => [
    VerificationQueueItem(
      attendanceId: 'CASE_OVERDUE',
      carpenterName: 'Md. Karim',
      campaignName: 'ACSL Pilot Carpenter Drive',
      age: const Duration(hours: 25),
      band: MatchBand.low,
      referenceSource: ReferenceSource.verifiedProfilePhoto,
      escalatedAt: DateTime(2026, 8, 14),
    ),
    const VerificationQueueItem(
      attendanceId: 'CASE_FRESH',
      carpenterName: 'Karim Uddin',
      campaignName: 'ACSL Pilot Carpenter Drive',
      age: Duration(hours: 2),
      band: MatchBand.medium,
      referenceSource: ReferenceSource.verifiedProfilePhoto,
    ),
    const VerificationQueueItem(
      attendanceId: 'CASE_MINE',
      carpenterName: 'Rahim Mia',
      campaignName: 'Chattogram Contractor Meet',
      age: Duration(minutes: 40),
      band: MatchBand.high,
      referenceSource: ReferenceSource.authorizedNidPhoto,
      assigneeId: 'u-1',
    ),
  ];
}

/// A CRM case with a machine advisory that pads for review and both evidence
/// images present. `flutter_test` blocks real HTTP, so both `Image.network`
/// calls deterministically render their `errorBuilder` ('Image unavailable')
/// — fine for geometry/spacing baselines.
class _SeededCase extends CrmCaseController {
  @override
  Future<VerificationCase> build(String attendanceId) async => VerificationCase(
    attendanceId: attendanceId,
    version: 1,
    status: AttendanceStatus.crmReview,
    carpenterName: 'Md. Karim',
    carpenterIdMasked: '••••5678',
    campaignName: 'ACSL Pilot Carpenter Drive',
    sessionName: 'Session A',
    capturedAt: DateTime(2026, 8, 13),
    capturedImageUrl: 'https://example.invalid/cap.png',
    referenceImageUrl: 'https://example.invalid/ref.png',
    machine: const MachineResult(
      band: MatchBand.medium,
      referenceSource: ReferenceSource.verifiedProfilePhoto,
      padReview: true,
      reasons: ['Pose differs from reference'],
    ),
  );
}

/// Three campaigns — active/active/pendingApproval — with distinct targets
/// and verified counts so the list's status chips and numeric columns all
/// exercise real data.
class _SeededList extends CampaignListNotifier {
  @override
  Future<Paged<Campaign>> build() async => const Paged(
    items: [
      Campaign(
        id: 'CAMP-1',
        name: 'ACSL Pilot Carpenter Drive',
        type: 'seminar',
        organizationId: 'ORG_1',
        status: CampaignStatus.active,
        ownerId: 'u-1',
        targetAudience: 500,
        verifiedAttendance: 320,
      ),
      Campaign(
        id: 'CAMP-2',
        name: 'Chattogram Contractor Meet',
        type: 'seminar',
        organizationId: 'ORG_1',
        status: CampaignStatus.active,
        ownerId: 'u-1',
        targetAudience: 300,
        verifiedAttendance: 140,
      ),
      Campaign(
        id: 'CAMP-3',
        name: 'Sylhet Mason Outreach',
        type: 'seminar',
        organizationId: 'ORG_1',
        status: CampaignStatus.pendingApproval,
        ownerId: 'u-1',
        targetAudience: 200,
        verifiedAttendance: 0,
      ),
    ],
    total: 3,
  );
}

/// One active, over-capacity session (readiness OK but registered exceeds
/// capacity) and one upcoming session — exercises the Overview KPIs (summed
/// across sessions) and the attendance progress meter in the header.
class _SeededDetail extends CampaignDetailController {
  @override
  Future<CampaignDetailData> build(String campaignId) async =>
      const CampaignDetailData(
        campaign: Campaign(
          id: 'CAMP-1',
          name: 'ACSL Pilot Carpenter Drive',
          type: 'seminar',
          organizationId: 'ORG_1',
          status: CampaignStatus.active,
          ownerId: 'u-1',
          targetAudience: 500,
          verifiedAttendance: 320,
        ),
        sessions: [
          CampaignSession(
            id: 's-1',
            campaignId: 'CAMP-1',
            venue: 'Dhaka Union Hall',
            status: SessionStatus.active,
            capacity: 30,
            registeredCount: 40,
            pendingSyncCount: 5,
            reviewCount: 3,
            approvedCount: 32,
          ),
          CampaignSession(
            id: 's-2',
            campaignId: 'CAMP-1',
            venue: 'Rangpur Community Center',
            status: SessionStatus.upcoming,
            capacity: 50,
            registeredCount: 20,
          ),
        ],
      );
}

/// A fixed 14-day analytics summary (2026-08-02..2026-08-15) — every field
/// hand-picked so the trend, funnel, band-mix and drill table all render
/// non-trivial data. `range` is fixed rather than derived from `DateTime.now`
/// (the only clock read in the feature lives in the repository, upstream of
/// this override) so the baseline never depends on the day the suite runs.
class _SeededAnalytics extends AnalyticsNotifier {
  @override
  Future<AnalyticsSummary> build(AnalyticsQuery query) async =>
      AnalyticsSummary(
        funnel: const AnalyticsFunnel(
          target: 500,
          registered: 320,
          captured: 210,
          inReview: 9,
          approved: 180,
          rejected: 12,
          returned: 6,
        ),
        verifiedPerDay: [
          DailyCount(date: DateTime.utc(2026, 8, 2), count: 0),
          DailyCount(date: DateTime.utc(2026, 8, 3), count: 3),
          DailyCount(date: DateTime.utc(2026, 8, 4), count: 8),
          DailyCount(date: DateTime.utc(2026, 8, 5), count: 5),
          DailyCount(date: DateTime.utc(2026, 8, 6), count: 0),
          DailyCount(date: DateTime.utc(2026, 8, 7), count: 12),
          DailyCount(date: DateTime.utc(2026, 8, 8), count: 14),
          DailyCount(date: DateTime.utc(2026, 8, 9), count: 9),
          DailyCount(date: DateTime.utc(2026, 8, 10), count: 4),
          DailyCount(date: DateTime.utc(2026, 8, 11), count: 0),
          DailyCount(date: DateTime.utc(2026, 8, 12), count: 6),
          DailyCount(date: DateTime.utc(2026, 8, 13), count: 11),
          DailyCount(date: DateTime.utc(2026, 8, 14), count: 7),
          DailyCount(date: DateTime.utc(2026, 8, 15), count: 2),
        ],
        bandMix: const {
          MatchBand.high: 120,
          MatchBand.medium: 60,
          MatchBand.low: 18,
          MatchBand.noReference: 12,
        },
        campaigns: const [
          AnalyticsCampaignRow(
            id: 'CAMP-1',
            name: 'ACSL Pilot Carpenter Drive',
            status: CampaignStatus.active,
            target: 500,
            verified: 320,
            inReview: 9,
          ),
          AnalyticsCampaignRow(
            id: 'CAMP-2',
            name: 'Chattogram Contractor Meet',
            status: CampaignStatus.active,
            target: 300,
            verified: 140,
            inReview: 4,
          ),
          AnalyticsCampaignRow(
            id: 'CAMP-3',
            name: 'Sylhet Mason Outreach',
            status: CampaignStatus.pendingApproval,
            target: 200,
            verified: 0,
            inReview: 0,
          ),
        ],
        sample: const AnalyticsSample(totalAttendance: 210, small: false),
        range: AnalyticsRange(
          from: DateTime.utc(2026, 8, 2),
          to: DateTime.utc(2026, 8, 15),
        ),
        generatedAt: DateTime.utc(2026, 8, 15, 12),
      );
}

final _screens = <String, Widget Function()>{
  'queue': () => const VerificationQueueScreen(),
  'crm_case': () => const CrmCaseScreen(attendanceId: 'CASE_OVERDUE'),
  'campaign_list': () => const CampaignListScreen(),
  'campaign_detail': () => const CampaignDetailScreen(campaignId: 'CAMP-1'),
  'analytics': () => const AnalyticsScreen(),
};

// Family providers are overridden at the family level (no call-argument):
// the old-style (non-codegen) `AsyncNotifierProvider.autoDispose.family`
// element returned by calling the provider with an argument does not itself
// expose `overrideWith` — only the family provider does, and the framework
// still passes the real argument into the seeded notifier's `build` (which
// each seed below ignores in favour of fixed data). Mirrors
// `campaign_detail_expressive_test.dart`'s
// `campaignDetailProvider.overrideWith(() => _SeededController(data))`.
List<Override> _overridesFor(String id) => switch (id) {
  'queue' => [verificationQueueProvider.overrideWith(_SeededQueue.new)],
  'crm_case' => [crmCaseControllerProvider.overrideWith(_SeededCase.new)],
  'campaign_list' => [campaignListProvider.overrideWith(_SeededList.new)],
  'campaign_detail' => [campaignDetailProvider.overrideWith(_SeededDetail.new)],
  'analytics' => [
    analyticsSummaryProvider.overrideWith(_SeededAnalytics.new),
    campaignListProvider.overrideWith(_SeededList.new),
  ],
  _ => throw StateError('unknown screen $id'),
};

/// Permissions are deliberately empty: no `verificationOverride` (hides the
/// queue's Escalated tab and the CRM decision panel's supervisor-override
/// switch — the sync `Switch` in the evidence zone is the only Switch these
/// baselines render).
Widget _host(String id, Brightness brightness) {
  final container = buildTestContainer(
    permissions: const {},
    overrides: _overridesFor(id),
  );

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, __) => _screens[id]!())],
  );
  addTearDown(router.dispose);

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: bmdTheme(brightness: brightness),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  for (final id in _screens.keys) {
    for (final (suffix, size, brightness) in _variants) {
      goldenTest('$id · $suffix', (tester) async {
        _setViewport(tester, size);

        await tester.pumpWidget(_host(id, brightness));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$id-$suffix.png'),
        );
      });
    }
  }
}
