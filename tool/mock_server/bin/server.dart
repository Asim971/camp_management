import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

/// In-memory stub backend for the ACSL Campaign app. Implements every endpoint
/// the Flutter repositories call, so local dev and the Maestro E2E suite run
/// end-to-end without a real backend. State is per-process (restart to reset).
///
///   dart pub get
///   dart run bin/server.dart            # listens on 0.0.0.0:8080
///   MOCK_CAMPAIGNS=empty dart run bin/server.dart   # campaign_list smoke variant
///
/// Android emulator reaches the host at http://10.0.2.2:8080; web/desktop at
/// http://localhost:8080. Point the app with --dart-define=API_BASE_URL=...
void main() async {
  final store = _Store();
  final api = _buildRouter(store);

  final handler = const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(logRequests())
      .addHandler(api.call);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Mock server on http://${server.address.host}:${server.port}');
  stdout.writeln(
    'Campaign fixture: ${Platform.environment['MOCK_CAMPAIGNS'] ?? 'rows'}',
  );
}

// ---------------------------------------------------------------------------
// CORS + JSON helpers
// ---------------------------------------------------------------------------

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
      'Origin, Content-Type, Authorization, If-Match, Idempotency-Key',
};

Middleware _cors() =>
    (inner) => (req) async {
      if (req.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final res = await inner(req);
      return res.change(headers: {...res.headers, ..._corsHeaders});
    };

Response _json(Object? body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'Content-Type': 'application/json'},
);

