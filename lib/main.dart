import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/di/providers.dart';
import 'core/dev/e2e_seeder.dart';

/// Single entry point. Flavor + environment are selected via `--dart-define`
/// (see lib/app/flavors.dart), so there is no per-flavor `main_*.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inter and Noto Sans Bengali are SIL OFL 1.1, which requires the license
  // text to accompany the fonts in distribution. Registering it here (rather
  // than reading assets/fonts/OFL.txt eagerly) keeps this off the startup hot
  // path: LicenseRegistry only invokes the callback — and only then does the
  // asset read happen — when something actually asks for the license list,
  // i.e. when the user opens the app's license page.
  LicenseRegistry.addLicense(() {
    return Stream<LicenseEntry>.fromFuture(
      rootBundle
          .loadString('assets/fonts/OFL.txt')
          .then(
            (license) => LicenseEntryWithLineBreaks(const [
              'Inter',
              'NotoSansBengali',
            ], license),
          ),
    );
  });

  final container = ProviderContainer();
  final config = container.read(appConfigProvider);

  // E2E-only: seed deterministic local data before the app renders. Best-effort
  // — a local-DB failure (e.g. Drift web wasm assets absent) must not block the
  // UI, so DB-independent screens still boot.
  if (config.e2e) {
    try {
      await seedE2EData(
        container.read(appDatabaseProvider),
        seed: config.e2eSeed,
      );
    } catch (_) {
      /* seeding is non-critical for the demo */
    }
  }

  // Audit must flush regardless of which screen the user visits, so the
  // flusher is started here rather than lazily on a feature's first read.
  container.read(auditFlusherProvider).start();

  // Exchange any persisted refresh token before the first frame, so the
  // router sees AuthRestoring rather than AuthSignedOut and does not flash
  // the login screen on a mobile cold start that has a valid session.
  await container.read(sessionManagerProvider).restore();

  // E2E signs in for real against FakeAuthService rather than being handed a
  // pre-built Session, so Maestro drives the same SessionManager path
  // production does. Awaited, not fire-and-forget: the router evaluates its
  // redirect on the first frame, and an unawaited sign-in would race it and
  // land the run on /login.
  if (config.e2e) {
    await container.read(sessionManagerProvider).signIn(config.e2eRole, 'e2e');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AcslCampaignApp(),
    ),
  );
}
