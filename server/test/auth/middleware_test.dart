import 'dart:convert';

import 'package:campaign_service/src/auth/middleware.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late TokenService tokens;
  late Handler handler;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // campaign_creator
    tokens = TokenService(db: db, config: config);

    handler = const Pipeline()
        .addMiddleware(authenticate(db: db, tokens: tokens))
        .addMiddleware(requirePermission('campaign_create'))
        .addHandler((req) {
          final auth = authOf(req);
          return Response.ok(
            jsonEncode({
              'userId': auth.userId,
              'organizationId': auth.organizationId,
              'territoryIds': auth.territoryIds.toList(),
            }),
          );
        });
  });
  tearDown(() async => db.close());

  Future<Response> call({String? bearer}) async => handler(
    Request(
      'GET',
      Uri.parse('http://localhost/protected'),
      headers: bearer == null ? null : {'authorization': 'Bearer $bearer'},
    ),
  );

  test('no Authorization header is 401', () async {
    expect((await call()).statusCode, 401);
  });

  test('a malformed or tampered token is 401, never 500', () async {
    expect((await call(bearer: 'not-a-jwt')).statusCode, 401);
    expect((await call(bearer: '')).statusCode, 401);
  });

  test('a valid token with the permission passes and carries scope', () async {
    final issued = await tokens.issueFor('user-1');
    final res = await call(bearer: issued.accessToken);

    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    expect(body['userId'], 'user-1');
    expect(body['organizationId'], 'org-1');
    expect(body['territoryIds'], ['terr-1']);
  });

  test('a valid token WITHOUT the permission is 403', () async {
    await seedOrganizationWithUser(
      db,
      userId: 'user-2',
      username: 'field',
      roles: ['field_user'],
    );
    final issued = await tokens.issueFor('user-2');
    expect((await call(bearer: issued.accessToken)).statusCode, 403);
  });

  // A route wired without `authenticate` must fail loudly. Returning an
  // anonymous context would let a protected handler run unauthenticated and
  // look fine in every test.
  test('authOf throws when authenticate did not run', () async {
    final unguarded = const Pipeline().addHandler((req) async {
      authOf(req);
      return Response.ok('unreachable');
    });
    await expectLater(
      unguarded(Request('GET', Uri.parse('http://localhost/x'))),
      throwsA(isA<StateError>()),
    );
  });

  test('a user deactivated after issuance is rejected', () async {
    final issued = await tokens.issueFor('user-1');
    await db.execute(
      "UPDATE staff_users SET is_active = FALSE WHERE id = 'user-1'",
    );
    expect(
      (await call(bearer: issued.accessToken)).statusCode,
      401,
      reason: 'a still-valid JWT must not outlive deactivation',
    );
  });
}