Future<Map<String, dynamic>> _body(Request req) async {
  final text = await req.readAsString();
  if (text.isEmpty) return {};
  final decoded = jsonDecode(text);
  return decoded is Map<String, dynamic> ? decoded : {};
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

Router _buildRouter(_Store store) {
  final r = Router();
  final importJobs = <String, Map<String, dynamic>>{};

  // ---- Campaigns ----------------------------------------------------------
  //
  // Decision values, `version` and list paging below match the real
  // server's wire contract (Tasks 8-9). This stub does not enforce
  // idempotency keys or emit the full `{"error": {...}}` envelope on every
  // path — Task 11's parity tests are what fills in the rest — but it must
  // not CONTRADICT the shape, which is why status/version/paging now agree.
  r.get('/campaigns', (Request req) {
    final fixture = Platform.environment['MOCK_CAMPAIGNS'] ?? 'rows';
    if (fixture == 'error') return _json({'error': 'boom'}, status: 500);
    var items = fixture == 'empty'
        ? <Map<String, dynamic>>[]
        : store.campaigns.values.toList();

    final q = req.url.queryParameters['q'];
    if (q != null && q.isNotEmpty) {
      final needle = q.toLowerCase();
      items = items
          .where((c) => (c['name'] as String).toLowerCase().contains(needle))
          .toList();
    }
    final statuses = req.url.queryParametersAll['status'] ?? const [];
    if (statuses.isNotEmpty) {
      items = items.where((c) => statuses.contains(c['status'])).toList();
    }

    final total = items.length;
    // Mirrors the real server exactly (campaign_routes.dart:65-66 for the
    // defaults, campaign_repo.dart:70-73 for the clamp): page is 1-based and
    // clamped to >= 1, pageSize clamped to 1..100. A 0-based `page * pageSize`
    // offset (this file's previous version) agreed with the real server only
    // when page was absent — anything else silently returned the wrong
    // slice, which is exactly the kind of contradiction this mock exists to
    // not have.
    final rawPage = int.tryParse(req.url.queryParameters['page'] ?? '') ?? 1;
    final rawPageSize =
        int.tryParse(req.url.queryParameters['pageSize'] ?? '') ?? 20;
    final page = rawPage < 1 ? 1 : rawPage;
    final pageSize = rawPageSize < 1
        ? 1
        : (rawPageSize > 100 ? 100 : rawPageSize);
    final start = ((page - 1) * pageSize).clamp(0, items.length);
    final end = (start + pageSize).clamp(start, items.length);
    return _json({'items': items.sublist(start, end), 'total': total});
  });

  r.post('/campaigns', (Request req) async {
    final b = await _body(req);
    final campaign = store.createCampaign(b);
    return _json(campaign);
  });

  r.get('/campaigns/<id>', (Request req, String id) {
    final c = store.campaigns[id];
    return c == null ? _json({'error': 'not found'}, status: 404) : _json(c);
  });

  r.put('/campaigns/<id>', (Request req, String id) async {
    final b = await _body(req);
    final result = store.updateCampaign(id, b);
    return result.toResponse();
  });

  r.post('/campaigns/<id>/submit', (Request req, String id) async {
    final b = await _body(req);
    final result = store.setStatus(
      id,
      'PENDING_APPROVAL',
      expectedVersion: b['version'],
    );
    return result.toResponse();
  });

  r.post('/campaigns/<id>/decision', (Request req, String id) async {
    final b = await _body(req);
    final status = switch (b['decision']) {
      'APPROVE' => 'APPROVED',
      'RETURN_FOR_CORRECTION' => 'RETURNED',
      'REJECT' => 'CANCELLED',
      _ => null,
    };
    if (status == null) {
      return _json({
        'error': {
          'code': 'BAD_REQUEST',
          'message': 'Unrecognised decision "${b['decision']}".',
        },
      }, status: 400);
    }
    final result = store.setStatus(id, status, expectedVersion: b['version']);
    return result.toResponse();
  });

  // ---- Sessions -----------------------------------------------------------
  r.get('/campaigns/<id>/sessions', (Request req, String id) {
    return _json({'items': store.sessionsFor(id)});
  });

  r.post('/sessions/<id>/<action>', (Request req, String id, String action) {
    final s = store.sessionAction(id, action);
    return s == null ? _json({'error': 'not found'}, status: 404) : _json(s);
  });

  // ---- Registration -------------------------------------------------------
  r.get('/carpenters', (Request req) {
    final q = (req.url.queryParameters['q'] ?? '').toLowerCase();
    final items = store.carpenters
        .where(
          (c) =>
              q.isEmpty ||
              (c['name'] as String).toLowerCase().contains(q) ||
              (c['displayId'] as String).toLowerCase().contains(q) ||
              (c['phoneSuffix'] as String).endsWith(q),
        )
        .toList();
    return _json({'items': items});
  });

  r.get('/sessions/<id>/registrations', (Request req, String id) {
    return _json({'items': store.carpenters});
  });

  r.post('/campaigns/<id>/registrations', (Request req, String id) async {
    final b = await _body(req);
    final ids = (b['carpenterIds'] as List?)?.cast<String>() ?? const [];
    if (ids.isEmpty) {
      return _json({
        'error': {'code': 'BAD_REQUEST', 'message': 'carpenterIds required'},
      }, status: 400);
    }
    return _json({'registered': ids.length, 'alreadyRegistered': 0});
  });

  r.post('/campaigns/<id>/profile-requests', (Request req, String id) async {
    final b = await _body(req);
    // A zero-padded 4-digit serial so displayId/phoneSuffix satisfy the
    // parity regexes ^CARP-••\d{4}$ and ^\d{4}$ exactly like the real
    // server's masks do.
    final serial = store.nextId().toString().padLeft(4, '0');
    final carpenter = {
      'id': 'CARP_REQ_$serial',
      'name': b['name'] ?? '',
      'displayId': 'CARP-••$serial',
      'phoneSuffix': serial,
      'territory': '',
      'dealerContext': null,
      'thumbnailUrl': null,
      'eligible': true,
      'syncStatus': 'PENDING_PROFILE_SYNC',
    };
    store.carpenters.add(carpenter);
    return _json({
      'requestId': 'REQ-$serial',
      'carpenter': carpenter,
    }, status: 201);
  });

  // ---- Verification -------------------------------------------------------
  //
  // `filter` matches the real service's QueueFilter wire vocabulary
  // (verification_routes.dart / packages/campaign_contracts/queue_filter.dart)
  // exactly: ALL/MINE/UNASSIGNED/ESCALATED, defaulting to ALL, with anything
  // else answering the same BAD_REQUEST envelope shape the rest of this file
  // uses. MINE/UNASSIGNED read the mutable `store.assignees` map (below)
  // rather than each item's static `assigneeId` field, so a case claimed via
  // POST .../claim shows up under MINE without a server restart.
  r.get('/verification/queue', (Request req) {
    final filterWire = req.url.queryParameters['filter'] ?? 'ALL';
    Iterable<Map<String, dynamic>> items = store.verificationQueue;
    switch (filterWire) {
      case 'ALL':
        break;
      case 'MINE':
        items = items.where(
          (i) =>
              store.assigneeOf(i['attendanceId'] as String) ==
              _Store.mockUserId,
        );
        break;
      case 'UNASSIGNED':
        items = items.where(
          (i) => store.assigneeOf(i['attendanceId'] as String) == null,
        );
        break;
      case 'ESCALATED':
        // The real service additionally 403s this filter for a caller
        // lacking `verification_override` (verification_routes.dart). This
        // mock has no per-request RBAC model at all -- no roles/permissions
        // are threaded through requests -- so that 403 stays a
        // REAL-SERVICE-ONLY assertion, same as 5a documented for
        // `sensitive_media_view`.
        items = items.where((i) => i['escalatedAt'] != null);
        break;
      default:
        return _json({
          'error': {
            'code': 'BAD_REQUEST',
            'message': 'Unknown queue filter "$filterWire".',
          },
        }, status: 400);
    }
    return _json({
      'items': [for (final i in items) store.queueItemWire(i)],
    });
  });

  r.get('/verification/cases/<id>', (Request req, String id) {
    return _json(store.verificationCase(id, req.requestedUri));
  });

  r.post('/verification/cases/<id>/decision', (Request req, String id) async {
    final b = await _body(req);
    // Version-aware, matching the real service (verification_routes.dart):
    // the caller presents the version it last saw via If-Match, and a value
    // that doesn't match the case's current version yields 412, not a
    // hardcoded 409. CASE_CONFLICT's fixture version is ahead of what the
    // e2e/parity flow sends (2 vs. an `If-Match: 1` client), so it always
    // reads as stale; CASE_E2E is at version 1, so `If-Match: 1` matches.
    final ifMatch = int.tryParse(req.headers['if-match'] ?? '');
    if (ifMatch != store.caseVersion(id)) {
      return _json({
        'error': {
          'code': 'PRECONDITION_FAILED',
          'message': 'This case was decided by someone else; reload it.',
        },
      }, status: 412);
    }
    // Outcome -> status, matching the real service's `statusForOutcome`
    // table exactly (verification_repo.dart): APPROVED/REJECTED stay
    // themselves, RETURN_FOR_RECAPTURE -> RETURNED, and ESCALATED stays
    // open at CRM_REVIEW. Anything else is unsupported, same as the real
    // service's `VerificationOutcome.tryParseWire` returning null.
    final outcome = (b['outcome'] as String?) ?? '';
    const statusForOutcome = {
      'APPROVED': 'APPROVED',
      'REJECTED': 'REJECTED',
      'RETURN_FOR_RECAPTURE': 'RETURNED',
      'ESCALATED': 'CRM_REVIEW',
    };
    final mappedStatus = statusForOutcome[outcome];
    if (mappedStatus == null) {
      return _json({
        'error': {
          'code': 'VERIFICATION_OUTCOME_UNSUPPORTED',
          'message': 'Unrecognised or unsupported outcome.',
        },
      }, status: 422);
    }
    // Rejecting, returning, escalating, or overriding requires a non-blank
    // reason -- same ordering and predicate as verification_repo.dart's
    // `reasonRequired` (checked only once the outcome itself is known-good).
    final supervisorOverride = b['supervisorOverride'] == true;
    final reasonRequired =
        supervisorOverride ||
        outcome == 'REJECTED' ||
        outcome == 'RETURN_FOR_RECAPTURE' ||
        outcome == 'ESCALATED';
    final reason = (b['reason'] as String?)?.trim();
    if (reasonRequired && (reason == null || reason.isEmpty)) {
      return _json({
        'error': {
          'code': 'DECISION_REASON_REQUIRED',
          'message': 'A reason is required for this decision.',
        },
      }, status: 422);
    }
    // The real service additionally 403s a `supervisorOverride: true` decision
    // from a verifier lacking `verification_override` (verification_routes.dart).
    // This mock has no per-request RBAC model at all -- no roles/permissions
    // are threaded through requests -- so that 403 stays a REAL-SERVICE-ONLY
    // assertion, same as 5a documented for `sensitive_media_view`.
    return _json({'status': mappedStatus});
  });

  // Claim/release (sub-project 5c): single-assignee workflow state, modeled
  // on the real service's `VerificationRepo.claim`/`.release` (same 409-when-
  // held-by-another rule) but acting as one fixed identity (`_Store.
  // mockUserId`) rather than a real per-request caller, since this mock has
  // no auth threaded through its handlers at all. Deliberately does NOT
  // touch a case's decision `version` -- same as the real repo -- so a
  // pending /decision call presenting the pre-claim version still succeeds.
  r.post('/verification/cases/<id>/claim', (Request req, String id) async {
    await req.read().drain<void>(); // no body is read
    if (!store.verificationQueue.any((i) => i['attendanceId'] == id)) {
      return _json({
        'error': {
          'code': 'NOT_FOUND',
          'message': 'The requested resource was not found.',
        },
      }, status: 404);
    }
    final current = store.assigneeOf(id);
    if (current != null && current != _Store.mockUserId) {
      return _json({
        'error': {
          'code': 'CONFLICT_STALE_VERSION',
          'message':
              'This case is being reviewed by someone else; reload the '
              'queue.',
        },
      }, status: 409);
    }
    store.assignees[id] = _Store.mockUserId;
    return _json({'status': 'ok'});
  });

  r.post('/verification/cases/<id>/release', (Request req, String id) async {
    await req.read().drain<void>(); // no body is read
    if (!store.verificationQueue.any((i) => i['attendanceId'] == id)) {
      return _json({
        'error': {
          'code': 'NOT_FOUND',
          'message': 'The requested resource was not found.',
        },
      }, status: 404);
    }
    if (store.assigneeOf(id) != _Store.mockUserId) {
      return _json({
        'error': {
          'code': 'CONFLICT_STALE_VERSION',
          'message':
              'This case is being reviewed by someone else; reload the '
              'queue.',
        },
      }, status: 409);
    }
    store.assignees[id] = null;
    return _json({'status': 'ok'});
  });

  // ---- Analytics ------------------------------------------------------
  //
  // RD3.D1 (Task 3): computed from this store's own campaign +
  // `_analyticsAttendance` fixtures (never hardcoded envelope constants),
  // transcribing `AnalyticsRepo.summary`'s semantics exactly (server/lib/
  // src/analytics/analytics_repo.dart): `funnel.target`/`registered` are
  // STRUCTURAL (campaignId-scoped but date-unranged) denominators; every
  // other field is governed by the resolved from/to. Gated on `export` via
  // [_permissionsOf] -- the first route in this file with a genuine
  // per-request permission check (every other gate mentioned elsewhere in
  // this file, e.g. on `/verification/queue`'s ESCALATED filter, is
  // REAL-SERVICE-ONLY, since no other route here threads auth through at
  // all).
  r.get('/analytics/summary', (Request req) {
    if (!_permissionsOf(req).contains('export')) {
      // JSON error envelope, not the bare `Response.forbidden(null)` the
      // real service's `requirePermission` middleware itself answers with
      // (server/lib/src/auth/middleware.dart) -- because that bare response
      // never reaches a real client as-is: `errorEnvelope()`, the outermost
      // middleware in server/lib/src/app.dart, rewraps any bare >=400
      // response into exactly this `{"error": {...}}` shape before it goes
      // over the wire (server/lib/src/infra/error_envelope.dart). `traceId`
      // is omitted -- this mock has no correlation-id middleware to source
      // one from, same as every other error envelope in this file.
      return _json({
        'error': {
          'code': 'FORBIDDEN',
          'message': 'You do not have permission to perform this action.',
        },
      }, status: 403);
    }
    final qp = req.url.queryParameters;
    final now = DateTime.now().toUtc();
    final to = qp['to'] == null ? now : DateTime.tryParse(qp['to']!);
    final from = qp['from'] == null
        ? (to ?? now).subtract(const Duration(days: 29))
        : DateTime.tryParse(qp['from']!);
    if (from == null || to == null || from.isAfter(to)) {
      return _json({
        'error': {'code': 'BAD_REQUEST', 'message': 'Invalid analytics range.'},
      }, status: 400);
    }
    return _json(
      store.analyticsSummary(campaignId: qp['campaignId'], from: from, to: to),
    );
  });

  // ---- Audit (🔒 contract-pending shape) ----------------------------------
  // Real so dev and E2E flush successfully; a throwing stub would fail every
  // flush and grow the local buffer for no reason.
  r.post('/audit/events', (Request req) async {
    final body = await _body(req);
    final events = body['events'];
    return _json({'accepted': events is List ? events.length : 0});
  });

  // ---- Bulk import --------------------------------------------------------
  //
  // Ratified async shapes (2b.D1-D5): dry-run answers 202 with a PROCESSING
  // job; the first poll flips it to READY_TO_COMMIT with classified rows
  // (this mock has no real classifier, so it just plants the terminal
  // outcome on the first GET); commit lives under the namespaced
  // `/campaigns/<id>/imports/<jobId>/commit` path, matching the real
  // server's route (server/lib/src/import_/import_routes.dart) — the old
  // un-namespaced `/imports/<jobId>/commit` never matched the real contract.
  r.post('/campaigns/<id>/imports/dry-run', (Request req, String id) async {
    await req.read().drain<void>(); // consume the multipart body
    final jobId = 'IMPORT-${store.nextId()}';
    final job = {
      'id': jobId,
      'campaignId': id,
      'status': 'PROCESSING',
      'totalRows': 2,
      'processedRows': 0,
      'rows': [
        {
          'rowId': 'row-1',
          'name': 'Md. Karim',
          'outcome': null,
          'message': null,
          'linkedCarpenterId': null,
        },
        {
          'rowId': 'row-2',
          'name': 'Brand New',
          'outcome': null,
          'message': null,
          'linkedCarpenterId': null,
        },
      ],
    };
    importJobs[jobId] = job;
    return _json(job, status: 202);
  });

  r.get('/imports/<jobId>', (Request req, String jobId) {
    final job = importJobs[jobId];
    if (job == null) {
      return _json({
        'error': {'code': 'NOT_FOUND', 'message': 'no job'},
      }, status: 404);
    }
    // First poll flips it to ready with classified rows.
    job['status'] = 'READY_TO_COMMIT';
    job['processedRows'] = 2;
    final rows = job['rows'] as List<Map<String, dynamic>>;
    rows[0]['outcome'] = 'VALID';
    rows[1]['outcome'] = 'NEEDS_PROFILE';
    return _json(job);
  });

  r.post('/campaigns/<id>/imports/<jobId>/commit', (
    Request req,
    String id,
    String jobId,
  ) async {
    await req.read().drain<void>(); // consume the (unused) request body
    final job =
        importJobs[jobId] ??
        {
          'id': jobId,
          'campaignId': id,
          'status': 'READY_TO_COMMIT',
          'totalRows': 2,
          'processedRows': 2,
          'rows': const [],
        };
    job['status'] = 'COMPLETED';
    return _json(job);
  });

  // ---- Media / attendance sync -------------------------------------------
  r.post('/media/presign', (Request req) async {
    final b = await _body(req);
    final id = b['attendanceId'] ?? 'unknown';
    final url = req.requestedUri.replace(path: '/media/upload/$id').toString();
    return _json({'url': url});
  });

  r.put('/media/upload/<id>', (Request req, String id) async {
    await req.read().drain<void>(); // accept the encrypted bytes
    return Response.ok('');
  });

  r.post('/attendance/<id>/confirm', (Request req, String id) async {
    await _body(req);
    return _json({'status': 'CRM_REVIEW'});
  });

  // ---- Consent --------------------------------------------------------
  // Matches the real service's shape exactly (server/lib/src/consent/
  // consent_routes.dart): {'notices': [...]} with each item carrying
  // version (int), language, title, body, contentHash.
  r.get('/consent/notices', (Request req) {
    return _json({
      'notices': [
        {
          'version': 1,
          'language': 'en',
          'title': 'Consent',
          'body': 'We record your attendance for verification.',
          'contentHash': 'mock-en',
        },
      ],
    });
  });

  // Tiny fixture image for CRM evidence (1x1 PNG).
  r.get('/media/fixtures/face.png', (Request req) {
    return Response.ok(
      base64Decode(_pngPixel),
      headers: {'Content-Type': 'image/png'},
    );
  });

  // ---- Auth (🔒 contract-pending shapes) ----------------------------------
  // Role is taken from the username so E2E can sign in as each role:
  // "crm_verifier", "campaign_creator", "admin", anything else -> field user.
  r.post('/auth/login', (Request req) async {
    final body = await _body(req);
    final username = (body['username'] as String?) ?? 'field_user';
    final password = (body['password'] as String?) ?? '';
    if (password.isEmpty) {
      return _json({'error': 'invalid credentials'}, status: 401);
    }
    return _json(_authPayload(username));
  });

  r.post('/auth/refresh', (Request req) async {
    final body = await _body(req);
    final token = (body['refreshToken'] as String?) ?? '';
    if (token.isEmpty || token == 'expired') {
      return _json({'error': 'invalid refresh token'}, status: 401);
    }
    // Rotate: a new refresh token each time, so the client's single-flight
    // guard is exercised against realistic rotation.
    return _json(_authPayload(token.replaceFirst('refresh-for-', '')));
  });

  r.post('/auth/logout', (Request req) async {
    await _body(req);
    return Response(204);
  });

  return r;
}

/// Role -> permission expansion, shared by [_authPayload] (what a login
/// response advertises for a role) and [_permissionsOf] (what
/// `/analytics/summary`'s gate actually checks a caller's bearer token
/// against) -- one source of truth, so a token this mock issues for role R
/// is always gated by exactly the permissions R's own login response
/// claimed.
const Map<String, List<String>> _permissionsByRole = {
  'crm_verifier': ['verification_decide', 'sensitive_media_view'],
  'campaign_creator': ['campaign_create', 'bulk_import', 'export'],
  'admin': [
    'campaign_create',
    'campaign_approve',
    'campaign_cancel',
    'bulk_import',
    'attendance_capture',
    'verification_decide',
    'verification_override',
    'sensitive_media_view',
    'nid_reveal',
    'config_manage',
    'export',
  ],
};

Map<String, dynamic> _authPayload(String username) {
  final role = _permissionsByRole.containsKey(username)
      ? username
      : 'field_user';
  return {
    'accessToken': 'mock-access-$role',
    'refreshToken': 'refresh-for-$role',
    'expiresInSeconds': 900,
    'claims': {
      'userId': 'mock-$role',
      'displayName': 'Mock $role',
      'organizationId': 'ORG_MOCK',
      'roles': [role],
      'permissions': _permissionsByRole[role] ?? ['attendance_capture'],
      'territoryIds': <String>[],
    },
  };
}

/// The caller's permission set, resolved from a mock-issued bearer token
/// (`mock-access-<role>`, minted by [_authPayload] above) against the same
/// [_permissionsByRole] map. A missing or malformed token (no `Bearer `
/// prefix, or a token that isn't of the `mock-access-<role>` shape) carries
/// no permissions at all (denied) -- this mock has no session store to
/// consult, so an unfamiliar token shape can never be assumed privileged.
/// A well-formed token naming a role [_permissionsByRole] doesn't recognise
/// falls back to `['attendance_capture']`, mirroring [_authPayload]'s own
/// fallback for an unrecognised role one line above.
Set<String> _permissionsOf(Request req) {
  final header = req.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) return const <String>{};
  final token = header.substring('Bearer '.length);
  const prefix = 'mock-access-';
  if (!token.startsWith(prefix)) return const <String>{};
  final role = token.substring(prefix.length);
  return (_permissionsByRole[role] ?? const ['attendance_capture']).toSet();
}

