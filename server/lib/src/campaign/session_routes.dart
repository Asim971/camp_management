import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/correlation.dart';
import '../infra/error_envelope.dart';
import 'session_machine.dart';
import 'session_repo.dart';

/// `GET /campaigns/<id>/sessions` (any authenticated org member; org-scoped)
/// and `POST /sessions/<id>/{start,pause,close}` (campaign_create). All are
/// org-scoped inside the repo SQL — a cross-org session id is a 404 (D7).
Router sessionRouter({required Db db}) {
  final router = Router();
  final repo = SessionRepo(db);

  Response json(Object? body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  router.get('/campaigns/<id>/sessions', (Request request, String id) async {
    final auth = authOf(request);
    final list = await repo.listForCampaign(
      id,
      organizationId: auth.organizationId,
    );
    if (list == null) throw ApiException(ApiErrorCode.notFound);
    return json({
      'items': [for (final s in list) s.toWireJson()],
    });
  });

  Handler buildAction(SessionAction action) => const Pipeline()
      .addMiddleware(requirePermission('campaign_create'))
      .addHandler((Request request) async {
        final auth = authOf(request);
        final sessionId = request.params['id']!;
        final result = await repo.apply(
          action,
          sessionId: sessionId,
          organizationId: auth.organizationId,
          actorId: auth.userId,
          correlationId: correlationOf(request),
        );
        switch (result.outcome) {
          case SessionOutcome.applied:
          case SessionOutcome.idempotentNoop:
            return json(result.view!.toWireJson());
          case SessionOutcome.notFound:
            throw ApiException(ApiErrorCode.notFound);
          case SessionOutcome.notReady:
            throw ApiException(
              ApiErrorCode.sessionNotReady,
              message:
                  'Session is not ready to start: it needs an approved or '
                  'active campaign, a venue and a start time.',
            );
          case SessionOutcome.invalidTransition:
            throw ApiException(
              ApiErrorCode.sessionInvalidTransition,
              message:
                  'Cannot ${action.name} a session in state '
                  '${result.currentStatus!.wireValue}.',
            );
        }
      });

  router.post('/sessions/<id>/start', buildAction(SessionAction.start));
  router.post('/sessions/<id>/pause', buildAction(SessionAction.pause));
  router.post('/sessions/<id>/close', buildAction(SessionAction.close));

  return router;
}
