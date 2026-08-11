import 'dart:convert';

import 'package:campaign_service/src/auth/middleware.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:campaign_service/src/infra/idempotency.dart';
// The middleware hashes the body with DartSha256; a seeded reservation whose
// request_hash does not match would fail as KEY_REUSED (422) before the
// in-flight/stale logic this file tests is ever reached.
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late Handler handler;
  late String token;
  var handlerCalls = 0;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // org-1 / user-1 / campaign_creator
    final tokens = TokenService(db: db, config: config);
    token = (await tokens.issueFor('user-1')).accessToken;
    handlerCalls = 0;
    handler = const Pipeline()
        .addMiddleware(correlation())
        .addMiddleware(errorEnvelope())
        .addMiddleware(authenticate(db: db, tokens: tokens))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          handlerCalls++;
          return Response.ok(
            '{"ok":true}',
            headers: {'content-type': 'application/json'},
          );
        });
  });
  tearDown(() async => db.close());

  const body = '{"x":1}';
  String bodyHash() =>
      base64.encode(const DartSha256().hashSync(utf8.encode(body)).bytes);

  Future<Response> post(String key) async => handler(
    Request(
      'POST',
      Uri.parse('http://localhost/anything'),
      body: body,
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
        'Idempotency-Key': key,
      },
    ),
  );

  /// A reservation as a crashed owner leaves it: claimed, no response, and
  /// [age] old. request_hash matches [body] so the KEY_REUSED guard passes.
  Future<void> seedReservation(String key, {required Duration age}) =>
      db.execute(
        'INSERT INTO idempotency_keys '
        '(user_id, key, request_hash, expires_at, created_at) '
        'VALUES (@user, @key, @hash, @expires, @created)',
        params: {
          'user': 'user-1',
          'key': key,
          'hash': bodyHash(),
          'expires': DateTime.now().toUtc().add(const Duration(hours: 24)),
          'created': DateTime.now().toUtc().subtract(age),
        },
      );

  test('a fresh reservation still answers 409 IN_FLIGHT', () async {
    await seedReservation('k-fresh', age: const Duration(seconds: 10));
    final res = await post('k-fresh');
    expect(res.statusCode, 409);
    final decoded =
        jsonDecode(await res.readAsString()) as Map<String, Object?>;
    expect(
      (decoded['error']! as Map)['code'],
      'IDEMPOTENCY_KEY_IN_FLIGHT',
      reason: 'the 5-minute reclaim window must not swallow live requests',
    );
    expect(handlerCalls, 0);
  });

  test('a stale reservation (crashed owner) is reclaimed and the handler '
      'runs', () async {
    await seedReservation('k-stale', age: const Duration(minutes: 6));
    final res = await post('k-stale');
    expect(res.statusCode, 200);
    expect(handlerCalls, 1, reason: 'the retry must win the key back');
  });

  test('an expired fulfilled row is swept by a later claim on a DIFFERENT '
      'key', () async {
    await db.execute(
      'INSERT INTO idempotency_keys '
      '(user_id, key, request_hash, response_status, response_body, '
      ' expires_at) '
      "VALUES ('user-1', 'k-old', 'h', 200, '{}', @expires)",
      params: {
        'expires': DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      },
    );
    await post('k-new'); // any claim sweeps
    final leftovers = await db.execute(
      "SELECT key FROM idempotency_keys WHERE key = 'k-old'",
    );
    expect(leftovers, isEmpty, reason: 'the reaper deletes expired rows');
  });

  test(
    'an unexpired fulfilled row survives the sweep and still replays',
    () async {
      final first = await post('k-live');
      expect(first.statusCode, 200);
      await post('k-other'); // triggers a sweep
      final replay = await post('k-live');
      expect(replay.statusCode, 200);
      expect(handlerCalls, 2, reason: 'k-live must replay, not re-run');
    },
  );
}