// ---------------------------------------------------------------------------
// Campaign mutation result — carries either the updated row or the reason it
// wasn't updated, so route handlers turn it into a response with one call.
// ---------------------------------------------------------------------------

class _MutationResult {
  const _MutationResult.ok(Map<String, dynamic> campaign)
    : _campaign = campaign,
      _error = null;
  const _MutationResult.notFound() : _campaign = null, _error = 'not_found';
  const _MutationResult.conflict() : _campaign = null, _error = 'conflict';

  final Map<String, dynamic>? _campaign;
  final String? _error;

  Response toResponse() => switch (_error) {
    'not_found' => _json({
      'error': {
        'code': 'NOT_FOUND',
        'message': 'The requested resource was not found.',
      },
    }, status: 404),
    'conflict' => _json({
      'error': {
        'code': 'CONFLICT_STALE_VERSION',
        'message': 'The campaign has changed since you last loaded it.',
      },
    }, status: 409),
    _ => _json(_campaign),
  };
}

// ---------------------------------------------------------------------------
// In-memory state + seeds
// ---------------------------------------------------------------------------

class _Store {
  _Store() {
    campaigns['CAMP-1'] = _campaign(
      id: 'CAMP-1',
      name: 'ACSL Pilot Carpenter Drive',
      status: 'APPROVED',
      target: 100,
      verified: 12,
    );
    campaigns['CAMP-2'] = _campaign(
      id: 'CAMP-2',
      name: 'Chattogram Contractor Meet',
      status: 'PENDING_APPROVAL',
      target: 60,
      verified: 0,
    );
    // A DRAFT row exists for .maestro/flows/locale_bengali.yaml, which asserts
    // the Bengali `campaignStatus_draft` chip ("খসড়া") on the campaign list.
    // Without a DRAFT campaign in the fixture that chip never renders and the
    // flow fails for a reason that has nothing to do with localization. The
    // Bengali string is a three-way contract: this fixture,
    // test/features/campaign_list/presentation/campaign_list_status_label_test.dart
    // and lib/l10n/app_bn.arb.
    campaigns['CAMP-3'] = _campaign(
      id: 'CAMP-3',
      name: 'Rajshahi Carpenter Drive',
      status: 'DRAFT',
      target: 40,
      verified: 0,
    );
    // Seeded from verificationQueue's own initial `assigneeId`s -- a field
    // initializer can't reference another instance member (only the
    // constructor body can), which is why this lives here rather than
    // alongside `assignees`'s declaration below.
    assignees.addEntries(
      verificationQueue.map(
        (item) => MapEntry(
          item['attendanceId'] as String,
          item['assigneeId'] as String?,
        ),
      ),
    );
  }

