import 'dart:async';

import 'package:acsl_campaign/app/app.dart';
import 'package:acsl_campaign/app/boot_diagnostics.dart';
import 'package:acsl_campaign/app/bootstrap.dart';
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/features/dev/presentation/dev_launcher_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Substitutes for the manual Maestro check in task-9-brief.md Step 5b
/// (`flutter run -d chrome --dart-define=E2E=true ...`), which this
/// environment cannot run interactively: no browser automation tool is wired
/// up here to observe a live Chrome tab. This drives the exact sequence
/// `main()` now runs, by calling the same `bootstrap()` it calls rather than
/// re-typing its steps — which is also the only coverage of `bootstrap()`'s two
/// `if (config.e2e)` branches (`seedE2EData` and the E2E `signIn`) — and asserts
/// both the effect Maestro checks for (the `/dev` launcher renders, not
/// `/login`) and the state it depends on (`authStateProvider` reaches
/// `AuthSignedIn`).
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

      // The harness swaps real Keystore/localStorage-backed storage for an
      // in-memory FakeTokenStore, so this stays a pure widget test. The E2E
      // config is the whole point of the file, so it is passed explicitly.
      //
      // Connectivity is stubbed for the same reason test/app/bootstrap_test.dart
      // stubs it (see the comment there): `bootstrap()` starts the audit
      // flusher, which subscribes to `Connectivity().onConnectivityChanged`, an
      // EventChannel with no plugin under `flutter_test`.
      final container = buildTestContainer(
        config: config,
        overrides: [
          connectivityStreamProvider.overrideWithValue(
            const Stream<bool>.empty(),
          ),
        ],
      );

      // The real thing, not a re-typed imitation of it: bootstrap() seeds the
      // E2E fixtures, loads the locale, starts the flusher, restores (finding
      // nothing, since the fake token store starts empty) and then performs the
      // E2E sign-in — all awaited before the router ever evaluates a redirect.
      await bootstrap(container: container);

      expect(container.read(authStateProvider), isA<AuthSignedIn>());
      // Nothing degraded on the way: a swallowed E2E sign-in failure would leave
      // the assertions below to fail for a reason the diagnostics already knew.
      expect(container.read(bootDiagnosticsProvider).isClean, isTrue);

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

      // Driving the real bootstrap() really starts the audit flusher, whose
      // 30-second Timer.periodic outlives these assertions - and `testWidgets`
      // fails any test that ends with a timer still pending, while the harness's
      // container teardown runs only AFTER that check. So stop it here.
      //
      // Deliberately NOT awaited: dispose() ends by awaiting any in-flight
      // flush, and awaiting a real database future inside testWidgets' fake
      // clock never completes (the test hangs to its 10-minute timeout). The
      // timer cancel is synchronous, which is the whole of what this needs, and
      // dispose() is idempotent so the container teardown still behaves.
      unawaited(container.read(auditFlusherProvider).dispose());
    },
  );
}
