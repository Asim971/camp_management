import 'dart:io';

import 'package:campaign_service/src/config.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main(List<String> args) async {
  final config = ServerConfig.fromEnvironment(Platform.environment);

  final router = Router()
    ..get(
      '/health',
      (Request req) => Response.ok(
        '{"status":"ok"}',
        headers: {'content-type': 'application/json'},
      ),
    );

  final server = await io.serve(
    const Pipeline().addHandler(router.call),
    InternetAddress.anyIPv4,
    config.port,
  );
  stdout.writeln('campaign_service listening on :${server.port}');
}