  final Map<String, Map<String, dynamic>> campaigns = {};
  var _seq = 100;

  int nextId() => ++_seq;

  final List<Map<String, dynamic>> carpenters = [
    {
      'id': 'CARP_E2E',
      'name': 'Md. Karim',
      'displayId': 'CARP-••4821',
      'phoneSuffix': '4821',
      'territory': 'Dhaka North',
      'dealerContext': 'Rahman Traders',
      'thumbnailUrl': null,
      'eligible': true,
      'syncStatus': 'LOCAL_ONLY',
      'attendanceState': 'notCaptured',
    },
    {
      'id': 'CARP_E2E_2',
      'name': 'Karim Uddin',
      'displayId': 'CARP-••7734',
      'phoneSuffix': '7734',
      'territory': 'Dhaka South',
      'dealerContext': null,
      'thumbnailUrl': null,
      'eligible': true,
      'syncStatus': 'LOCAL_ONLY',
      'attendanceState': 'notCaptured',
    },
  ];

  /// The fixed identity `claim`/`release` act "as" (sub-project 5c) — this
  /// mock has no per-request auth threaded through its handlers, so every
  /// claim always assigns to this one id rather than a real caller's.
  static const mockUserId = 'seed-crm_verifier';

  final List<Map<String, dynamic>> verificationQueue = [
    {
      // Kept unassigned with a null escalatedAt: the e2e/parity flow (and
      // Task 7 (5a)'s decision-shape parity case above) depend on this exact
      // id staying open and unclaimed.
      'attendanceId': 'CASE_E2E',
      'carpenterName': 'Md. Karim',
      'campaignName': 'ACSL Pilot Carpenter Drive',
      'ageSeconds': 3600,
      'band': 'MEDIUM',
      'referenceSource': 'VERIFIED_PROFILE_PHOTO',
      'assigneeId': null,
      'escalatedAt': null,
    },
    {
      // Pre-assigned to `mockUserId` itself, so filter=MINE has something to
      // return even before any claim call is made in a given process.
      'attendanceId': 'CASE_ASSIGNED',
      'carpenterName': 'Karim Uddin',
      'campaignName': 'ACSL Pilot Carpenter Drive',
      'ageSeconds': 1800,
      'band': 'HIGH',
      'referenceSource': 'VERIFIED_PROFILE_PHOTO',
      'assigneeId': mockUserId,
      'escalatedAt': null,
    },
    {
      'attendanceId': 'CASE_ESCALATED',
      'carpenterName': 'Abdul Jabbar',
      'campaignName': 'Chattogram Contractor Meet',
      'ageSeconds': 7200,
      'band': 'NO_REFERENCE',
      'referenceSource': 'UNAVAILABLE',
      'assigneeId': null,
      'escalatedAt': '2026-08-10T09:00:00.000Z',
    },
    {
      // Pre-assigned to someone OTHER than `mockUserId`. This mock has no
      // real per-request identity to claim "as" a second, different
      // principal, so this fixture item stands in for "already held by
      // someone else" when exercising the claim route's 409 conflict path
      // (parity_test.dart's Task 7 (5c) case).
      'attendanceId': 'CASE_HELD_BY_OTHER',
      'carpenterName': 'Nasima Begum',
      'campaignName': 'Rajshahi Carpenter Drive',
      'ageSeconds': 900,
      'band': 'LOW',
      'referenceSource': 'APPROVED_BASELINE_PHOTO',
      'assigneeId': 'seed-other-verifier',
      'escalatedAt': null,
    },
  ];

