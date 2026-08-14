import 'dart:convert';
import 'dart:typed_data';

import 'package:campaign_service/src/app.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/media/signed_url.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late Handler handler;
  late String fieldToken; // attendance_capture
  late String viewerToken; // no attendance_capture

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

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
  });
  tearDown(() async => db.close());

  Future<Response> presign(String attendanceId, {String? bearer}) async =>
      handler(
        Request(
          'POST',
          Uri.parse('http://10.0.2.2:8080/media/presign'),
          headers: {
            if (bearer != null) 'authorization': 'Bearer $bearer',
            'content-type': 'application/json',
          },
          body: jsonEncode({'attendanceId': attendanceId}),
        ),
      );

  Future<Map<String, Object?>> body(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  test('presign requires attendance_capture', () async {
    expect((await presign('att-1', bearer: viewerToken)).statusCode, 403);
    expect((await presign('att-1')).statusCode, 401);
  });

  test('presign returns a signed upload URL for this host', () async {
    final res = await presign('att-1', bearer: fieldToken);
    expect(res.statusCode, 200);
    final url = (await body(res))['url']! as String;
    expect(url, contains('/media/upload/att-1?exp='));
    expect(url, contains('sig='));
  });

  test(
    'upload with a valid signature stores the bytes; a bad signature is 403',
    () async {
      final url =
          ((await body(await presign('att-1', bearer: fieldToken)))['url']!)
              as String;
      final signed = Uri.parse(url);

      // A bearer-less PUT with the signed query succeeds.
      final ok = await handler(
        Request(
          'PUT',
          signed,
          body: const [1, 2, 3, 4],
          headers: {'content-type': 'application/octet-stream'},
        ),
      );
      expect(ok.statusCode, 200);

      // Tampering with the signature is 403.
      final bad = signed.replace(
        queryParameters: {...signed.queryParameters, 'sig': 'forged'},
      );
      final rejected = await handler(
        Request(
          'PUT',
          bad,
          body: const [1, 2, 3],
          headers: {'content-type': 'application/octet-stream'},
        ),
      );
      expect(rejected.statusCode, 403);
    },
  );

  test(
    'signed GET /media/<id> serves the bytes; bad signature 403; unknown 404',
    () async {
      await db.execute(
        "INSERT INTO media_objects (id, content_type, bytes) VALUES ('read-1','image/png',@b)",
        params: {
          'b': Uint8List.fromList(const [9, 8, 7]),
        },
      );
      final url = await signReadUrl(
        baseUrl: 'http://10.0.2.2:8080',
        id: 'read-1',
        signingKey: config.uploadSigningKey,
        now: DateTime.now(),
      );
      final ok = await handler(Request('GET', Uri.parse(url)));
      expect(ok.statusCode, 200);
      expect((await ok.read().expand((x) => x).toList()), const [9, 8, 7]);

      final signed = Uri.parse(url);
      final bad = signed.replace(
        queryParameters: {...signed.queryParameters, 'sig': 'forged'},
      );
      expect((await handler(Request('GET', bad))).statusCode, 403);

      final missing = Uri.parse(
        await signReadUrl(
          baseUrl: 'http://h',
          id: 'nope',
          signingKey: config.uploadSigningKey,
          now: DateTime.now(),
        ),
      );
      expect((await handler(Request('GET', missing))).statusCode, 404);
    },
  );

  test('a read capability cannot be replayed to overwrite the upload route '
      '(and an upload capability cannot be replayed to read)', () async {
    await db.execute(
      "INSERT INTO media_objects (id, content_type, bytes) VALUES "
      "('evidence-1','image/png',@b)",
      params: {
        'b': Uint8List.fromList(const [1, 2, 3]),
      },
    );

    // A URL minted by signReadUrl (the one handed to the CRM/<img>) must
    // NOT authorize overwriting the evidence blob via the upload route.
    final readUrl = await signReadUrl(
      baseUrl: 'http://10.0.2.2:8080',
      id: 'evidence-1',
      signingKey: config.uploadSigningKey,
      now: DateTime.now(),
    );
    final readSigned = Uri.parse(readUrl);
    final uploadAttempt = readSigned.replace(path: '/media/upload/evidence-1');
    final rejectedUpload = await handler(
      Request(
        'PUT',
        uploadAttempt,
        body: const [9, 9, 9],
        headers: {'content-type': 'application/octet-stream'},
      ),
    );
    expect(rejectedUpload.statusCode, 403);

    // The evidence blob must be untouched by the rejected replay.
    final stillOriginal = await handler(Request('GET', readSigned));
    expect(stillOriginal.statusCode, 200);
    expect((await stillOriginal.read().expand((x) => x).toList()), const [
      1,
      2,
      3,
    ]);

    // And, symmetrically: an upload capability must not be replayable
    // against the read route.
    final uploadUrl =
        ((await body(await presign('att-replay', bearer: fieldToken)))['url']!)
            as String;
    final uploadSigned = Uri.parse(uploadUrl);
    final readAttempt = uploadSigned.replace(path: '/media/att-replay');
    final rejectedRead = await handler(Request('GET', readAttempt));
    expect(rejectedRead.statusCode, 403);

    // The genuine upload capability still works as an upload, though.
    final okUpload = await handler(
      Request(
        'PUT',
        uploadSigned,
        body: const [4, 5, 6],
        headers: {'content-type': 'application/octet-stream'},
      ),
    );
    expect(okUpload.statusCode, 200);
  });
}
