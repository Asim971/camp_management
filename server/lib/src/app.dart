import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth/auth_routes.dart';
import 'auth/middleware.dart';
import 'auth/password.dart';
import 'auth/tokens.dart';
import 'campaign/campaign_repo.dart';
import 'campaign/campaign_routes.dart';
import 'config.dart';
import 'db/pool.dart';
import 'infra/correlation.dart';
import 'infra/error_envelope.dart';
import 'seed/seed_routes.dart';

/// Assembles the full request-handling pipeline: `/health`, `/auth/*`,
/// `/campaigns` (behind `authenticate`), and — ONLY when
/// [ServerConfig.seedingEnabled] — `/__test__/*`.
///
/// Factored out of `bin/server.dart` so tests build the EXACT handler tree
/// the real process serves, rather than a parallel hand-assembled pipeline
/// that could silently diverge from it. This function is also Task 11 step
/// 1's gate test subject: when seeding is disabled, [seedRouter] is never
/// constructed and never added to the [Cascade] — there is no route for
/// `seed_gate_test.dart` to find, rather than one that exists behind a guard
/// and would still answer *some* status to a probe.
Handler buildApp({required Db db, required ServerConfig config}) {
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
  // This hasher's `params` only matter for `hash()`; `/auth/login` only ever
  // calls `verify()`, which reads the params encoded in the stored hash, so
  // production strength here is a documentation choice, not a correctness one.
  final authHandler = authRouter(
    db: db,
    tokens: tokens,
    hasher: const PasswordHasher(),
  ).call;

  var campaignPipeline = const Pipeline().addMiddleware(
    _authenticateOnlyUnderCampaigns(db: db, tokens: tokens),
  );
  if (config.seedingEnabled) {
    // Lets `POST /__test__/campaigns {"fixture":"error"}` arm the next
    // `GET /campaigns` to fail once with a 500 — mirrors the mock's
    // `MOCK_CAMPAIGNS=error` (tool/mock_server/bin/server.dart). Wired only
    // under seeding, alongside the seed router itself, so a production
    // deploy never carries this extra branch at all.
    campaignPipeline = campaignPipeline.addMiddleware(
      campaignsErrorArmMiddleware(),
    );
  }
  final campaignHandler = campaignPipeline.addHandler(
    campaignRouter(db: db, repo: repo).call,
  );

  var cascade = Cascade()
      .add(publicRouter.call)
      .add(authHandler)
      .add(campaignHandler);

  // Seed routes are ABSENT, not registered-and-guarded, when seeding is
  // disabled: there is no route at all for a probe to find (spec §9; Task 11
  // step 1's gate test pins exactly this).
  if (config.seedingEnabled) {
    cascade = cascade.add(
      seedRouter(
        db: db,
        config: config,
        hasher: const PasswordHasher(params: Argon2Params.fastForTests),
      ).call,
    );
  }

  return const Pipeline()
      .addMiddleware(correlation())
      .addMiddleware(errorEnvelope())
      .addHandler(cascade.handler);
}

/// [authenticate], but only actually invoked for a request under
/// `/campaigns`; anything else passes straight through to [inner] —
/// `campaignRouter`'s own handler — unauthenticated.
///
/// `authenticate` answers 401 for a missing/invalid Bearer token,
/// unconditionally. Wiring it as a `Pipeline` middleware OUTSIDE
/// `campaignRouter.call` (as `bin/server.dart` did before this file existed)
/// means it runs before shelf_router ever gets to decide whether the path
/// even matches — so campaignHandler answered 401, not 404, for a completely
/// unregistered path with no Authorization header. That was latent and
/// untested until Task 11 added a Cascade candidate (`seedRouter`) AFTER
/// this one and a gate test that probes `/__test__/reset` with no token
/// while seeding is disabled: it needs a genuine 404 (`seed_gate_test.dart`
/// — "a data-wiping route must not exist"), and with the unconditional wrap
/// it got 401 instead, because campaignHandler swallowed the unmatched path
/// before campaignRouter's own shelf_router routing ever ran.
///
/// Scoping the check to `/campaigns`* here restores the real 404 for every
/// other path — `campaignRouter.call` runs unauthenticated, matches nothing,
/// and returns shelf_router's own "not found" sentinel, which is what lets
/// [Cascade] relinquish to whatever candidate (or nothing) comes next —
/// while every genuine `/campaigns` request is authenticated exactly as
/// before.
Middleware _authenticateOnlyUnderCampaigns({
  required Db db,
  required TokenService tokens,
}) {
  final authenticated = authenticate(db: db, tokens: tokens);
  return (Handler inner) {
    final gated = authenticated(inner);
    return (Request request) {
      final path = request.requestedUri.path;
      if (path == '/campaigns' || path.startsWith('/campaigns/')) {
        return gated(request);
      }
      return inner(request);
    };
  };
}
