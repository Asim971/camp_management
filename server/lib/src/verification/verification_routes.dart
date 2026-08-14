import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/correlation.dart';
import '../infra/error_envelope.dart';
import 'verification_repo.dart';

/// `/verification/*` — the CRM verification queue, case view, and decision
/// (approve/reject/return-for-recapture/escalate; sub-project 5a/5b). Every
/// route requires
/// `verification_decide`; the case view additionally requires
/// `sensitive_media_view` since it mints a signed URL onto the raw capture
/// and reads NID-adjacent identity data.
Router verificationRouter({required Db db, required String signingKey}) {
  final router = Router();
  final repo = VerificationRepo(db, signingKey: signingKey);

  router.get(
    '/verification/queue',
    const Pipeline()
        .addMiddleware(requirePermission('verification_decide'))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final items = await repo.queue(organizationId: auth.organizationId);
          return _json({'items': items});
        }),
  );

  router.get(
    '/verification/cases/<id>',
    const Pipeline()
        .addMiddleware(requirePermission('verification_decide'))
        .addMiddleware(requirePermission('sensitive_media_view'))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final u = request.requestedUri;
          final view = await repo.loadCase(
            attendanceId: request.params['id']!,
            organizationId: auth.organizationId,
            viewerId: auth.userId,
            baseUrl: '${u.scheme}://${u.authority}',
            correlationId: correlationOf(request),
          );
          if (view == null) throw ApiException(ApiErrorCode.notFound);
          return _json(view);
        }),
  );

  router.post(
    '/verification/cases/<id>/decision',
    const Pipeline()
        .addMiddleware(requirePermission('verification_decide'))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final ifMatch = int.tryParse(request.headers['if-match'] ?? '');
          if (ifMatch == null) {
            throw ApiException(
              ApiErrorCode.badRequest,
              message: 'If-Match header is required.',
            );
          }
          final raw = await request.readAsString();
          final Object? decoded;
          try {
            decoded = jsonDecode(raw);
          } on FormatException {
            throw ApiException(
              ApiErrorCode.badRequest,
              message: 'Request body must be a JSON object.',
            );
          }
          if (decoded is! Map) {
            throw ApiException(
              ApiErrorCode.badRequest,
              message: 'Request body must be a JSON object.',
            );
          }
          final body = decoded.cast<String, Object?>();
          final supervisorOverride =
              (body['supervisorOverride'] as bool?) ?? false;
          if (supervisorOverride && !auth.can('verification_override')) {
            throw ApiException(
              ApiErrorCode.forbidden,
              message:
                  'Supervisor override requires the verification_override '
                  'permission.',
            );
          }
          final result = await repo.decide(
            attendanceId: request.params['id']!,
            organizationId: auth.organizationId,
            verifierId: auth.userId,
            outcomeWire: body['outcome'] as String? ?? '',
            reason: body['reason'] as String?,
            supervisorOverride: supervisorOverride,
            ifMatchVersion: ifMatch,
            correlationId: correlationOf(request),
          );
          switch (result.code) {
            case VerificationDecisionCode.applied:
              // The client ignores this body; returning just the new status
              // avoids a second loadCase (and its own audit-on-view row) for
              // what is already an audited decision.
              return _json({'status': result.finalStatus});
            case VerificationDecisionCode.notFound:
              throw ApiException(ApiErrorCode.notFound);
            case VerificationDecisionCode.versionConflict:
              throw ApiException(
                ApiErrorCode.preconditionFailed,
                message: 'This case was decided by someone else; reload it.',
              );
            case VerificationDecisionCode.reasonRequired:
              throw ApiException(
                ApiErrorCode.decisionReasonRequired,
                message: 'A reason is required for this decision.',
              );
            case VerificationDecisionCode.unsupportedOutcome:
              throw ApiException(
                ApiErrorCode.verificationOutcomeUnsupported,
                message: 'Unrecognised or unsupported outcome.',
              );
          }
        }),
  );

  return router;
}

Response _json(Object? body) => Response.ok(
  jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
