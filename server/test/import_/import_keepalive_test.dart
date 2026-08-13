import 'dart:convert';
import 'dart:io';

import 'package:campaign_service/src/app.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

/// Regression: the multipart dry-run must fully drain the request body so the
/// keep-alive connection stays reusable.
///
/// The other import route tests invoke `buildApp`'s handler in-process with a
/// `shelf.Request` — that never touches a socket, so a handler that leaves the
/// request body half-read looks fine there. Over a REAL connection it is not:
/// `_readFilePart` used to `return` from inside its `await for` the moment it
/// found the `file` part, leaving the closing `--boundary--` unread. shelf /
/// dart:io then cannot reuse that connection and closes it after the 202; on a
/// pooled client the FIN races the next request off the same connection and
/// surfaces as a `connectionError`, reported to the app as a FAILED dry-run
/// even though the server logged a clean 202 — so polling never starts and the
/// bulk-import screen sticks on the error state (the W-07 e2e symptom).
void main() {
  late Db db;
  late HttpServer server;
  late String creatorToken;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // user-1 campaign_creator (bulk_import)
    final tokens = TokenService(db: db, config: config);
    creatorToken = (await tokens.issueFor('user-1')).accessToken;
    await seedCampaign(db, id: 'camp-1');
    server = await shelf_io.serve(
      buildApp(db: db, config: config),
      'localhost',
      0,
    );
  });
  tearDown(() async {
    await server.close(force: true);
    await db.close();
  });

  test('a multipart dry-run keeps its pooled connection reusable for the '
      'poll that follows', () async {
    // A single pooled connection, reused for every request — exactly how the
    // app's one Dio client behaves (dry-run then poll on the same pool). Force
    // reuse so the drain bug cannot be masked by opening fresh sockets.
    final client = HttpClient()..maxConnectionsPerHost = 1;
    addTearDown(() => client.close(force: true));

    const csv = 'name,phone\nMd. Karim,+8801700004821\n';
    const boundary = 'X-BOUNDARY';
    final body = utf8.encode(
      '--$boundary\r\n'
      'content-disposition: form-data; name="file"; filename="import.csv"\r\n'
      'content-type: text/csv\r\n\r\n'
      '$csv\r\n'
      '--$boundary--\r\n',
    );

    // Repeated so the connection-reuse path is exercised many times: without
    // the drain the connection dies within a few iterations; with it, all pass.
    for (var i = 0; i < 20; i++) {
      final req = await client.postUrl(
        Uri.parse(
          'http://localhost:${server.port}/campaigns/camp-1/imports/dry-run',
        ),
      );
      req.headers.set('authorization', 'Bearer $creatorToken');
      req.headers.set(
        'content-type',
        'multipart/form-data; boundary=$boundary',
      );
      req.add(body);
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      expect(
        resp.statusCode,
        202,
        reason: 'iteration $i saw ${resp.statusCode}: $text',
      );

      // A GET on the SAME pooled connection right after the multipart POST —
      // the real dry-run→poll sequence. This is the request that broke.
      final pollReq = await client.getUrl(
        Uri.parse('http://localhost:${server.port}/imports/no-such-job'),
      );
      pollReq.headers.set('authorization', 'Bearer $creatorToken');
      final pollResp = await pollReq.close();
      await pollResp.drain<void>();
      expect(
        pollResp.statusCode,
        404,
        reason: 'iteration $i: poll on the reused connection failed',
      );
    }
  });
}
