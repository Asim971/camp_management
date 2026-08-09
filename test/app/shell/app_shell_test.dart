import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/shell/app_shell.dart';
import 'package:acsl_campaign/app/shell/nav_destinations.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/features/settings/presentation/language_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth.dart';

void main() {
  AuthState signedIn(Set<Permission> permissions) => AuthSignedIn(
    Session(
      userId: 'u-1',
      displayName: 'Rina Akter',
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

  group('visibleDestinations', () {
    test('a field user sees only what they hold', () {
      // The old shell showed all four web surfaces to everyone, every one of
      // which the route guard then bounced to /forbidden.
      final visible = visibleDestinations(
        signedIn({Permission.attendanceCapture}),
      );

      expect(visible.map((d) => d.label), isNot(contains('Analytics')));
      expect(visible.map((d) => d.label), isNot(contains('Verification')));
    });

    test('an admin sees every destination', () {
      final visible = visibleDestinations(signedIn(Permission.values.toSet()));

      expect(visible.length, allNavDestinations.length);
    });

    test('signed out yields no destinations', () {
      expect(visibleDestinations(const AuthSignedOut()), isEmpty);
    });

    test('a destination with no permission requirement is always visible', () {
      final visible = visibleDestinations(signedIn(const {}));

      expect(
        visible.map((d) => d.path),
        contains(allNavDestinations.first.path),
      );
    });
  });

  group('selectedIndexFor', () {
    const destinations = [
      NavDestinationSpec(path: '/', label: 'Dashboard', icon: Icons.home),
      NavDestinationSpec(
        path: '/campaigns',
        label: 'Campaigns',
        icon: Icons.campaign,
      ),
    ];

    test('matches a nested location to its section', () {
      // Selection must be derived, not passed: filtering shifts indices per
      // user, so a hardcoded 2 can point at the wrong item or off the end.
      expect(selectedIndexFor(destinations, '/campaigns/CMP-1/approve'), 1);
    });

    test('matches the root exactly, not as a prefix of everything', () {
      expect(selectedIndexFor(destinations, '/'), 0);
      expect(selectedIndexFor(destinations, '/campaigns'), 1);
    });

    test('returns null for a location outside every section', () {
      expect(selectedIndexFor(destinations, '/queue'), isNull);
    });

    test('prefers the longest matching path', () {
      const nested = [
        NavDestinationSpec(path: '/', label: 'Home', icon: Icons.home),
        NavDestinationSpec(path: '/a', label: 'A', icon: Icons.abc),
        NavDestinationSpec(path: '/a/b', label: 'AB', icon: Icons.abc),
      ];

      expect(selectedIndexFor(nested, '/a/b/c'), 2);
    });
  });

  group('AppShell', () {
    Future<void> pump(
      WidgetTester tester, {
      required AuthState auth,
      Size size = const Size(1440, 900),
      List<Override> overrides = const [],
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // AppShell derives its selection from GoRouterState.of(context), which
      // requires a real GoRouter ancestor building it via a RouteBase.builder
      // (a plain MaterialApp(home: ...) has no GoRouterState above it and
      // GoRouterState.of throws a GoError) - so route it through a minimal
      // GoRouter rather than a bare MaterialApp.
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) =>
                const AppShell(title: 'Campaigns', body: Text('BODY')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => auth),
            ...overrides,
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the body and the title', (tester) async {
      await pump(tester, auth: signedIn(Permission.values.toSet()));

      expect(find.text('BODY'), findsOneWidget);
      expect(find.text('Campaigns'), findsWidgets);
    });

    testWidgets(
      'shows the signed-in display name in the account menu, and tapping '
      'Sign out ends the session via the real SessionManager',
      (tester) async {
        // This test overrides authStateProvider directly with the `auth:`
        // fixture below (rather than deriving it from the SessionManager
        // override, as the real composition root does) so the rendered
        // display name and permissions stay a fixed, readable fixture
        // instead of depending on ScriptedAuthService's claims. The real
        // SessionManager override alongside it is what proves Sign out
        // drives the actual sign-out path, rather than a stub that merely
        // records a call.
        final tokenStore = FakeTokenStore();
        final manager = SessionManager(
          service: ScriptedAuthService(),
          tokens: tokenStore,
        );
        addTearDown(manager.dispose);

        final signInResult = await manager.signIn('user', 'pass');
        expect(signInResult.isOk, isTrue);
        expect(manager.state, isA<AuthSignedIn>());
        expect(tokenStore.value, isNotNull);

        await pump(
          tester,
          auth: signedIn(Permission.values.toSet()),
          overrides: [sessionManagerProvider.overrideWithValue(manager)],
        );

        await tester.tap(find.byIcon(Icons.account_circle_outlined));
        await tester.pumpAndSettle();

        expect(find.text('Rina Akter'), findsOneWidget);
        expect(find.text('Sign out'), findsOneWidget);

        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();

        expect(manager.state, isA<AuthSignedOut>());
        expect(tokenStore.value, isNull);
      },
    );

    testWidgets(
      'the account menu reaches the language picker through the Semantics '
      'identifiers Maestro drives (account_menu → account_language)',
      (tester) async {
        // The menu is the ONLY way into /settings/language, and Task 12's
        // Bengali flow has to walk it on an emulator, where a missing
        // identifier is the most expensive kind of defect to discover.
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) =>
                  const AppShell(title: 'Campaigns', body: Text('BODY')),
            ),
            GoRoute(
              path: '/settings/language',
              builder: (_, __) => const LanguageScreen(),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(
                (ref) => signedIn(Permission.values.toSet()),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        Finder byIdentifier(String id) => find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.identifier == id,
        );

        // find.bySemanticsIdentifier reads the RENDERED semantics tree, which
        // is what Maestro sees; the widget-tree predicate alone would still
        // pass if the identifier were merged away.
        final semantics = tester.ensureSemantics();

        expect(find.bySemanticsIdentifier('account_menu'), findsOneWidget);
        await tester.tap(byIdentifier('account_menu'));
        await tester.pumpAndSettle();

        expect(find.bySemanticsIdentifier('account_language'), findsOneWidget);
        // Disposed inline: the binding checks for live SemanticsHandles at the
        // end of the test BODY, before any tearDown runs.
        semantics.dispose();

        await tester.tap(byIdentifier('account_language'));
        await tester.pumpAndSettle();

        expect(find.byType(LanguageScreenBody), findsOneWidget);
      },
    );

    testWidgets(
      'the language picker can be backed out of, rather than trapping the user',
      (tester) async {
        // Found by running the app on an emulator. The account menu used
        // context.go(), which REPLACES the location rather than stacking it, so
        // /settings/language had nothing beneath it: AppBar's
        // automaticallyImplyLeading rendered no back arrow, and the Android
        // system back button left the APP instead of returning. The screen also
        // shows no bottom nav (it matches no destination), so the account menu
        // was the only way off it — a dead end reachable in two taps.
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) =>
                  const AppShell(title: 'Campaigns', body: Text('BODY')),
            ),
            GoRoute(
              path: '/settings/language',
              builder: (_, __) => const LanguageScreen(),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(
                (ref) => signedIn(Permission.values.toSet()),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.identifier == 'account_menu',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Language'));
        await tester.pumpAndSettle();

        expect(find.byType(LanguageScreenBody), findsOneWidget);

        // The route must sit ON TOP of where the user came from. Without this,
        // Android's back gesture pops the last route and exits the app.
        expect(
          Navigator.of(
            tester.element(find.byType(LanguageScreenBody)),
          ).canPop(),
          isTrue,
          reason: 'nothing to pop means system back exits the app',
        );

        // And there must be a visible affordance, not only a system gesture —
        // AppBar supplies one automatically once the route is poppable.
        expect(find.byType(BackButton), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        // Back lands on the originating screen, not a blank tree.
        expect(find.text('BODY'), findsOneWidget);
        expect(find.byType(LanguageScreenBody), findsNothing);
      },
    );

    testWidgets('a field user does not see the Analytics destination', (
      tester,
    ) async {
      await pump(tester, auth: signedIn({Permission.attendanceCapture}));

      expect(find.text('Analytics'), findsNothing);
    });
  });
}
