import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/correlation.dart';
import '../infra/error_envelope.dart';
import '../infra/idempotency.dart';
import '../infra/json_fields.dart';
import 'participant_repo.dart';

/// Accepts `+`, digits, spaces and dashes; 8–15 digits after normalisation
/// (E.164 ceiling). Anything else is a badRequest naming the field — the
/// same "no silent coercion" contract as json_fields.dart.
String _requirePhone(Map<String, Object?> body) {
  final raw = stringField(body, 'phone');
  final normalized = raw?.replaceAll(RegExp(r'[ -]'), '');
  if (normalized == null || !RegExp(r'^\+?\d{8,15}$').hasMatch(normalized)) {
    badField(
      'phone',
      'must be 8-15 digits, optionally with +, spaces or '
          'dashes',
    );
  }
  return normalized;
}

String _requireNonEmptyString(Map<String, Object?> body, String field) {
  final value = stringField(body, field);
  if (value == null || value.trim().isEmpty) {
    badField(field, 'is required and must be non-empty');
  }
  return value.trim();
}

/// `/carpenters`, `/sessions/<id>/registrations` and the two write routes
/// under `/campaigns/<id>/`. Reads are authenticate-only (same posture and
/// same product-confirmation caveat as campaign reads — no read permission
/// exists in the client's claim vocabulary); writes require
/// `campaign_create`, matching the client's own route guard.
Router participantRouter({required Db db, required ParticipantRepo repo}) {
  final router = Router();

  router.get('/carpenters', (Request request) async {
    final auth = authOf(request);
    final q = request.url.queryParameters['q'] ?? '';
    if (q.trim().length < 2) {
      // The client UI already enforces this; the server re-enforces it so a
      // one-character probe cannot enumerate the whole org master.
      throw ApiException(
        ApiErrorCode.badRequest,
        message: '"q" must be at least 2 characters.',
        details: {'field': 'q'},
      );
    }
    final items = await repo.search(
      organizationId: auth.organizationId,
      q: q.trim(),
    );
    return _jsonResponse({
      'items': [for (final c in items) c.toWireJson()],
    });
  });

  router.get('/sessions/<id>/registrations', (
    Request request,
    String id,
  ) async {
    final auth = authOf(request);
    final roster = await repo.rosterForSession(
      id,
      organizationId: auth.organizationId,
    );
    if (roster == null) throw ApiException(ApiErrorCode.notFound);
    return _jsonResponse({
      'items': [for (final c in roster) c.toWireJson()],
    });
  });

  router.post(
    '/campaigns/<id>/registrations',
    const Pipeline()
        .addMiddleware(requirePermission('campaign_create'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final campaignId = request.params['id']!;
          final body = await readJsonBody(request);
          final ids = stringListField(body, 'carpenterIds');
          if (ids.isEmpty) {
            badField('carpenterIds', 'must be a non-empty array');
          }
          final result = await repo.register(
            campaignId: campaignId,
            organizationId: auth.organizationId,
            carpenterIds: ids,
            registeredBy: auth.userId,
            correlationId: correlationOf(request),
          );
          if (result == null) throw ApiException(ApiErrorCode.notFound);
          return _jsonResponse({
            'registered': result.registered,
            'alreadyRegistered': result.alreadyRegistered,
          });
        }),
  );

  router.post(
    '/campaigns/<id>/profile-requests',
    const Pipeline()
        .addMiddleware(requirePermission('campaign_create'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final campaignId = request.params['id']!;
          final body = await readJsonBody(request);
          final name = _requireNonEmptyString(body, 'name');
          final phone = _requirePhone(body);
          final result = await repo.createProfileRequest(
            campaignId: campaignId,
            organizationId: auth.organizationId,
            name: name,
            phone: phone,
            requestedBy: auth.userId,
            correlationId: correlationOf(request),
          );
          if (result == null) throw ApiException(ApiErrorCode.notFound);
          return Response(
            201,
            body: jsonEncode({
              'requestId': result.requestId,
              'carpenter': result.carpenter.toWireJson(),
            }),
            headers: {'content-type': 'application/json'},
          );
        }),
  );

  return router;
}

Response _jsonResponse(Map<String, Object?> body) => Response.ok(
  jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
