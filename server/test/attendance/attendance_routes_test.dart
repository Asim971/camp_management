import 'dart:convert';
import 'dart:typed_data';

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
  late String fieldToken; // attendance_capture
  late String viewerToken; // reporting_viewer, no attendance_capture

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  Map<String, Object?> confirmBody() => {
    'sessionId': 'sess-1',
    'carpenterId': 'carp-1',
    'capturedAt': '2026-09-01T09:00:00.000Z',
    'capturedBy': 'user-f',
    'consentVersion': 1,
    'consentLanguage': 'en',
    'consentShownAt': '2026-09-01T08:59:00.000Z',
    'consentContentHash': 'h',
  };

  Future<void> seedEvidence(String id) => db.execute(
    'INSERT INTO media_objects (id, content_type, bytes) '
    "VALUES (@id, 'application/octet-stream', @b)",
    params: {
      'id': id,
      'b': Uint8List.fromList(const [1, 2, 3]),
    },
  );

  Future<Response> confirm(
    String key, {
    String? bearer,
    Map<String, Object?>? body,
    String? rawBody,
    String? idempotencyKey,
  }) async => handler(
    Request(
      'POST',
      Uri.parse('http://localhost/attendance/$key/confirm'),
      headers: {
        if (bearer != null) 'authorization': 'Bearer $bearer',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
        'content-type': 'application/json',
      },
      body: rawBody ?? jsonEncode(body ?? confirmBody()),
    ),
  );

  Future<Map<String, Object?>> decode(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(
      db,
      userId: 'user-f',
      username: 'field',
      roles: const ['field_user'],
    );
    await seedOrganizationWithUser(
      db,
      userId: 'user-v',
      username: 'viewer',
      roles: const ['reporting_viewer'],
    );
    final tokens = TokenService(db: db, config: config);
    fieldToken = (await tokens.issueFor('user-f')).accessToken;
    viewerToken = (await tokens.issueFor('user-v')).accessToken;
    handler = buildApp(db: db, config: config);

    // `ownerId` explicit: seedCampaign's default owner ('user-1') is never
    // seeded in this file — only 'user-f' (field_user) and 'user-v'
    // (reporting_viewer) are — and owner_id is a NOT NULL FK to staff_users.
    await seedCampaign(
      db,
      id: 'camp-1',
      ownerId: 'user-f',
      status: CampaignStatus.approved,
    );
    await seedCampaignSession(
      db,
      campaignId: 'camp-1',
      id: 'sess-1',
      venue: 'Hall',
      startAt: DateTime.utc(2026, 9, 1, 9),
      capacity: 60,
    );
    await seedCarpenter(db, id: 'carp-1');
  });
  tearDown(() async => db.close());

  test('happy path: persists attendance + consent_records + an audit row, '
      'returns MATCH_PROCESSING', () async {
    await seedEvidence('K');
    final res = await confirm('K', bearer: fieldToken, idempotencyKey: 'K');
    expect(res.statusCode, 200);
    final body = await decode(res);
    expect(body['status'], 'MATCH_PROCESSING');
    expect(body['id'], 'K');

    final attendance = await db.execute(
      'SELECT organization_id, campaign_id, session_id, carpenter_id, '
      '  status, captured_by '
      'FROM attendance WHERE id = @id',
      params: {'id': 'K'},
    );
    expect(attendance.length, 1);
    final a = row(attendance.single);
    expect(a['organization_id'], 'org-1');
    expect(a['campaign_id'], 'camp-1');
    expect(a['session_id'], 'sess-1');
    expect(a['carpenter_id'], 'carp-1');
    expect(a['status'], 'MATCH_PROCESSING');
    // The server trusts auth.userId, not the payload's capturedBy.
    expect(a['captured_by'], 'user-f');

    final consent = await db.execute(
      'SELECT notice_version, language, content_hash '
      'FROM consent_records WHERE attendance_id = @id',
      params: {'id': 'K'},
    );
    expect(consent.length, 1);
    final c = row(consent.single);
    expect(c['notice_version'], 1);
    expect(c['language'], 'en');
    expect(c['content_hash'], 'h');

    final audit = await db.execute(
      "SELECT actor_id, resource_id FROM audit_events "
      "WHERE action = 'attendance.captured'",
    );
    expect(audit.length, 1);
    final auditRow = row(audit.single);
    expect(auditRow['actor_id'], 'user-f');
    expect(auditRow['resource_id'], 'K');
  });

  test('idempotent replay: same key + same body twice -> 200 both times, '
      'exactly one attendance row', () async {
    await seedEvidence('K');
    final first = await confirm('K', bearer: fieldToken, idempotencyKey: 'K');
    expect(first.statusCode, 200);
    final second = await confirm('K', bearer: fieldToken, idempotencyKey: 'K');
    expect(second.statusCode, 200);

    final attendance = await db.execute(
      'SELECT id FROM attendance WHERE id = @id',
      params: {'id': 'K'},
    );
    expect(attendance.length, 1);
  });

  test('cross-org session -> 404', () async {
    await seedOrganizationWithUser(
      db,
      orgId: 'org-2',
      userId: 'user-2',
      username: 'other',
    );
    await seedCampaign(
      db,
      id: 'c2',
      organizationId: 'org-2',
      ownerId: 'user-2',
      status: CampaignStatus.approved,
    );
    await seedCampaignSession(db, campaignId: 'c2', id: 'sess-2');

    await seedEvidence('K');
    final body = confirmBody()..['sessionId'] = 'sess-2';
    final res = await confirm(
      'K',
      bearer: fieldToken,
      body: body,
      idempotencyKey: 'K',
    );
    expect(res.statusCode, 404);
  });

  test('unknown carpenter -> 404', () async {
    await seedEvidence('K');
    final body = confirmBody()..['carpenterId'] = 'no-such-carpenter';
    final res = await confirm(
      'K',
      bearer: fieldToken,
      body: body,
      idempotencyKey: 'K',
    );
    expect(res.statusCode, 404);
  });

  test(
    'confirm with no prior upload -> 422 ATTENDANCE_EVIDENCE_MISSING',
    () async {
      // No seedEvidence call: no media_objects row for 'K'.
      final res = await confirm('K', bearer: fieldToken, idempotencyKey: 'K');
      expect(res.statusCode, 422);
      expect(
        ((await decode(res))['error']! as Map)['code'],
        'ATTENDANCE_EVIDENCE_MISSING',
      );
    },
  );

  test('403 without attendance_capture', () async {
    await seedEvidence('K');
    final res = await confirm('K', bearer: viewerToken, idempotencyKey: 'K');
    expect(res.statusCode, 403);
  });

  test('401 unauthenticated', () async {
    await seedEvidence('K');
    final res = await confirm('K', idempotencyKey: 'K');
    expect(res.statusCode, 401);
  });

  // A non-object JSON body (a bare array or string) must be a clean 400, not
  // a raw 500 from an unguarded `as Map` cast -- mirrors the presign handler.
  test('non-object body -> 400, not 500', () async {
    await seedEvidence('K');
    final res = await confirm(
      'K',
      bearer: fieldToken,
      idempotencyKey: 'K',
      rawBody: '[]',
    );
    expect(res.statusCode, 400);
  });

  test('non-object body (bare string) -> 400, not 500', () async {
    await seedEvidence('K');
    final res = await confirm(
      'K',
      bearer: fieldToken,
      idempotencyKey: 'K',
      rawBody: '"x"',
    );
    expect(res.statusCode, 400);
  });

  test('malformed (non-JSON) body -> 400, not 500', () async {
    await seedEvidence('K');
    final res = await confirm(
      'K',
      bearer: fieldToken,
      idempotencyKey: 'K',
      rawBody: '{not json',
    );
    expect(res.statusCode, 400);
  });
}
