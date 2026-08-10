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

  Handler wrapWithAuth(Handler inner, {String userId = 'user-1', Db? using}) =>
      const Pipeline()
          .addMiddleware(correlation())
          .addMiddleware(errorEnvelope())
          .addHandler(
            (request) => _stubAuth(userId)((req) {
              return const Pipeline()
                  .addMiddleware(idempotency(db: using ?? db))
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

  // C1: the client's RetryInterceptor resends an identical POST, key and all,
  // on a send/receive timeout — precisely when the first attempt may still
  // be running. A plain "SELECT, miss, run handler, INSERT ... ON CONFLICT DO
  // NOTHING" shape lets both requests miss the SELECT and both run the
  // handler, with DO NOTHING silently absorbing the collision. Two separate
  // `Db.open` connections (not two futures sharing one connection) are used
  // so the two POSTs are genuine, independent, concurrent sessions against
  // Postgres — the same shape as two real HTTP requests racing each other —
  // and the atomic claim (not application-level sequencing) is what must
  // decide the winner.
  test('two concurrent identical POSTs run the handler exactly once', () async {
    final dbA = await Db.open(testDatabaseUrl);
    final dbB = await Db.open(testDatabaseUrl);
    addTearDown(dbA.close);
    addTearDown(dbB.close);

    var calls = 0;
    Future<Response> slowHandler(Request req) async {
      calls++;
      // Holds the winner inside the handler long enough that the loser's
      // claim attempt and follow-up SELECT are guaranteed to run while the
      // winner's reservation is still unfulfilled (response_status IS
      // NULL) — otherwise the two requests might not overlap at all and
      // this test would prove nothing about the race.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return Response(201, body: jsonEncode({'id': 'race-result'}));
    }

    final handlerA = wrapWithAuth(slowHandler, using: dbA);
    final handlerB = wrapWithAuth(slowHandler, using: dbB);

    final results = await Future.wait([
      post(handlerA, key: 'race-key', body: {'name': 'A'}),
      post(handlerB, key: 'race-key', body: {'name': 'A'}),
    ]);

    expect(
      calls,
      1,
      reason:
          'exactly one of the two concurrent requests may run the '
          'handler',
    );
    final statuses = results.map((r) => r.statusCode).toList()..sort();
    expect(
      statuses,
      anyOf(
        equals([201, 201]), // the loser's SELECT ran after fulfilment.
        equals([201, 409]), // the loser's SELECT ran while still in flight.
      ),
      reason:
          'the loser must be a replay (201) or IN_FLIGHT (409), never a '
          'second handler execution',
    );
  });

  // I2: expiry was enforced on read, but the row's PK survived, so the
  // follow-up INSERT ... ON CONFLICT DO NOTHING never stored again and the
  // original response was fossilized forever. The atomic claim's
  // `DO UPDATE ... WHERE expires_at <= now()` branch reclaims an expired row
  // as a fresh reservation, so an old key becomes idempotent again rather
  // than permanently replaying (or permanently failing to replay) a stale
  // answer.
  test(
    'an expired key is reclaimed: the handler reruns once and refulfils',
    () async {
      var calls = 0;
      final handler = wrapWithAuth((_) {
        calls++;
        return Response(201, body: jsonEncode({'id': 'result-$calls'}));
      });

      final first = await post(handler, key: 'stale-key', body: {'name': 'A'});
      expect(first.statusCode, 201);
      expect(calls, 1);

      await db.execute(
        "UPDATE idempotency_keys SET expires_at = now() - interval '1 hour' "
        "WHERE user_id = 'user-1' AND key = 'stale-key'",
      );

      final second = await post(handler, key: 'stale-key', body: {'name': 'A'});
      expect(
        second.statusCode,
        201,
        reason: 'an expired key must be usable again, not fossilized',
      );
      expect(calls, 2, reason: 'the handler must rerun for the expired key');
      final secondBody = await second.readAsString();
      expect(
        secondBody,
        jsonEncode({'id': 'result-2'}),
        reason: 'the fresh response, not the stale one, must be stored',
      );

      // The follow-up POST after the rerun must replay the NEW response,
      // proving the row was refulfilled with the new answer and a fresh
      // expiry, not left in some half-reclaimed state.
      final third = await post(handler, key: 'stale-key', body: {'name': 'A'});
      expect(calls, 2, reason: 'the third call must replay, not rerun');
      expect(await third.readAsString(), secondBody);
    },
  );

  // M6: the throw path through the atomic claim must behave exactly like
  // the ordinary non-2xx path — the reservation is deleted, not left
  // fossilized as an unfulfillable in-flight row, so a retry can rerun.
  test('a thrown exception through idempotency is a 500 envelope, and a '
      'retry reruns rather than replaying or hanging on IN_FLIGHT', () async {
    var calls = 0;
    final handler = wrapWithAuth((_) {
      calls++;
      throw StateError('handler exploded');
    });

    final first = await post(handler, key: 'boom-key', body: {'name': 'A'});
    expect(first.statusCode, 500);
    final error = (await decodeBody(first))['error']! as Map<String, Object?>;
    expect(error['code'], 'INTERNAL');

    final second = await post(handler, key: 'boom-key', body: {'name': 'A'});
    expect(second.statusCode, 500);
    expect(
      calls,
      2,
      reason:
          'a thrown exception must not leave a fossilized reservation — '
          'the retry must rerun the handler, not hang on IN_FLIGHT',
    );
  });
}
