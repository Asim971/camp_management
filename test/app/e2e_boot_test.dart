import 'package:acsl_campaign/app/app.dart';
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/features/dev/presentation/dev_launcher_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';

/// Substitutes for the manual Maestro check in task-9-brief.md Step 5b
/// (`flutter run -d chrome --dart-define=E2E=true ...`), which this
/// environment cannot run interactively: no browser automation tool is wired
/// up here to observe a live Chrome tab. This drives the exact sequence
/// `main()` now runs — `SessionManager.restore()` then, under E2E,
/// `SessionManager.signIn(config.e2eRole, 'e2e')`, both awaited before the
/// widget tree is pumped — and asserts both the effect Maestro checks for
/// (the `/dev` launcher renders, not `/login`) and the state it depends on
/// (`authStateProvider` reaches `AuthSignedIn`).
void main() {
  testWidgets(
    'an E2E boot signs in before first frame and lands on /dev, not /login',
    (tester) async {
      const config = AppConfig(
        flavor: Flavor.dev,
        apiBaseUrl: 'https://example.invalid',
        mediaHost: 'https://example.invalid',
        e2e: true,
        e2eRole: 'crm_verifier',
      );

      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          // Swap real Keystore/localStorage-backed storage for the same
          // in-memory fake used elsewhere, so this stays a pure widget test.
          tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        ],
      );
      addTearDown(container.dispose);

      // Mirrors main(): restore() first (finds nothing, since the fake token
      // store starts empty), then the E2E sign-in - both awaited before the
      // router ever evaluates a redirect.
      await container.read(sessionManagerProvider).restore();
      await container
          .read(sessionManagerProvider)
          .signIn(config.e2eRole, 'e2e');

      expect(container.read(authStateProvider), isA<AuthSignedIn>());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AcslCampaignApp(),
        ),
      );
      await tester.pumpAndSettle();

      // The regression this guards: Task 6 deleted the config.e2e branch
      // that used to start an E2E run already authenticated, and nothing
      // replaced it until this task's main() change - an E2E run landed on
      // /login instead of /dev.
      expect(find.byType(DevLauncherScreen), findsOneWidget);
      expect(find.text('E2E launcher'), findsOneWidget);
    },
  );
}
