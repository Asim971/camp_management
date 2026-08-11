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
            correlationId: correlationOf(request),
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
            correlationId: correlationOf(request),
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
            correlationId: correlationOf(request),
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
            acknowledgedWarnings: _stringListField(
              body,
              'acknowledgedWarnings',
            ),
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
///
/// Every field below is read through one of the typed `_*Field` helpers,
/// which throw [ApiErrorCode.badRequest] naming the offending field on a
/// type mismatch, rather than an unguarded `as` cast: `{"target": "50"}`,
/// `{"sessions": {}}`, `{"territoryIds": [1]}` and a session's
/// `{"startAt": "nope"}` were all reaching the error envelope's catch-all as
/// an unhandled `TypeError`/`FormatException` — a 500, reporting a client's
/// malformed request as a server fault — before this existed. This mirrors
/// `_requireVersion`/`_requireDecision` below, which already did this for
/// their one field each.
CampaignDraftInput _draftInputFromBody(
  Map<String, Object?> body, {
  required String ownerId,
}) {
  final sessionsJson = _listField(body, 'sessions');
  return CampaignDraftInput(
    name: _stringField(body, 'name') ?? '',
    type: _stringField(body, 'type') ?? '',
    objective: _stringField(body, 'objective'),
    territoryIds: _stringListField(body, 'territoryIds'),
    target: _intField(body, 'target') ?? 0,
    budgetReference: _stringField(body, 'budgetReference'),
    approverId: _stringField(body, 'approverId'),
    ownerId: ownerId,
    geofenceEnabled: _boolField(body, 'geofenceEnabled') ?? false,
    sessions: [
      for (var i = 0; i < sessionsJson.length; i++)
        _sessionInputFromJson(sessionsJson[i], index: i),
    ],
  );
}

// `reportAs` names the field in the error, `field` is the actual JSON key to
// read — a session object's own keys are still plain `venue`/`startAt`/etc
// (it has no idea it's element 0 of the array), so looking it up BY its
// prefixed report name (`sessions[0].startAt`) would silently miss every
// real value: every session field would read back as "absent" and the
// wrong error (missing) would fire instead of the right one (wrong type),
// or worse, a well-formed session would lose its own data. Caught by the
// existing suite: 8 pre-existing tests broke when this file's first draft
// conflated the two.
SessionInput _sessionInputFromJson(Object? raw, {required int index}) {
  if (raw is! Map<String, Object?>) {
    _badField('sessions[$index]', 'must be an object');
  }
  final prefix = 'sessions[$index]';
  return SessionInput(
    venue: _stringField(raw, 'venue', reportAs: '$prefix.venue'),
    capacity: _intField(raw, 'capacity', reportAs: '$prefix.capacity'),
    startAt: _dateTimeField(raw, 'startAt', reportAs: '$prefix.startAt'),
    endAt: _dateTimeField(raw, 'endAt', reportAs: '$prefix.endAt'),
  );
}

/// Every `_*Field` helper below shares the same contract: `null`/absent is
/// a valid "not provided" (the caller decides the fallback), but a value
/// that IS present and the wrong JSON type is a [badRequest] naming [field]
/// (or [reportAs], for a nested field whose own JSON key isn't the name a
/// caller wants surfaced) — never a silent coercion and never an uncaught
/// cast exception.
Never _badField(String field, String problem) => throw ApiException(
  ApiErrorCode.badRequest,
  message: '"$field" $problem.',
  details: {'field': field},
);

String? _stringField(
  Map<String, Object?> body,
  String field, {
  String? reportAs,
}) {
  final value = body[field];
  if (value == null) return null;
  if (value is! String) _badField(reportAs ?? field, 'must be a string');
  return value;
}

int? _intField(Map<String, Object?> body, String field, {String? reportAs}) {
  final value = body[field];
  if (value == null) return null;
  if (value is! int) _badField(reportAs ?? field, 'must be an integer');
  return value;
}

bool? _boolField(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value == null) return null;
  if (value is! bool) _badField(field, 'must be a boolean');
  return value;
}

/// `[]` when [field] is absent — every caller here treats "not provided"
/// the same as "provided empty" — but a [field] that IS present and not a
/// JSON array (e.g. `{}`) is a [badRequest], not a value silently coerced
/// into an empty list.
List<Object?> _listField(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value == null) return const [];
  if (value is! List) _badField(field, 'must be an array');
  return value;
}

/// [_listField] plus an element-type check — `{"territoryIds": [1]}` names
/// the specific offending index (`territoryIds[0]`) rather than failing
/// lazily, mid-iteration, wherever the list is later consumed (`cast`'s
/// laziness is exactly how this one reached the envelope as a 500 before
/// this check existed).
List<String> _stringListField(Map<String, Object?> body, String field) {
  final list = _listField(body, field);
  for (var i = 0; i < list.length; i++) {
    if (list[i] is! String) _badField('$field[$i]', 'must be a string');
  }
  return list.cast<String>();
}

DateTime? _dateTimeField(
  Map<String, Object?> body,
  String field, {
  String? reportAs,
}) {
  final value = body[field];
  if (value == null) return null;
  if (value is! String) {
    _badField(reportAs ?? field, 'must be an ISO-8601 string');
  }
  try {
    return DateTime.parse(value);
  } on FormatException {
    _badField(reportAs ?? field, 'must be a valid ISO-8601 date/time');
  }
}

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
