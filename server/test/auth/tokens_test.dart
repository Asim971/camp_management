import 'dart:convert';

import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

/// Builds an unsigned JWT with an attacker-chosen header, so tests can prove
/// [TokenService.userIdFromAccessToken] never throws no matter what `alg` (or
/// absence of one) a caller puts in front of it. The signature segment is
/// garbage on purpose: a forged header must be rejected before signature
/// verification is ever reached.
String _forgedToken(Map<String, Object?> header, Map<String, Object?> payload) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment(header)}.${segment(payload)}.not-a-real-signature';
}

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

  // C1: two concurrent rotations of the same refresh token, from two
  // separate connections, must not both succeed. Under READ COMMITTED, a
  // plain "SELECT then UPDATE" gives both transactions the same
  // used_at-is-null snapshot, so both proceed and reuse detection never
  // fires — exactly the theft window family revocation exists to close.
  test('two concurrent rotations of the same token: exactly one succeeds, '
      'and reuse revokes the family', () async {
    final dbA = await Db.open(testDatabaseUrl);
    final dbB = await Db.open(testDatabaseUrl);
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
    });
    final tokensA = TokenService(db: dbA, config: config);
    final tokensB = TokenService(db: dbB, config: config);

    final first = await tokens.issueFor('user-1');

    Future<Object> attempt(TokenService svc) async {
      try {
        return await svc.rotate(first.refreshToken);
      } on Object catch (e) {
        return e;
      }
    }

    final results = await Future.wait([attempt(tokensA), attempt(tokensB)]);

    final successes = results.whereType<IssuedTokens>().toList();
    final reuseFailures = results.whereType<RefreshReuseException>().toList();

    expect(
      successes,
      hasLength(1),
      reason: 'exactly one racer must win the rotation',
    );
    expect(
      reuseFailures,
      hasLength(1),
      reason: 'the loser must see reuse, not a silent second success',
    );

    // Reuse detection is only meaningful if it actually revoked the
    // family: the winner's own newly-minted token must be dead too.
    await expectLater(
      tokens.rotate(successes.single.refreshToken),
      throwsA(isA<InvalidRefreshTokenException>()),
    );
  });

  // C2: dart_jsonwebtoken picks the verification algorithm from the token's
  // own (attacker-controlled) header, and its RSA/ECDSA/EdDSA verify paths
  // perform an unchecked cast that throws a raw TypeError — not a
  // JWTException — when the key doesn't match. userIdFromAccessToken's
  // contract is "null on anything invalid, never throws"; these tests forge
  // exactly the headers that broke that contract.
  group('userIdFromAccessToken never throws on a forged header', () {
    test('alg: RS256', () {
      final forged = _forgedToken(
        {'alg': 'RS256', 'typ': 'JWT'},
        {'sub': 'user-1'},
      );
      expect(tokens.userIdFromAccessToken(forged), isNull);
    });

    test('alg: ES256', () {
      final forged = _forgedToken(
        {'alg': 'ES256', 'typ': 'JWT'},
        {'sub': 'user-1'},
      );
      expect(tokens.userIdFromAccessToken(forged), isNull);
    });

    test('alg: EdDSA', () {
      final forged = _forgedToken(
        {'alg': 'EdDSA', 'typ': 'JWT'},
        {'sub': 'user-1'},
      );
      expect(tokens.userIdFromAccessToken(forged), isNull);
    });

    test('missing alg', () {
      final forged = _forgedToken({'typ': 'JWT'}, {'sub': 'user-1'});
      expect(tokens.userIdFromAccessToken(forged), isNull);
    });
  });

  // C3: login checks is_active, but rotation did not — a deactivated user
  // could keep refreshing for up to the full 30-day refresh-token lifetime.
  test('a deactivated user cannot rotate their refresh token', () async {
    final issued = await tokens.issueFor('user-1');
    await db.execute(
      "UPDATE staff_users SET is_active = FALSE WHERE id = 'user-1'",
    );
    await expectLater(
      tokens.rotate(issued.refreshToken),
      throwsA(isA<InvalidRefreshTokenException>()),
    );
  });

  // I5: the two reject branches below had no direct test — only the reuse
  // and unknown-token paths did.
  test('an expired refresh token is rejected', () async {
    final issued = await tokens.issueFor('user-1');
    await db.execute(
      "UPDATE refresh_tokens SET expires_at = now() - INTERVAL '1 second' "
      'WHERE user_id = @u',
      params: {'u': 'user-1'},
    );
    await expectLater(
      tokens.rotate(issued.refreshToken),
      throwsA(isA<InvalidRefreshTokenException>()),
    );
  });

  test(
    'a revoked-but-never-used refresh token is rejected as invalid, not reuse',
    () async {
      final issued = await tokens.issueFor('user-1');
      await db.execute(
        'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = @u',
        params: {'u': 'user-1'},
      );
      await expectLater(
        tokens.rotate(issued.refreshToken),
        throwsA(isA<InvalidRefreshTokenException>()),
      );
    },
  );
}
