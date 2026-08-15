// The mock stays until the real service has been green for a while (spec
// §9). While both exist, they must agree on the contract the client depends
// on: status vocabulary, list envelope shape, `version` presence, and
// pagination clamp semantics — so this file runs the SAME assertions
// against both, rather than trusting the mock's own comments to stay
// accurate as the real service evolves underneath it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

/// One backend to probe: [name] names it in test descriptions, [getJson]
/// performs a `GET` and returns the decoded JSON object body, [postJson]
/// performs a `POST` with a JSON body and returns the status and decoded
/// JSON object body.
class ParityTarget {
  ParityTarget(this.name, this.getJson, this.postJson);

  final String name;
  final Future<Map<String, Object?>> Function(String pathAndQuery) getJson;
  final Future<({int status, Map<String, Object?> body})> Function(
    String pathAndQuery,
    Map<String, Object?> body,
  )
  postJson;
}

/// The mock's listen port for this file only — distinct from its usual 8080
/// default so this suite never collides with a locally-running dev instance
/// of either backend.
const int _mockPort = 8099;

/// File-level counter so every real-side POST in this suite gets a unique
/// `Idempotency-Key` — reusing one across distinct requests would make the
/// second call replay the first's cached response instead of actually
/// running (server/lib/src/infra/idempotency.dart).
var _keySeq = 0;