  /// case id -> current assignee, mutated only by the claim/release routes.
  /// Kept separate from [verificationQueue]'s own (initial) `assigneeId`
  /// field so the queue filter and claim/release handlers share one mutable
  /// source of truth for "who holds this case now" -- mirrors how
  /// `_sessions` below is the one place session state lives. Populated in
  /// the constructor above (see its comment for why).
  final Map<String, String?> assignees = {};

  String? assigneeOf(String attendanceId) => assignees[attendanceId];

  /// The wire item for a queue [fixture] row, with its current mutable
  /// assignee overlaid onto the otherwise-static fixture fields.
  Map<String, dynamic> queueItemWire(Map<String, dynamic> fixture) => {
    ...fixture,
    'assigneeId': assignees[fixture['attendanceId']],
  };

  Map<String, dynamic> _campaign({
    required String id,
    required String name,
    required String status,
    required int target,
    required int verified,
    int version = 1,
  }) => {
    'id': id,
    'name': name,
    'type': 'seminar',
    'organizationId': 'ORG_E2E',
    'status': status,
    'ownerId': 'owner-123', // != approver, so approval is allowed
    'startAt': null,
    'endAt': null,
    'venue': 'BMD Training Center',
    'objective': 'Engage carpenters and verify attendance.',
    'territoryIds': ['Dhaka North'],
    'targetAudience': target,
    'verifiedAttendance': verified,
    'version': version,
  };

