import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/design_system/bmd_cards.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/session/campaign_session.dart';
import 'package:acsl_campaign/features/campaign_detail/application/campaign_detail_controller.dart';
import 'package:acsl_campaign/features/campaign_detail/presentation/campaign_detail_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/harness.dart';

/// Slice 2 RD2.D7 — the campaign-detail header becomes a [ScreenHero] with an
/// S4 attendance progress meter, and the Overview tab's KPIs become glass
/// [KpiCard]s. These tests pin the NEW structure; the existing header/session
/// test files in this directory pin narrow-width layout, status-label
/// localisation and frozen session-op identifiers and are left unmodified.
class _SeededController extends CampaignDetailController {
  _SeededController(this.data);
  final CampaignDetailData data;

  @override
  Future<CampaignDetailData> build(String campaignId) async => data;
}

Campaign _campaign({
  required int targetAudience,
  required int verifiedAttendance,
}) => Campaign(
  id: 'c-1',
  name: 'Boro season seminar',
  type: 'seminar',
  organizationId: 'ORG_1',
  status: CampaignStatus.active,
  ownerId: 'u-1',
  targetAudience: targetAudience,
  verifiedAttendance: verifiedAttendance,
);

Future<void> _pump(
  WidgetTester tester,
  CampaignDetailData data, {
  Set<Permission>? permissions,
}) async {
  final container = buildTestContainer(
    permissions: permissions ?? const {},
    overrides: [
      campaignDetailProvider.overrideWith(() => _SeededController(data)),
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
        // The meter and KPI values animate via TweenAnimationBuilder;
        // disabling animations makes them snap to their final value on the
        // first frame (see CountUp's note on TweenAnimationBuilder and zero
        // durations), so a plain pumpAndSettle sees the real numbers.
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
  testWidgets('S4: meter renders the defence line and clamps', (tester) async {
    await _pump(
      tester,
      CampaignDetailData(
        campaign: _campaign(targetAudience: 500, verifiedAttendance: 320),
        sessions: const [],
      ),
    );

    expect(find.text('320 of 500 verified'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.64, 0.001));
  });

  testWidgets('S4: zero target renders "No target set" and an empty track', (
    tester,
  ) async {
    await _pump(
      tester,
      CampaignDetailData(
        campaign: _campaign(targetAudience: 0, verifiedAttendance: 0),
        sessions: const [],
      ),
    );

    expect(find.text('No target set'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.0);
  });

  testWidgets('S4: overview KPIs are glass KpiCards with defence lines', (
    tester,
  ) async {
    await _pump(
      tester,
      CampaignDetailData(
        campaign: _campaign(targetAudience: 100, verifiedAttendance: 10),
        sessions: const [
          CampaignSession(
            id: 's-1',
            campaignId: 'c-1',
            venue: 'Rangpur union hall',
            status: SessionStatus.upcoming,
            registeredCount: 45,
          ),
        ],
      ),
    );

    expect(find.byType(KpiCard), findsNWidgets(4));
    expect(find.text('REGISTERED'), findsOneWidget); // KpiCard uppercases
    expect(find.textContaining('Campaign service'), findsWidgets);
  });

  testWidgets('frozen session-op identifiers survive', (tester) async {
    await _pump(
      tester,
      CampaignDetailData(
        campaign: _campaign(targetAudience: 100, verifiedAttendance: 10),
        sessions: const [
          CampaignSession(
            id: 's-1',
            campaignId: 'c-1',
            venue: 'Rangpur union hall',
            status: SessionStatus.upcoming,
          ),
        ],
      ),
    );

    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('session_start'), findsOneWidget);
  });
}
