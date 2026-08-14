// The mock stays until the real service has been green for a while (spec
// §9). While both exist, they must agree on the contract the client depends
// on: status vocabulary, list envelope shape, `version` presence, and
// pagination clamp semantics — so this file runs the SAME assertions
// against both, rather than trusting the mock's own comments to stay
// accurate as the real service evolves underneath it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
        'ratified SessionStatus vocabulary and key set', () async {
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
    });
  }
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
