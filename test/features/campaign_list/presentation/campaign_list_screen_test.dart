import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/design_system/screen_hero.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:acsl_campaign/domain/common/status.dart';
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
///
/// [_seed] defaults to an empty page so every pre-existing call site
/// (`_FixedCampaignListNotifier.new`, a zero-arg tear-off) keeps behaving
/// exactly as before; Task 5's summary-strip tests pass a populated page
/// instead.
class _FixedCampaignListNotifier extends CampaignListNotifier {
  _FixedCampaignListNotifier([Paged<Campaign>? seed])
    : _seed = seed ?? const Paged(items: [], total: 0);
  final Paged<Campaign> _seed;
  @override
  Future<Paged<Campaign>> build() async => _seed;
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Set<Permission> permissions,
    Paged<Campaign>? seed,
  }) async {
    final container = buildTestContainer(
      permissions: permissions,
      overrides: [
        campaignListProvider.overrideWith(
          () => _FixedCampaignListNotifier(seed),
        ),
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
          // The hero's summary chips render via `CountUp`; disabling
          // animations makes its `TweenAnimationBuilder` snap straight to
          // the final value on the first frame instead of animating from
          // zero, so `pumpAndSettle` (used below) sees the real counts.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
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

  testWidgets('S3: hero summary chips show page-scoped counts', (tester) async {
    // The default 800x600 test surface leaves BmdDataTable too little width
    // for all four columns, which both overflows the status chip's Row and
    // is beside the point of this test anyway — widen it, as the table's own
    // tests (e.g. crm_case_screen_test.dart) already do for the same reason.
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(
      tester,
      permissions: const {},
      seed: const Paged<Campaign>(
        items: [
          Campaign(
            id: 'c1',
            name: 'Alpha',
            type: 'seminar',
            organizationId: 'ORG_1',
            status: CampaignStatus.active,
            ownerId: 'u-1',
          ),
          Campaign(
            id: 'c2',
            name: 'Beta',
            type: 'seminar',
            organizationId: 'ORG_1',
            status: CampaignStatus.active,
            ownerId: 'u-1',
          ),
          Campaign(
            id: 'c3',
            name: 'Gamma',
            type: 'seminar',
            organizationId: 'ORG_1',
            status: CampaignStatus.pendingApproval,
            ownerId: 'u-1',
          ),
        ],
        total: 3,
      ),
    );

    // 'Active' and 'Pending approval' also appear as row-level StatusChip
    // labels once the table itself is wide enough to show the status column
    // (the point of widening the surface above), so those two are matched
    // scoped to the hero rather than globally — the table's own copies are
    // BmdDataTable's frozen behaviour, not this test's concern.
    final hero = find.byType(ScreenHero);
    expect(find.text('3'), findsWidgets); // total
    expect(find.text('Total'), findsOneWidget);
    expect(
      find.descendant(of: hero, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hero, matching: find.text('Pending approval')),
      findsOneWidget,
    );
    expect(find.text('2'), findsWidgets); // active count
  });

  testWidgets('S3: create action still permission-gated inside the hero', (
    tester,
  ) async {
    await pump(tester, permissions: const {});

    expect(find.byTooltip('Create campaign'), findsOneWidget);
  });
}
