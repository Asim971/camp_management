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
/// performs a `GET` and returns the decoded JSON object body.
class ParityTarget {
  ParityTarget(this.name, this.getJson);

  final String name;
  final Future<Map<String, Object?>> Function(String pathAndQuery) getJson;
}

/// The mock's listen port for this file only — distinct from its usual 8080
/// default so this suite never collides with a locally-running dev instance
/// of either backend.
const int _mockPort = 8099;

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
  Future<({ParityTarget real, ParityTarget mock})> buildTargets({
    required int campaignCount,
  }) async {
    final db = await freshDb();
    openDbs.add(db);
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // campaign_creator, org-1/user-1
    if (campaignCount > 0) {
      await seedCampaigns(db, count: campaignCount);
    }

    final config = ServerConfig.fromEnvironment({
      'DATABASE_URL': testDatabaseUrl,
      'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
    });
    final tokens = TokenService(db: db, config: config);
    final token = (await tokens.issueFor('user-1')).accessToken;
    final handler = buildApp(db: db, config: config);

    final real = ParityTarget('real service', (pathAndQuery) async {
      final res = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost$pathAndQuery'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      return jsonDecode(await res.readAsString()) as Map<String, Object?>;
    });

    final mock = ParityTarget('mock server', (pathAndQuery) async {
      final res = await _httpGet(
        Uri.parse('http://127.0.0.1:$_mockPort$pathAndQuery'),
      );
      return jsonDecode(res) as Map<String, Object?>;
    });

    return (real: real, mock: mock);
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
