import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:acsl_campaign/features/campaign_list/application/campaign_list_notifier.dart';
import 'package:acsl_campaign/features/campaign_list/presentation/campaign_list_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/harness.dart';

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
  Future<void> pump(
    WidgetTester tester, {
    required Set<Permission> permissions,
  }) async {
    final container = buildTestContainer(
      permissions: permissions,
      overrides: [
        campaignListProvider.overrideWith(_FixedCampaignListNotifier.new),
      ],
    );

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
        child: MaterialApp.router(
          // Required since Task 6b: the status chips resolve their labels
          // through AppL10n, and `AppL10n.of` is a non-nullable getter, so a
          // MaterialApp without the delegate throws while building the screen
          // rather than quietly falling back to English. The real app registers
          // these (test/app/l10n_wiring_test.dart pins that), so a harness that
          // omitted them was never faithful.
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a user lacking campaignCreate sees "Create campaign" disabled, not absent',
    (tester) async {
      await pump(tester, permissions: const {});

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
    await pump(tester, permissions: {Permission.campaignCreate});

    await tester.tap(find.byTooltip('Create campaign'));
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsOneWidget);
  });
}
