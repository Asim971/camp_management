import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/auth/middleware.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/campaign/campaign_repo.dart';
import 'package:campaign_service/src/campaign/campaign_routes.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late TokenService tokens;
  late Handler handler;
  late String token;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // campaign_creator, org-1/user-1
    tokens = TokenService(db: db, config: config);
    token = (await tokens.issueFor('user-1')).accessToken;

    handler = const Pipeline()
        .addMiddleware(correlation())
        .addMiddleware(errorEnvelope())
        .addMiddleware(authenticate(db: db, tokens: tokens))
        .addHandler(campaignRouter(db: db, repo: CampaignRepo(db)).call);
  });
  tearDown(() async => db.close());

  Future<Response> get(
    Handler handler,
    String pathAndQuery,
    String bearer,
  ) async => handler(
    Request(
      'GET',
      Uri.parse('http://localhost$pathAndQuery'),
      headers: {'authorization': 'Bearer $bearer'},
    ),
  );

  test(
    'list paginates for real, and total counts all matches not the page',
    () async {
      await seedCampaigns(db, count: 25);
      final res = await get(handler, '/campaigns?page=2&pageSize=10', token);

      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      expect((body['items']! as List).length, 10);
      expect(
        body['total'],
        25,
        reason: 'the mock returned items.length, which made paging invisible',
      );
    },
  );

  test('pageSize is capped server-side', () async {
    await seedCampaigns(db, count: 120);
    final res = await get(handler, '/campaigns?pageSize=10000', token);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    expect((body['items']! as List).length, lessThanOrEqualTo(100));
  });

  test('q filters by name, case-insensitively', () async {
    await seedCampaign(db, id: 'c1', name: 'Carpenter Drive');
    await seedCampaign(db, id: 'c2', name: 'Mason Workshop');
    final res = await get(handler, '/campaigns?q=carpenter', token);
    final items =
        (jsonDecode(await res.readAsString()) as Map<String, Object?>)['items']!
            as List;
    expect(items.map((e) => (e as Map<String, Object?>)['id']), ['c1']);
  });

  test('repeated status params filter to that set', () async {
    await seedCampaign(db, id: 'c1', status: CampaignStatus.draft);
    await seedCampaign(db, id: 'c2', status: CampaignStatus.approved);
    await seedCampaign(db, id: 'c3', status: CampaignStatus.cancelled);

    final res = await get(
      handler,
      '/campaigns?status=DRAFT&status=APPROVED',
      token,
    );
    final items =
        (jsonDecode(await res.readAsString()) as Map<String, Object?>)['items']!
            as List;
    expect(items.map((e) => (e as Map<String, Object?>)['id']).toSet(), {
      'c1',
      'c2',
    });
  });

  test('an unknown status value is a 400, not silently ignored', () async {
    final res = await get(handler, '/campaigns?status=NOPE', token);
    expect(res.statusCode, 400);
  });

  test('the wire shape matches the client DTO exactly', () async {
    await seedCampaign(db, id: 'c1');
    final res = await get(handler, '/campaigns/c1', token);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;

    expect(
      body.keys,
      containsAll(<String>[
        'id',
        'name',
        'type',
        'organizationId',
        'status',
        'ownerId',
        'startAt',
        'endAt',
        'venue',
        'objective',
        'territoryIds',
        'targetAudience',
        'verifiedAttendance',
        'version',
      ]),
    );
    expect(body['status'], 'DRAFT');
    expect(
      body['verifiedAttendance'],
      0,
      reason: 'derived, never stored, until sub-project 4',
    );
  });

  // D7. The scope filter lives in the WHERE clause, so this is the ordinary
  // not-found path rather than a separate check that could be forgotten.
  test('a campaign in another organization is 404, never 403', () async {
    await seedOrganizationWithUser(
      db,
      orgId: 'org-2',
      territoryId: 'terr-2',
      userId: 'user-9',
      username: 'other',
    );
    await seedCampaign(
      db,
      id: 'foreign',
      organizationId: 'org-2',
      ownerId: 'user-9',
    );

    final res = await get(handler, '/campaigns/foreign', token);
    expect(res.statusCode, 404, reason: '403 would confirm the id exists');
  });

  test('a missing campaign is 404 with the NOT_FOUND code', () async {
    final res = await get(handler, '/campaigns/nope', token);
    expect(res.statusCode, 404);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    expect((body['error']! as Map<String, Object?>)['code'], 'NOT_FOUND');
  });

  test('timestamps are UTC ISO-8601 on the wire', () async {
    await seedCampaign(db, id: 'c1', startAt: DateTime.utc(2026, 9, 1, 9));
    final res = await get(handler, '/campaigns/c1', token);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    expect(body['startAt'], '2026-09-01T09:00:00.000Z');
  });
}
