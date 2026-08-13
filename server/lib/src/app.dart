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
import 'import_/import_routes.dart';
import 'infra/correlation.dart';
import 'infra/error_envelope.dart';
import 'infra/request_log.dart';
import 'participant/participant_repo.dart';
import 'participant/participant_routes.dart';
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
    _authenticateUnder(const {'campaigns'}, db: db, tokens: tokens),
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

  final participantHandler = const Pipeline()
      .addMiddleware(
        // 'campaigns' is here too: /campaigns/<id>/registrations and
        // /campaigns/<id>/profile-requests reach this leg via Cascade
        // fall-through from campaignRouter (which does not know them). For a
        // request that already passed the campaign leg's authenticate this
        // runs authenticate twice -- one extra indexed query, accepted for
        // keeping both legs independently fail-closed.
        _authenticateUnder(
          const {'carpenters', 'sessions', 'campaigns'},
          db: db,
          tokens: tokens,
        ),
      )
      .addHandler(participantRouter(db: db, repo: ParticipantRepo(db)).call);

  final importHandler = const Pipeline()
      .addMiddleware(
        _authenticateUnder(
          const {'campaigns', 'imports'},
          db: db,
          tokens: tokens,
        ),
      )
      .addHandler(importRouter(db: db, databaseUrl: config.databaseUrl).call);

  var cascade = Cascade()
      .add(publicRouter.call)
      .add(authHandler)
      .add(campaignHandler)
      .add(participantHandler)
      .add(importHandler);

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
      // Inside correlation (so the trace id resolves), outside errorEnvelope
      // (so a thrown handler still logs the 500 the client actually saw).
      .addMiddleware(requestLog())
      .addMiddleware(errorEnvelope())
      .addHandler(cascade.handler);
}

/// [authenticate], but only actually invoked for a request under one of
/// [roots]; anything else passes straight through to [inner] — the
/// Cascade leg's own router handler — unauthenticated, so a LATER Cascade
/// candidate still gets a real shot at it.
///
/// `authenticate` answers 401 for a missing/invalid Bearer token,
/// unconditionally. Wiring it as a `Pipeline` middleware OUTSIDE the leg's
/// own router (as `bin/server.dart` did before this file existed) means it
/// runs before shelf_router ever gets to decide whether the path even
/// matches — so the leg answered 401, not 404, for a completely unregistered
/// path with no Authorization header. That was latent and untested until
/// Task 11 added a Cascade candidate (`seedRouter`) AFTER the campaign leg
/// and a gate test that probes `/__test__/reset` with no token while
/// seeding is disabled: it needs a genuine 404 (`seed_gate_test.dart` — "a
/// data-wiping route must not exist"), and with the unconditional wrap it
/// got 401 instead, because the campaign leg swallowed the unmatched path
/// before its own shelf_router routing ever ran.
///
/// Scoping the check to [roots] here restores the real 404 for every other
/// path — the leg's own router runs unauthenticated, matches nothing, and
/// returns shelf_router's own "not found" sentinel, which is what lets
/// [Cascade] relinquish to whatever candidate (or nothing) comes next —
/// while every genuine request under [roots] is authenticated exactly as
/// before.
Middleware _authenticateUnder(
  Set<String> roots, {
  required Db db,
  required TokenService tokens,
}) {
  final authenticated = authenticate(db: db, tokens: tokens);
  return (Handler inner) {
    final gated = authenticated(inner);
    return (Request request) {
      // `request.url` (not `request.requestedUri`) is relative to wherever
      // this handler is mounted -- shelf's own doc: "[url]'s path is always
      // relative... to requestedUri.path without the initial '/'". Today
      // this handler sits at the top level, so the two agree modulo the
      // leading slash (`campaigns` vs `/campaigns`), which is why the
      // literals in [roots] have none. The point of reading `url` instead of
      // `requestedUri` is that THIS predicate keeps matching correctly if
      // the leg is ever mounted under a prefix (e.g.
      // `Router().mount('/api', ...)`) -- `url.path` stays `campaigns`
      // relative to that mount, while `requestedUri.path` would still be the
      // full, unstripped `/api/campaigns` and would stop matching, silently
      // routing real requests past `authenticate` unauthenticated. Reading
      // `url` is what keeps a future mount failing CLOSED (still
      // authenticated) instead of open.
      final path = request.url.path;
      final matches = roots.any(
        (root) => path == root || path.startsWith('$root/'),
      );
      return matches ? gated(request) : inner(request);
    };
  };
}
