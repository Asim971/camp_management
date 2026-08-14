import 'package:campaign_service/src/config.dart';
import 'package:test/test.dart';

void main() {
  const required = {
    'DATABASE_URL': 'postgres://u:p@localhost:5432/campaign',
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  };

  test('reads required values and defaults the port', () {
    final c = ServerConfig.fromEnvironment(required);
    expect(c.databaseUrl, required['DATABASE_URL']);
    expect(c.port, 8080);
    expect(c.accessTokenTtl, const Duration(minutes: 15));
  });

  test('a missing DATABASE_URL fails at startup, not at first request', () {
    expect(
      () =>
          ServerConfig.fromEnvironment({'JWT_SECRET': required['JWT_SECRET']!}),
      throwsA(isA<StateError>()),
    );
  });

  // A short secret is worse than no secret: it starts, signs tokens, and is
  // brute-forceable. Fail loudly at boot.
  test('a short JWT secret is rejected', () {
    expect(
      () => ServerConfig.fromEnvironment({...required, 'JWT_SECRET': 'short'}),
      throwsA(isA<StateError>()),
    );
  });

  // Seeding must fail CLOSED. An unset variable in production must not enable
  // it, and it is the single gate for the test-only routes in Task 10.
  test('seeding is disabled unless explicitly enabled', () {
    expect(ServerConfig.fromEnvironment(required).seedingEnabled, isFalse);
    expect(
      ServerConfig.fromEnvironment({
        ...required,
        'ENABLE_TEST_SEEDING': 'yes',
      }).seedingEnabled,
      isFalse,
      reason: 'only the exact string "true" enables it',
    );
    expect(
      ServerConfig.fromEnvironment({
        ...required,
        'ENABLE_TEST_SEEDING': 'true',
      }).seedingEnabled,
      isTrue,
    );
  });

  // 4a.D3 / spec §5: the upload-URL HMAC must never share a key with JWT
  // signing. uploadSigningKey is derived (not equal to jwtSecret) and stable
  // for a given config, so presign and verify agree without a raw-secret leak.
  test('uploadSigningKey is derived, non-empty, and stable', () {
    final c = ServerConfig.fromEnvironment(required);
    expect(c.uploadSigningKey, isNotEmpty);
    expect(c.uploadSigningKey, equals(c.uploadSigningKey));
    expect(c.uploadSigningKey, isNot(equals(c.jwtSecret)));
  });
}
