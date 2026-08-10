import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late TokenService tokens;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db);
    tokens = TokenService(db: db, config: config);
  });
  tearDown(() async => db.close());

  test('issues an access token that resolves back to the user', () async {
    final issued = await tokens.issueFor('user-1');
    expect(tokens.userIdFromAccessToken(issued.accessToken), 'user-1');
    expect(issued.expiresInSeconds, 15 * 60);
  });

  test('claims carry only names the client recognises', () async {
    final issued = await tokens.issueFor('user-1');
    expect(issued.claims['userId'], 'user-1');
    expect(issued.claims['organizationId'], 'org-1');
    expect(issued.claims['roles'], ['campaign_creator']);
    expect(issued.claims['territoryIds'], ['terr-1']);
    // campaign_creator's permission set, per the client's vocabulary.
    expect(
      issued.claims['permissions'],
      containsAll(<String>['campaign_create', 'bulk_import', 'export']),
    );
  });

  test('a tampered access token does not resolve', () async {
    final issued = await tokens.issueFor('user-1');
    final tampered =
        '${issued.accessToken.substring(0, issued.accessToken.length - 4)}AAAA';
    expect(tokens.userIdFromAccessToken(tampered), isNull);
  });

  test('rotation issues a new refresh token and retires the old one', () async {
    final first = await tokens.issueFor('user-1');
    final second = await tokens.rotate(first.refreshToken);

    expect(second.refreshToken, isNot(first.refreshToken));
    expect(tokens.userIdFromAccessToken(second.accessToken), 'user-1');
  });

  // Reuse means a copy leaked. Revoking only the presented token would leave
  // the attacker's newer token valid, so the whole family goes.
  //
  // Assert the SPECIFIC exception, never `throwsA(anything)`: Task 3's audit
  // showed a loose matcher lets an unrelated failure (a protocol error, a bad
  // cast) satisfy the test while the guarantee it names is broken.
  test('presenting a rotated token twice revokes the entire family', () async {
    final first = await tokens.issueFor('user-1');
    final second = await tokens.rotate(first.refreshToken);

    await expectLater(
      tokens.rotate(first.refreshToken),
      throwsA(isA<RefreshReuseException>()),
    );

    // The legitimate holder's newer token is dead too — that is the point.
    // Family revocation surfaces as an INVALID token, not as reuse: only the
    // twice-presented token was "reused"; its descendants are merely revoked.
    await expectLater(
      tokens.rotate(second.refreshToken),
      throwsA(isA<InvalidRefreshTokenException>()),
    );
  });

  test('an unknown refresh token is rejected', () async {
    await expectLater(
      tokens.rotate('never-issued'),
      throwsA(isA<InvalidRefreshTokenException>()),
    );
  });

  test('the stored token is hashed, not the token itself', () async {
    final issued = await tokens.issueFor('user-1');
    final res = await db.execute('SELECT token_hash FROM refresh_tokens');
    final stored = row(res.single)['token_hash']! as String;
    expect(
      stored,
      isNot(issued.refreshToken),
      reason: 'a database dump must not yield usable refresh tokens',
    );
  });
}
