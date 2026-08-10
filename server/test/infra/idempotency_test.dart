import 'dart:convert';

import 'package:campaign_service/src/auth/auth_context.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:campaign_service/src/infra/idempotency.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

/// The same string key `authenticate` uses internally
/// (`server/lib/src/auth/middleware.dart`) — `authOf`'s lookup is keyed by
/// this literal string, not by any symbol private to that library, so a test
/// stub that sets it directly is observed identically to a request that
/// actually went through `authenticate`.
const String _authContextKey = 'auth';

/// Injects a fixed [AuthContext] without needing a real token/DB round trip
/// through `authenticate` — idempotency only cares about `authOf(...)
/// .userId`.
Middleware _stubAuth(String userId) {
  return (Handler inner) {
    return (Request request) => inner(
      request.change(
        context: {
          _authContextKey: AuthContext(
            userId: userId,
            organizationId: 'org-1',
            roles: const {},
            permissions: const {},
            territoryIds: const {},
          ),
        },
      ),
    );
  };
}

void main() {
  late Db db;

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    // idempotency_keys.user_id has an FK to staff_users, so the stubbed
    // AuthContext's userId must be a real row, not just an arbitrary string.
    await seedOrganizationWithUser(db, userId: 'user-1', username: 'u1');
    await seedOrganizationWithUser(db, userId: 'user-2', username: 'u2');
  });
  tearDown(() async => db.close());

  Handler wrapWithAuth(Handler inner, {String userId = 'user-1'}) =>
      const Pipeline()
          .addMiddleware(correlation())
          .addMiddleware(errorEnvelope())
          .addHandler(
            (request) => _stubAuth(userId)((req) {
              return const Pipeline()
                  .addMiddleware(idempotency(db: db))
                  .addHandler(inner)(req);
            })(request),
          );

  Future<Response> post(
    Handler handler, {
    required String? key,
    required Map<String, Object?> body,
  }) async => handler(
    Request(
      'POST',
      Uri.parse('http://localhost/campaigns'),
      body: jsonEncode(body),
      headers: {
        'content-type': 'application/json',
        if (key != null) 'Idempotency-Key': key,
      },
    ),
  );

  Future<Response> get(Handler handler) async =>
      handler(Request('GET', Uri.parse('http://localhost/campaigns')));

  Future<Map<String, Object?>> decodeBody(Response res) async =>
      jsonDecode(await res.readAsString()) as Map<String, Object?>;

  test('a repeated key replays the first response verbatim', () async {
    var calls = 0;
    final handler = wrapWithAuth((req) {
      calls++;
      return Response(201, body: jsonEncode({'id': 'campaign-$calls'}));
    });

    final first = await post(handler, key: 'k1', body: {'name': 'A'});
    final second = await post(handler, key: 'k1', body: {'name': 'A'});

    expect(calls, 1, reason: 'the handler must run exactly once');
    expect(second.statusCode, first.statusCode);
    expect(await second.readAsString(), await first.readAsString());
  });

  // The guard that stops a client's key collision from returning someone
  // else's answer. Without the body hash, reusing a key with different
  // content silently replays the wrong response.
  test(
    'the same key with a different body is rejected, not replayed',
    () async {
      final handler = wrapWithAuth((_) => Response(201, body: '{"id":"c1"}'));
      await post(handler, key: 'k1', body: {'name': 'A'});

      final res = await post(handler, key: 'k1', body: {'name': 'B'});
      expect(res.statusCode, 422);
      final error = (await decodeBody(res))['error']! as Map<String, Object?>;
      expect(error['code'], 'IDEMPOTENCY_KEY_REUSED');
    },
  );

  // Keys are scoped per user: PRIMARY KEY (user_id, key). Two different
  // users presenting the exact same key and body must each get the
  // handler's own response, not one replaying the other's.
  test('two users may use the same key independently', () async {
    var calls = 0;
    final handlerFor = <String, Handler>{
      'user-1': wrapWithAuth((_) {
        calls++;
        return Response(201, body: jsonEncode({'id': 'user-1-result'}));
      }, userId: 'user-1'),
      'user-2': wrapWithAuth((_) {
        calls++;
        return Response(201, body: jsonEncode({'id': 'user-2-result'}));
      }, userId: 'user-2'),
    };

    final resUser1 = await post(
      handlerFor['user-1']!,
      key: 'shared-key',
      body: {'name': 'A'},
    );
    final resUser2 = await post(
      handlerFor['user-2']!,
      key: 'shared-key',
      body: {'name': 'A'},
    );

    expect(calls, 2, reason: 'each user must get their own handler run');
    expect((await decodeBody(resUser1))['id'], 'user-1-result');
    expect((await decodeBody(resUser2))['id'], 'user-2-result');
  });

  test('a POST without a key is rejected on a domain route', () async {
    final handler = wrapWithAuth((_) => Response(201, body: '{"id":"c1"}'));
    final res = await post(handler, key: null, body: {'name': 'A'});
    expect(res.statusCode, 400);
    final error = (await decodeBody(res))['error']! as Map<String, Object?>;
    expect(error['code'], 'IDEMPOTENCY_KEY_REQUIRED');
  });

  test('GET needs no key', () async {
    final handler = wrapWithAuth((_) => Response.ok('ok'));
    expect((await get(handler)).statusCode, 200);
  });

  // A failed write must not be cached, or a transient 500 becomes permanent
  // for that key and the client can never retry it.
  test('a failed response is not stored', () async {
    var calls = 0;
    final handler = wrapWithAuth((_) {
      calls++;
      return Response(500, body: '{"error":{"code":"INTERNAL"}}');
    });
    await post(handler, key: 'k1', body: {'name': 'A'});
    await post(handler, key: 'k1', body: {'name': 'A'});
    expect(calls, 2, reason: 'only 2xx responses are replayable');
  });
}
