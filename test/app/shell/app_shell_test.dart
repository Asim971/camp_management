import 'package:acsl_campaign/app/router/app_router.dart';
import 'package:acsl_campaign/app/shell/app_shell.dart';
import 'package:acsl_campaign/app/shell/nav_destinations.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
          overrides: [authStateProvider.overrideWith((ref) => auth)],
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

    testWidgets('shows the signed-in display name in the account menu', (
      tester,
    ) async {
      await pump(tester, auth: signedIn(Permission.values.toSet()));

      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Rina Akter'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('a field user does not see the Analytics destination', (
      tester,
    ) async {
      await pump(tester, auth: signedIn({Permission.attendanceCapture}));

      expect(find.text('Analytics'), findsNothing);
    });
  });
}
