import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dev/e2e_seeder.dart';
import '../core/l10n/locale_controller.dart';
import 'boot_diagnostics.dart';
import 'di/providers.dart';

/// Everything that must happen before the first frame.
///
/// NEVER THROWS. A blank screen is strictly worse than a degraded one: a user
/// who cannot reach the app can neither sign in nor generate audit, so every
/// step below degrades and is recorded on [bootDiagnosticsProvider] instead of
/// aborting. Returns the container `runApp` should use.
Future<ProviderContainer> bootstrap({ProviderContainer? container}) async {
  final c = container ?? ProviderContainer();
  final diagnostics = c.read(bootDiagnosticsProvider);
  final config = c.read(appConfigProvider); // pure; cannot fail

  void degrade(String name, Object error) {
    debugPrint('Boot step "$name" degraded: $error');
    diagnostics.record(name, error);
  }

  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
    } catch (error) {
      degrade(name, error);
    }
  }

  // E2E-only fixtures. Already best-effort before this refactor: missing
  // fixtures make the Maestro flows fail loudly, which is correct for a test
  // build.
  if (config.e2e) {
    await step(
      'seedE2EData',
      () => seedE2EData(c.read(appDatabaseProvider), seed: config.e2eSeed),
    );
  }

  // Adopt the persisted language before the first frame so a Bengali device
  // does not flash English.
  //
  // `onDegraded` is not optional decoration here. LocaleController.load catches
  // its own store failure and continues, because a display preference must not
  // block startup (spec D7) - which means step()'s catch, whose only signal is
  // a thrown error, can NEVER fire for the failure that actually happens. With
  // the database unavailable the user's persisted Bengali choice was being
  // dropped with nothing in `failures` to say so: guarded but silent, one layer
  // below the recorder. The callback is the reporting channel; the locale still
  // degrades to the LOCALE define or the system, and boot still continues.
  await step(
    'localeController.load',
    () => c
        .read(localeControllerProvider.notifier)
        .load(onDegraded: (error) => degrade('localeController.load', error)),
  );

  // Audit must flush regardless of which screen the user visits. Reading the
  // flusher resolves the database, which is where the web failure landed.
  await step(
    'auditFlusher.start',
    () async => c.read(auditFlusherProvider).start(),
  );

  // Exchange any persisted refresh token before the first frame, so the router
  // sees AuthRestoring rather than AuthSignedOut and does not flash the login
  // screen on a cold start with a valid session. On failure the user simply
  // signs in again — far better than not rendering.
  await step(
    'sessionManager.restore',
    () => c.read(sessionManagerProvider).restore(),
  );

  // E2E signs in for real against FakeAuthService so Maestro drives the same
  // SessionManager path production does.
  if (config.e2e) {
    await step(
      'e2eSignIn',
      () => c.read(sessionManagerProvider).signIn(config.e2eRole, 'e2e'),
    );
  }

  return c;
}
