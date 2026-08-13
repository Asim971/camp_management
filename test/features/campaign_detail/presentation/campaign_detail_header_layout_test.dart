import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/features/campaign_detail/application/campaign_detail_controller.dart';
import 'package:acsl_campaign/features/campaign_detail/presentation/campaign_detail_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/harness.dart';

/// 2b's second header button ("Bulk import", next to "Add registrations")
/// pushed the header `Row`'s non-flexible children (StatusChip + two buttons
/// + spacers) past a narrow CI-emulator viewport (~320-360dp), clamping the
/// `Expanded(name)` to near-zero width. That renders the campaign name one
/// letter per line and overflows the Row horizontally (plus a pre-existing
/// bottom overflow) — which is why three e2e flows (realAuth, registration,
/// bulkImport) failed their `.*ACSL Pilot Carpenter Drive.*` assertion on
/// this screen: the title text node was fragmented into single-letter nodes.
///
/// Seeds an APPROVED campaign so BOTH contextual actions render (that is the
/// combination that overflowed) and pumps at a 320px logical width — the same
/// `tester.view.physicalSize`/`devicePixelRatio` idiom
/// registration_workspace_screen_test.dart uses to force a narrow layout.
class _ApprovedDetailController extends CampaignDetailController {
  @override
  Future<CampaignDetailData> build(String campaignId) async =>
      const CampaignDetailData(
        campaign: Campaign(
          id: 'c-1',
          name: 'ACSL Pilot Carpenter Drive',
          type: 'seminar',
          organizationId: 'ORG_1',
          status: CampaignStatus.approved,
          ownerId: 'u-1',
        ),
        sessions: [],
      );
}

void main() {
  testWidgets(
    'campaign name renders as one findable text node, and both action '
    'buttons are present, with no RenderFlex overflow at a 320px-wide '
    'viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = buildTestContainer(
        permissions: {Permission.campaignCreate, Permission.bulkImport},
        overrides: [
          campaignDetailProvider.overrideWith(_ApprovedDetailController.new),
        ],
      );

      final router = GoRouter(
        initialLocation: '/campaigns/c-1',
        routes: [
          GoRoute(
            path: '/campaigns/:id',
            builder: (_, state) =>
                CampaignDetailScreen(campaignId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'register',
                builder: (_, __) => const Placeholder(),
              ),
              GoRoute(path: 'import', builder: (_, __) => const Placeholder()),
            ],
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
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No RenderFlex overflow anywhere in the header (or elsewhere).
      expect(tester.takeException(), isNull);

      // The full name as ONE text node — not fragmented letter-by-letter.
      expect(
        find.text('ACSL Pilot Carpenter Drive'),
        findsOneWidget,
        reason:
            'the name must stay a single Text widget even at 320px; a '
            'clamped Expanded wraps it one letter per line instead',
      );

      // Both contextual actions for an approved campaign still render.
      expect(find.text('Add registrations'), findsOneWidget);
      expect(find.text('Bulk import'), findsOneWidget);
    },
  );
}
