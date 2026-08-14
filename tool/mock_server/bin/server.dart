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
  r.get('/verification/queue', (Request req) {
    return _json({'items': store.verificationQueue});
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
    // SCREAMING_SNAKE outcome (APPROVED/REJECTED), matching the real wire —
    // the mock doesn't deeply validate it, just echoes it back as `status`.
    final outcome = (b['outcome'] as String?) ?? 'APPROVED';
    return _json({'status': outcome});
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

Map<String, dynamic> _authPayload(String username) {
  final roles = <String, List<String>>{
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
  final role = roles.containsKey(username) ? username : 'field_user';
  return {
    'accessToken': 'mock-access-$role',
    'refreshToken': 'refresh-for-$role',
    'expiresInSeconds': 900,
    'claims': {
      'userId': 'mock-$role',
      'displayName': 'Mock $role',
      'organizationId': 'ORG_MOCK',
      'roles': [role],
      'permissions': roles[role] ?? ['attendance_capture'],
      'territoryIds': <String>[],
    },
  };
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

  final List<Map<String, dynamic>> verificationQueue = [
    {
      'attendanceId': 'CASE_E2E',
      'carpenterName': 'Md. Karim',
      'campaignName': 'ACSL Pilot Carpenter Drive',
      'ageSeconds': 3600,
      'band': 'MEDIUM',
      'referenceSource': 'VERIFIED_PROFILE_PHOTO',
      'assigneeId': null,
    },
  ];

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
}

/// 1×1 transparent PNG — enough for Image.network to load in E2E.
const _pngPixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
