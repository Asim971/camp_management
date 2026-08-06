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
enum Flavor { dev, stg, prod }

/// Maps a `FLAVOR` dart-define to its enum. An unrecognized name falls back to
/// [Flavor.dev] — failing closed toward the dev API rather than production.
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
    );
  }

  bool get isProd => flavor == Flavor.prod;

  /// Whether the dev-only routes (`/dev` launcher, `/gallery` component
  /// gallery) are registered. E2E builds get them whatever the flavor, because
  /// Maestro deep-links through `/dev`.
  bool get devRoutesEnabled => e2e || !isProd;
}
