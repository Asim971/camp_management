import 'dart:convert';

import 'package:campaign_service/src/auth/auth_routes.dart';
import 'package:campaign_service/src/auth/password.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

/// Builds a `shelf.Request` carrying a JSON body and runs it through
/// [handler], the same shape Task 5's middleware tests use.
Future<shelf.Response> _post(
  Future<shelf.Response> Function(shelf.Request) handler,
  String path,
  Map<String, Object?> body,
) {
  final request = shelf.Request(
    'POST',
    Uri.parse('http://localhost$path'),
    body: jsonEncode(body),
    headers: const {'content-type': 'application/json'},
  );
  return handler(request);
}

/// I4: records every encoded hash `/auth/login` actually verifies against,
/// so a test can prove the "no such user" path still executes an Argon2id
/// verify (against the fixed dummy hash) rather than skipping straight to
/// 401 — the behaviour that made response *timing* an enumeration oracle
/// even though the status code and body never differed.
class _RecordingHasher extends PasswordHasher {
  _RecordingHasher(Argon2Params params) : super(params: params);

  final List<String> verifiedAgainst = [];

  @override
  Future<bool> verify(String password, String encoded) async {
    verifiedAgainst.add(encoded);
    return super.verify(password, encoded);
  }
}

void main() {
  late Db db;
  late TokenService tokens;
  late Future<shelf.Response> Function(shelf.Request) handler;

  const hasher = PasswordHasher(params: Argon2Params.fastForTests);
  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db, hasher: hasher);
    tokens = TokenService(db: db, config: config);
    final router = authRouter(db: db, tokens: tokens, hasher: hasher);
    handler = router.call;
  });
  tearDown(() async => db.close());

  test('login returns the exact shape the client parses', () async {
    final res = await _post(handler, '/auth/login', {
      'username': 'creator',
      'password': 'pw',
    });

    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    expect(
      body.keys,
      containsAll(<String>[
        'accessToken',
        'refreshToken',
        'expiresInSeconds',
        'claims',
      ]),
    );
    expect(body['expiresInSeconds'], isA<num>());

    final claims = body['claims']! as Map<String, Object?>;
    expect(
      claims.keys,
      containsAll(<String>[
        'userId',
        'displayName',
        'organizationId',
        'territoryIds',
        'roles',
        'permissions',
      ]),
    );
  });

  test(
    'a wrong password is 401 with no hint about which field failed',
    () async {
      final res = await _post(handler, '/auth/login', {
        'username': 'creator',
        'password': 'wrong',
      });
      expect(res.statusCode, 401);
      expect(await res.readAsString(), isNot(contains('password')));
    },
  );

  test('an unknown username is also 401, not 404', () async {
    final res = await _post(handler, '/auth/login', {
      'username': 'nobody',
      'password': 'pw',
    });
    expect(
      res.statusCode,
      401,
      reason: '404 would confirm which usernames exist',
    );
  });

  // I4: assert BEHAVIOUR, not timing — a strict timing assertion would be
  // flaky under CI load. What must be true is that the no-such-user path
  // executes exactly one Argon2id verify, against the fixed dummy hash, so
  // it costs the same as a real user's wrong-password path. A version of
  // this route that returns 401 without ever hashing would still pass every
  // other test in this file but would leak valid usernames through response
  // timing alone.
  test('an unknown username still pays one Argon2id verify, against the '
      'fixed dummy hash (constant-time defence)', () async {
    final recording = _RecordingHasher(Argon2Params.fastForTests);
    final recordingRouter = authRouter(
      db: db,
      tokens: tokens,
      hasher: recording,
    );
    final res = await _post(recordingRouter.call, '/auth/login', {
      'username': 'nobody',
      'password': 'pw',
    });
    expect(res.statusCode, 401);
    expect(
      recording.verifiedAgainst,
      [dummyPasswordHash],
      reason:
          'the no-such-user path must verify against the dummy hash — '
          'not skip verification, and not verify against a real row',
    );
  });

  test('an inactive user cannot log in', () async {
    await db.execute(
      "UPDATE staff_users SET is_active = FALSE WHERE id = 'user-1'",
    );
    final res = await _post(handler, '/auth/login', {
      'username': 'creator',
      'password': 'pw',
    });
    expect(res.statusCode, 401);
  });

  test('logout is 204 and is idempotent', () async {
    final issued = await tokens.issueFor('user-1');
    expect(
      (await _post(handler, '/auth/logout', {
        'refreshToken': issued.refreshToken,
      })).statusCode,
      204,
    );
    expect(
      (await _post(handler, '/auth/logout', {
        'refreshToken': issued.refreshToken,
      })).statusCode,
      204,
    );
  });

  test(
    'refresh rotates and returns the same response shape as login',
    () async {
      final issued = await tokens.issueFor('user-1');
      final res = await _post(handler, '/auth/refresh', {
        'refreshToken': issued.refreshToken,
      });
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      expect(body['refreshToken'], isNot(issued.refreshToken));
    },
  );

  test('refreshing with a reused token is 401', () async {
    final issued = await tokens.issueFor('user-1');
    await tokens.rotate(issued.refreshToken);
    final res = await _post(handler, '/auth/refresh', {
      'refreshToken': issued.refreshToken,
    });
    expect(res.statusCode, 401);
  });

  test('refreshing with an unknown token is 401', () async {
    final res = await _post(handler, '/auth/refresh', {
      'refreshToken': 'never-issued',
    });
    expect(res.statusCode, 401);
  });
}
