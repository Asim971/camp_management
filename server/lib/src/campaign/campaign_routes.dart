import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/correlation.dart';
import '../infra/error_envelope.dart';
import '../infra/idempotency.dart';
import 'campaign_repo.dart';
import 'validation.dart';

/// `/campaigns` routes. Task 8 wires the two read routes below; Task 9 adds
/// the write routes (create/update/submit/decide) to this same router, each
/// behind its own `requirePermission` and, for the mutating ones,
/// `idempotency`.
///
/// [db] is unused by the read routes themselves — [repo] already wraps it —
/// but is threaded through so Task 9's write routes, which need it directly
/// for `idempotency(db: db)`, don't have to change this function's shape.
///
/// No permission gate on the read routes: reading the campaign list within
/// one's own organization is available to every authenticated role in
/// `permissionsByRole` (`auth/tokens.dart`) today — there is no
/// `campaign_view`-style permission to require. Both routes still run behind
/// `authenticate` wherever this router is mounted, so an unauthenticated
/// caller never reaches them.
///
/// Every query is scoped to `authOf(request).organizationId` inside
/// [CampaignRepo] itself, not as a check applied here after the fact (D7):
/// a campaign in another organization is simply never selected, so
/// `findById` returning `null` is the ONLY signal a missing-vs-foreign
/// campaign ever produces, and both become the ordinary 404 below — never a
/// 403, which would confirm the id exists.
Router campaignRouter({required Db db, required CampaignRepo repo}) {
  final router = Router();

  router.get('/campaigns', (Request request) async {
    final auth = authOf(request);
    final query = request.url.queryParameters;
    final statusValues = request.url.queryParametersAll['status'] ?? const [];

    final statuses = <CampaignStatus>[];
    for (final raw in statusValues) {
      final parsed = CampaignStatus.tryParseWire(raw);
      if (parsed == null) {
        // Silently dropping an unrecognised status would return a superset
        // of what was asked for, not the empty/narrower result the caller
        // expects when they typo a status.
        throw ApiException(
          ApiErrorCode.badRequest,
          message: 'Unknown status value "$raw".',
          details: {'status': raw},
        );
      }
      statuses.add(parsed);
    }

    final result = await repo.list(
      organizationId: auth.organizationId,
      search: query['q'],
      statuses: statuses,
      page: int.tryParse(query['page'] ?? '') ?? 1,
      pageSize: int.tryParse(query['pageSize'] ?? '') ?? 20,
    );

    return _jsonResponse({
      'items': [for (final c in result.items) c.toWireJson()],
      'total': result.total,
    });
  });

  router.get('/campaigns/<id>', (Request request, String id) async {
    final auth = authOf(request);
    final campaign = await repo.findById(
      id,
      organizationId: auth.organizationId,
    );
    if (campaign == null) {
      throw ApiException(ApiErrorCode.notFound);
    }
    return _jsonResponse(campaign.toWireJson());
  });

  // ---- Writes --------------------------------------------------------
  //
  // `campaign_create` gates create/update/submit; `campaign_approve` gates
  // decide. `requirePermission` runs first in every pipeline below so a
  // caller lacking the permission never reaches `idempotency` (a denied
  // request must not claim/replay a key) — the handler's rule order (auth →
  // idempotency → the domain checks inside `CampaignRepo`) starts here and
  // continues inside each repo method.
  //
  // `idempotency` only intercepts POST (see its own doc), so it is simply
  // omitted from the PUT route below rather than added and relied on to no-op.

  router.post(
    '/campaigns',
    const Pipeline()
        .addMiddleware(requirePermission('campaign_create'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final body = await _readJsonBody(request);
          final input = _draftInputFromBody(body, ownerId: auth.userId);
          final created = await repo.create(
            input,
            organizationId: auth.organizationId,
            ownerId: auth.userId,
          );
          return _jsonResponse(created.toWireJson());
        }),
  );

  router.put(
    '/campaigns/<id>',
    const Pipeline()
        .addMiddleware(requirePermission('campaign_create'))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final id = request.params['id']!;
          final body = await _readJsonBody(request);
          final input = _draftInputFromBody(body, ownerId: auth.userId);
          final updated = await repo.updateDraft(
            id,
            input,
            organizationId: auth.organizationId,
            expectedVersion: _requireVersion(body),
          );
          return _jsonResponse(updated.toWireJson());
        }),
  );

  router.post(
    '/campaigns/<id>/submit',
    const Pipeline()
        .addMiddleware(requirePermission('campaign_create'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final id = request.params['id']!;
          final body = await _readJsonBody(request);
          final submitted = await repo.submit(
            id,
            organizationId: auth.organizationId,
            submittedBy: auth.userId,
            expectedVersion: _requireVersion(body),
          );
          return _jsonResponse(submitted.toWireJson());
        }),
  );

  router.post(
    '/campaigns/<id>/decision',
    const Pipeline()
        .addMiddleware(requirePermission('campaign_approve'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final id = request.params['id']!;
          final body = await _readJsonBody(request);
          final decided = await repo.decide(
            id,
            organizationId: auth.organizationId,
            reviewerId: auth.userId,
            decision: _requireDecision(body),
            reason: body['reason'] as String?,
            acknowledgedWarnings: _stringListOf(body['acknowledgedWarnings']),
            expectedVersion: _requireVersion(body),
            correlationId: correlationOf(request),
          );
          return _jsonResponse(decided.toWireJson());
        }),
  );

  return router;
}

