/// Build flavor + environment configuration. Values are injected at build time
/// via `--dart-define` (Task T-0.1.2); no secrets are committed.
///
///   flutter run --dart-define=FLAVOR=dev \
///     --dart-define=API_BASE_URL=https://dev.api.example/campaign \
///     --dart-define=MEDIA_HOST=https://dev.media.example
///
/// `tool/scripts/flavors.env` holds the same dev/stg/prod URLs for the
/// run.ps1 wrapper. The defaults below exist only because a bare
/// `flutter test`/`flutter run` supplies no `--dart-define`; keep both
/// files in sync or `run.ps1` and a bare `flutter run` will silently
/// point at different hosts.
library;

import 'package:flutter/foundation.dart' show kReleaseMode;

enum Flavor { dev, stg, prod }

/// Maps a `FLAVOR` dart-define to its enum. An unrecognized name falls back to
/// [Flavor.dev] — failing closed toward the dev API rather than production.
///
/// That default is right for *which backend a request goes to*, but it is the
/// wrong default for *route exposure* — see [AppConfig.devRoutesEnabled],
/// which deliberately does not lean on this fallback for that second concern.
Flavor parseFlavor(String name) =>
    Flavor.values.firstWhere((f) => f.name == name, orElse: () => Flavor.dev);

class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.mediaHost,
    this.e2e = false,
    this.e2eRole = 'field_user',
    this.e2eQuality = 'pass',
    this.e2eSeed = '',
    this.locale = '',
  });

  final Flavor flavor;
  final String apiBaseUrl;
  final String mediaHost;

  /// E2E test mode (`--dart-define=E2E=true`). Enables fake auth, the dev
  /// launcher, a fake camera source and data seeding so Maestro can drive the
  /// app without live backends. See TESTING_MAESTRO.md §3.
  final bool e2e;
  final String e2eRole; // ROLE: field_user | crm_verifier | campaign_creator
  final String e2eQuality; // QUALITY: pass | fail (fail → recapture path)
  final String e2eSeed; // SEED: extra fixtures to seed, e.g. "queue"

  /// Language this build starts in (`--dart-define=LOCALE=bn`); empty means
  /// unset. Deliberately *not* prefixed `e2e` like the three fields above,
  /// because it has two callers, not one:
  ///
  ///  * E2E — every Maestro flow has passed `LOCALE` since it was written and
  ///    the app ignored it until P0.5, so text selectors depended on the
  ///    device happening to be English.
  ///  * Provisioning — a build handed to a Bengali-speaking territory can ship
  ///    with `LOCALE=bn` so the first frame is already Bengali, with no test
  ///    harness involved.
  ///
  /// A persisted user choice takes precedence over this; an unsupported or
  /// empty value falls through to the system locale — see
  /// `LocaleController.load`. Note this is compile-time
  /// (`String.fromEnvironment`), so it is fixed per APK: a Maestro
  /// `launchApp: arguments:` entry of the same name cannot change it.
  final String locale;

  static AppConfig fromEnvironment() {
    const flavorName = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
    return AppConfig(
      flavor: parseFlavor(flavorName),
      apiBaseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://dev.api.example/campaign',
      ),
      mediaHost: const String.fromEnvironment(
        'MEDIA_HOST',
        defaultValue: 'https://dev.media.example',
      ),
      e2e: const bool.fromEnvironment('E2E'),
      e2eRole: const String.fromEnvironment('ROLE', defaultValue: 'field_user'),
      e2eQuality: const String.fromEnvironment('QUALITY', defaultValue: 'pass'),
      e2eSeed: const String.fromEnvironment('SEED'),
      locale: const String.fromEnvironment('LOCALE'),
    );
  }

  bool get isProd => flavor == Flavor.prod;

  /// Whether the dev-only routes (`/dev` launcher, `/gallery` component
  /// gallery) are registered. E2E builds get them whatever the flavor, because
  /// Maestro deep-links through `/dev`.
  ///
  /// Deliberately not `e2e || !isProd` alone: [parseFlavor] falls back to
  /// [Flavor.dev] for an absent or unrecognized `FLAVOR`, so a release build
  /// run without `--dart-define=FLAVOR` — exactly what `flutter build web
  /// --release` does in CI — would otherwise register these routes in the
  /// artifact it ships. `parseFlavor`'s dev fallback is the right default for
  /// *which backend a request goes to* (accidentally hitting the dev API is
  /// safer than accidentally hitting production) but the wrong default for
  /// *route exposure*; `&& !kReleaseMode` fails that half closed regardless of
  /// what `FLAVOR` resolves to, while leaving the flavor-based behaviour
  /// intact — and testable — everywhere else. `kReleaseMode` is always
  /// `false` under `flutter test`, so this getter's release-mode path itself
  /// cannot be exercised by a widget/unit test; see
  /// test/app/dev_routes_test.dart for what is and is not covered.
  bool get devRoutesEnabled => e2e || (!isProd && !kReleaseMode);
}
