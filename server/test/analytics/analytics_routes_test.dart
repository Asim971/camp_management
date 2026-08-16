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

/// Inserts an `attendance` row directly, plus its `media_objects` evidence
/// row (the attendance id doubles as the media id — same convention
/// `AttendanceRepo.confirm` uses). Bypasses the confirm/decision routes
/// entirely so tests can pin a deterministic status/band/captured_at.
///
/// Copied verbatim (module-local) from
/// `server/test/verification/verification_routes_test.dart`'s
/// `seedCrmReviewAttendance`, renamed for this file's broader status range.
Future<void> seedAttendance(
  Db db, {
  required String id,
  required String organizationId,
  required String campaignId,
  required String sessionId,
  required String carpenterId,
  String capturedBy = 'user-1',
  DateTime? capturedAt,
  String machineBand = 'MEDIUM',
  String machineReferenceSrc = 'APPROVED_BASELINE_PHOTO',
  List<String> machineReasons = const [],
  String status = 'APPROVED',
  int version = 1,
}) async {
  await db.execute(
    'INSERT INTO attendance '
    '(id, organization_id, campaign_id, session_id, carpenter_id, media_ref, '
    ' status, captured_by, captured_at, machine_band, machine_reference_src, '
    ' machine_reasons, version) '
    'VALUES (@id, @org, @camp, @sess, @carp, @id, @status, @by, @at, @mb, '
    '        @mrs, @mr::jsonb, @v)',
    params: {
      'id': id,
      'org': organizationId,
      'camp': campaignId,
      'sess': sessionId,
      'carp': carpenterId,
      'status': status,
      'by': capturedBy,
      'at':
          capturedAt ??
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      'mb': machineBand,
      'mrs': machineReferenceSrc,
      'mr': jsonEncode(machineReasons),
      'v': version,
    },
  );
  await db.execute(
    "INSERT INTO media_objects (id, content_type, bytes) "
    "VALUES (@id, 'image/png', @bytes)",
    params: {
      'id': id,
      'bytes': Uint8List.fromList(const [1, 2, 3, 4]),
    },
  );
}

