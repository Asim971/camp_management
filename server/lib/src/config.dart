/// Startup configuration. Every value is validated here so a misconfigured
/// deploy fails at boot with a precise message rather than at the first
/// request with a stack trace.
class ServerConfig {
  const ServerConfig({
    required this.port,
    required this.databaseUrl,
    required this.jwtSecret,
    required this.accessTokenTtl,
    required this.refreshTokenTtl,
    required this.seedingEnabled,
  });

  final int port;
  final String databaseUrl;
  final String jwtSecret;
  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;

  /// Gates the test-only seeding routes. Defaults to false and requires the
  /// exact string 'true': a typo must not open a data-mutating surface.
  final bool seedingEnabled;

  static ServerConfig fromEnvironment(Map<String, String> env) {
    final databaseUrl = env['DATABASE_URL'];
    if (databaseUrl == null || databaseUrl.isEmpty) {
      throw StateError('DATABASE_URL is required.');
    }
    final secret = env['JWT_SECRET'];
    if (secret == null || secret.length < 32) {
      throw StateError(
        'JWT_SECRET is required and must be at least 32 characters.',
      );
    }
    final rawPort = env['PORT'];
    final port = rawPort == null ? 8080 : int.tryParse(rawPort);
    if (port == null || port <= 0 || port > 65535) {
      throw StateError('PORT must be a valid port number, got "$rawPort".');
    }
    return ServerConfig(
      port: port,
      databaseUrl: databaseUrl,
      jwtSecret: secret,
      accessTokenTtl: const Duration(minutes: 15),
      refreshTokenTtl: const Duration(days: 30),
      seedingEnabled: env['ENABLE_TEST_SEEDING'] == 'true',
    );
  }
}