void main() {
  late Process mockProcess;
  final openDbs = <Db>[];

  setUpAll(() async {
    // Run as a real subprocess rather than in-process: tool/mock_server is a
    // standalone `bin/server.dart` with its own `main()`, not a library this
    // package can import and call a handler out of.
    mockProcess = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      workingDirectory: '../tool/mock_server',
      environment: {'PORT': '$_mockPort'},
    );
    unawaited(mockProcess.stderr.transform(utf8.decoder).forEach(stderr.write));
    // Must be drained, not left unread: the mock's logRequests() middleware
    // writes a line per request to its stdout, and an unread child-process
    // stdout pipe fills and blocks the child on its next write once enough
    // requests accumulate — which stalls whatever HTTP response it was mid-
    // write on. That surfaced as this suite's later, request-heavier tests
    // (Task 9's import poll/commit flow) hanging until the 30s test timeout
    // with "Connection closed before full header was received", even though
    // the exact same requests replayed by hand against a fresh mock process
    // succeeded instantly — the difference was purely this unread pipe.
    unawaited(mockProcess.stdout.drain<void>());
    await _waitUntilUp(Uri.parse('http://127.0.0.1:$_mockPort/campaigns'));
  });

  tearDownAll(() async {
    mockProcess.kill();
    for (final db in openDbs) {
      await db.close();
    }
  });

  /// Builds both targets against a freshly seeded real database and the
  /// already-running mock. A fresh helper per test, not a shared fixture:
  /// each test seeds the real side differently (row counts, statuses), and
  /// `freshDb()` (test/support/test_db.dart) enforces `concurrency: 1` across
  /// the whole suite so this is safe.
  Future<({ParityTarget real, ParityTarget mock, Db realDb})> buildTargets({
    required int campaignCount,
    bool seedCarpenters = false,
  }) async {
    final db = await freshDb();
    openDbs.add(db);
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // campaign_creator, org-1/user-1
    if (campaignCount > 0) {
      await seedCampaigns(db, count: campaignCount);
    }
    if (seedCarpenters) {
      await seedCarpenter(db, id: 'CARP_E2E');
      await seedCarpenter(
        db,
        id: 'CARP_E2E_2',
        name: 'Karim Uddin',
        phone: '+8801700007734',
        displayCode: 'CARP-00007734',
      );
    }

    final config = ServerConfig.fromEnvironment({
      'DATABASE_URL': testDatabaseUrl,
      'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
    });
    final tokens = TokenService(db: db, config: config);
    final token = (await tokens.issueFor('user-1')).accessToken;
    final handler = buildApp(db: db, config: config);

    final real = ParityTarget(
      'real service',
      (pathAndQuery) async {
        final res = await handler(
          Request(
            'GET',
            Uri.parse('http://localhost$pathAndQuery'),
            headers: {'authorization': 'Bearer $token'},
          ),
        );
        return jsonDecode(await res.readAsString()) as Map<String, Object?>;
      },
      (pathAndQuery, body) async {
        final res = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost$pathAndQuery'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
              'Idempotency-Key': 'parity-${_keySeq++}',
            },
            body: jsonEncode(body),
          ),
        );
        final decoded =
            jsonDecode(await res.readAsString()) as Map<String, Object?>;
        return (status: res.statusCode, body: decoded);
      },
    );

    final mock = ParityTarget(
      'mock server',
      (pathAndQuery) async {
        final res = await _httpGet(
          Uri.parse('http://127.0.0.1:$_mockPort$pathAndQuery'),
        );
        return jsonDecode(res) as Map<String, Object?>;
      },
      (pathAndQuery, body) async {
        final res = await _httpPost(
          Uri.parse('http://127.0.0.1:$_mockPort$pathAndQuery'),
          body,
        );
        return (
          status: res.status,
          body: jsonDecode(res.body) as Map<String, Object?>,
        );
      },
    );

    return (real: real, mock: mock, realDb: db);
  }

  for (final targetName in ['real', 'mock']) {
    test('$targetName: list returns {items,total} with wire statuses and an '
        'int version', () async {
      final targets = await buildTargets(campaignCount: 5);
      final target = targetName == 'real' ? targets.real : targets.mock;

      final body = await target.getJson('/campaigns?page=1&pageSize=5');
      expect(body.keys, containsAll(<String>['items', 'total']));
      for (final item in body['items']! as List<Object?>) {
        final status = (item as Map<String, Object?>)['status']! as String;
        expect(
          CampaignStatus.tryParseWire(status),
          isNotNull,
          reason: '$status is not in the shared vocabulary',
        );
        expect(item['version'], isA<int>());
      }
    });

    // D6's clamp (campaign_repo.dart: page < 1 -> 1; pageSize > 100 -> 100)
    // must hold on BOTH backends, or a client that relies on it (T-8's list
    // screen) would silently paginate differently depending on which
    // process happens to be behind API_BASE_URL. Task 10 made the mock agree
    // with this; this test is what stops it drifting back.
    test(
      '$targetName: page < 1 clamps to page 1, same items as page=1',
      () async {
        final targets = await buildTargets(campaignCount: 3);
        final target = targetName == 'real' ? targets.real : targets.mock;

        final zero = await target.getJson('/campaigns?page=0&pageSize=5');
        final one = await target.getJson('/campaigns?page=1&pageSize=5');
        expect(zero['items'], one['items']);
      },
    );

    // Review finding (F3, Task 11 fix round): a shared `campaignCount: 3`
    // made this assertion vacuous on BOTH targets -- `<= 100` can never fail
    // when only 3 rows exist, whichever backend answers it. The two targets
    // now get genuinely different, falsifiable setups: the real target is
    // seeded past 100 rows so the clamp has something to actually clamp;
    // the mock has no seeding endpoint of its own (`tool/mock_server` is a
    // fixed 3-row fixture, `CAMP-1..3`, for the lifetime of this file's one
    // subprocess -- see `setUpAll`), so it gets a paging assertion sized to
    // what it actually holds instead. Every assertion here must be able to
    // fail; neither branch is `lessThanOrEqualTo`.
    if (targetName == 'real') {
      test(
        'real: pageSize is clamped to 100 even with 105 seeded rows',
        () async {
          final targets = await buildTargets(campaignCount: 105);
          final body = await targets.real.getJson('/campaigns?pageSize=10000');
          expect(
            (body['items']! as List<Object?>).length,
            100,
            reason:
                '105 seeded rows must clamp to exactly 100, not be served '
                'unbounded and not be silently truncated below the clamp',
          );
        },
      );
    } else {
      test('mock: paginates its 3 fixed rows exactly (falsifiable stand-in for '
          'the >100 clamp, which 3 fixed rows can never exercise)', () async {
        final targets = await buildTargets(campaignCount: 0);
        final firstPage = await targets.mock.getJson('/campaigns?pageSize=2');
        expect(
          (firstPage['items']! as List<Object?>).length,
          2,
          reason: 'the mock always seeds exactly 3 fixture campaigns',
        );
        final secondPage = await targets.mock.getJson(
          '/campaigns?pageSize=2&page=2',
        );
        expect(
          (secondPage['items']! as List<Object?>).length,
          1,
          reason:
              'page 2 of size 2 over 3 rows must be the single remaining '
              'row -- 0 would mean a broken offset, 2 would mean page was '
              'silently ignored',
        );
      });
    }

    test(
      '$targetName: carpenter search items satisfy the masked shape',
      () async {
        final targets = await buildTargets(
          campaignCount: 0,
          seedCarpenters: true,
        );
        final target = targetName == 'real' ? targets.real : targets.mock;

        final body = await target.getJson('/carpenters?q=karim');
        final items = (body['items']! as List).cast<Map<String, Object?>>();
        expect(items, isNotEmpty);
        for (final c in items) {
          expect(c['displayId'], matches(RegExp(r'^CARP-••\d{4}$')));
          expect(c['phoneSuffix'], matches(RegExp(r'^\d{4}$')));
          expect(c['eligible'], isA<bool>());
          expect(c['syncStatus'], anyOf('LOCAL_ONLY', 'PENDING_PROFILE_SYNC'));
          // attendanceState is OPTIONAL in the shared contract (2a.D4): the
          // real service omits it, the mock still emits it for the configs
          // that remain mocked. If present it must at least be a string.
          if (c.containsKey('attendanceState')) {
            expect(c['attendanceState'], isA<String>());
          }
        }
      },
    );

    test('$targetName: registration answers the counts shape', () async {
      final targets = await buildTargets(
        campaignCount: 1,
        seedCarpenters: true,
      );
      final target = targetName == 'real' ? targets.real : targets.mock;
      // seed-0 is buildTargets' first campaign on the real side; the mock
      // ignores the id entirely.
      final res = await target.postJson('/campaigns/seed-0/registrations', {
        'carpenterIds': ['CARP_E2E'],
      });
      expect(res.status, 200);
      expect(res.body['registered'], isA<int>());
      expect(res.body['alreadyRegistered'], isA<int>());
    });

    test('$targetName: profile request answers 201 with a provisional '
        'carpenter', () async {
      final targets = await buildTargets(
        campaignCount: 1,
        seedCarpenters: false,
      );
      final target = targetName == 'real' ? targets.real : targets.mock;
      final res = await target.postJson('/campaigns/seed-0/profile-requests', {
        'name': 'Parity Person',
        'phone': '+8801755556666',
      });
      expect(res.status, 201);
      expect(res.body['requestId'], isA<String>());
      final carpenter = res.body['carpenter']! as Map<String, Object?>;
      expect(carpenter['syncStatus'], 'PENDING_PROFILE_SYNC');
      expect(carpenter['displayId'], matches(RegExp(r'^CARP-••\d{4}$')));
      expect(carpenter.containsKey('phone'), isFalse);
    });

    // Task 9: the ratified async import shapes (2b.D1-D5). dry-run -> 202
    // PROCESSING -> (poll) READY_TO_COMMIT with classified rows -> commit ->
    // COMPLETED, under the namespaced `/campaigns/<id>/imports/<jobId>/commit`
    // path on both backends.
    //
    // The real dry-run route requires an actual multipart "file" part
    // (server/lib/src/import_/import_routes.dart's `_readFilePart`, backed by
    // shelf_multipart) that this harness's JSON-only `postJson` cannot send.
    // So only the mock is driven through dry-run itself; the real side is
    // seeded directly into the DB with `seedImportJob`, landing in the same
    // post-classify state the mock reaches after its first poll — mirroring
    // `import_routes_test.dart`'s commit test. Everything from the shape
    // assertions onward runs identically on both targets.
    test(
      '$targetName: import job shape pins {id,campaignId,status,rows} and '
      'the ImportStatus/ImportRowOutcome vocabularies through poll and commit',
      () async {
        final targets = await buildTargets(
          campaignCount: 1,
          seedCarpenters: true,
        );
        final target = targetName == 'real' ? targets.real : targets.mock;

        late final String jobId;
        late final Map<String, Object?> initial;
        if (targetName == 'mock') {
          // The mock's dry-run just drains whatever body arrives, so the
          // harness's plain-JSON postJson is enough to create the job.
          final created = await target.postJson(
            '/campaigns/seed-0/imports/dry-run',
            const {},
          );
          expect(created.status, 202);
          initial = created.body;
          expect(initial['status'], 'PROCESSING');
          jobId = initial['id']! as String;
        } else {
          jobId = 'parity-import-1';
          await seedImportJob(
            targets.realDb,
            id: jobId,
            campaignId: 'seed-0',
            rows: const [
              (
                rowId: 'row-1',
                name: 'Md. Karim',
                phone: '+8801700004821',
                outcome: 'VALID',
              ),
              (
                rowId: 'row-2',
                name: 'Brand New',
                phone: '+8801733334444',
                outcome: 'NEEDS_PROFILE',
              ),
            ],
          );
          // The seed helper leaves linked_carpenter_id null; the VALID row
          // needs it set for commit to find the matched carpenter (mirrors
          // import_routes_test.dart's commit test).
          await targets.realDb.execute(
            "UPDATE import_job_rows SET linked_carpenter_id = 'CARP_E2E' "
            "WHERE job_id = @j AND row_id = 'row-1'",
            params: {'j': jobId},
          );
          initial = await target.getJson('/imports/$jobId');
        }

        // Shape pinned identically on both targets.
        expect(
          initial.keys,
          containsAll(<String>[
            'id',
            'campaignId',
            'status',
            'rows',
            'totalRows',
            'processedRows',
          ]),
        );
        expect(
          ImportStatus.tryParseWire(initial['status']! as String),
          isNotNull,
          reason:
              '${initial['status']} is not in the shared ImportStatus '
              'vocabulary',
        );

        // Poll: the mock flips PROCESSING -> READY_TO_COMMIT (planting
        // classified rows) on this GET; the real job above was already
        // seeded in that terminal state, so this is a same-shape re-read.
        // Both must land on the identical destination.
        final polled = await target.getJson('/imports/$jobId');
        expect(polled['status'], 'READY_TO_COMMIT');
        final rows = (polled['rows']! as List).cast<Map<String, Object?>>();
        expect(rows, isNotEmpty);
        for (final r in rows) {
          final outcome = r['outcome'];
          expect(
            outcome == null ||
                ImportRowOutcome.tryParseWire(outcome as String) != null,
            isTrue,
            reason:
                '$outcome is not null and not in the shared '
                'ImportRowOutcome vocabulary',
          );
        }
        expect(
          rows.map((r) => r['outcome']).toSet(),
          containsAll(<String>['VALID', 'NEEDS_PROFILE']),
        );

        // Commit: READY_TO_COMMIT -> COMPLETED, namespaced under the
        // campaign — the real server has no un-namespaced commit route.
        final committed = await target.postJson(
          '/campaigns/seed-0/imports/$jobId/commit',
          const {},
        );
        expect(committed.status, 200);
        expect(committed.body['status'], 'COMPLETED');
      },
    );

    // Task 7 (3a): the mock's session fixture was modernised to the ratified
    // SCREAMING_SNAKE wire (UPCOMING, zeroed activity counts) to match the
    // real service exactly -- this pins that neither backend drifts back to
    // the old camelCase/non-zero fixture. The real side is seeded with its
    // own campaign+session (buildTargets' fixture campaigns don't carry
    // sessions), while the mock answers from its own fixed 'CAMP-1' session
    // -- what's compared is the SHAPE and VOCABULARY both return, not a
    // shared row.
    test('$targetName: session list returns {items} whose entries carry the '
        'ratified SessionStatus vocabulary and key set, and POST start '
        'transitions to ACTIVE', () async {
      final targets = await buildTargets(campaignCount: 0);
      await seedCampaign(
        targets.realDb,
        id: 'parity-session-camp',
        status: CampaignStatus.approved,
      );
      await seedCampaignSession(
        targets.realDb,
        id: 'parity-session-0',
        campaignId: 'parity-session-camp',
        venue: 'Hall A',
        startAt: DateTime.utc(2026, 9, 1, 9),
        capacity: 60,
      );

      final path = targetName == 'real'
          ? '/campaigns/parity-session-camp/sessions'
          : '/campaigns/CAMP-1/sessions';
      final target = targetName == 'real' ? targets.real : targets.mock;

      final body = await target.getJson(path);
      expect(body.keys, contains('items'));
      final items = (body['items']! as List).cast<Map<String, Object?>>();
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.keys.toSet(), <String>{
          'id',
          'campaignId',
          'venue',
          'status',
          'startAt',
          'endAt',
          'capacity',
          'registeredCount',
          'pendingSyncCount',
          'reviewCount',
          'approvedCount',
          'readinessOk',
        });
        final status = item['status']! as String;
        expect(
          SessionStatus.tryParseWire(status),
          isNotNull,
          reason: '$status is not in the shared SessionStatus vocabulary',
        );
      }

      // The GET assertions above only ever observe the seeded UPCOMING
      // status, so they never exercise `sessionAction`'s SCREAMING_SNAKE
      // action map (Task 7) -- a regression back to lowercase 'active'
      // there would go uncaught. Starting the session on both targets and
      // asserting the returned status is exactly 'ACTIVE' is what actually
      // pins that map. Real POST requires `campaign_create`, which is the
      // default role `seedOrganizationWithUser` grants `user-1` -- the same
      // user `buildTargets` already mints the bearer token for above.
      final sessionId = targetName == 'real'
          ? 'parity-session-0'
          : (items.first['id']! as String);
      // Uri.encodeComponent defensively: neither id is expected to carry
      // reserved characters, but a session id built into a path segment
      // should always be encoded rather than assumed safe.
      final started = await target.postJson(
        '/sessions/${Uri.encodeComponent(sessionId)}/start',
        const {},
      );
      expect(started.status, 200);
      final startedStatus = started.body['status']! as String;
      expect(
        SessionStatus.tryParseWire(startedStatus),
        isNotNull,
        reason: '$startedStatus is not in the shared SessionStatus vocabulary',
      );
      expect(
        startedStatus,
        'ACTIVE',
        reason:
            'a regression to the mock\'s old lowercase action map ("active") '
            'must fail this, not just fail SessionStatus.tryParseWire',
      );
    });

    // Task 7 (4a): the mock's confirm status and consent shape were aligned
    // to the real service's wire -- SCREAMING_SNAKE (previously camelCase
    // 'matchProcessing') and a {'notices': [...]} envelope from a new GET
    // /consent/notices route. Task 3 (5a) moved the confirm literal on:
    // a captured attendance now lands straight in CRM_REVIEW so it flows
    // into the verification queue, rather than sitting in MATCH_PROCESSING.
    // This pins both so neither backend drifts back.
    //
    // GET /consent/notices only needs any authenticated org member, so
    // buildTargets' default user-1 token (via `target.getJson`) works
    // unchanged on both backends. POST /attendance/<id>/confirm needs the
    // `attendance_capture` permission, which user-1's default
    // `campaign_creator` role does NOT carry (auth/tokens.dart's
    // permissionsByRole) -- so the real side mints its own field_user token
    // and calls the app handler directly instead of going through
    // `real.postJson`, which always sends user-1's baked-in bearer.
    test('$targetName: consent notices carry version+language, and confirm '
        'returns the exact literal CRM_REVIEW', () async {
      final targets = await buildTargets(campaignCount: 0);
      final target = targetName == 'real' ? targets.real : targets.mock;

      if (targetName == 'real') {
        await targets.realDb.execute(
          'INSERT INTO consent_notices '
          '(version, language, title, body, content_hash) VALUES '
          "(1, 'en', 'Consent', 'We record your attendance for "
          "verification.', 'hash-en')",
        );
      }
      final notices = await target.getJson('/consent/notices');
      expect(notices.keys, contains('notices'));
      final items = (notices['notices']! as List).cast<Map<String, Object?>>();
      expect(items, isNotEmpty);
      for (final n in items) {
        expect(n['version'], isA<int>());
        expect(n['language'], isA<String>());
      }

      const key = 'parity-attendance-key';
      final confirmBody = <String, Object?>{
        'sessionId': 'parity-attendance-sess',
        'carpenterId': 'parity-attendance-carp',
        'capturedAt': '2026-09-01T09:05:00.000Z',
        'consentVersion': 1,
        'consentLanguage': 'en',
        'consentShownAt': '2026-09-01T09:04:00.000Z',
        'consentContentHash': 'hash-en',
      };

      late final Map<String, Object?> confirmed;
      if (targetName == 'mock') {
        // The mock doesn't validate sessionId/carpenterId or require
        // evidence to exist first -- it just echoes the confirmed status.
        final res = await target.postJson(
          '/attendance/$key/confirm',
          confirmBody,
        );
        expect(res.status, 200);
        confirmed = res.body;
      } else {
        await seedCampaign(
          targets.realDb,
          id: 'parity-attendance-camp',
          status: CampaignStatus.approved,
        );
        await seedCampaignSession(
          targets.realDb,
          id: 'parity-attendance-sess',
          campaignId: 'parity-attendance-camp',
          venue: 'Hall A',
          startAt: DateTime.utc(2026, 9, 1, 9),
          capacity: 60,
        );
        await seedCarpenter(targets.realDb, id: 'parity-attendance-carp');
        // The real confirm requires an uploaded evidence blob for the
        // attendance key before it will confirm (attendance_repo.dart's
        // evidenceMissing check) -- inserted directly rather than via a
        // real presign+upload round trip, mirroring
        // attendance_routes_test.dart's `seedEvidence`.
        await targets.realDb.execute(
          'INSERT INTO media_objects (id, content_type, bytes) '
          "VALUES (@id, 'application/octet-stream', @b)",
          params: {
            'id': key,
            'b': Uint8List.fromList(const [1, 2, 3]),
          },
        );
        await seedOrganizationWithUser(
          targets.realDb,
          userId: 'parity-field-user',
          username: 'parity-field',
          roles: const ['field_user'],
        );
        final config = ServerConfig.fromEnvironment({
          'DATABASE_URL': testDatabaseUrl,
          'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
        });
        final fieldToken = (await TokenService(
          db: targets.realDb,
          config: config,
        ).issueFor('parity-field-user')).accessToken;
        final handler = buildApp(db: targets.realDb, config: config);

        final res = await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/attendance/$key/confirm'),
            headers: {
              'authorization': 'Bearer $fieldToken',
              'content-type': 'application/json',
              'Idempotency-Key': 'parity-confirm-${_keySeq++}',
            },
            body: jsonEncode(confirmBody),
          ),
        );
        expect(res.statusCode, 200);
        confirmed =
            jsonDecode(await res.readAsString()) as Map<String, Object?>;
      }

      expect(
        confirmed['status'],
        'CRM_REVIEW',
        reason:
            '$targetName must return the exact literal, not a camelCase '
            'or otherwise-cased variant',
      );
    });

    // Task 7 (5a): the mock's verification queue/case fixtures were
    // modernised to the ratified SCREAMING_SNAKE wire (`band`/`referenceSource`
    // were previously camelCase, e.g. 'medium'/'verifiedProfilePhoto'), and
    // its decision handler now reads the case's own version against the
    // caller's `If-Match` header instead of hardcoding a 409 for
    // CASE_CONFLICT. This pins both: the queue/case shapes carry real
    // MatchBand/ReferenceSource wire values on both backends, and a stale
    // If-Match yields exactly 412 on both — not the mock's old unconditional
    // 409.
    //
    // The real side needs its own `crm_verifier` token (verification_decide +
    // sensitive_media_view): `buildTargets`' default user-1 is
    // `campaign_creator`, which carries neither (auth/tokens.dart's
    // permissionsByRole) -- so, as the confirm-parity case above does for its
    // field_user token, the real side mints its own token and calls the app
    // handler directly instead of going through `target.getJson`/`postJson`.
    test(
      '$targetName: verification queue/case carry SCREAMING_SNAKE '
      'band/referenceSource, and a stale If-Match decision returns 412',
      () async {
        final targets = await buildTargets(campaignCount: 0);

        late final String attendanceId;
        late final Map<String, Object?> queueItem;
        late final Map<String, Object?> caseView;
        String verifierBearer = '';
        Handler? realHandler;

        Future<Map<String, Object?>> getReal(String path) async {
          final res = await realHandler!(
            Request(
              'GET',
              Uri.parse('http://localhost$path'),
              headers: {'authorization': 'Bearer $verifierBearer'},
            ),
          );
          return jsonDecode(await res.readAsString()) as Map<String, Object?>;
        }

        if (targetName == 'real') {
          attendanceId = 'parity-verify-att';
          await seedOrganizationWithUser(
            targets.realDb,
            userId: 'parity-verifier',
            username: 'parity-verifier',
            roles: const ['crm_verifier'],
          );
          await seedCampaign(
            targets.realDb,
            id: 'parity-verify-camp',
            status: CampaignStatus.approved,
          );
          await seedCampaignSession(
            targets.realDb,
            id: 'parity-verify-sess',
            campaignId: 'parity-verify-camp',
            venue: 'Hall A',
          );
          await seedCarpenter(targets.realDb, id: 'parity-verify-carp');
          await targets.realDb.execute(
            'INSERT INTO attendance '
            '(id, organization_id, campaign_id, session_id, carpenter_id, '
            ' media_ref, status, captured_by, captured_at, machine_band, '
            ' machine_reference_src, machine_reasons, version) '
            "VALUES (@id, 'org-1', 'parity-verify-camp', "
            "'parity-verify-sess', 'parity-verify-carp', @id, 'CRM_REVIEW', "
            "'parity-verifier', now(), 'MEDIUM', 'APPROVED_BASELINE_PHOTO', "
            "@reasons::jsonb, 1)",
            params: {
              'id': attendanceId,
              'reasons': jsonEncode(const [
                'Landmark alignment within tolerance',
              ]),
            },
          );
          await targets.realDb.execute(
            "INSERT INTO media_objects (id, content_type, bytes) "
            "VALUES (@id, 'image/png', @bytes)",
            params: {
              'id': attendanceId,
              'bytes': Uint8List.fromList(const [1, 2, 3, 4]),
            },
          );

          final config = ServerConfig.fromEnvironment({
            'DATABASE_URL': testDatabaseUrl,
            'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
          });
          verifierBearer = (await TokenService(
            db: targets.realDb,
            config: config,
          ).issueFor('parity-verifier')).accessToken;
          realHandler = buildApp(db: targets.realDb, config: config);

          final queueBody = await getReal('/verification/queue');
          queueItem =
              ((queueBody['items']! as List).cast<Map<String, Object?>>())
                  .singleWhere((i) => i['attendanceId'] == attendanceId);
          caseView = await getReal('/verification/cases/$attendanceId');
        } else {
          attendanceId = 'CASE_E2E';
          final queueBody = await targets.mock.getJson('/verification/queue');
          queueItem =
              ((queueBody['items']! as List).cast<Map<String, Object?>>())
                  .singleWhere((i) => i['attendanceId'] == attendanceId);
          caseView = await targets.mock.getJson(
            '/verification/cases/$attendanceId',
          );
        }

        // (a) Queue item shape.
        expect(
          queueItem.keys,
          containsAll(<String>[
            'attendanceId',
            'carpenterName',
            'campaignName',
            'ageSeconds',
            'band',
            'referenceSource',
            'assigneeId',
          ]),
        );
        expect(
          MatchBand.tryParseWire(queueItem['band']! as String),
          isNotNull,
          reason:
              '${queueItem['band']} is not a SCREAMING_SNAKE MatchBand wire '
              'value',
        );

        // (b) Case shape.
        expect(
          caseView.keys,
          containsAll(<String>[
            'attendanceId',
            'version',
            'carpenterName',
            'carpenterIdMasked',
            'campaignName',
            'sessionName',
            'capturedAt',
            'capturedImageUrl',
            'referenceImageUrl',
            'band',
            'referenceSource',
            'padReview',
            'lowQuality',
            'reasons',
          ]),
        );
        expect(
          MatchBand.tryParseWire(caseView['band']! as String),
          isNotNull,
          reason:
              '${caseView['band']} is not a SCREAMING_SNAKE MatchBand '
              'wire value',
        );
        expect(
          ReferenceSource.tryParseWire(caseView['referenceSource']! as String),
          isNotNull,
          reason:
              '${caseView['referenceSource']} is not a SCREAMING_SNAKE '
              'ReferenceSource wire value',
        );

        // (c) A stale If-Match on the decision returns exactly 412 on both
        // backends. The real fixture is at version 1, so `If-Match: 0` is
        // stale; the mock's CASE_CONFLICT fixture is fixed at version 2, so
        // `If-Match: 1` (what a client that last saw version 1 would send)
        // is stale there too.
        if (targetName == 'real') {
          final res = await realHandler!(
            Request(
              'POST',
              Uri.parse(
                'http://localhost/verification/cases/$attendanceId/decision',
              ),
              headers: {
                'authorization': 'Bearer $verifierBearer',
                'if-match': '0',
                'content-type': 'application/json',
              },
              body: jsonEncode(const {'outcome': 'APPROVED'}),
            ),
          );
          expect(res.statusCode, 412);
        } else {
          final res = await _httpPostWithIfMatch(
            Uri.parse(
              'http://127.0.0.1:$_mockPort/verification/cases/'
              'CASE_CONFLICT/decision',
            ),
            const {'outcome': 'APPROVED'},
            ifMatch: '1',
          );
          expect(res.status, 412);
        }
      },
    );

    // Task 7 (5b): the mock's decision handler now honours the full
    // four-outcome map (previously it just echoed `outcome` back verbatim
    // as `status`) and the reason-422, and its case fixture now carries a
    // `status` key it previously omitted entirely. This pins all three on
    // both backends: RETURN_FOR_RECAPTURE maps to the exact literal
    // RETURNED, a blank reason on that same reject/return/escalate family
    // 422s as DECISION_REASON_REQUIRED, and the case wire's `status` is
    // always a value AttendanceStatus.tryParseWire accepts.
    //
    // supervisorOverride's permission gate (403 without
    // verification_override) is REAL-SERVICE-ONLY, same as
    // sensitive_media_view (5a) and the RBAC 403s already noted above: the
    // mock has no per-request permission model to 403 against, so it is not
    // asserted here on either backend.
    test('$targetName: RETURN_FOR_RECAPTURE decision maps to RETURNED, a blank '
        'reason on it 422s DECISION_REASON_REQUIRED, and the case wire\'s '
        'status is a valid AttendanceStatus wire value', () async {
      final targets = await buildTargets(campaignCount: 0);

      late final String attendanceId;
      late final Map<String, Object?> caseView;
      String verifierBearer = '';
      Handler? realHandler;

      Future<Map<String, Object?>> getReal(String path) async {
        final res = await realHandler!(
          Request(
            'GET',
            Uri.parse('http://localhost$path'),
            headers: {'authorization': 'Bearer $verifierBearer'},
          ),
        );
        return jsonDecode(await res.readAsString()) as Map<String, Object?>;
      }

      Future<({int status, Map<String, Object?> body})> decideReal(
        String id, {
        required String ifMatch,
        required Map<String, Object?> body,
      }) async {
        final res = await realHandler!(
          Request(
            'POST',
            Uri.parse('http://localhost/verification/cases/$id/decision'),
            headers: {
              'authorization': 'Bearer $verifierBearer',
              'if-match': ifMatch,
              'content-type': 'application/json',
            },
            body: jsonEncode(body),
          ),
        );
        final decoded =
            jsonDecode(await res.readAsString()) as Map<String, Object?>;
        return (status: res.statusCode, body: decoded);
      }

      if (targetName == 'real') {
        attendanceId = 'parity-decision-att';
        await seedOrganizationWithUser(
          targets.realDb,
          userId: 'parity-decision-verifier',
          username: 'parity-decision-verifier',
          roles: const ['crm_verifier'],
        );
        await seedCampaign(
          targets.realDb,
          id: 'parity-decision-camp',
          status: CampaignStatus.approved,
        );
        await seedCampaignSession(
          targets.realDb,
          id: 'parity-decision-sess',
          campaignId: 'parity-decision-camp',
          venue: 'Hall A',
        );
        await seedCarpenter(targets.realDb, id: 'parity-decision-carp');
        await targets.realDb.execute(
          'INSERT INTO attendance '
          '(id, organization_id, campaign_id, session_id, carpenter_id, '
          ' media_ref, status, captured_by, captured_at, machine_band, '
          ' machine_reference_src, machine_reasons, version) '
          "VALUES (@id, 'org-1', 'parity-decision-camp', "
          "'parity-decision-sess', 'parity-decision-carp', @id, "
          "'CRM_REVIEW', 'parity-decision-verifier', now(), 'MEDIUM', "
          "'APPROVED_BASELINE_PHOTO', @reasons::jsonb, 1)",
          params: {
            'id': attendanceId,
            'reasons': jsonEncode(const [
              'Landmark alignment within tolerance',
            ]),
          },
        );
        await targets.realDb.execute(
          "INSERT INTO media_objects (id, content_type, bytes) "
          "VALUES (@id, 'image/png', @bytes)",
          params: {
            'id': attendanceId,
            'bytes': Uint8List.fromList(const [1, 2, 3, 4]),
          },
        );

        final config = ServerConfig.fromEnvironment({
          'DATABASE_URL': testDatabaseUrl,
          'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
        });
        verifierBearer = (await TokenService(
          db: targets.realDb,
          config: config,
        ).issueFor('parity-decision-verifier')).accessToken;
        realHandler = buildApp(db: targets.realDb, config: config);

        caseView = await getReal('/verification/cases/$attendanceId');
      } else {
        attendanceId = 'CASE_E2E';
        caseView = await targets.mock.getJson(
          '/verification/cases/$attendanceId',
        );
      }

      // (a) The case wire always carries a `status` in the shared
      // AttendanceStatus vocabulary.
      expect(
        caseView.keys,
        contains('status'),
        reason: 'the case view must carry a status key',
      );
      expect(
        AttendanceStatus.tryParseWire(caseView['status']! as String),
        isNotNull,
        reason:
            '${caseView['status']} is not in the shared AttendanceStatus '
            'vocabulary',
      );

      // (b) A blank reason on RETURN_FOR_RECAPTURE (part of the
      // reject/return/escalate family that requires one) 422s without
      // mutating the case -- so the very same case can go on to (c) below.
      if (targetName == 'real') {
        final blank = await decideReal(
          attendanceId,
          ifMatch: '1',
          body: const {'outcome': 'RETURN_FOR_RECAPTURE', 'reason': '   '},
        );
        expect(blank.status, 422);
        expect(
          (blank.body['error']! as Map)['code'],
          'DECISION_REASON_REQUIRED',
        );
      } else {
        final blank = await _httpPostWithIfMatch(
          Uri.parse(
            'http://127.0.0.1:$_mockPort/verification/cases/'
            '$attendanceId/decision',
          ),
          const {'outcome': 'RETURN_FOR_RECAPTURE', 'reason': '   '},
          ifMatch: '1',
        );
        expect(blank.status, 422);
        final decoded = jsonDecode(blank.body) as Map<String, Object?>;
        expect((decoded['error']! as Map)['code'], 'DECISION_REASON_REQUIRED');
      }

      // (c) The same decision with a real reason maps to the exact
      // literal RETURNED on both backends.
      if (targetName == 'real') {
        final decided = await decideReal(
          attendanceId,
          ifMatch: '1',
          body: const {
            'outcome': 'RETURN_FOR_RECAPTURE',
            'reason': 'Face not clearly visible; recapture in better light.',
          },
        );
        expect(decided.status, 200);
        expect(decided.body['status'], 'RETURNED');
      } else {
        final decided = await _httpPostWithIfMatch(
          Uri.parse(
            'http://127.0.0.1:$_mockPort/verification/cases/'
            '$attendanceId/decision',
          ),
          const {
            'outcome': 'RETURN_FOR_RECAPTURE',
            'reason': 'Face not clearly visible; recapture in better light.',
          },
          ifMatch: '1',
        );
        expect(decided.status, 200);
        final decoded = jsonDecode(decided.body) as Map<String, Object?>;
        expect(decoded['status'], 'RETURNED');
      }
    });

    // Task 7 (5c): the mock's `/verification/queue` now honours `?filter=`
    // (it previously ignored the parameter and returned every fixture item
    // unconditionally), and it gained claim/release routes carrying the same
    // single-assignee conflict rule as the real service's
    // `VerificationRepo.claim`/`.release`. This pins three things identically
    // on both backends: `filter=UNASSIGNED` excludes every item that already
    // carries a non-null `assigneeId`; claiming an unassigned case succeeds
    // (200) while claiming one already held by a different principal
    // conflicts (409); and every queue item carries an `escalatedAt` key
    // that parses as either null or an ISO-8601 timestamp.
    //
    // `filter=ESCALATED`'s additional `verification_override` gate (403
    // without it, verification_routes.dart) is REAL-SERVICE-ONLY, same as
    // 5a documented for `sensitive_media_view` and the RBAC notes on the
    // decision route above: this mock has no per-request permission model to
    // 403 against, so it is not asserted here on either backend.
    test(
      '$targetName: filter=UNASSIGNED excludes assigned items, claim/release '
      'follow the single-assignee conflict rule, and every queue item '
      'carries a parseable escalatedAt',
      () async {
        final targets = await buildTargets(campaignCount: 0);

        late final List<Map<String, Object?>> unassignedItems;
        late final List<Map<String, Object?>> allItems;
        late final int claimStatus;
        late final int secondClaimStatus;

        if (targetName == 'real') {
          // Two distinct crm_verifier users, so the "second claim" below is
          // genuinely a different principal from the first, mirroring
          // verification_routes_test.dart's "claiming a case held by
          // another is 409" case.
          await seedOrganizationWithUser(
            targets.realDb,
            userId: 'parity-queue-verifier-a',
            username: 'parity-queue-verifier-a',
            roles: const ['crm_verifier'],
          );
          await seedOrganizationWithUser(
            targets.realDb,
            userId: 'parity-queue-verifier-b',
            username: 'parity-queue-verifier-b',
            roles: const ['crm_verifier'],
          );
          await seedCampaign(
            targets.realDb,
            id: 'parity-queue-camp',
            status: CampaignStatus.approved,
          );
          await seedCampaignSession(
            targets.realDb,
            id: 'parity-queue-sess',
            campaignId: 'parity-queue-camp',
            venue: 'Hall A',
          );
          await seedCarpenter(targets.realDb, id: 'parity-queue-carp-1');
          await seedCarpenter(
            targets.realDb,
            id: 'parity-queue-carp-2',
            name: 'Held Elsewhere',
            phone: '+8801700009999',
            displayCode: 'CARP-00009999',
          );
          const unassignedId = 'parity-queue-unassigned';
          const assignedId = 'parity-queue-assigned';
          final reasons = jsonEncode(const [
            'Landmark alignment within tolerance',
          ]);
          await targets.realDb.execute(
            'INSERT INTO attendance '
            '(id, organization_id, campaign_id, session_id, carpenter_id, '
            ' media_ref, status, captured_by, captured_at, machine_band, '
            ' machine_reference_src, machine_reasons, version) '
            "VALUES (@id, 'org-1', 'parity-queue-camp', 'parity-queue-sess', "
            "'parity-queue-carp-1', @id, 'CRM_REVIEW', "
            "'parity-queue-verifier-a', now(), 'MEDIUM', "
            "'APPROVED_BASELINE_PHOTO', @reasons::jsonb, 1)",
            params: {'id': unassignedId, 'reasons': reasons},
          );
          // Pre-assigned to verifier-b, so verifier-a's claim below hits the
          // conflict path without needing a prior claim call.
          await targets.realDb.execute(
            'INSERT INTO attendance '
            '(id, organization_id, campaign_id, session_id, carpenter_id, '
            ' media_ref, status, captured_by, captured_at, machine_band, '
            ' machine_reference_src, machine_reasons, assignee_id, version) '
            "VALUES (@id, 'org-1', 'parity-queue-camp', 'parity-queue-sess', "
            "'parity-queue-carp-2', @id, 'CRM_REVIEW', "
            "'parity-queue-verifier-a', now(), 'LOW', "
            "'APPROVED_BASELINE_PHOTO', @reasons::jsonb, "
            "'parity-queue-verifier-b', 1)",
            params: {'id': assignedId, 'reasons': reasons},
          );

          final config = ServerConfig.fromEnvironment({
            'DATABASE_URL': testDatabaseUrl,
            'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
          });
          final tokens = TokenService(db: targets.realDb, config: config);
          final bearerA = (await tokens.issueFor(
            'parity-queue-verifier-a',
          )).accessToken;
          // verifier-b only needs to exist as the FK target for the
          // pre-assigned row above -- it never authenticates, so no token is
          // minted for it.
          final handler = buildApp(db: targets.realDb, config: config);

          Future<Map<String, Object?>> getAs(String bearer, String path) async {
            final res = await handler(
              Request(
                'GET',
                Uri.parse('http://localhost$path'),
                headers: {'authorization': 'Bearer $bearer'},
              ),
            );
            return jsonDecode(await res.readAsString()) as Map<String, Object?>;
          }

          Future<int> claimAs(String bearer, String id) async {
            final res = await handler(
              Request(
                'POST',
                Uri.parse('http://localhost/verification/cases/$id/claim'),
                headers: {'authorization': 'Bearer $bearer'},
              ),
            );
            return res.statusCode;
          }

          final unassignedBody = await getAs(
            bearerA,
            '/verification/queue?filter=UNASSIGNED',
          );
          unassignedItems = (unassignedBody['items']! as List)
              .cast<Map<String, Object?>>();
          final allBody = await getAs(bearerA, '/verification/queue');
          allItems = (allBody['items']! as List).cast<Map<String, Object?>>();

          claimStatus = await claimAs(bearerA, unassignedId);
          secondClaimStatus = await claimAs(bearerA, assignedId);
        } else {
          final unassignedBody = await targets.mock.getJson(
            '/verification/queue?filter=UNASSIGNED',
          );
          unassignedItems = (unassignedBody['items']! as List)
              .cast<Map<String, Object?>>();
          final allBody = await targets.mock.getJson('/verification/queue');
          allItems = (allBody['items']! as List).cast<Map<String, Object?>>();

          // The mock has no per-request identity to claim "as" a second,
          // different principal, so CASE_HELD_BY_OTHER (pre-assigned in the
          // mock's own fixture to someone other than its one fixed claiming
          // identity) stands in for that second, conflicting principal —
          // see tool/mock_server/bin/server.dart's comment on that fixture
          // item.
          final claimed = await targets.mock.postJson(
            '/verification/cases/CASE_E2E/claim',
            const {},
          );
          claimStatus = claimed.status;
          final secondClaimed = await targets.mock.postJson(
            '/verification/cases/CASE_HELD_BY_OTHER/claim',
            const {},
          );
          secondClaimStatus = secondClaimed.status;

          // The mock subprocess (and its in-memory state) is shared across
          // every test in this file via setUpAll -- unlike the real target's
          // freshDb() per test -- so the claim above must be undone, or
          // CASE_E2E would stay permanently assigned for any test appended
          // after this one.
          await targets.mock.postJson(
            '/verification/cases/CASE_E2E/release',
            const {},
          );
        }

        // (a) filter=UNASSIGNED excludes every assigned item, and the
        // unfiltered queue actually contains at least one assigned item (or
        // the exclusion above would be vacuously true).
        expect(unassignedItems, isNotEmpty);
        for (final item in unassignedItems) {
          expect(
            item['assigneeId'],
            isNull,
            reason:
                'filter=UNASSIGNED must never return an item that already '
                'carries an assigneeId',
          );
        }
        expect(
          allItems.any((i) => i['assigneeId'] != null),
          isTrue,
          reason:
              'the unfiltered queue must contain at least one assigned '
              'item, or the exclusion assertion above could never fail',
        );

        // (b) claim's single-assignee conflict rule: an unassigned case can
        // be claimed (200); a case already held by a different principal
        // cannot (409).
        expect(claimStatus, 200);
        expect(secondClaimStatus, 409);

        // (c) every queue item's escalatedAt parses as null or an ISO
        // timestamp on both backends.
        for (final item in allItems) {
          expect(item.containsKey('escalatedAt'), isTrue);
          final escalatedAt = item['escalatedAt'];
          if (escalatedAt != null) {
            expect(
              DateTime.tryParse(escalatedAt as String),
              isNotNull,
              reason:
                  '$escalatedAt is neither null nor a parseable ISO '
                  'timestamp',
            );
          }
        }
      },
    );
  }

  // Task 3 (RD3.D1): the mock gained a genuine, fixture-computed
  // `/analytics/summary` (tool/mock_server/bin/server.dart's `_Store.
  // analyticsSummary`, backed by `_analyticsAttendance`/
  // `_registeredByCampaign`), mirroring `AnalyticsRepo.summary`'s envelope
  // and range semantics exactly. Unlike the loop above, each case here
  // seeds the real DB to numerically MATCH the mock's own fixed fixture
  // (three campaigns CAMP-1/CAMP-2/CAMP-3 at the same targets/statuses, the
  // mock's fixed per-campaign registration counts, and its five attendance
  // rows against CAMP-1) so the two backends can be compared on actual
  // computed NUMBERS, not just shape — the same spirit as the carpenter
  // (CARP_E2E) seeding above, applied to a richer envelope.
  group('/analytics/summary parity', () {
    Future<void> seedRealToMatchMockFixture(Db db) async {
      await seedCampaign(
        db,
        id: 'CAMP-1',
        name: 'ACSL Pilot Carpenter Drive',
        status: CampaignStatus.approved,
        targetAudience: 100,
      );
      await seedCampaign(
        db,
        id: 'CAMP-2',
        name: 'Chattogram Contractor Meet',
        status: CampaignStatus.pendingApproval,
        targetAudience: 60,
      );
      await seedCampaign(
        db,
        id: 'CAMP-3',
        name: 'Rajshahi Carpenter Drive',
        status: CampaignStatus.draft,
        targetAudience: 40,
      );
      await seedCampaignSession(
        db,
        id: 'CAMP-1-sess',
        campaignId: 'CAMP-1',
        venue: 'Hall A',
      );

      await seedCarpenter(db, id: 'AN_CARP_1');
      await seedCarpenter(
        db,
        id: 'AN_CARP_2',
        phone: '+8801700009101',
        displayCode: 'CARP-00009101',
      );
      await seedCarpenter(
        db,
        id: 'AN_CARP_3',
        phone: '+8801700009102',
        displayCode: 'CARP-00009102',
      );
      // Mirrors the mock's fixed `_registeredByCampaign`: CAMP-1: 2,
      // CAMP-2: 1, CAMP-3: 0.
      await seedRegistration(
        db,
        campaignId: 'CAMP-1',
        carpenterId: 'AN_CARP_1',
      );
      await seedRegistration(
        db,
        campaignId: 'CAMP-1',
        carpenterId: 'AN_CARP_2',
      );
      await seedRegistration(
        db,
        campaignId: 'CAMP-2',
        carpenterId: 'AN_CARP_3',
      );

      // Mirrors the mock's fixed `_analyticsAttendance` list exactly.
      await seedAttendanceForAnalytics(
        db,
        id: 'AN_A1',
        campaignId: 'CAMP-1',
        sessionId: 'CAMP-1-sess',
        carpenterId: 'AN_CARP_1',
        status: 'APPROVED',
        machineBand: 'HIGH',
        capturedAt: DateTime.utc(2025, 6, 1, 10),
      );
      await seedAttendanceForAnalytics(
        db,
        id: 'AN_A2',
        campaignId: 'CAMP-1',
        sessionId: 'CAMP-1-sess',
        carpenterId: 'AN_CARP_1',
        status: 'APPROVED',
        machineBand: 'MEDIUM',
        capturedAt: DateTime.utc(2025, 6, 1, 15),
      );
      await seedAttendanceForAnalytics(
        db,
        id: 'AN_A3',
        campaignId: 'CAMP-1',
        sessionId: 'CAMP-1-sess',
        carpenterId: 'AN_CARP_1',
        status: 'APPROVED',
        machineBand: 'HIGH',
        capturedAt: DateTime.utc(2025, 6, 3, 9),
      );
      await seedAttendanceForAnalytics(
        db,
        id: 'AN_A4',
        campaignId: 'CAMP-1',
        sessionId: 'CAMP-1-sess',
        carpenterId: 'AN_CARP_1',
        status: 'CRM_REVIEW',
        machineBand: 'LOW',
        capturedAt: DateTime.utc(2025, 6, 3, 11),
      );
      await seedAttendanceForAnalytics(
        db,
        id: 'AN_A5',
        campaignId: 'CAMP-1',
        sessionId: 'CAMP-1-sess',
        carpenterId: 'AN_CARP_1',
        status: 'REJECTED',
        machineBand: 'NO_REFERENCE',
        capturedAt: DateTime.utc(2025, 6, 4, 8),
      );
    }

    Future<({Handler handler, String creatorBearer, String fieldBearer})>
    buildRealAnalyticsHandler() async {
      final db = await freshDb();
      openDbs.add(db);
      await Migrator(db).applyPending();
      await seedOrganizationWithUser(db); // campaign_creator, org-1/user-1
      await seedOrganizationWithUser(
        db,
        userId: 'analytics-field',
        username: 'analytics-field',
        roles: const ['field_user'],
      );
      await seedRealToMatchMockFixture(db);

      final config = ServerConfig.fromEnvironment({
        'DATABASE_URL': testDatabaseUrl,
        'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
      });
      final tokens = TokenService(db: db, config: config);
      final creatorBearer = (await tokens.issueFor('user-1')).accessToken;
      final fieldBearer = (await tokens.issueFor(
        'analytics-field',
      )).accessToken;
      return (
        handler: buildApp(db: db, config: config),
        creatorBearer: creatorBearer,
        fieldBearer: fieldBearer,
      );
    }

    Future<Map<String, Object?>> getRealJson(
      Handler handler,
      String path, {
      required String bearer,
    }) async {
      final res = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost$path'),
          headers: {'authorization': 'Bearer $bearer'},
        ),
      );
      return jsonDecode(await res.readAsString()) as Map<String, Object?>;
    }

    test('default query (no params): same key set, funnel field names, int '
        'types, and equal numbers across backends', () async {
      final real = await buildRealAnalyticsHandler();
      final realBody = await getRealJson(
        real.handler,
        '/analytics/summary',
        bearer: real.creatorBearer,
      );
      final mockBody = await _mockGetJson(
        '/analytics/summary',
        bearer: 'mock-access-campaign_creator',
      );

      const expectedKeys = <String>{
        'funnel',
        'verifiedPerDay',
        'bandMix',
        'campaigns',
        'sample',
        'range',
        'generatedAt',
      };
      expect(realBody.keys.toSet(), expectedKeys);
      expect(mockBody.keys.toSet(), expectedKeys);

      const funnelKeys = <String>[
        'target',
        'registered',
        'captured',
        'inReview',
        'approved',
        'rejected',
        'returned',
      ];
      for (final body in [realBody, mockBody]) {
        final funnel = body['funnel']! as Map<String, Object?>;
        expect(funnel.keys.toSet(), funnelKeys.toSet());
        for (final key in funnelKeys) {
          expect(funnel[key], isA<int>());
        }
      }

      // Structural denominators (unranged): target sums all 3 seeded
      // campaigns (100+60+40), registered sums all 3 fixed registrations
      // (2+1+0) — identical on both backends because the real DB above
      // was seeded to numerically match the mock's own fixed fixture.
      expect((realBody['funnel']! as Map)['target'], 200);
      expect((mockBody['funnel']! as Map)['target'], 200);
      expect((realBody['funnel']! as Map)['registered'], 3);
      expect((mockBody['funnel']! as Map)['registered'], 3);

      // Ranged numbers: both backends' attendance fixtures are dated in
      // mid-2025, outside the default (last-30-days-from-today) window,
      // so every ranged number is zero on both, regardless of which day
      // this suite happens to run.
      expect(realBody['funnel'], mockBody['funnel']);
      expect(realBody['verifiedPerDay'], <Object?>[]);
      expect(mockBody['verifiedPerDay'], <Object?>[]);
      expect(realBody['bandMix'], mockBody['bandMix']);
      expect(realBody['sample'], mockBody['sample']);
      expect(realBody['sample'], {'totalAttendance': 0, 'small': true});
      expect(realBody['campaigns'], mockBody['campaigns']);
    });

    test('?campaignId=CAMP-1 filters campaigns to one row on both, with '
        "matching ranged numbers over the fixture's own fixed range", () async {
      final real = await buildRealAnalyticsHandler();
      const query =
          '/analytics/summary?campaignId=CAMP-1&from=2025-06-01'
          '&to=2025-06-30';
      final realBody = await getRealJson(
        real.handler,
        query,
        bearer: real.creatorBearer,
      );
      final mockBody = await _mockGetJson(
        query,
        bearer: 'mock-access-campaign_creator',
      );

      for (final body in [realBody, mockBody]) {
        final campaigns = (body['campaigns']! as List)
            .cast<Map<String, Object?>>();
        expect(campaigns, hasLength(1));
        expect(campaigns.single['id'], 'CAMP-1');
      }

      expect(realBody['funnel'], mockBody['funnel']);
      expect(realBody['funnel'], {
        'target': 100,
        'registered': 2,
        'captured': 5,
        'inReview': 1,
        'approved': 3,
        'rejected': 1,
        'returned': 0,
      });
      expect(realBody['verifiedPerDay'], mockBody['verifiedPerDay']);
      expect(realBody['verifiedPerDay'], [
        {'date': '2025-06-01', 'count': 2},
        {'date': '2025-06-03', 'count': 1},
      ]);
      expect(realBody['bandMix'], mockBody['bandMix']);
      expect(realBody['bandMix'], {
        'HIGH': 2,
        'MEDIUM': 1,
        'LOW': 1,
        'NO_REFERENCE': 1,
      });
      expect(realBody['sample'], mockBody['sample']);
      expect(realBody['sample'], {'totalAttendance': 5, 'small': true});
      expect(realBody['range'], mockBody['range']);
      expect(realBody['range'], {'from': '2025-06-01', 'to': '2025-06-30'});
    });

    test('empty range (2020-01-01..2020-01-02): captured==0, small==true, '
        'verifiedPerDay==[] on both', () async {
      final real = await buildRealAnalyticsHandler();
      const query = '/analytics/summary?from=2020-01-01&to=2020-01-02';
      final realBody = await getRealJson(
        real.handler,
        query,
        bearer: real.creatorBearer,
      );
      final mockBody = await _mockGetJson(
        query,
        bearer: 'mock-access-campaign_creator',
      );

      for (final body in [realBody, mockBody]) {
        final funnel = body['funnel']! as Map<String, Object?>;
        expect(funnel['captured'], 0);
        expect(body['sample'], {'totalAttendance': 0, 'small': true});
        expect(body['verifiedPerDay'], <Object?>[]);
      }
    });

    test(
      'denied: a token without export -> 403 parity on both backends',
      () async {
        final real = await buildRealAnalyticsHandler();
        final realRes = await real.handler(
          Request(
            'GET',
            Uri.parse('http://localhost/analytics/summary'),
            headers: {'authorization': 'Bearer ${real.fieldBearer}'},
          ),
        );
        expect(realRes.statusCode, 403);

        final mockRes = await _mockGetRaw(
          '/analytics/summary',
          bearer: 'mock-access-field_user',
        );
        expect(mockRes.status, 403);
      },
    );
  });
}

