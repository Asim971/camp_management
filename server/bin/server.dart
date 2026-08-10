import 'dart:io';

import 'package:campaign_service/src/auth/auth_routes.dart';
import 'package:campaign_service/src/auth/middleware.dart';
import 'package:campaign_service/src/auth/password.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/campaign/campaign_repo.dart';
import 'package:campaign_service/src/campaign/campaign_routes.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main(List<String> args) async {
  final config = ServerConfig.fromEnvironment(Platform.environment);

  final db = await Db.open(config.databaseUrl);
  final applied = await Migrator(db).applyPending();
  stdout.writeln('applied migrations: $applied');

  final tokens = TokenService(db: db, config: config);
  final repo = CampaignRepo(db);

  final publicRouter = Router()
    ..get(
      '/health',
      (Request req) => Response.ok(
        '{"status":"ok"}',
        headers: {'content-type': 'application/json'},
      ),
    );

  // /auth/* never sees `authenticate` -- nobody has a token yet to present.
  final authHandler = authRouter(
    db: db,
    tokens: tokens,
    hasher: const PasswordHasher(),
  ).call;

  // Only /campaigns runs behind `authenticate`. Per-route `requirePermission`
  // (and, for Task 9's write routes, `idempotency`) are applied inside
  // campaignRouter itself, not here.
  final campaignHandler = const Pipeline()
      .addMiddleware(authenticate(db: db, tokens: tokens))
      .addHandler(campaignRouter(db: db, repo: repo).call);

  // Cascade tries each candidate in turn, moving on whenever one answers
  // "not found" (its default `shouldRelinquish`, status 404) -- exactly how
  // /health, /auth/* (unauthenticated) and /campaigns (authenticated) get to
  // share one handler tree despite needing different middleware ahead of
  // them.
  final routing = Cascade()
      .add(publicRouter.call)
      .add(authHandler)
      .add(campaignHandler)
      .handler;

  final handler = const Pipeline()
      .addMiddleware(correlation())
      .addMiddleware(errorEnvelope())
      .addHandler(routing);

  final server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  stdout.writeln('campaign_service listening on :${server.port}');
}
