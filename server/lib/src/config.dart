import 'dart:convert';

import 'package:cryptography/dart.dart' show DartSha256;

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

  /// The key that signs media upload URLs — DERIVED from [jwtSecret] with a
  /// fixed context so the upload-URL HMAC is domain-separated from JWT signing
  /// (they must never share a key). Synchronous: SHA-256 over a context-prefixed
  /// secret (DartSha256 is already used elsewhere in this service).
  String get uploadSigningKey => base64Url.encode(
    const DartSha256()
        .hashSync(utf8.encode('media-upload-url|v1|$jwtSecret'))
        .bytes,
  );

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
