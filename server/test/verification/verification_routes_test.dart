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

/// Inserts an `attendance` row directly in `CRM_REVIEW`, plus its
/// `media_objects` evidence row (the attendance id doubles as the media id —
/// same convention `AttendanceRepo.confirm` uses). Bypasses the confirm route
/// entirely so tests can pin a deterministic band/reasons/captured_at.
Future<void> seedCrmReviewAttendance(
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
  List<String> machineReasons = const [
    'Face comparison inconclusive — manual review required.',
  ],
  String status = 'CRM_REVIEW',
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
  late String
  verifierToken; // crm_verifier: verification_decide + sensitive_media_view
  late String supervisorToken; // crm_supervisor: adds verification_override
  late String viewerToken; // field_user: neither permission

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
      username: 'verifier',
      roles: const ['crm_verifier'],
    );
    await seedOrganizationWithUser(
      db,
      userId: 'user-2',
      username: 'field',
      roles: const ['field_user'],
    );
    await seedOrganizationWithUser(
      db,
      userId: 'user-4',
      username: 'supervisor',
      roles: const ['crm_supervisor'],
    );
    final tokens = TokenService(db: db, config: config);
    verifierToken = (await tokens.issueFor('user-1')).accessToken;
    viewerToken = (await tokens.issueFor('user-2')).accessToken;
    supervisorToken = (await tokens.issueFor('user-4')).accessToken;
    handler = buildApp(db: db, config: config);

    await seedCampaign(
      db,
      id: 'camp-1',
      organizationId: 'org-1',
      ownerId: 'user-1',
      status: CampaignStatus.approved,
    );
    await seedCampaignSession(
      db,
      id: 'sess-1',
      campaignId: 'camp-1',
      venue: 'Hall A',
    );
    await seedCarpenter(
      db,
      id: 'c-1',
      organizationId: 'org-1',
      displayCode: 'CARP-00004821',
      thumbnailUrl: 'https://cdn.example/thumb/c-1.jpg',
    );
    await seedCrmReviewAttendance(
      db,
      id: 'att-1',
      organizationId: 'org-1',
      campaignId: 'camp-1',
      sessionId: 'sess-1',
      carpenterId: 'c-1',
    );

    // A second organization's own case — must never surface through org-1's
    // queue/case/decision routes.
    await seedOrganizationWithUser(
      db,
      orgId: 'org-2',
      territoryId: 'terr-2',
      userId: 'user-3',
      username: 'other-org-verifier',
      roles: const ['crm_verifier'],
    );
    await seedCampaign(
      db,
      id: 'camp-2',
      organizationId: 'org-2',
      ownerId: 'user-3',
      status: CampaignStatus.approved,
    );
    await seedCampaignSession(
      db,
      id: 'sess-2',
      campaignId: 'camp-2',
      venue: 'Hall B',
    );
    await seedCarpenter(
      db,
      id: 'c-2',
      organizationId: 'org-2',
      territoryId: 'terr-2',
      phone: '+8801700009999',
      displayCode: 'CARP-00009999',
    );
    await seedCrmReviewAttendance(
      db,
      id: 'att-2',
      organizationId: 'org-2',
      campaignId: 'camp-2',
      sessionId: 'sess-2',
      carpenterId: 'c-2',
      capturedBy: 'user-3',
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

  Future<Response> decide(
    String id, {
    String? bearer,
    String? ifMatch,
    required Map<String, Object?> body,
  }) async => handler(
    Request(
      'POST',
      Uri.parse('http://localhost/verification/cases/$id/decision'),
      headers: {
        if (bearer != null) 'authorization': 'Bearer $bearer',
        if (ifMatch != null) 'if-match': ifMatch,
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    ),
  );

  // Mirrors [decide] but sends a raw (possibly non-JSON) string body, for
  // the malformed-body -> 400 test.
  Future<Response> rawDecide(
    String id, {
    String? bearer,
    String? ifMatch,
    required String rawBody,
  }) async => handler(
    Request(
      'POST',
      Uri.parse('http://localhost/verification/cases/$id/decision'),
      headers: {
        if (bearer != null) 'authorization': 'Bearer $bearer',
        if (ifMatch != null) 'if-match': ifMatch,
        'content-type': 'application/json',
      },
      body: rawBody,
    ),
  );

  Future<String> errorCode(Response r) async =>
      ((await decode(r))['error']! as Map)['code']! as String;

  Future<String> attendanceStatus(String id) async {
    final res = await db.execute(
      'SELECT status FROM attendance WHERE id = @id',
      params: {'id': id},
    );
    return row(res.single)['status']! as String;
  }

  Future<int> attendanceVersion(String id) async {
    final res = await db.execute(
      'SELECT version FROM attendance WHERE id = @id',
      params: {'id': id},
    );
    return row(res.single)['version']! as int;
  }

  // Most-recent decision row for [id] — the override tests each seed a
  // fresh, never-before-decided attendance, so "the" decision row is
  // unambiguous.
  Future<Map<String, Object?>> latestDecision(String id) async {
    final res = await db.execute(
      'SELECT outcome, supervisor_override FROM verification_decisions '
      'WHERE attendance_id = @id',
      params: {'id': id},
    );
    return row(res.single);
  }

  group('GET /verification/queue', () {
    test('lists the CRM_REVIEW attendance, org-scoped', () async {
      final res = await get('/verification/queue', bearer: verifierToken);
      expect(res.statusCode, 200);
      final items = ((await decode(res))['items']! as List)
          .cast<Map<String, Object?>>();
      expect(items, hasLength(1));
      final item = items.single;
      expect(item['attendanceId'], 'att-1');
      expect(item['carpenterName'], 'Md. Karim');
      expect(item['campaignName'], 'Test Campaign');
      expect(item['band'], 'MEDIUM');
      expect(item['ageSeconds'], greaterThanOrEqualTo(0));
      expect(
        items.any((i) => i['attendanceId'] == 'att-2'),
        isFalse,
        reason: 'a cross-org attendance must never appear',
      );
    });

    test('403 without verification_decide', () async {
      final res = await get('/verification/queue', bearer: viewerToken);
      expect(res.statusCode, 403);
    });

    test('401 unauthenticated', () async {
      final res = await get('/verification/queue');
      expect(res.statusCode, 401);
    });
  });

  group('GET /verification/cases/<id>', () {
    test('returns the case view and writes an audit-on-view row', () async {
      final res = await get('/verification/cases/att-1', bearer: verifierToken);
      expect(res.statusCode, 200);
      final body = await decode(res);
      expect(body['version'], 1);
      expect(body['carpenterIdMasked'], 'CARP-00004821');
      expect(body['carpenterName'], 'Md. Karim');
      expect(body['campaignName'], 'Test Campaign');
      expect(body['sessionName'], 'Hall A');
      expect(body['band'], 'MEDIUM');
      expect(body['referenceSource'], 'APPROVED_BASELINE_PHOTO');
      expect(
        body['reasons'],
        contains('Face comparison inconclusive — manual review required.'),
      );
      final capturedImageUrl = body['capturedImageUrl']! as String;
      expect(capturedImageUrl, contains('/media/att-1?'));
      expect(capturedImageUrl, contains('sig='));
      expect(body['referenceImageUrl'], 'https://cdn.example/thumb/c-1.jpg');

      final auditRes = await db.execute(
        "SELECT actor_id FROM audit_events "
        "WHERE action = 'verification.case_viewed' AND resource_id = 'att-1'",
      );
      expect(auditRes, hasLength(1));
      expect(row(auditRes.single)['actor_id'], 'user-1');
    });

    test(
      '403 without sensitive_media_view (and verification_decide)',
      () async {
        // No role in the vocabulary grants verification_decide without also
        // granting sensitive_media_view (auth/tokens.dart's crm_verifier and
        // crm_supervisor both carry both), so this exercises the same
        // fail-closed behaviour via the plain viewer, who lacks both gates on
        // this route.
        final res = await get('/verification/cases/att-1', bearer: viewerToken);
        expect(res.statusCode, 403);
      },
    );

    test('404 for a cross-org case id', () async {
      final res = await get('/verification/cases/att-2', bearer: verifierToken);
      expect(res.statusCode, 404);
    });

    test('401 unauthenticated', () async {
      final res = await get('/verification/cases/att-1');
      expect(res.statusCode, 401);
    });
  });

  group('POST /verification/cases/<id>/decision', () {
    test(
      'approve with a matching If-Match -> 200, APPROVED, version bumped, audited',
      () async {
        final res = await decide(
          'att-1',
          bearer: verifierToken,
          ifMatch: '1',
          body: const {'outcome': 'APPROVED'},
        );
        expect(res.statusCode, 200);
        expect((await decode(res))['status'], 'APPROVED');
        expect(await attendanceStatus('att-1'), 'APPROVED');
        expect(await attendanceVersion('att-1'), 2);

        final decisionRes = await db.execute(
          'SELECT verifier_id, outcome, version_at_decision '
          'FROM verification_decisions WHERE attendance_id = @id',
          params: {'id': 'att-1'},
        );
        expect(decisionRes, hasLength(1));
        final decisionRow = row(decisionRes.single);
        expect(decisionRow['verifier_id'], 'user-1');
        expect(decisionRow['outcome'], 'APPROVED');
        expect(decisionRow['version_at_decision'], 1);

        final auditRes = await db.execute(
          "SELECT actor_id FROM audit_events "
          "WHERE action = 'verification.decided' AND resource_id = 'att-1'",
        );
        expect(auditRes, hasLength(1));
        expect(row(auditRes.single)['actor_id'], 'user-1');
      },
    );

    test('reject with a reason -> 200, REJECTED', () async {
      final res = await decide(
        'att-1',
        bearer: verifierToken,
        ifMatch: '1',
        body: const {'outcome': 'REJECTED', 'reason': 'Face does not match.'},
      );
      expect(res.statusCode, 200);
      expect((await decode(res))['status'], 'REJECTED');
      expect(await attendanceStatus('att-1'), 'REJECTED');

      final decisionRes = await db.execute(
        'SELECT reason FROM verification_decisions WHERE attendance_id = @id',
        params: {'id': 'att-1'},
      );
      expect(row(decisionRes.single)['reason'], 'Face does not match.');
    });

    test('reject without a reason -> 422 DECISION_REASON_REQUIRED', () async {
      final res = await decide(
        'att-1',
        bearer: verifierToken,
        ifMatch: '1',
        body: const {'outcome': 'REJECTED'},
      );
      expect(res.statusCode, 422);
      expect(
        ((await decode(res))['error']! as Map)['code'],
        'DECISION_REASON_REQUIRED',
      );
      expect(await attendanceStatus('att-1'), 'CRM_REVIEW');
    });

    test('a blank reason is treated as no reason -> 422', () async {
      final res = await decide(
        'att-1',
        bearer: verifierToken,
        ifMatch: '1',
        body: const {'outcome': 'REJECTED', 'reason': '   '},
      );
      expect(res.statusCode, 422);
      expect(
        ((await decode(res))['error']! as Map)['code'],
        'DECISION_REASON_REQUIRED',
      );
    });

    test(
      'a stale If-Match -> 412 PRECONDITION_FAILED, status unchanged',
      () async {
        final res = await decide(
          'att-1',
          bearer: verifierToken,
          ifMatch: '0', // version-1: current version is 1
          body: const {'outcome': 'APPROVED'},
        );
        expect(res.statusCode, 412);
        expect(
          ((await decode(res))['error']! as Map)['code'],
          'PRECONDITION_FAILED',
        );
        expect(await attendanceStatus('att-1'), 'CRM_REVIEW');
        expect(await attendanceVersion('att-1'), 1);
      },
    );

    test(
      'an already-decided case cannot be re-decided even with a matching '
      'If-Match -> 412 PRECONDITION_FAILED, row unchanged, no new decision row',
      () async {
        await seedCrmReviewAttendance(
          db,
          id: 'att-decided',
          organizationId: 'org-1',
          campaignId: 'camp-1',
          sessionId: 'sess-1',
          carpenterId: 'c-1',
          status: 'APPROVED',
          version: 2,
        );

        final res = await decide(
          'att-decided',
          bearer: verifierToken,
          ifMatch: '2', // matches the current version exactly
          body: const {'outcome': 'REJECTED', 'reason': 'Second look.'},
        );

        expect(res.statusCode, 412);
        expect(
          ((await decode(res))['error']! as Map)['code'],
          'PRECONDITION_FAILED',
        );
        expect(await attendanceStatus('att-decided'), 'APPROVED');
        expect(await attendanceVersion('att-decided'), 2);

        final decisionRes = await db.execute(
          'SELECT 1 FROM verification_decisions WHERE attendance_id = @id',
          params: {'id': 'att-decided'},
        );
        expect(
          decisionRes,
          isEmpty,
          reason: 'the CAS must not insert a decision for a closed case',
        );
      },
    );

    test('return-for-recapture moves the case to RETURNED', () async {
      final res = await decide(
        'att-1',
        bearer: verifierToken,
        ifMatch: '1',
        body: const {
          'outcome': 'RETURN_FOR_RECAPTURE',
          'reason': 'Face not clearly visible; recapture in better light.',
        },
      );
      expect(res.statusCode, 200);
      expect((await decode(res))['status'], 'RETURNED');
      expect(await attendanceStatus('att-1'), 'RETURNED');
      expect(await attendanceVersion('att-1'), 2);

      final decisionRes = await db.execute(
        'SELECT outcome, reason FROM verification_decisions '
        'WHERE attendance_id = @id',
        params: {'id': 'att-1'},
      );
      final decisionRow = row(decisionRes.single);
      expect(decisionRow['outcome'], 'RETURN_FOR_RECAPTURE');
      expect(
        decisionRow['reason'],
        'Face not clearly visible; recapture in better light.',
      );
    });

    test('return-for-recapture requires a reason', () async {
      final res = await decide(
        'att-1',
        bearer: verifierToken,
        ifMatch: '1',
        body: const {'outcome': 'RETURN_FOR_RECAPTURE', 'reason': '  '},
      );
      expect(res.statusCode, 422);
      expect(
        ((await decode(res))['error']! as Map)['code'],
        'DECISION_REASON_REQUIRED',
      );
      expect(await attendanceStatus('att-1'), 'CRM_REVIEW');
    });

    test(
      'escalate keeps CRM_REVIEW and stamps the escalation marker',
      () async {
        final res = await decide(
          'att-1',
          bearer: verifierToken,
          ifMatch: '1',
          body: const {
            'outcome': 'ESCALATED',
            'reason': 'Ambiguous match; needs supervisor eyes.',
          },
        );
        expect(res.statusCode, 200);
        expect((await decode(res))['status'], 'CRM_REVIEW');
        expect(await attendanceStatus('att-1'), 'CRM_REVIEW');
        expect(await attendanceVersion('att-1'), 2);

        final attendanceRes = await db.execute(
          'SELECT escalated_at, escalated_by FROM attendance WHERE id = @id',
          params: {'id': 'att-1'},
        );
        final attendanceRow = row(attendanceRes.single);
        expect(attendanceRow['escalated_at'], isNotNull);
        expect(attendanceRow['escalated_by'], 'user-1');

        final decisionRes = await db.execute(
          'SELECT outcome, reason FROM verification_decisions '
          'WHERE attendance_id = @id',
          params: {'id': 'att-1'},
        );
        expect(row(decisionRes.single)['outcome'], 'ESCALATED');
      },
    );

    test('escalate requires a reason', () async {
      final res = await decide(
        'att-1',
        bearer: verifierToken,
        ifMatch: '1',
        body: const {'outcome': 'ESCALATED'},
      );
      expect(res.statusCode, 422);
      expect(
        ((await decode(res))['error']! as Map)['code'],
        'DECISION_REASON_REQUIRED',
      );
      expect(await attendanceStatus('att-1'), 'CRM_REVIEW');
    });

    // Superseded by Task 4: supervisorOverride:true from a caller lacking
    // verification_override is gated in the route (403 FORBIDDEN) before
    // the repo is ever called, even on an open CRM_REVIEW case — the 422
    // VERIFICATION_OUTCOME_UNSUPPORTED path Task 3 exercised here no longer
    // applies once override is a supported (permission-gated) outcome.
    test('supervisorOverride:true without the permission is 403', () async {
      final res = await decide(
        'att-1',
        bearer: verifierToken,
        ifMatch: '1',
        body: const {'outcome': 'APPROVED', 'supervisorOverride': true},
      );
      expect(res.statusCode, 403);
      expect(await errorCode(res), 'FORBIDDEN');
      expect(await attendanceStatus('att-1'), 'CRM_REVIEW');
    });

    // An unrecognised outcome wire (not the override path) still 422s.
    test('unknown outcome -> 422 VERIFICATION_OUTCOME_UNSUPPORTED', () async {
      final res = await decide(
        'att-1',
        bearer: verifierToken,
        ifMatch: '1',
        body: const {'outcome': 'NOT_A_REAL_OUTCOME', 'reason': 'x'},
      );
      expect(res.statusCode, 422);
      expect(await errorCode(res), 'VERIFICATION_OUTCOME_UNSUPPORTED');
      expect(await attendanceStatus('att-1'), 'CRM_REVIEW'); // unchanged
    });

    // A supervisor can re-decide a closed case; the override is recorded.
    test('supervisor override re-decides a closed case', () async {
      await seedCrmReviewAttendance(
        db,
        id: 'att-ov-1',
        organizationId: 'org-1',
        campaignId: 'camp-1',
        sessionId: 'sess-1',
        carpenterId: 'c-1',
        status: 'APPROVED',
        version: 2,
      );

      final res = await decide(
        'att-ov-1',
        bearer: supervisorToken,
        ifMatch: '2',
        body: const {
          'outcome': 'REJECTED',
          'reason': 'Original approval was incorrect on review.',
          'supervisorOverride': true,
        },
      );
      expect(res.statusCode, 200);
      expect(await attendanceStatus('att-ov-1'), 'REJECTED');
      expect(await attendanceVersion('att-ov-1'), 3);

      final decision = await latestDecision('att-ov-1');
      expect(decision['outcome'], 'REJECTED');
      expect(decision['supervisor_override'], isTrue);
    });

    // A plain verifier sending override -> 403 (not 422), even for an
    // already-closed case, and the row is untouched.
    test('override without verification_override is 403', () async {
      await seedCrmReviewAttendance(
        db,
        id: 'att-ov-2',
        organizationId: 'org-1',
        campaignId: 'camp-1',
        sessionId: 'sess-1',
        carpenterId: 'c-1',
        status: 'APPROVED',
        version: 2,
      );

      final res = await decide(
        'att-ov-2',
        bearer: verifierToken,
        ifMatch: '2',
        body: const {
          'outcome': 'REJECTED',
          'reason': 'x',
          'supervisorOverride': true,
        },
      );
      expect(res.statusCode, 403);
      expect(await errorCode(res), 'FORBIDDEN');
      expect(await attendanceStatus('att-ov-2'), 'APPROVED'); // unchanged
    });

    // Override stays version-safe: a stale If-Match still 412s even for a
    // supervisor — dropping the status guard must not drop the version one.
    test('supervisor override with a stale If-Match is 412', () async {
      await seedCrmReviewAttendance(
        db,
        id: 'att-ov-3',
        organizationId: 'org-1',
        campaignId: 'camp-1',
        sessionId: 'sess-1',
        carpenterId: 'c-1',
        status: 'APPROVED',
        version: 2,
      );

      final res = await decide(
        'att-ov-3',
        bearer: supervisorToken,
        ifMatch: '1', // stale: current version is 2
        body: const {
          'outcome': 'REJECTED',
          'reason': 'stale',
          'supervisorOverride': true,
        },
      );
      expect(res.statusCode, 412);
      expect(await attendanceStatus('att-ov-3'), 'APPROVED'); // unchanged
      expect(await attendanceVersion('att-ov-3'), 2);
    });

    // Override requires a reason, same as reject/return/escalate.
    test('supervisor override requires a reason', () async {
      await seedCrmReviewAttendance(
        db,
        id: 'att-ov-4',
        organizationId: 'org-1',
        campaignId: 'camp-1',
        sessionId: 'sess-1',
        carpenterId: 'c-1',
        status: 'APPROVED',
        version: 2,
      );

      final res = await decide(
        'att-ov-4',
        bearer: supervisorToken,
        ifMatch: '2',
        body: const {'outcome': 'APPROVED', 'supervisorOverride': true},
      );
      expect(res.statusCode, 422);
      expect(await errorCode(res), 'DECISION_REASON_REQUIRED');
      expect(await attendanceStatus('att-ov-4'), 'APPROVED'); // unchanged
    });

    // A non-JSON body -> 400, not 500.
    test('a malformed decision body is 400', () async {
      final res = await rawDecide(
        'att-1',
        bearer: verifierToken,
        ifMatch: '1',
        rawBody: 'not json',
      );
      expect(res.statusCode, 400);
      expect(await errorCode(res), 'BAD_REQUEST');
    });

    test('missing If-Match -> 400', () async {
      final res = await decide(
        'att-1',
        bearer: verifierToken,
        body: const {'outcome': 'APPROVED'},
      );
      expect(res.statusCode, 400);
    });

    test('403 without verification_decide', () async {
      final res = await decide(
        'att-1',
        bearer: viewerToken,
        ifMatch: '1',
        body: const {'outcome': 'APPROVED'},
      );
      expect(res.statusCode, 403);
    });

    test('404 for a cross-org attendance id', () async {
      final res = await decide(
        'att-2',
        bearer: verifierToken,
        ifMatch: '1',
        body: const {'outcome': 'APPROVED'},
      );
      expect(res.statusCode, 404);
    });

    test('401 unauthenticated', () async {
      final res = await decide(
        'att-1',
        ifMatch: '1',
        body: const {'outcome': 'APPROVED'},
      );
      expect(res.statusCode, 401);
    });
  });
}
