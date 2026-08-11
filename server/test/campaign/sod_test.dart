import 'dart:convert';

import 'package:campaign_service/src/auth/middleware.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/campaign/campaign_repo.dart';
import 'package:campaign_service/src/campaign/campaign_routes.dart';
import 'package:campaign_service/src/campaign/config_gate.dart';
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
  late String ownerTokenWithApprovePermission;
  var seq = 0;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    // 'admin' carries both campaign_create and campaign_approve
    // (auth/tokens.dart's permissionsByRole) — exactly the setup the "Given
    // the campaign creator is also the current user under SoD policy"
    // scenario needs: user-1 must be able to both create/submit its own
    // campaign AND pass the campaign_approve RBAC gate on /decision, so the
    // 403 the tests observe is specifically SEGREGATION_OF_DUTIES_VIOLATION,
    // never a bare RBAC forbidden that would happen to look the same.
    await seedOrganizationWithUser(
      db,
      userId: 'user-1',
      username: 'creator-admin',
      roles: const ['admin'],
    );
    // Referenced only as campaign_draft's approverId data field — never
    // logs in. validateForSubmit rejects approverId == ownerId outright
    // (validation.dart), and approver_id has an FK to staff_users, so the
    // draft needs a *second* real row to name as its approver even though
    // the SoD check itself (campaign_repo.dart's decide) compares the
    // campaign's owner_id against whoever actually calls /decision, not
    // this stored field.
    await seedOrganizationWithUser(
      db,
      userId: 'user-2',
      username: 'nominal-approver',
      roles: const [],
    );
    tokens = TokenService(db: db, config: config);
    ownerTokenWithApprovePermission = (await tokens.issueFor(
      'user-1',
    )).accessToken;
    handler = const Pipeline()
        .addMiddleware(correlation())
        .addMiddleware(errorEnvelope())
        .addMiddleware(authenticate(db: db, tokens: tokens))
        .addHandler(campaignRouter(db: db, repo: CampaignRepo(db)).call);
  });
  tearDown(() async => db.close());

  String nextKey(String label) => '$label-${seq++}';

  Future<Response> post(
    Handler handler,
    String pathAndQuery,
    Map<String, Object?> body,
    String bearer, {
    String? key,
  }) async => handler(
    Request(
      'POST',
      Uri.parse('http://localhost$pathAndQuery'),
      body: jsonEncode(body),
      headers: {
        'authorization': 'Bearer $bearer',
        'content-type': 'application/json',
        if (key != null) 'Idempotency-Key': key,
      },
    ),
  );

  Map<String, Object?> draftBody({String? approverId = 'user-2'}) => {
    'name': 'Test Campaign',
    'type': 'ATTENDANCE',
    'objective': 'Reach carpenters',
    'territoryIds': const ['terr-1'],
    'target': 50,
    'budgetReference': 'BUD-1',
    'approverId': approverId,
    'geofenceEnabled': false,
    'sessions': [
      {
        'venue': 'Hall A',
        'capacity': 100,
        'startAt': '2026-09-01T09:00:00.000Z',
        'endAt': '2026-09-01T12:00:00.000Z',
      },
    ],
  };

  // Drives the real create -> submit flow through the handler so the
  // resulting row carries the version (2) a genuine submission produces.
  Future<String> pendingCampaign(
    Db db,
    Handler handler, {
    String ownerId = 'user-1',
  }) async {
    final ownerToken = ownerId == 'user-1'
        ? ownerTokenWithApprovePermission
        : (await tokens.issueFor(ownerId)).accessToken;
    final createRes = await post(
      handler,
      '/campaigns',
      draftBody(),
      ownerToken,
      key: nextKey('create'),
    );
    final id =
        (jsonDecode(await createRes.readAsString())
                as Map<String, Object?>)['id']!
            as String;
    await post(
      handler,
      '/campaigns/$id/submit',
      {'version': 1},
      ownerToken,
      key: nextKey('submit'),
    );
    return id;
  }

  // "Given the campaign creator is also the current user under SoD policy,
  // when approval opens, then decision controls are unavailable and the
  // reason is shown." The server enforces it regardless of what the UI does.
  test(
    'the owner cannot decide their own campaign when SoD is enforced',
    () async {
      final id = await pendingCampaign(db, handler, ownerId: 'user-1');
      final res = await post(
        handler,
        '/campaigns/$id/decision',
        {'decision': 'APPROVE', 'version': 2},
        ownerTokenWithApprovePermission,
        key: 'k-i',
      );

      expect(res.statusCode, 403);
      final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
      final error = body['error']! as Map<String, Object?>;
      expect(error['code'], 'SEGREGATION_OF_DUTIES_VIOLATION');
    },
  );

  test('SoD defaults to enforced when the config row is missing', () async {
    await db.execute("DELETE FROM app_config WHERE key = 'sod.enforced'");
    expect(
      await sodEnforced(db),
      isTrue,
      reason: 'a missing row must not silently disable a governance control',
    );
  });

  // M11-part rider: only the literal string 'false' disables SoD — a
  // garbled/unexpected value (a typo, a bad migration, anything that isn't
  // the one recognised opt-out) must fail closed, the same as a missing row.
  test('a garbage sod.enforced value still enforces', () async {
    await db.execute(
      "UPDATE app_config SET value = 'maybe' WHERE key = 'sod.enforced'",
    );
    expect(
      await sodEnforced(db),
      isTrue,
      reason:
          'only the literal value "false" may disable a governance '
          'control — anything unrecognised must fail closed',
    );
  });

  test('SoD can be disabled by configuration', () async {
    await db.execute(
      "UPDATE app_config SET value = 'false' WHERE key = 'sod.enforced'",
    );
    final id = await pendingCampaign(db, handler, ownerId: 'user-1');
    final res = await post(
      handler,
      '/campaigns/$id/decision',
      {'decision': 'APPROVE', 'version': 2, 'acknowledgedWarnings': <String>[]},
      ownerTokenWithApprovePermission,
      key: 'k-j',
    );
    expect(res.statusCode, 200);
  });
}
