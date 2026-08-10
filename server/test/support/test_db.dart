import 'dart:io';

import 'package:campaign_service/src/db/pool.dart';

/// CI sets DATABASE_URL for its service container. Locally, what matters is
/// that this URL resolves to a reachable Postgres 16+ — a `docker compose up
/// -d db` container and a native install both work; the fallback below
/// targets a native PostgreSQL at the default port.
String get testDatabaseUrl =>
    Platform.environment['DATABASE_URL'] ??
    'postgres://campaign:campaign@localhost:5432/campaign';

/// Drops every table so each test starts from nothing. A migration test that
/// inherits another test's schema proves nothing.
///
/// Invariant this relies on: every DB-touching test file calls this helper
/// (rather than reusing a connection or schema another test set up), and
/// `dart_test.yaml`'s `concurrency: 1` serializes test files so that no two
/// suites can run at once. Both hold together: the DROP SCHEMA below runs
/// against the one shared database, so if a second file's tests were running
/// concurrently, this call would nuke that file's tables mid-run. Do not
/// remove `concurrency: 1` without giving every test file its own schema.
Future<Db> freshDb() async {
  final db = await Db.open(testDatabaseUrl);
  await db.execute('DROP SCHEMA public CASCADE');
  await db.execute('CREATE SCHEMA public');
  return db;
}
