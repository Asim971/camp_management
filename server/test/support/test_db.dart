import 'dart:io';

import 'package:campaign_service/src/db/pool.dart';

/// CI sets DATABASE_URL for its service container; locally use
/// `docker compose up -d db`.
String get testDatabaseUrl =>
    Platform.environment['DATABASE_URL'] ??
    'postgres://campaign:campaign@localhost:5432/campaign';

/// Drops every table so each test starts from nothing. A migration test that
/// inherits another test's schema proves nothing.
Future<Db> freshDb() async {
  final db = await Db.open(testDatabaseUrl);
  await db.execute('DROP SCHEMA public CASCADE');
  await db.execute('CREATE SCHEMA public');
  return db;
}