/// Inserts an `attendance` row directly, plus its `media_objects` evidence
/// row (the attendance id doubles as the media id — same convention
/// `AttendanceRepo.confirm` uses). Copied verbatim (module-local) from
/// `server/test/analytics/analytics_routes_test.dart`'s `seedAttendance`,
/// dropping the `organizationId` parameter (every call site here is
/// `org-1`, this file's one fixed default) — this file's own established
/// convention for small cross-test helper duplication rather than a shared
/// import (see this file's `getReal`/`decideReal` local closures above).
Future<void> seedAttendanceForAnalytics(
  Db db, {
  required String id,
  required String campaignId,
  required String sessionId,
  required String carpenterId,
  String organizationId = 'org-1',
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

Future<void> _waitUntilUp(Uri uri, {int attempts = 30}) async {
  for (var i = 0; i < attempts; i++) {
    try {
      await _httpGet(uri);
      return;
    } on Object {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  throw StateError('$uri did not come up after $attempts attempts.');
}

Future<String> _httpGet(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

/// Like [_httpGet], but against the mock's fixed port and with an optional
/// bearer token — needed for `/analytics/summary`'s permission gate, the
/// first route in this suite's mock target that ever checks one (every
/// other mock route this file exercises ignores Authorization entirely).
Future<({int status, String body})> _mockGetRaw(
  String pathAndQuery, {
  String? bearer,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$_mockPort$pathAndQuery'),
    );
    if (bearer != null) {
      request.headers.set('authorization', 'Bearer $bearer');
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: text);
  } finally {
    client.close();
  }
}

/// [_mockGetRaw], decoded as a JSON object — for the happy-path analytics
/// parity cases, which always expect 200 with a JSON body.
Future<Map<String, Object?>> _mockGetJson(
  String pathAndQuery, {
  String? bearer,
}) async {
  final res = await _mockGetRaw(pathAndQuery, bearer: bearer);
  return jsonDecode(res.body) as Map<String, Object?>;
}

Future<({int status, String body})> _httpPost(
  Uri uri,
  Map<String, Object?> body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: text);
  } finally {
    client.close();
  }
}

/// Like [_httpPost], but also sets an `If-Match` header — needed for the
/// mock's version-aware verification decision endpoint, which [_httpPost]
/// alone can't exercise.
Future<({int status, String body})> _httpPostWithIfMatch(
  Uri uri,
  Map<String, Object?> body, {
  required String ifMatch,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set('if-match', ifMatch);
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: text);
  } finally {
    client.close();
  }
}
