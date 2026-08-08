import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
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

/// Task 6b, second half. The campaign detail screen renders TWO status chips
/// from two different enum families, and one of them — [SessionStatus] — had no
/// ARB keys and no `label` extension at all until this task added the sixth
/// family. Without it this screen would still show "captureClosed" beside a
/// header reading "Pending approval".
///
/// The header chip is a [StatelessWidget]'s own `build`, and so is the session
/// card's, so both resolve `AppL10n.of(context)` directly; nothing needed a
/// context threaded through a constructor.
class _FixedDetailController extends CampaignDetailController {
  @override
  Future<CampaignDetailData> build(
    String campaignId,
  ) async => const CampaignDetailData(
    campaign: Campaign(
      id: 'c-1',
      name: 'Boro season seminar',
      type: 'seminar',
      organizationId: 'ORG_1',
      status: CampaignStatus.pendingApproval,
      ownerId: 'u-1',
    ),
    sessions: [
      // captureClosed deliberately: it is the one SessionStatus value whose
      // Bengali is unique to this family (active/paused/completed correctly
      // share theirs with CampaignStatus), and it renders no action buttons,
      // so the chip is the only thing under test.
      CampaignSession(
        id: 's-1',
        campaignId: 'c-1',
        venue: 'Rangpur union hall',
        status: SessionStatus.captureClosed,
      ),
    ],
  );
}

void main() {
  Future<void> pump(WidgetTester tester, Locale locale) async {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWithValue(
          AuthSignedIn(
            Session(
              userId: 'u-1',
              displayName: 'Test User',
              scope: const AccessScope(
                roles: {AppRole.fieldUser},
                permissions: {Permission.campaignApprove},
                organizationId: 'ORG_1',
              ),
              accessToken: 'a',
              refreshToken: 'r',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          ),
        ),
        campaignDetailProvider.overrideWith(_FixedDetailController.new),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/campaigns/c-1',
      routes: [
        GoRoute(
          path: '/campaigns/:id',
          builder: (_, state) =>
              CampaignDetailScreen(campaignId: state.pathParameters['id']!),
          routes: [
            GoRoute(path: 'approve', builder: (_, __) => const Placeholder()),
            GoRoute(path: 'register', builder: (_, __) => const Placeholder()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: locale,
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the header chip renders Bengali, not "pendingApproval"', (
    tester,
  ) async {
    await pump(tester, const Locale('bn'));

    expect(find.text('অনুমোদনের অপেক্ষায়'), findsOneWidget);
    expect(find.text('Pending approval'), findsNothing);
    expect(
      find.text('pendingApproval'),
      findsNothing,
      reason: 'the raw identifier the brief names as the worst offender',
    );
  });

  testWidgets('the session chip renders the sixth family in Bengali, not '
      '"captureClosed"', (tester) async {
    await pump(tester, const Locale('bn'));

    // The Sessions tab is index 1 and TabBarView builds pages lazily, so the
    // card does not exist until the tab is selected.
    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();

    expect(find.text('ধারণ বন্ধ'), findsOneWidget);
    expect(find.text('Capture closed'), findsNothing);
    expect(find.text('captureClosed'), findsNothing);
  });

  testWidgets('both chips render their English labels under Locale(en), and '
      'neither raw identifier', (tester) async {
    await pump(tester, const Locale('en'));

    expect(find.text('Pending approval'), findsOneWidget);
    expect(find.text('pendingApproval'), findsNothing);

    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();

    expect(find.text('Capture closed'), findsOneWidget);
    expect(find.text('captureClosed'), findsNothing);
  });
}
