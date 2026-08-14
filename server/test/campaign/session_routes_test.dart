import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/app.dart';
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
  late Handler handler;
  late String creatorToken; // campaign_create
  late String viewerToken; // reporting_viewer, no campaign_create

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // user-1 campaign_creator
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
    await seedCampaign(db, id: 'camp-1', status: CampaignStatus.approved);
    await seedCampaignSession(
      db,
      campaignId: 'camp-1',
      id: 's-1',
      venue: 'BMD Training Center, Hall A',
      startAt: DateTime.utc(2026, 9, 1, 9),
      capacity: 60,
    );
  });
  tearDown(() async => db.close());

  Future<Response> get(String path, {String? bearer}) async => handler(
    Request(
      'GET',
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'authorization': 'Bearer $bearer'},
    ),
  );

  Future<Response> post(String path, {String? bearer}) async => handler(
    Request(
      'POST',
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'authorization': 'Bearer $bearer'},
    ),
  );

  Future<Map<String, Object?>> body(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  test('GET lists the campaign sessions with zero counts', () async {
    final res = await get('/campaigns/camp-1/sessions', bearer: creatorToken);
    expect(res.statusCode, 200);
    final items = (await body(res))['items']! as List;
    expect(items, hasLength(1));
    final s = items.single as Map<String, Object?>;
    expect(s['status'], 'UPCOMING');
    expect(s['registeredCount'], 0);
    expect(s['readinessOk'], true);
  });

  test('GET a campaign outside the org is 404, not 403', () async {
    await seedOrganizationWithUser(
      db,
      orgId: 'org-2',
      userId: 'user-x',
      username: 'other',
    );
    await seedCampaign(
      db,
      id: 'other-org-camp',
      organizationId: 'org-2',
      ownerId: 'user-x',
      status: CampaignStatus.approved,
    );
    final res = await get(
      '/campaigns/other-org-camp/sessions',
      bearer: creatorToken,
    );
    expect(res.statusCode, 404);
  });

  test('start -> pause -> close walks the lifecycle', () async {
    final started = await post('/sessions/s-1/start', bearer: creatorToken);
    expect(started.statusCode, 200);
    expect((await body(started))['status'], 'ACTIVE');

    final paused = await post('/sessions/s-1/pause', bearer: creatorToken);
    expect((await body(paused))['status'], 'PAUSED');

    final closed = await post('/sessions/s-1/close', bearer: creatorToken);
    expect((await body(closed))['status'], 'CAPTURE_CLOSED');
  });

  test('start twice is an idempotent 200 (double-tap safe)', () async {
    await post('/sessions/s-1/start', bearer: creatorToken);
    final again = await post('/sessions/s-1/start', bearer: creatorToken);
    expect(again.statusCode, 200);
    expect((await body(again))['status'], 'ACTIVE');
  });

  test('start on a closed session is 409 SESSION_INVALID_TRANSITION', () async {
    await post('/sessions/s-1/start', bearer: creatorToken);
    await post('/sessions/s-1/close', bearer: creatorToken);
    final res = await post('/sessions/s-1/start', bearer: creatorToken);
    expect(res.statusCode, 409);
    expect(
      ((await body(res))['error']! as Map)['code'],
      'SESSION_INVALID_TRANSITION',
    );
  });

  test('start when not ready is 422 SESSION_NOT_READY', () async {
    await seedCampaignSession(
      db,
      campaignId: 'camp-1',
      id: 's-novenue',
      venue: null,
    );
    final res = await post('/sessions/s-novenue/start', bearer: creatorToken);
    expect(res.statusCode, 422);
    expect(((await body(res))['error']! as Map)['code'], 'SESSION_NOT_READY');
  });

  test('an unknown session id is 404', () async {
    final res = await post('/sessions/nope/start', bearer: creatorToken);
    expect(res.statusCode, 404);
  });

  test('a viewer without campaign_create is 403', () async {
    final res = await post('/sessions/s-1/start', bearer: viewerToken);
    expect(res.statusCode, 403);
  });

  test('unauthenticated is 401', () async {
    final res = await post('/sessions/s-1/start');
    expect(res.statusCode, 401);
  });
}