Response _jsonResponse(Map<String, Object?> body) => Response.ok(
  jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

/// Decodes [request]'s body as a JSON object. A missing/empty body decodes
/// to `{}` (every field below is then "missing", which the field-level
/// parsing turns into its own specific error) rather than failing outright —
/// only a body that IS present but isn't a JSON object is a [badRequest].
Future<Map<String, Object?>> _readJsonBody(Request request) async {
  final text = await request.readAsString();
  if (text.isEmpty) return const {};
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw ApiException(ApiErrorCode.badRequest, message: 'Invalid JSON body.');
  }
  if (decoded is! Map<String, Object?>) {
    throw ApiException(
      ApiErrorCode.badRequest,
      message: 'Expected a JSON object body.',
    );
  }
  return decoded;
}

/// The wire shape the client's wizard sends for create/update: everything
/// [CampaignDraftInput] needs, with [ownerId] coming from the caller's own
/// `AuthContext` — never from the body, so a client cannot create or edit a
/// campaign "as" someone else by naming a different owner.
CampaignDraftInput _draftInputFromBody(
  Map<String, Object?> body, {
  required String ownerId,
}) {
  final sessionsJson = body['sessions'] as List? ?? const [];
  return CampaignDraftInput(
    name: body['name'] as String? ?? '',
    type: body['type'] as String? ?? '',
    objective: body['objective'] as String?,
    territoryIds: _stringListOf(body['territoryIds']),
    target: body['target'] as int? ?? 0,
    budgetReference: body['budgetReference'] as String?,
    approverId: body['approverId'] as String?,
    ownerId: ownerId,
    geofenceEnabled: body['geofenceEnabled'] as bool? ?? false,
    sessions: [
      for (final raw in sessionsJson)
        _sessionInputFromJson(raw as Map<String, Object?>),
    ],
  );
}

SessionInput _sessionInputFromJson(Map<String, Object?> json) => SessionInput(
  venue: json['venue'] as String?,
  capacity: json['capacity'] as int?,
  startAt: _parseDateTime(json['startAt']),
  endAt: _parseDateTime(json['endAt']),
);

DateTime? _parseDateTime(Object? value) =>
    value is String ? DateTime.parse(value) : null;

List<String> _stringListOf(Object? value) =>
    (value as List? ?? const []).cast<String>();

/// `version` is required on every version-checked write (update, submit,
/// decide) — a missing or non-integer value is a client bug, not something
/// to default away and pretend the caller opted into overwriting whatever is
/// currently there.
int _requireVersion(Map<String, Object?> body) {
  final version = body['version'];
  if (version is! int) {
    throw ApiException(
      ApiErrorCode.badRequest,
      message: '"version" is required and must be an integer.',
    );
  }
  return version;
}

/// `decision` on the wire is SCREAMING_SNAKE (`APPROVE`,
/// `RETURN_FOR_CORRECTION`, `REJECT`) — see
/// [CampaignDecisionInput.tryParseWire]. Missing or unrecognised is a
/// [badRequest], not any of the campaign-specific codes: the caller sent a
/// malformed request, not one that failed a business rule.
CampaignDecisionInput _requireDecision(Map<String, Object?> body) {
  final raw = body['decision'];
  final parsed = raw is String ? CampaignDecisionInput.tryParseWire(raw) : null;
  if (parsed == null) {
    throw ApiException(
      ApiErrorCode.badRequest,
      message: 'Unknown or missing decision value.',
      details: {'decision': raw},
    );
  }
  return parsed;
}
