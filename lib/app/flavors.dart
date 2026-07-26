/// Build flavor + environment configuration. Values are injected at build time
/// via `--dart-define` (Task T-0.1.2); no secrets are committed.
///
///   flutter run --dart-define=FLAVOR=dev \
///     --dart-define=API_BASE_URL=https://dev.api.example/campaign \
///     --dart-define=MEDIA_HOST=https://dev.media.example
enum Flavor { dev, stg, prod }

class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.mediaHost,
    this.e2e = false,
    this.e2eRole = 'field_user',
    this.e2eQuality = 'pass',
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
      flavor: Flavor.values.firstWhere(
        (f) => f.name == flavorName,
        orElse: () => Flavor.dev,
      ),
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
      e2eQuality:
          const String.fromEnvironment('QUALITY', defaultValue: 'pass'),
      e2eSeed: const String.fromEnvironment('SEED'),
    );
  }

  bool get isProd => flavor == Flavor.prod;
}
