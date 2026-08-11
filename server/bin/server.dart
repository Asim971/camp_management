import 'dart:io';

import 'package:campaign_service/src/app.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main(List<String> args) async {
  final config = ServerConfig.fromEnvironment(Platform.environment);

  final db = await Db.open(config.databaseUrl);
  final applied = await Migrator(db).applyPending();
  stdout.writeln('applied migrations: $applied');

  // buildApp assembles the exact same handler tree test/seed/seed_gate_test
  // and test/contract/parity_test exercise directly -- see its doc.
  final handler = buildApp(db: db, config: config);

  final server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  stdout.writeln('campaign_service listening on :${server.port}');
  if (config.seedingEnabled) {
    stdout.writeln(
      'WARNING: ENABLE_TEST_SEEDING=true -- /__test__/* is mounted. '
      'This must never be true in a production deploy.',
    );
  }
}
