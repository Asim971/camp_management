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
  late String token;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db);
    token = (await TokenService(
      db: db,
      config: config,
    ).issueFor('user-1')).accessToken;
    handler = buildApp(db: db, config: config);
    await db.execute(
      "INSERT INTO consent_notices (version, language, title, body, content_hash) "
      "VALUES (1, 'en', 'Consent', 'We record your attendance.', 'hash-en')",
    );
  });
  tearDown(() async => db.close());

  test('GET /consent/notices returns the notices; requires auth', () async {
    final unauth = await handler(
      Request('GET', Uri.parse('http://h/consent/notices')),
    );
    expect(unauth.statusCode, 401);

    final res = await handler(
      Request(
        'GET',
        Uri.parse('http://h/consent/notices'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    expect(res.statusCode, 200);
    final notices =
        (jsonDecode(await res.readAsString()) as Map)['notices']! as List;
    expect(notices, hasLength(1));
    final n = notices.single as Map;
    expect(n['version'], 1);
    expect(n['language'], 'en');
  });
}
