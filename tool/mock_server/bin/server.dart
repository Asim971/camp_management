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
  stdout.writeln('Campaign fixture: ${Platform.environment['MOCK_CAMPAIGNS'] ?? 'rows'}');
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

Middleware _cors() => (inner) => (req) async {
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

  // ---- Campaigns ----------------------------------------------------------
  r.get('/campaigns', (Request req) {
    final fixture = Platform.environment['MOCK_CAMPAIGNS'] ?? 'rows';
    if (fixture == 'error') return _json({'error': 'boom'}, status: 500);
    final items = fixture == 'empty' ? <Map>[] : store.campaigns.values.toList();
    return _json({'items': items, 'total': items.length});
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
    final c = store.updateCampaign(id, b);
    return c == null ? _json({'error': 'not found'}, status: 404) : _json(c);
  });

  r.post('/campaigns/<id>/submit', (Request req, String id) {
    final c = store.setStatus(id, 'PENDING_APPROVAL');
    return c == null ? _json({'error': 'not found'}, status: 404) : _json(c);
  });

  r.post('/campaigns/<id>/decision', (Request req, String id) async {
    final b = await _body(req);
    final status = switch (b['decision']) {
      'approve' => 'APPROVED',
      'returnForCorrection' => 'RETURNED',
      'reject' => 'CANCELLED',
      _ => 'PENDING_APPROVAL',
    };
    final c = store.setStatus(id, status);
    return c == null ? _json({'error': 'not found'}, status: 404) : _json(c);
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
        .where((c) =>
            q.isEmpty ||
            (c['name'] as String).toLowerCase().contains(q) ||
            (c['displayId'] as String).toLowerCase().contains(q) ||
            (c['phoneSuffix'] as String).endsWith(q))
        .toList();
    return _json({'items': items});
  });

  r.get('/sessions/<id>/registrations', (Request req, String id) {
    return _json({'items': store.carpenters});
  });

  r.post('/campaigns/<id>/registrations', (Request req, String id) async {
    await _body(req);
    return _json({'ok': true});
  });

  r.post('/campaigns/<id>/profile-requests', (Request req, String id) async {
    await _body(req);
    return _json({'status': 'pendingProfileSync'});
  });

  // ---- Verification -------------------------------------------------------
  r.get('/verification/queue', (Request req) {
    return _json({'items': store.verificationQueue});
  });

  r.get('/verification/cases/<id>', (Request req, String id) {
    return _json(store.verificationCase(id, req.requestedUri));
  });

  r.post('/verification/cases/<id>/decision', (Request req, String id) async {
    await _body(req);
    // Concurrency fixture: this case was "already decided" by another reviewer.
    if (id == 'CASE_CONFLICT') {
      return _json({'error': 'already decided'}, status: 409);
    }
    return _json({'ok': true});
  });

  // ---- Bulk import --------------------------------------------------------
  r.post('/campaigns/<id>/imports/dry-run', (Request req, String id) async {
    await req.read().drain<void>(); // consume the multipart body
    return _json(store.dryRunJob(id));
  });

  r.post('/imports/<jobId>/commit', (Request req, String jobId) {
    return _json(store.commitJob(jobId));
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
    return _json({'status': 'matchProcessing'});
  });

  // Tiny fixture image for CRM evidence (1x1 PNG).
  r.get('/media/fixtures/face.png', (Request req) {
    return Response.ok(
      base64Decode(_pngPixel),
      headers: {'Content-Type': 'image/png'},
    );
  });

  return r;
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
  }

  final Map<String, Map<String, dynamic>> campaigns = {};
  var _seq = 100;

  final List<Map<String, dynamic>> carpenters = [
    {
      'id': 'CARP_E2E',
      'name': 'Md. Karim',
      'displayId': 'CARP-••4821',
      'phoneSuffix': '821',
      'territory': 'Dhaka North',
      'dealerContext': 'Rahman Traders',
      'thumbnailUrl': null,
      'eligible': true,
      'attendanceState': 'notCaptured',
    },
    {
      'id': 'CARP_E2E_2',
      'name': 'Karim Uddin',
      'displayId': 'CARP-••7734',
      'phoneSuffix': '734',
      'territory': 'Dhaka South',
      'dealerContext': null,
      'thumbnailUrl': null,
      'eligible': true,
      'attendanceState': 'notCaptured',
    },
  ];

  final List<Map<String, dynamic>> verificationQueue = [
    {
      'attendanceId': 'CASE_E2E',
      'carpenterName': 'Md. Karim',
      'campaignName': 'ACSL Pilot Carpenter Drive',
      'ageSeconds': 3600,
      'band': 'medium',
      'referenceSource': 'verifiedProfilePhoto',
      'assigneeId': null,
    },
  ];

  Map<String, dynamic> _campaign({
    required String id,
    required String name,
    required String status,
    required int target,
    required int verified,
  }) =>
      {
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
      };

  Map<String, dynamic> createCampaign(Map<String, dynamic> draft) {
    final id = 'CAMP-${_seq++}';
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

  Map<String, dynamic>? updateCampaign(String id, Map<String, dynamic> draft) {
    final c = campaigns[id];
    if (c == null) return null;
    if (draft['name'] != null) c['name'] = draft['name'];
    if (draft['target'] != null) c['targetAudience'] = draft['target'];
    return c;
  }

  Map<String, dynamic>? setStatus(String id, String status) {
    final c = campaigns[id];
    if (c == null) return null;
    c['status'] = status;
    return c;
  }

  final Map<String, Map<String, dynamic>> _sessions = {};

  List<Map<String, dynamic>> sessionsFor(String campaignId) {
    if (!_sessions.containsKey('$campaignId#1')) {
      _sessions['$campaignId#1'] = {
        'id': '$campaignId#1',
        'campaignId': campaignId,
        'venue': 'BMD Training Center, Hall A',
        'status': 'upcoming',
        'startAt': '2026-08-01T09:00:00.000',
        'endAt': '2026-08-01T13:00:00.000',
        'capacity': 60,
        'registeredCount': 42,
        'pendingSyncCount': 3,
        'reviewCount': 5,
        'approvedCount': 30,
        'readinessOk': true,
      };
    }
    return _sessions.values.where((s) => s['campaignId'] == campaignId).toList();
  }

  Map<String, dynamic>? sessionAction(String id, String action) {
    final s = _sessions[id];
    if (s == null) return null;
    s['status'] = switch (action) {
      'start' => 'active',
      'close' => 'captureClosed',
      'pause' => 'paused',
      _ => s['status'],
    };
    return s;
  }

  Map<String, dynamic> verificationCase(String id, Uri origin) {
    final img = origin.replace(path: '/media/fixtures/face.png').toString();
    return {
      'attendanceId': id,
      'version': 1,
      'carpenterName': 'Md. Karim',
      'carpenterIdMasked': 'CARP-••4821',
      'campaignName': 'ACSL Pilot Carpenter Drive',
      'sessionName': 'Hall A · 01 Aug',
      'capturedAt': '2026-08-01T10:15:00.000',
      'capturedImageUrl': img,
      'referenceImageUrl': img,
      'band': 'medium',
      'referenceSource': 'verifiedProfilePhoto',
      'padReview': false,
      'lowQuality': false,
      'reasons': ['Landmark alignment within tolerance'],
    };
  }

  Map<String, dynamic> dryRunJob(String campaignId) => {
        'id': 'IMPORT-1',
        'campaignId': campaignId,
        'status': 'dryRun',
        'rows': [
          {'rowId': '1', 'name': 'Md. Karim', 'outcome': 'valid'},
          {'rowId': '2', 'name': 'Karim Uddin', 'outcome': 'valid'},
          {
            'rowId': '3',
            'name': 'Md. Karim',
            'outcome': 'duplicate',
            'message': 'Matches row 1 by phone',
          },
          {
            'rowId': '4',
            'name': '',
            'outcome': 'error',
            'message': 'Missing name',
          },
          {
            'rowId': '5',
            'name': 'New Person',
            'outcome': 'needsProfile',
            'message': 'No Sales Eco profile — request required',
          },
        ],
      };

  Map<String, dynamic> commitJob(String jobId) => {
        'id': jobId,
        'campaignId': 'CAMP-1',
        'status': 'completed',
        'rows': [
          {'rowId': '1', 'name': 'Md. Karim', 'outcome': 'valid'},
          {'rowId': '2', 'name': 'Karim Uddin', 'outcome': 'valid'},
        ],
      };
}

/// 1×1 transparent PNG — enough for Image.network to load in E2E.
const _pngPixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
