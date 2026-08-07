import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:acsl_campaign/features/campaign_list/application/campaign_list_notifier.dart';
import 'package:acsl_campaign/features/campaign_list/presentation/campaign_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// I5: PermissionGate had zero production call sites while four affordances
/// led straight to /forbidden - the same defect diagnosed for the nav bar,
/// one level down. This pins the "Create campaign" wiring: a user lacking
/// [Permission.campaignCreate] must see the button disabled, not absent (a
/// missing button is indistinguishable from a permission problem, a
/// lifecycle-state problem, or a bug), and a holder must still be able to
/// activate it.
class _FixedCampaignListNotifier extends CampaignListNotifier {
  @override
  Future<Paged<Campaign>> build() async => const Paged(items: [], total: 0);
}

void main() {
  AuthState signedIn(Set<Permission> permissions) => AuthSignedIn(
    Session(
      userId: 'u-1',
      displayName: 'Test User',
      scope: AccessScope(
        roles: const {AppRole.fieldUser},
        permissions: permissions,
        organizationId: 'ORG_1',
      ),
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  Future<void> pump(WidgetTester tester, {required AuthState auth}) async {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWithValue(auth),
        campaignListProvider.overrideWith(_FixedCampaignListNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/campaigns',
      routes: [
        GoRoute(
          path: '/campaigns',
          builder: (_, __) => const CampaignListScreen(),
          routes: [
            GoRoute(path: 'new', builder: (_, __) => const Placeholder()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a user lacking campaignCreate sees "Create campaign" disabled, not absent',
    (tester) async {
      await pump(tester, auth: signedIn(const {}));

      expect(find.byTooltip('Create campaign'), findsOneWidget);

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Create campaign'),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason:
            'onPressed stays wired - PermissionGate blocks interaction via '
            'IgnorePointer, not by nulling the callback',
      );

      // Blocked at the pointer level: tapping must not navigate to /new.
      await tester.tap(find.byTooltip('Create campaign'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(Placeholder), findsNothing);
    },
  );

  testWidgets('a holder of campaignCreate can activate "Create campaign"', (
    tester,
  ) async {
    await pump(tester, auth: signedIn({Permission.campaignCreate}));

    await tester.tap(find.byTooltip('Create campaign'));
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsOneWidget);
  });
}
