import 'dart:convert';

import 'package:campaign_service/src/app.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

/// Drives the REAL buildApp tree (the slice-1 app_test lesson: a
/// hand-assembled pipeline is exactly how the routing bug went untested).
void main() {
  late Db db;
  late Handler handler;
  late String creatorToken; // campaign_create
  late String viewerToken; // no write permission
  var seq = 0;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // user-1, campaign_creator
    await seedOrganizationWithUser(
      db,
      userId: 'user-2',
      username: 'viewer',
      roles: const ['reporting_viewer'],
    );
    final tokens = TokenService(db: db, config: config);
    creatorToken = (await tokens.issueFor('user-1')).accessToken;
    viewerToken = (await tokens.issueFor('user-2')).accessToken;
    handler = buildApp(db: db, config: config);

    await seedCampaign(db, id: 'camp-1');
    await seedCarpenter(db, id: 'c-1'); // Md. Karim …4821
  });
  tearDown(() async => db.close());

  String nextKey() => 'key-${seq++}';

  Future<Response> get(String path, {String? bearer}) async => handler(
    Request(
      'GET',
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'authorization': 'Bearer $bearer'},
    ),
  );

  Future<Response> post(
    String path,
    Map<String, Object?> body, {
    required String bearer,
    String? key,
  }) async => handler(
    Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      headers: {
        'authorization': 'Bearer $bearer',
        'content-type': 'application/json',
        if (key != null) 'Idempotency-Key': key,
      },
    ),
  );

  Future<Map<String, Object?>> decode(Response res) async =>
      jsonDecode(await res.readAsString()) as Map<String, Object?>;

  group('GET /carpenters', () {
    test('401 without a token, through the real tree', () async {
      expect((await get('/carpenters?q=ka')).statusCode, 401);
    });

    test('400 below the 2-character minimum', () async {
      final res = await get('/carpenters?q=k', bearer: creatorToken);
      expect(res.statusCode, 400);
    });

    test('returns masked items', () async {
      final res = await get('/carpenters?q=karim', bearer: creatorToken);
      expect(res.statusCode, 200);
      final items = (await decode(res))['items']! as List;
      final first = items.first as Map<String, Object?>;
      expect(first['displayId'], 'CARP-••4821');
      expect(first['phoneSuffix'], '4821');
      expect(first['syncStatus'], 'LOCAL_ONLY');
    });
  });

  group('POST /campaigns/<id>/registrations', () {
    test('registers and answers the counts', () async {
      final res = await post(
        '/campaigns/camp-1/registrations',
        {
          'carpenterIds': ['c-1'],
        },
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 200);
      expect(await decode(res), {'registered': 1, 'alreadyRegistered': 0});
    });

    test('403 without campaign_create', () async {
      final res = await post(
        '/campaigns/camp-1/registrations',
        {
          'carpenterIds': ['c-1'],
        },
        bearer: viewerToken,
        key: nextKey(),
      );
      expect(res.statusCode, 403);
    });

    test('404 for a cross-org campaign (D7), 422 UNKNOWN_CARPENTER for a '
        'bad id', () async {
      expect(
        (await post(
          '/campaigns/not-mine/registrations',
          {
            'carpenterIds': ['c-1'],
          },
          bearer: creatorToken,
          key: nextKey(),
        )).statusCode,
        404,
      );
      final res = await post(
        '/campaigns/camp-1/registrations',
        {
          'carpenterIds': ['ghost'],
        },
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 422);
      expect(
        ((await decode(res))['error']! as Map)['code'],
        'UNKNOWN_CARPENTER',
      );
    });

    test('empty carpenterIds is a 400, not a silent no-op', () async {
      final res = await post(
        '/campaigns/camp-1/registrations',
        {'carpenterIds': <String>[]},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 400);
    });

    test('replays through the idempotency middleware', () async {
      final key = nextKey();
      final first = await post(
        '/campaigns/camp-1/registrations',
        {
          'carpenterIds': ['c-1'],
        },
        bearer: creatorToken,
        key: key,
      );
      final replay = await post(
        '/campaigns/camp-1/registrations',
        {
          'carpenterIds': ['c-1'],
        },
        bearer: creatorToken,
        key: key,
      );
      expect(
        await replay.readAsString(),
        await first.readAsString(),
        reason:
            'same key + same body = verbatim replay, so the counts '
            'must say registered:1 both times, NOT alreadyRegistered:1',
      );
      final rows = await db.execute('SELECT 1 FROM registrations');
      expect(rows, hasLength(1));
    });

    test('a missing Idempotency-Key is a 400', () async {
      final res = await post('/campaigns/camp-1/registrations', {
        'carpenterIds': ['c-1'],
      }, bearer: creatorToken);
      expect(res.statusCode, 400);
      expect(
        ((await decode(res))['error']! as Map)['code'],
        'IDEMPOTENCY_KEY_REQUIRED',
      );
    });
  });

  group('POST /campaigns/<id>/profile-requests', () {
    test(
      '201 with the provisional carpenter, which is then registrable',
      () async {
        final res = await post(
          '/campaigns/camp-1/profile-requests',
          {'name': 'New Person', 'phone': '+880 1711-112222'},
          bearer: creatorToken,
          key: nextKey(),
        );
        expect(res.statusCode, 201);
        final body = await decode(res);
        expect(body['requestId'], isA<String>());
        final carpenter = body['carpenter']! as Map<String, Object?>;
        expect(carpenter['syncStatus'], 'PENDING_PROFILE_SYNC');
        expect(carpenter['phoneSuffix'], '2222');
        expect(
          carpenter.containsKey('phone'),
          isFalse,
          reason: 'no raw-phone key on the wire (spec 2a.D2)',
        );
        expect(
          jsonEncode(body),
          isNot(contains('+880')),
          reason: 'nothing in the body may carry the full number',
        );

        final reg = await post(
          '/campaigns/camp-1/registrations',
          {
            'carpenterIds': [carpenter['id']],
          },
          bearer: creatorToken,
          key: nextKey(),
        );
        expect(await decode(reg), {'registered': 1, 'alreadyRegistered': 0});
      },
    );

    test('400 for a malformed phone, naming the field', () async {
      final res = await post(
        '/campaigns/camp-1/profile-requests',
        {'name': 'X', 'phone': 'call me maybe'},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 400);
      final error = (await decode(res))['error']! as Map;
      expect((error['details']! as Map)['field'], 'phone');
    });

    test('400 for a missing name', () async {
      final res = await post(
        '/campaigns/camp-1/profile-requests',
        {'phone': '+8801711112222'},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 400);
    });
  });

  group('GET /sessions/<id>/registrations', () {
    test('roster for an in-org session; 404 out of scope', () async {
      await seedCampaignSession(db, id: 'sess-1', campaignId: 'camp-1');
      await seedRegistration(db, campaignId: 'camp-1', carpenterId: 'c-1');

      final res = await get(
        '/sessions/sess-1/registrations',
        bearer: creatorToken,
      );
      expect(res.statusCode, 200);
      final items = (await decode(res))['items']! as List;
      expect((items.single as Map)['id'], 'c-1');

      expect(
        (await get(
          '/sessions/ghost/registrations',
          bearer: creatorToken,
        )).statusCode,
        404,
      );
    });
  });
}