  Map<String, dynamic> createCampaign(Map<String, dynamic> draft) {
    final id = 'CAMP-${_seq++}';
    // Matches the real server: a freshly created row starts at version 1
    // (server/lib/src/campaign/campaign_repo.dart's INSERT), not 0.
    final c = _campaign(
      id: id,
      name: (draft['name'] as String?) ?? 'Untitled',
      status: 'DRAFT',
      target: (draft['target'] as int?) ?? 0,
      verified: 0,
    );
    campaigns[id] = c;
    return c;
  }

  /// Zero-affected-rows-as-409 is the real server's whole concurrency
  /// guarantee (campaign_repo.dart); this mirrors it with a plain
  /// version-equality check since there is no row to fail to update.
  _MutationResult updateCampaign(String id, Map<String, dynamic> draft) {
    final c = campaigns[id];
    if (c == null) return const _MutationResult.notFound();
    if (!_versionMatches(c, draft['version'])) {
      return const _MutationResult.conflict();
    }
    if (draft['name'] != null) c['name'] = draft['name'];
    if (draft['target'] != null) c['targetAudience'] = draft['target'];
    c['version'] = (c['version'] as int) + 1;
    return _MutationResult.ok(c);
  }

  _MutationResult setStatus(
    String id,
    String status, {
    required Object? expectedVersion,
  }) {
    final c = campaigns[id];
    if (c == null) return const _MutationResult.notFound();
    if (!_versionMatches(c, expectedVersion)) {
      return const _MutationResult.conflict();
    }
    c['status'] = status;
    c['version'] = (c['version'] as int) + 1;
    return _MutationResult.ok(c);
  }