void main() {
  late Db db;
  late Handler handler;
  late String creatorToken; // campaign_creator: has 'export'
  late String fieldToken; // field_user: does NOT have 'export'

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();

    await seedOrganizationWithUser(
      db,
      userId: 'user-1',
      username: 'creator',
      roles: const ['campaign_creator'],
    );
    await seedOrganizationWithUser(
      db,
      userId: 'user-2',
      username: 'field',
      roles: const ['field_user'],
    );
    final tokens = TokenService(db: db, config: config);
    creatorToken = (await tokens.issueFor('user-1')).accessToken;
    fieldToken = (await tokens.issueFor('user-2')).accessToken;
    handler = buildApp(db: db, config: config);

    await seedCampaign(
      db,
      id: 'C1',
      name: 'Campaign One',
      organizationId: 'org-1',
      ownerId: 'user-1',
      status: CampaignStatus.approved,
      targetAudience: 500,
    );
    await seedCampaignSession(
      db,
      id: 'sess-1',
      campaignId: 'C1',
      venue: 'Hall A',
    );
    await seedCarpenter(db, id: 'carp-1', organizationId: 'org-1');
    await seedCarpenter(
      db,
      id: 'carp-2',
      organizationId: 'org-1',
      phone: '+8801700004822',
      displayCode: 'CARP-00004822',
    );
  });
  tearDown(() async => db.close());

  Future<Map<String, Object?>> decode(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  Future<Response> get(String path, {String? bearer}) async => handler(
    Request(
      'GET',
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'authorization': 'Bearer $bearer'},
    ),
  );

  Future<Map<String, Object?>> summary(String query, {String? bearer}) async {
    final res = await get('/analytics/summary?$query', bearer: bearer);
    expect(res.statusCode, 200);
    return decode(res);
  }

  group('GET /analytics/summary', () {
    test('403 without export', () async {
      final res = await get('/analytics/summary', bearer: fieldToken);
      expect(res.statusCode, 403);
    });

    test('401 unauthenticated', () async {
      final res = await get('/analytics/summary');
      expect(res.statusCode, 401);
    });

    test(
      'happy path: funnel, verifiedPerDay, bandMix, campaigns, sample',
      () async {
        await seedRegistration(db, campaignId: 'C1', carpenterId: 'carp-1');
        await seedRegistration(db, campaignId: 'C1', carpenterId: 'carp-2');

        await seedAttendance(
          db,
          id: 'A1',
          organizationId: 'org-1',
          campaignId: 'C1',
          sessionId: 'sess-1',
          carpenterId: 'carp-1',
          status: 'APPROVED',
          capturedAt: DateTime.utc(2026, 8, 1, 10),
          machineBand: 'HIGH',
        );
        await seedAttendance(
          db,
          id: 'A2',
          organizationId: 'org-1',
          campaignId: 'C1',
          sessionId: 'sess-1',
          carpenterId: 'carp-1',
          status: 'APPROVED',
          capturedAt: DateTime.utc(2026, 8, 1, 15),
          machineBand: 'MEDIUM',
        );
        await seedAttendance(
          db,
          id: 'A3',
          organizationId: 'org-1',
          campaignId: 'C1',
          sessionId: 'sess-1',
          carpenterId: 'carp-1',
          status: 'APPROVED',
          capturedAt: DateTime.utc(2026, 8, 3, 9),
          machineBand: 'HIGH',
        );
        await seedAttendance(
          db,
          id: 'A4',
          organizationId: 'org-1',
          campaignId: 'C1',
          sessionId: 'sess-1',
          carpenterId: 'carp-1',
          status: 'CRM_REVIEW',
          capturedAt: DateTime.utc(2026, 8, 3, 11),
          machineBand: 'LOW',
        );
        await seedAttendance(
          db,
          id: 'A5',
          organizationId: 'org-1',
          campaignId: 'C1',
          sessionId: 'sess-1',
          carpenterId: 'carp-1',
          status: 'REJECTED',
          capturedAt: DateTime.utc(2026, 8, 4, 8),
          machineBand: 'NO_REFERENCE',
        );

        final body = await summary(
          'from=2026-08-01&to=2026-08-31',
          bearer: creatorToken,
        );

        expect(body['funnel'], {
          'target': 500,
          'registered': 2,
          'captured': 5,
          'inReview': 1,
          'approved': 3,
          'rejected': 1,
          'returned': 0,
        });
        expect(body['verifiedPerDay'], [
          {'date': '2026-08-01', 'count': 2},
          {'date': '2026-08-03', 'count': 1},
        ]);
        expect(body['bandMix'], {
          'HIGH': 2,
          'MEDIUM': 1,
          'LOW': 1,
          'NO_REFERENCE': 1,
        });
        final campaigns = (body['campaigns']! as List)
            .cast<Map<String, Object?>>();
        expect(campaigns, hasLength(1));
        expect(campaigns.single['id'], 'C1');
        expect(campaigns.single['name'], 'Campaign One');
        expect(campaigns.single['status'], 'APPROVED');
        expect(campaigns.single['target'], 500);
        expect(campaigns.single['verified'], 3);
        expect(campaigns.single['inReview'], 1);
        expect(body['sample'], {'totalAttendance': 5, 'small': true});
        expect(body['range'], {'from': '2026-08-01', 'to': '2026-08-31'});
        expect(body['generatedAt'], isNotNull);
      },
    );

    test('range edges are inclusive on both ends', () async {
      await seedAttendance(
        db,
        id: 'A3',
        organizationId: 'org-1',
        campaignId: 'C1',
        sessionId: 'sess-1',
        carpenterId: 'carp-1',
        status: 'APPROVED',
        capturedAt: DateTime.utc(2026, 8, 3, 9),
      );
      await seedAttendance(
        db,
        id: 'A4',
        organizationId: 'org-1',
        campaignId: 'C1',
        sessionId: 'sess-1',
        carpenterId: 'carp-1',
        status: 'CRM_REVIEW',
        capturedAt: DateTime.utc(2026, 8, 3, 11),
      );
      // Outside the range on either side — must never be counted.
      await seedAttendance(
        db,
        id: 'A-before',
        organizationId: 'org-1',
        campaignId: 'C1',
        sessionId: 'sess-1',
        carpenterId: 'carp-1',
        status: 'APPROVED',
        capturedAt: DateTime.utc(2026, 8, 2, 23, 59, 59),
      );
      await seedAttendance(
        db,
        id: 'A-after',
        organizationId: 'org-1',
        campaignId: 'C1',
        sessionId: 'sess-1',
        carpenterId: 'carp-1',
        status: 'APPROVED',
        capturedAt: DateTime.utc(2026, 8, 4, 0, 0, 0),
      );

      final body = await summary(
        'from=2026-08-03&to=2026-08-03',
        bearer: creatorToken,
      );
      expect((body['funnel']! as Map)['captured'], 2);

      // A row captured at the very last instant of the inclusive `to` date
      // is still counted.
      await seedAttendance(
        db,
        id: 'A6',
        organizationId: 'org-1',
        campaignId: 'C1',
        sessionId: 'sess-1',
        carpenterId: 'carp-1',
        status: 'APPROVED',
        capturedAt: DateTime.utc(2026, 8, 3, 23, 59, 59),
      );
      final body2 = await summary(
        'from=2026-08-03&to=2026-08-03',
        bearer: creatorToken,
      );
      expect((body2['funnel']! as Map)['captured'], 3);
      expect((body2['funnel']! as Map)['approved'], 2);
      expect((body2['funnel']! as Map)['inReview'], 1);
    });

    test('campaignId filter excludes another campaign everywhere', () async {
      await seedAttendance(
        db,
        id: 'A1',
        organizationId: 'org-1',
        campaignId: 'C1',
        sessionId: 'sess-1',
        carpenterId: 'carp-1',
        status: 'APPROVED',
        capturedAt: DateTime.utc(2026, 8, 1, 10),
        machineBand: 'HIGH',
      );
      await seedRegistration(db, campaignId: 'C1', carpenterId: 'carp-1');

      await seedCampaign(
        db,
        id: 'C2',
        name: 'Campaign Two',
        organizationId: 'org-1',
        ownerId: 'user-1',
        status: CampaignStatus.approved,
        targetAudience: 200,
      );
      await seedCampaignSession(
        db,
        id: 'sess-2',
        campaignId: 'C2',
        venue: 'Hall B',
      );
      await seedAttendance(
        db,
        id: 'B1',
        organizationId: 'org-1',
        campaignId: 'C2',
        sessionId: 'sess-2',
        carpenterId: 'carp-2',
        status: 'APPROVED',
        capturedAt: DateTime.utc(2026, 8, 1, 12),
        machineBand: 'MEDIUM',
      );
      await seedRegistration(db, campaignId: 'C2', carpenterId: 'carp-2');

      final body = await summary(
        'from=2026-08-01&to=2026-08-31&campaignId=C1',
        bearer: creatorToken,
      );
      expect((body['funnel']! as Map)['target'], 500);
      expect((body['funnel']! as Map)['registered'], 1);
      expect((body['funnel']! as Map)['captured'], 1);
      expect(body['verifiedPerDay'], [
        {'date': '2026-08-01', 'count': 1},
      ]);
      expect(body['bandMix'], {
        'HIGH': 1,
        'MEDIUM': 0,
        'LOW': 0,
        'NO_REFERENCE': 0,
      });
      final campaigns = (body['campaigns']! as List)
          .cast<Map<String, Object?>>();
      expect(campaigns, hasLength(1));
      expect(campaigns.single['id'], 'C1');
    });

    test('org scoping: another org never surfaces', () async {
      await seedAttendance(
        db,
        id: 'A1',
        organizationId: 'org-1',
        campaignId: 'C1',
        sessionId: 'sess-1',
        carpenterId: 'carp-1',
        status: 'APPROVED',
        capturedAt: DateTime.utc(2026, 8, 1, 10),
      );

      await seedOrganizationWithUser(
        db,
        orgId: 'org-2',
        territoryId: 'terr-2',
        userId: 'user-3',
        username: 'other-org-creator',
        roles: const ['campaign_creator'],
      );
      await seedCampaign(
        db,
        id: 'C-org2',
        name: 'Other Org Campaign',
        organizationId: 'org-2',
        ownerId: 'user-3',
        status: CampaignStatus.approved,
        targetAudience: 999,
      );
      await seedCampaignSession(
        db,
        id: 'sess-org2',
        campaignId: 'C-org2',
        venue: 'Hall C',
      );
      await seedCarpenter(
        db,
        id: 'carp-org2',
        organizationId: 'org-2',
        territoryId: 'terr-2',
        phone: '+8801700009999',
        displayCode: 'CARP-00009999',
      );
      await seedAttendance(
        db,
        id: 'A-org2',
        organizationId: 'org-2',
        campaignId: 'C-org2',
        sessionId: 'sess-org2',
        carpenterId: 'carp-org2',
        capturedBy: 'user-3',
        status: 'APPROVED',
        capturedAt: DateTime.utc(2026, 8, 1, 10),
      );

      final body = await summary(
        'from=2026-08-01&to=2026-08-31',
        bearer: creatorToken,
      );
      expect((body['funnel']! as Map)['target'], 500);
      expect((body['funnel']! as Map)['captured'], 1);
      final campaigns = (body['campaigns']! as List)
          .cast<Map<String, Object?>>();
      expect(campaigns, hasLength(1));
      expect(campaigns.single['id'], 'C1');
    });

    test('sample.small is false at exactly 30 in-range rows', () async {
      for (var i = 0; i < 30; i++) {
        await seedAttendance(
          db,
          id: 'small-30-$i',
          organizationId: 'org-1',
          campaignId: 'C1',
          sessionId: 'sess-1',
          carpenterId: 'carp-1',
          status: 'APPROVED',
          machineBand: 'HIGH',
          capturedAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
        );
      }
      final body = await summary(
        'from=2026-01-01&to=2026-01-31',
        bearer: creatorToken,
      );
      expect(body['sample'], {'totalAttendance': 30, 'small': false});
    });

    test('sample.small is true at 29 in-range rows', () async {
      for (var i = 0; i < 29; i++) {
        await seedAttendance(
          db,
          id: 'small-29-$i',
          organizationId: 'org-1',
          campaignId: 'C1',
          sessionId: 'sess-1',
          carpenterId: 'carp-1',
          status: 'APPROVED',
          machineBand: 'HIGH',
          capturedAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
        );
      }
      final body = await summary(
        'from=2026-01-01&to=2026-01-31',
        bearer: creatorToken,
      );
      expect(body['sample'], {'totalAttendance': 29, 'small': true});
    });

    test('an unparseable from date is 400', () async {
      final res = await get(
        '/analytics/summary?from=notadate&to=2026-08-31',
        bearer: creatorToken,
      );
      expect(res.statusCode, 400);
      expect(((await decode(res))['error']! as Map)['code'], 'BAD_REQUEST');
    });

    test('from after to is 400', () async {
      final res = await get(
        '/analytics/summary?from=2026-08-31&to=2026-08-01',
        bearer: creatorToken,
      );
      expect(res.statusCode, 400);
      expect(((await decode(res))['error']! as Map)['code'], 'BAD_REQUEST');
    });
  });
}
