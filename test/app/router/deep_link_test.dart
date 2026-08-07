import 'package:acsl_campaign/app/app.dart';
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/app/router/app_router.dart';
import 'package:acsl_campaign/core/design_system/placeholder_screen.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/features/auth/presentation/login_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth.dart';

/// I3: [RouteGuards.evaluate] carried a [location] parameter its doc comment
/// claimed preserved the intended destination, but nothing ever built the
/// `?from=` query string that would let it do so - a deep link into a
/// permitted protected route always landed home after sign-in instead of
/// where it was headed. This is the end-to-end proof the wiring works: an
/// unauthenticated deep link survives the round trip through /login.
void main() {
  testWidgets(
    'an unauthenticated deep link to a permitted route survives sign-in',
    (tester) async {
      const config = AppConfig(
        flavor: Flavor.dev,
        apiBaseUrl: 'https://example.invalid',
        mediaHost: 'https://example.invalid',
      );

      final service = ScriptedAuthService(
        loginResults: [
          Ok(
            testTokens(
              claims: {
                'userId': 'u-1',
                'displayName': 'Verifier',
                'organizationId': 'ORG_1',
                'roles': ['crm_verifier'],
                'permissions': ['verification_decide'],
                'territoryIds': <String>[],
              },
            ),
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          tokenStoreProvider.overrideWithValue(FakeTokenStore()),
          authServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionManagerProvider).restore();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AcslCampaignApp(),
        ),
      );
      await tester.pumpAndSettle();

      final router = container.read(routerProvider);
      router.go('/verification');
      await tester.pumpAndSettle();

      // Unauthenticated: bounced to /login with the intended destination
      // preserved in the query string, not dropped on the floor.
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/login?from=%2Fverification',
      );

      await container.read(sessionManagerProvider).signIn('verifier', 'pw');
      await tester.pumpAndSettle();

      // Lands on the ORIGINAL destination, not home - a plain
      // redirect-to-home on sign-in would be indistinguishable from a
      // broken deep link from this assertion alone.
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/verification',
      );
      expect(find.byType(PlaceholderScreen), findsOneWidget);
    },
  );
}