  bool _versionMatches(Map<String, dynamic> campaign, Object? expected) =>
      expected is int && campaign['version'] == expected;

  final Map<String, Map<String, dynamic>> _sessions = {};

  List<Map<String, dynamic>> sessionsFor(String campaignId) {
    // '-S1', not '#1': '#' is the URI fragment delimiter, so any client that
    // builds this id into a request path via the normal Uri APIs (as the
    // parity suite's POST /sessions/<id>/start does) would have it truncated
    // client-side or split off server-side by dart:io's own request-target
    // parsing -- '#1/start' never reaches this router at all. No real
    // client (Flutter app, Maestro flows) depended on the old delimiter.
    if (!_sessions.containsKey('$campaignId-S1')) {
      _sessions['$campaignId-S1'] = {
        'id': '$campaignId-S1',
        'campaignId': campaignId,
        'venue': 'BMD Training Center, Hall A',
        'status': 'UPCOMING',
        'startAt': '2026-08-01T09:00:00.000',
        'endAt': '2026-08-01T13:00:00.000',
        'capacity': 60,
        'registeredCount': 0,
        'pendingSyncCount': 0,
        'reviewCount': 0,
        'approvedCount': 0,
        'readinessOk': true,
      };
    }
    return _sessions.values
        .where((s) => s['campaignId'] == campaignId)
        .toList();
  }

  Map<String, dynamic>? sessionAction(String id, String action) {
    final s = _sessions[id];
    if (s == null) return null;
    s['status'] = switch (action) {
      'start' => 'ACTIVE',
      'close' => 'CAPTURE_CLOSED',
      'pause' => 'PAUSED',
      _ => s['status'],
    };
    return s;
  }

  /// CASE_CONFLICT's version is ahead of the fixed `If-Match: 1` the
  /// e2e/parity flow sends, so a decision against it always reads as stale
  /// (412); CASE_E2E stays at version 1, so `If-Match: 1` matches (200).
  int caseVersion(String id) => id == 'CASE_CONFLICT' ? 2 : 1;

  Map<String, dynamic> verificationCase(String id, Uri origin) {
    final img = origin.replace(path: '/media/fixtures/face.png').toString();
    return {
      'attendanceId': id,
      'version': caseVersion(id),
      // CASE_CONFLICT is the already-decided fixture (version 2, see
      // caseVersion above) -- its status reflects that decision rather than
      // still being open for one, matching the real wire (Task 5).
      'status': id == 'CASE_CONFLICT' ? 'APPROVED' : 'CRM_REVIEW',
      'carpenterName': 'Md. Karim',
      'carpenterIdMasked': 'CARP-••4821',
      'campaignName': 'ACSL Pilot Carpenter Drive',
      'sessionName': 'Hall A · 01 Aug',
      'capturedAt': '2026-08-01T10:15:00.000',
      'capturedImageUrl': img,
      'referenceImageUrl': img,
      'band': 'MEDIUM',
      'referenceSource': 'VERIFIED_PROFILE_PHOTO',
      'padReview': false,
      'lowQuality': false,
      'reasons': ['Landmark alignment within tolerance'],
    };
  }

  /// Fixed structural registration counts per campaign (RD3.D1) -- this
  /// mock has no persistent `registrations` table, so
  /// `/analytics/summary`'s unranged `funnel.registered` denominator is a
  /// small fixed fixture rather than a derived count, same spirit as
  /// `_campaign`'s fixed `verifiedAttendance` field above.
  static const Map<String, int> _registeredByCampaign = {
    'CAMP-1': 2,
    'CAMP-2': 1,
    'CAMP-3': 0,
  };

  /// The four `MatchBand` wire values, in the fixed order the wire envelope
  /// always presents `bandMix` in — mirrors `AnalyticsRepo`'s own
  /// `_bandKeys` (server/lib/src/analytics/analytics_repo.dart).
  static const List<String> _bandKeys = [
    'HIGH',
    'MEDIUM',
    'LOW',
    'NO_REFERENCE',
  ];

  /// Attendance-shaped rows `/analytics/summary` computes its ranged
  /// numbers from (RD3.D1) -- status/band/capturedAt per campaign,
  /// mirroring the real `attendance` table's columns
  /// `AnalyticsRepo.summary` reads. Dated in mid-2025: comfortably outside
  /// any rolling "last 30 days" default window for the foreseeable life of
  /// this fixture, so a no-params query always sees zero ranged activity
  /// -- deterministic regardless of the day the mock (or the parity suite)
  /// happens to run.
  static final List<_AnalyticsAttendance> _analyticsAttendance = [
    _AnalyticsAttendance(
      campaignId: 'CAMP-1',
      status: 'APPROVED',
      band: 'HIGH',
      capturedAt: DateTime.utc(2025, 6, 1, 10),
    ),
    _AnalyticsAttendance(
      campaignId: 'CAMP-1',
      status: 'APPROVED',
      band: 'MEDIUM',
      capturedAt: DateTime.utc(2025, 6, 1, 15),
    ),
    _AnalyticsAttendance(
      campaignId: 'CAMP-1',
      status: 'APPROVED',
      band: 'HIGH',
      capturedAt: DateTime.utc(2025, 6, 3, 9),
    ),
    _AnalyticsAttendance(
      campaignId: 'CAMP-1',
      status: 'CRM_REVIEW',
      band: 'LOW',
      capturedAt: DateTime.utc(2025, 6, 3, 11),
    ),
    _AnalyticsAttendance(
      campaignId: 'CAMP-1',
      status: 'REJECTED',
      band: 'NO_REFERENCE',
      capturedAt: DateTime.utc(2025, 6, 4, 8),
    ),
  ];

