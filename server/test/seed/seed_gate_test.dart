import 'dart:convert';

import 'package:campaign_service/src/app.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/seed/seed_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/test_db.dart';

/// The gate matters more than the seeding (Task 11 step 1's own framing):
/// this file exists to prove `/__test__/*` is ABSENT — not
/// registered-and-guarded — whenever seeding is off, before a single line of
/// seeding logic is trusted.
ServerConfig configWithSeeding(bool enabled) => ServerConfig.fromEnvironment({
  'DATABASE_URL': testDatabaseUrl,
  'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  if (enabled) 'ENABLE_TEST_SEEDING': 'true',
});

Future<Response> _post(Handler handler, String path, {Object? body}) async =>
    await handler(
      Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
        headers: body == null
            ? const {}
            : const {'content-type': 'application/json'},
      ),
    );

void main() {
  late Db db;

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
  });
  tearDown(() async => db.close());

  test('seed routes are absent when seeding is disabled', () async {
    final handler = buildApp(db: db, config: configWithSeeding(false));
    final res = await _post(handler, '/__test__/reset');
    expect(
      res.statusCode,
      404,
      reason: 'a data-wiping route must not exist in production',
    );
  });

  test(
    'the campaigns fixture route is also absent when seeding is disabled',
    () async {
      final handler = buildApp(db: db, config: configWithSeeding(false));
      final res = await _post(
        handler,
        '/__test__/campaigns',
        body: {'fixture': 'rows'},
      );
      expect(res.statusCode, 404);
    },
  );

  test('seed routes work when explicitly enabled', () async {
    final handler = buildApp(db: db, config: configWithSeeding(true));
    final res = await _post(handler, '/__test__/reset');
    expect(res.statusCode, 204);
  });

  // Fails closed: ENABLE_TEST_SEEDING must be exactly 'true'.
  test('any value other than "true" leaves seeding off', () {
    for (final value in ['1', 'yes', 'TRUE', 'True', '']) {
      final config = ServerConfig.fromEnvironment({
        'DATABASE_URL': testDatabaseUrl,
        'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
        'ENABLE_TEST_SEEDING': value,
      });
      expect(config.seedingEnabled, isFalse, reason: 'value: "$value"');
    }
  });

  test('reset seeds one user per wire role who can sign in with the '
      'documented password', () async {
    final handler = buildApp(db: db, config: configWithSeeding(true));
    final resetRes = await _post(handler, '/__test__/reset');
    expect(resetRes.statusCode, 204);

    for (final role in seedRoles) {
      final res = await _post(
        handler,
        '/auth/login',
        body: {'username': role, 'password': seedPassword},
      );
      expect(
        res.statusCode,
        200,
        reason: 'role "$role" should be able to sign in after reset',
      );
      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      final claims = body['claims']! as Map<String, Object?>;
      expect((claims['roles']! as List<Object?>), contains(role));
    }
  });

  test('reset seeds the campaign rows locale_bengali.yaml and the real-auth '
      'flow depend on', () async {
    final handler = buildApp(db: db, config: configWithSeeding(true));
    await _post(handler, '/__test__/reset');

    final loginRes = await _post(
      handler,
      '/auth/login',
      body: {'username': 'field_user', 'password': seedPassword},
    );
    final token =
        (jsonDecode(await loginRes.readAsString())
                as Map<String, Object?>)['accessToken']!
            as String;

    final res = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/campaigns'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    final items = (body['items']! as List<Object?>)
        .cast<Map<String, Object?>>();

    final rajshahi = items.singleWhere(
      (c) => c['name'] == 'Rajshahi Carpenter Drive',
      orElse: () => throw TestFailure(
        'reset did not seed the "Rajshahi Carpenter Drive" campaign that '
        '.maestro/flows/locale_bengali.yaml asserts.',
      ),
    );
    expect(rajshahi['status'], 'DRAFT');
  });

  test(
    'POST /__test__/campaigns {"fixture":"empty"} clears campaigns',
    () async {
      final handler = buildApp(db: db, config: configWithSeeding(true));
      await _post(handler, '/__test__/reset');

      final res = await _post(
        handler,
        '/__test__/campaigns',
        body: {'fixture': 'empty'},
      );
      expect(res.statusCode, 204);

      final loginRes = await _post(
        handler,
        '/auth/login',
        body: {'username': 'field_user', 'password': seedPassword},
      );
      final token =
          (jsonDecode(await loginRes.readAsString())
                  as Map<String, Object?>)['accessToken']!
              as String;
      final listRes = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/campaigns'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      final body =
          jsonDecode(await listRes.readAsString()) as Map<String, Object?>;
      expect(body['items'], isEmpty);
      expect(body['total'], 0);
    },
  );

  test('POST /__test__/campaigns {"fixture":"error"} fails the next GET '
      '/campaigns once, then reverts to normal', () async {
    final handler = buildApp(db: db, config: configWithSeeding(true));
    await _post(handler, '/__test__/reset');
    final armRes = await _post(
      handler,
      '/__test__/campaigns',
      body: {'fixture': 'error'},
    );
    expect(armRes.statusCode, 204);

    final loginRes = await _post(
      handler,
      '/auth/login',
      body: {'username': 'field_user', 'password': seedPassword},
    );
    final token =
        (jsonDecode(await loginRes.readAsString())
                as Map<String, Object?>)['accessToken']!
            as String;

    Future<Response> getCampaigns() async => await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/campaigns'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );

    final first = await getCampaigns();
    expect(first.statusCode, 500);

    final second = await getCampaigns();
    expect(
      second.statusCode,
      200,
      reason: 'the armed failure is one-shot, mirroring MOCK_CAMPAIGNS=error',
    );
  });

  test('reset seeds one operable session on seed-camp-1', () async {
    final handler = buildApp(db: db, config: configWithSeeding(true));
    await _post(handler, '/__test__/reset');

    final loginRes = await _post(
      handler,
      '/auth/login',
      body: {'username': 'campaign_creator', 'password': seedPassword},
    );
    final token =
        (jsonDecode(await loginRes.readAsString())
                as Map<String, Object?>)['accessToken']!
            as String;

    final res = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/campaigns/seed-camp-1/sessions'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    final items = (body['items']! as List<Object?>)
        .cast<Map<String, Object?>>();

    expect(
      items,
      hasLength(1),
      reason:
          '.maestro/flows/session_ops.yaml needs exactly one seeded session '
          'on seed-camp-1',
    );
    final session = items.single;
    expect(session['id'], 'seed-camp-1-session-1');
    expect(session['status'], 'UPCOMING');
    expect(session['readinessOk'], true);
  });

  test('reset seeds no session for the other campaign fixtures', () async {
    final handler = buildApp(db: db, config: configWithSeeding(true));
    await _post(handler, '/__test__/reset');

    final loginRes = await _post(
      handler,
      '/auth/login',
      body: {'username': 'campaign_creator', 'password': seedPassword},
    );
    final token =
        (jsonDecode(await loginRes.readAsString())
                as Map<String, Object?>)['accessToken']!
            as String;

    for (final campaignId in ['seed-camp-2', 'seed-camp-3']) {
      final res = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/campaigns/$campaignId/sessions'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      expect(
        body['items'],
        isEmpty,
        reason:
            '$campaignId is not APPROVED and should get no seeded '
            'session',
      );
    }
  });

  test('reset seeds the two carpenter fixtures', () async {
    final handler = buildApp(db: db, config: configWithSeeding(true));
    await _post(handler, '/__test__/reset');

    final res = await db.execute(
      'SELECT id, display_code FROM carpenters ORDER BY id',
    );
    final byId = {
      for (final r in res.map(row)) r['id']! as String: r['display_code'],
    };
    expect(byId, {'CARP_E2E': 'CARP-00004821', 'CARP_E2E_2': 'CARP-00007734'});
  });

  test('reset seeds the v1 consent notices in both languages, and GET '
      '/consent/notices serves them back', () async {
    final handler = buildApp(db: db, config: configWithSeeding(true));
    await _post(handler, '/__test__/reset');

    final loginRes = await _post(
      handler,
      '/auth/login',
      body: {'username': 'field_user', 'password': seedPassword},
    );
    final token =
        (jsonDecode(await loginRes.readAsString())
                as Map<String, Object?>)['accessToken']!
            as String;

    final res = await handler(
      Request(
        'GET',
        Uri.parse('http://localhost/consent/notices'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    final notices = (body['notices']! as List<Object?>)
        .cast<Map<String, Object?>>();

    final byLanguage = {for (final n in notices) n['language']: n};
    expect(
      byLanguage.keys,
      containsAll(['en', 'bn']),
      reason: 'reset should seed the v1 notice in both bundled languages',
    );
    expect(byLanguage['en']!['version'], 1);
    expect(byLanguage['bn']!['version'], 1);
  });
}
