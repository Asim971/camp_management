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

void main() {
  late Db db;
  late Handler handler;
  late String creatorToken; // has bulk_import
  late String viewerToken; // reporting_viewer, no bulk_import
  var seq = 0;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // user-1 campaign_creator (bulk_import)
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
    await seedCarpenter(
      db,
      id: 'c-1',
      phone: '+8801700004821',
      displayCode: 'CARP-00004821',
    );
  });
  tearDown(() async => db.close());

  String nextKey() => 'key-${seq++}';

  /// Builds a multipart/form-data body with a single `file` part.
  Request uploadRequest(String path, String csv, {String? bearer}) {
    const boundary = 'X-BOUNDARY';
    final body =
        '--$boundary\r\n'
        'content-disposition: form-data; name="file"; filename="import.csv"\r\n'
        'content-type: text/csv\r\n\r\n'
        '$csv\r\n'
        '--$boundary--\r\n';
    return Request(
      'POST',
      Uri.parse('http://localhost$path'),
      headers: {
        if (bearer != null) 'authorization': 'Bearer $bearer',
        'content-type': 'multipart/form-data; boundary=$boundary',
      },
      body: body,
    );
  }

  Future<Map<String, Object?>> decode(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  Future<Response> get(String path, {String? bearer}) async => handler(
    Request(
      'GET',
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'authorization': 'Bearer $bearer'},
    ),
  );

  test('unauthenticated dry-run is 401 through the real tree', () async {
    final res = await handler(
      uploadRequest(
        '/campaigns/camp-1/imports/dry-run',
        'name,phone\nA,+8801700000001\n',
      ),
    );
    expect(res.statusCode, 401);
  });

  test('403 without bulk_import', () async {
    final res = await handler(
      uploadRequest(
        '/campaigns/camp-1/imports/dry-run',
        'name,phone\nA,+8801700000001\n',
        bearer: viewerToken,
      ),
    );
    expect(res.statusCode, 403);
  });

  test('422 IMPORT_FILE_INVALID for a bad file, no job created', () async {
    final res = await handler(
      uploadRequest(
        '/campaigns/camp-1/imports/dry-run',
        'name,territory\nA,North\n',
        bearer: creatorToken,
      ),
    );
    expect(res.statusCode, 422);
    expect(
      ((await decode(res))['error']! as Map)['code'],
      'IMPORT_FILE_INVALID',
    );
  });

  test('202 then poll reaches READY_TO_COMMIT with classified rows', () async {
    final res = await handler(
      uploadRequest(
        '/campaigns/camp-1/imports/dry-run',
        'name,phone\nMd. Karim,+8801700004821\nBrand New,+8801733334444\n',
        bearer: creatorToken,
      ),
    );
    expect(res.statusCode, 202);
    final job = await decode(res);
    expect(job['status'], 'PROCESSING');
    final jobId = job['id']! as String;

    // Poll until terminal (the background task is fast; bound the loop).
    Map<String, Object?> polled = job;
    for (var i = 0; i < 50 && polled['status'] == 'PROCESSING'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      polled = await decode(await get('/imports/$jobId', bearer: creatorToken));
    }
    expect(polled['status'], 'READY_TO_COMMIT');
    final rows = (polled['rows']! as List).cast<Map<String, Object?>>();
    expect(
      rows.map((r) => r['outcome']).toSet(),
      containsAll(<String>['VALID', 'NEEDS_PROFILE']),
    );
    expect(
      jsonEncode(polled),
      isNot(contains('+8801700004821')),
      reason: 'raw phone never on the wire (2a.D2)',
    );
  });

  test('400 when the multipart body has no "file" part', () async {
    const boundary = 'X-BOUNDARY';
    final body =
        '--$boundary\r\n'
        'content-disposition: form-data; name="notfile"\r\n\r\n'
        'irrelevant\r\n'
        '--$boundary--\r\n';
    final res = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/campaigns/camp-1/imports/dry-run'),
        headers: {
          'authorization': 'Bearer $creatorToken',
          'content-type': 'multipart/form-data; boundary=$boundary',
        },
        body: body,
      ),
    );
    expect(res.statusCode, 400);
  });

  test('404 for an unknown job id on poll', () async {
    final res = await get('/imports/no-such-job', bearer: creatorToken);
    expect(res.statusCode, 404);
  });

  test('404 for a cross-org campaign on dry-run', () async {
    final res = await handler(
      uploadRequest(
        '/campaigns/not-mine/imports/dry-run',
        'name,phone\nA,+8801700000001\n',
        bearer: creatorToken,
      ),
    );
    expect(res.statusCode, 404);
  });

  test(
    'commit registers the committable set and completes; replay is 409',
    () async {
      // Seed a ready job directly for a deterministic commit test.
      await seedImportJob(
        db,
        id: 'job-1',
        status: 'READY_TO_COMMIT',
        rows: [
          (
            rowId: 'row-1',
            name: 'Md. Karim',
            phone: '+8801700004821',
            outcome: 'VALID',
          ),
        ],
      );
      // The VALID row needs its linked carpenter id set (seed helper leaves it
      // null); set it so commit uses the matched path.
      await db.execute(
        "UPDATE import_job_rows SET linked_carpenter_id = 'c-1' "
        "WHERE job_id = 'job-1' AND row_id = 'row-1'",
      );

      final res = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/campaigns/camp-1/imports/job-1/commit'),
          headers: {
            'authorization': 'Bearer $creatorToken',
            'Idempotency-Key': nextKey(),
          },
        ),
      );
      expect(res.statusCode, 200);
      expect((await decode(res))['status'], 'COMPLETED');

      final replay = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/campaigns/camp-1/imports/job-1/commit'),
          headers: {
            'authorization': 'Bearer $creatorToken',
            'Idempotency-Key': nextKey(),
          },
        ),
      );
      expect(
        replay.statusCode,
        409,
        reason: 'a COMPLETED job is not committable',
      );
    },
  );
}