  /// Computes the `/analytics/summary` envelope from this store's own
  /// [campaigns] + [_analyticsAttendance] fixtures -- transcribing
  /// `AnalyticsRepo.summary`'s semantics exactly (see that method's doc
  /// comment for the binding ruling this mirrors): `target`/`registered`
  /// are structural (campaignId-scoped, date-unranged) denominators; every
  /// other field is governed by [from]/[to], which the route has already
  /// resolved and validated before calling this.
  Map<String, dynamic> analyticsSummary({
    String? campaignId,
    required DateTime from,
    required DateTime to,
  }) {
    final fromUtc = DateTime.utc(from.year, from.month, from.day);
    // Built from [to]'s year/month/day fields directly, not `.toUtc()` --
    // same reason as AnalyticsRepo.summary's `toDateOnly`: a bare
    // "yyyy-MM-dd" query param parses to a local-time DateTime, and
    // `.toUtc()` on one can roll the calendar date across a host timezone
    // offset.
    final toDateOnly = DateTime.utc(to.year, to.month, to.day);
    final toExclusive = toDateOnly.add(const Duration(days: 1));

    final scopedCampaigns = campaignId == null
        ? campaigns.values.toList()
        : campaigns.values.where((c) => c['id'] == campaignId).toList();

    final target = scopedCampaigns.fold<int>(
      0,
      (sum, c) => sum + (c['targetAudience']! as int),
    );
    final registered = campaignId == null
        ? _registeredByCampaign.values.fold<int>(0, (a, b) => a + b)
        : (_registeredByCampaign[campaignId] ?? 0);

    bool inRange(_AnalyticsAttendance a) =>
        (campaignId == null || a.campaignId == campaignId) &&
        !a.capturedAt.isBefore(fromUtc) &&
        a.capturedAt.isBefore(toExclusive);

    final rangedRows = _analyticsAttendance.where(inRange).toList();

    final statusCounts = <String, int>{};
    for (final row in rangedRows) {
      statusCounts[row.status] = (statusCounts[row.status] ?? 0) + 1;
    }
    final captured = rangedRows.length;
    final approved = statusCounts['APPROVED'] ?? 0;
    final inReview = statusCounts['CRM_REVIEW'] ?? 0;
    final rejected = statusCounts['REJECTED'] ?? 0;
    final returned = statusCounts['RETURNED'] ?? 0;

    final perDay = <String, int>{};
    for (final row in rangedRows.where((r) => r.status == 'APPROVED')) {
      final day = _dateOnly(row.capturedAt);
      perDay[day] = (perDay[day] ?? 0) + 1;
    }
    final sortedDays = perDay.keys.toList()..sort();
    final verifiedPerDay = [
      for (final day in sortedDays) {'date': day, 'count': perDay[day]!},
    ];

    final bandCounts = <String, int>{};
    for (final row in rangedRows) {
      bandCounts[row.band] = (bandCounts[row.band] ?? 0) + 1;
    }
    final bandMix = {for (final key in _bandKeys) key: bandCounts[key] ?? 0};

    final campaignRows = [
      for (final c in scopedCampaigns)
        {
          'id': c['id'],
          'name': c['name'],
          'status': c['status'],
          'target': c['targetAudience'],
          'verified': _analyticsAttendance
              .where(
                (a) =>
                    a.campaignId == c['id'] &&
                    a.status == 'APPROVED' &&
                    !a.capturedAt.isBefore(fromUtc) &&
                    a.capturedAt.isBefore(toExclusive),
              )
              .length,
          'inReview': _analyticsAttendance
              .where(
                (a) =>
                    a.campaignId == c['id'] &&
                    a.status == 'CRM_REVIEW' &&
                    !a.capturedAt.isBefore(fromUtc) &&
                    a.capturedAt.isBefore(toExclusive),
              )
              .length,
        },
    ]..sort((a, b) => (a['name']! as String).compareTo(b['name']! as String));

    return {
      'funnel': {
        'target': target,
        'registered': registered,
        'captured': captured,
        'inReview': inReview,
        'approved': approved,
        'rejected': rejected,
        'returned': returned,
      },
      'verifiedPerDay': verifiedPerDay,
      'bandMix': bandMix,
      'campaigns': campaignRows,
      'sample': {'totalAttendance': captured, 'small': captured < 30},
      'range': {'from': _dateOnly(fromUtc), 'to': _dateOnly(toDateOnly)},
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

/// One `/analytics/summary` fixture row (RD3.D1) -- see `_Store.
/// _analyticsAttendance`'s doc comment for why these dates are fixed in
/// mid-2025.
class _AnalyticsAttendance {
  const _AnalyticsAttendance({
    required this.campaignId,
    required this.status,
    required this.band,
    required this.capturedAt,
  });

  final String campaignId;
  final String status;
  final String band;
  final DateTime capturedAt;
}

/// yyyy-MM-dd for a UTC [d] -- mirrors `AnalyticsRepo`'s own `_dateOnly`.
String _dateOnly(DateTime d) => d.toIso8601String().substring(0, 10);

/// 1×1 transparent PNG — enough for Image.network to load in E2E.
const _pngPixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
