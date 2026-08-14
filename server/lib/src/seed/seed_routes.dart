import 'dart:convert';
import 'dart:typed_data';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/password.dart';
import '../config.dart';
import '../db/pool.dart';
import '../infra/error_envelope.dart';

// Test-only fixture data. Every value here is deliberately fixed and
// documented, rather than randomly generated, so a Maestro flow (or a human
// debugging one) can hard-code exactly what `POST /__test__/reset` leaves
// behind instead of discovering it at runtime.

// ---------------------------------------------------------------------------
// Fixture identifiers
// ---------------------------------------------------------------------------

const String seedOrganizationId = 'org-e2e';
const String seedTerritoryNorthId = 'terr-dhaka-north';
const String seedTerritorySouthId = 'terr-dhaka-south';

// Mirror tool/mock_server's carpenters (same ids and names) so
// carpenter-facing flows keep working whichever backend is behind
// API_BASE_URL. displayId on the wire: CARP-••4821 / CARP-••7734;
// phoneSuffix: 4821 / 7734 (4 digits — Task 8 aligns the mock's data).
const String seedCarpenterKarimId = 'CARP_E2E';
const String seedCarpenterUddinId = 'CARP_E2E_2';

/// The 7 roles `permissionsByRole` (auth/tokens.dart) recognises. These ARE
/// the exact wire role names: the client's `scope_claims.dart` rejects
/// sign-in on any role name it does not recognise, so nothing here may be
/// invented or renamed (spec D4/D5).
const List<String> seedRoles = [
  'campaign_creator',
  'marketing_approver',
  'crm_verifier',
  'crm_supervisor',
  'field_user',
  'admin',
  'reporting_viewer',
];

/// Every seeded user's username IS its role name and every seeded user
/// shares this one password — a Maestro flow authenticating for real only
/// needs to remember a role name, not a lookup table.
const String seedPassword = 'Test1234!';

String seedUserId(String role) => 'seed-$role';

/// One fixture campaign: [name] and [status] are asserted verbatim by
/// `.maestro/flows/locale_bengali.yaml` (the Rajshahi/DRAFT row) and are
/// modelled on `tool/mock_server/bin/server.dart`'s CAMP-1..3 so the same
/// flow keeps working whichever backend is behind the app's API_BASE_URL.
class _CampaignFixture {
  const _CampaignFixture({
    required this.id,
    required this.name,
    required this.status,
    required this.targetAudience,
    required this.territoryId,
  });

  final String id;
  final String name;
  final CampaignStatus status;
  final int targetAudience;
  final String territoryId;
}

const List<_CampaignFixture> _campaignFixtures = [
  _CampaignFixture(
    id: 'seed-camp-1',
    name: 'ACSL Pilot Carpenter Drive',
    status: CampaignStatus.approved,
    targetAudience: 100,
    territoryId: seedTerritoryNorthId,
  ),
  _CampaignFixture(
    id: 'seed-camp-2',
    name: 'Chattogram Contractor Meet',
    status: CampaignStatus.pendingApproval,
    targetAudience: 60,
    territoryId: seedTerritoryNorthId,
  ),
  // `locale_bengali.yaml` asserts this exact name + DRAFT status (rendered
  // as the Bengali chip "খসড়া") on the campaign list and detail header.
  _CampaignFixture(
    id: 'seed-camp-3',
    name: 'Rajshahi Carpenter Drive',
    status: CampaignStatus.draft,
    targetAudience: 40,
    territoryId: seedTerritorySouthId,
  ),
];

// ---------------------------------------------------------------------------
// The armed-error fixture, shared with buildApp's campaignsErrorArmMiddleware
// ---------------------------------------------------------------------------

/// Set by `POST /__test__/campaigns {"fixture":"error"}`, consumed by
/// [campaignsErrorArmMiddleware]. A plain top-level flag, not a class: this
/// module is only ever loaded once per server process, and the middleware it
/// backs is only ever wired in when seeding is enabled (see `app.dart`) — the
/// same lifetime the flag itself needs.
bool _armedCampaignsError = false;

/// Fails the next `GET /campaigns` with a 500 exactly once, then reverts to
/// normal — mirrors the mock's `MOCK_CAMPAIGNS=error`
/// (tool/mock_server/bin/server.dart), which the app's error-state flow
/// (campaign_list_smoke.yaml, run manually) depends on. Must run inside
/// `errorEnvelope()` (i.e. be part of the same pipeline `app.dart` builds),
/// so throwing here still comes back as the documented `{"error": {...}}`
/// shape.
Middleware campaignsErrorArmMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      if (_armedCampaignsError &&
          request.method == 'GET' &&
          request.requestedUri.path == '/campaigns') {
        _armedCampaignsError = false;
        throw ApiException(
          ApiErrorCode.internal,
          message: 'Armed test failure (fixture "error").',
        );
      }
      return inner(request);
    };
  };
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

/// `/__test__/*`. Mounted by `buildApp` ONLY when [ServerConfig.seedingEnabled]
/// — see that function's doc — so this router existing at all is already
/// proof seeding was explicitly turned on.
///
/// `POST /__test__/reset` truncates every table and re-seeds one
/// organization, two territories, one user per role (known
/// username/password), and the same three campaigns
/// `POST /__test__/campaigns {"fixture":"rows"}` would produce — so a caller
/// that only ever calls `reset` between flows (as
/// `tool/scripts/run_maestro_flows.sh` does) still gets a backend the
/// campaign-reading flows can drive without a second call.
///
/// `POST /__test__/campaigns` accepts `{"fixture": "rows" | "empty" |
/// "error"}`, matching the mock's `MOCK_CAMPAIGNS` values, for the flows/runs
/// that need a different campaign state than `reset`'s default.
Router seedRouter({
  required Db db,
  required ServerConfig config,
  required PasswordHasher hasher,
}) {
  final router = Router();

  router.post('/__test__/reset', (Request request) async {
    await _truncateEverything(db);
    await _seedBaseline(db, hasher: hasher);
    await _seedCampaignFixture(db, _campaignFixtures);
    await _seedCarpenterFixture(db);
    await _seedConsentNotices(db);
    await _seedVerificationFixture(db);
    return Response(204);
  });

  router.post('/__test__/campaigns', (Request request) async {
    final body = await _readJsonBody(request);
    final fixture = body['fixture'] as String? ?? 'rows';
    switch (fixture) {
      case 'rows':
        await _seedCampaignFixture(db, _campaignFixtures);
        break;
      case 'empty':
        await _seedCampaignFixture(db, const []);
        break;
      case 'error':
        _armedCampaignsError = true;
        break;
      default:
        throw ApiException(
          ApiErrorCode.badRequest,
          message: 'Unknown fixture "$fixture". Expected rows|empty|error.',
        );
    }
    return Response(204);
  });

  return router;
}

// ---------------------------------------------------------------------------
// Seeding
// ---------------------------------------------------------------------------

/// Every table the foundation schema defines (`db/migrations/embedded.dart`),
/// `schema_migrations` itself excluded — truncating that would make the
/// server think it needs to reapply migrations it already ran.
const List<String> _allSeedableTables = [
  'consent_notices',
  'import_job_rows',
  'import_jobs',
  'profile_requests',
  'registrations',
  // verification_decisions/attendance would cascade from carpenters/campaigns
  // anyway (both FK ON DELETE CASCADE onto attendance/carpenters/campaigns),
  // but media_objects has NO foreign key back to either -- it must be listed
  // explicitly or a reset would leave CASE_E2E/CASE_CONFLICT's old evidence
  // blobs behind under a truncated-and-reused id.
  'verification_decisions',
  'attendance',
  'media_objects',
  'carpenters',
  'campaign_decisions',
  'campaign_submissions',
  'campaign_territories',
  'campaign_sessions',
  'campaigns',
  'idempotency_keys',
  'audit_events',
  'refresh_tokens',
  'staff_user_territories',
  'staff_user_roles',
  'staff_users',
  'territories',
  'organizations',
  'app_config',
];

Future<void> _truncateEverything(Db db) async {
  await db.execute(
    'TRUNCATE ${_allSeedableTables.join(', ')} RESTART IDENTITY CASCADE',
  );
  // The foundation migration seeds this row once, at migration time; a
  // truncated table must not silently disable the SoD gate it backs
  // (config_gate.dart already defaults to enforced when the row is
  // missing, but `reset` restoring it keeps a freshly-reset database
  // identical to a freshly-migrated one).
  await db.execute(
    "INSERT INTO app_config (key, value) VALUES ('sod.enforced', 'true')",
  );
}

Future<void> _seedBaseline(Db db, {required PasswordHasher hasher}) async {
  await db.execute(
    'INSERT INTO organizations (id, name) VALUES (@id, @name)',
    params: {'id': seedOrganizationId, 'name': 'ACSL E2E'},
  );
  await db.execute(
    'INSERT INTO territories (id, organization_id, name) '
    'VALUES (@id, @org, @name)',
    params: {
      'id': seedTerritoryNorthId,
      'org': seedOrganizationId,
      'name': 'Dhaka North',
    },
  );
  await db.execute(
    'INSERT INTO territories (id, organization_id, name) '
    'VALUES (@id, @org, @name)',
    params: {
      'id': seedTerritorySouthId,
      'org': seedOrganizationId,
      'name': 'Dhaka South',
    },
  );

  final passwordHash = await hasher.hash(seedPassword);
  for (final role in seedRoles) {
    final userId = seedUserId(role);
    await db.execute(
      'INSERT INTO staff_users '
      '(id, username, display_name, password_hash, organization_id) '
      'VALUES (@id, @u, @d, @h, @org)',
      params: {
        'id': userId,
        'u': role,
        'd': 'E2E ${role.replaceAll('_', ' ')}',
        'h': passwordHash,
        'org': seedOrganizationId,
      },
    );
    await db.execute(
      'INSERT INTO staff_user_roles (user_id, role) VALUES (@u, @r)',
      params: {'u': userId, 'r': role},
    );
    // Both territories, not just north: seed-camp-3 ("Rajshahi Carpenter
    // Drive", asserted by locale_bengali.yaml) lives in the south
    // territory. Campaign reads only scope by organization today, so a
    // north-only grant happens to work now, but territory-scoped reads are
    // future sub-project work -- granting both up front keeps the locale
    // e2e flow (and any other south-territory fixture) from going red the
    // day that scope lands.
    for (final territoryId in [seedTerritoryNorthId, seedTerritorySouthId]) {
      await db.execute(
        'INSERT INTO staff_user_territories (user_id, territory_id) '
        'VALUES (@u, @t)',
        params: {'u': userId, 't': territoryId},
      );
    }
  }
}

/// Replaces every campaign row with exactly [fixtures] — an empty list is
/// how the `empty` fixture is implemented. Owned by `campaign_creator`,
/// approved/returned by `marketing_approver`: both must already exist, i.e.
/// this must run after [_seedBaseline] (both `reset` and the `rows`/`empty`
/// branches of `POST /__test__/campaigns` rely on `reset` having run first;
/// see the class doc on [seedRouter]).
Future<void> _seedCampaignFixture(
  Db db,
  List<_CampaignFixture> fixtures,
) async {
  await db.execute(
    'TRUNCATE campaign_decisions, campaign_submissions, '
    'campaign_territories, campaign_sessions, campaigns RESTART IDENTITY '
    'CASCADE',
  );
  final ownerId = seedUserId('campaign_creator');
  final approverId = seedUserId('marketing_approver');
  for (final fixture in fixtures) {
    await db.execute(
      'INSERT INTO campaigns '
      '(id, organization_id, name, type, status, owner_id, approver_id, '
      ' target_audience, version) '
      'VALUES (@id, @org, @name, @type, @status, @owner, @approver, '
      '        @target, 1)',
      params: {
        'id': fixture.id,
        'org': seedOrganizationId,
        'name': fixture.name,
        'type': 'seminar',
        'status': fixture.status.wireValue,
        'owner': ownerId,
        'approver': approverId,
        'target': fixture.targetAudience,
      },
    );
    await db.execute(
      'INSERT INTO campaign_territories (campaign_id, territory_id) '
      'VALUES (@campaign, @territory)',
      params: {'campaign': fixture.id, 'territory': fixture.territoryId},
    );
    // One operable session, `seed-camp-1` only: it is the sole APPROVED
    // fixture, so it is the only one a session can legally start on. Fixed
    // id/venue/capacity/start_at so `.maestro/flows/session_ops.yaml` (Task
    // 8) can hard-code exactly what `POST /__test__/reset` leaves behind.
    if (fixture.id == 'seed-camp-1') {
      await db.execute(
        'INSERT INTO campaign_sessions '
        '(id, campaign_id, venue, capacity, start_at, status) '
        "VALUES (@id, @c, @v, 60, @s, 'UPCOMING')",
        params: {
          'id': 'seed-camp-1-session-1',
          'c': fixture.id,
          'v': 'BMD Training Center, Hall A',
          's': DateTime.utc(2026, 9, 1, 9),
        },
      );
      // The dev launcher's `dev_open_search`/`dev_open_capture` entries are
      // hard-coded to `SESSION_E2E` (dev_launcher_screen.dart) — Task 8's
      // real-service capture flow reaches the capture screen through that
      // launcher, so a session with this exact id must exist on
      // `seed-camp-1` (APPROVED) or the confirm's session lookup 404s.
      // Separate row from `seed-camp-1-session-1` (owned by
      // `session_ops.yaml`'s start/pause/close lifecycle) so the capture
      // flow's session is never mutated by that flow's actions.
      //
      // Status CAPTURE_CLOSED, deliberately NOT UPCOMING: neither the confirm
      // transaction (attendance_repo.dart — it joins campaign_sessions only
      // on id + the campaign's organization_id, never status) nor the
      // client's search/capture screens (carpenter_search_controller.dart,
      // capture_controller.dart — sessionId is passed through opaquely) read
      // this session's status, so it has no bearing on the capture flow. A
      // second UPCOMING row here WOULD matter elsewhere though:
      // campaign_detail_screen.dart renders one `session_start`-identified
      // button per UPCOMING/PAUSED session, and session_ops.yaml's
      // `tapOn: {id: session_start}` (no index) assumes exactly one such
      // button on seed-camp-1. CAPTURE_CLOSED renders no action button at
      // all, so that flow's selector stays unambiguous.
      await db.execute(
        'INSERT INTO campaign_sessions '
        '(id, campaign_id, venue, capacity, start_at, status) '
        "VALUES (@id, @c, @v, 60, @s, 'CAPTURE_CLOSED')",
        params: {
          'id': 'SESSION_E2E',
          'c': fixture.id,
          'v': 'BMD Training Center, Hall B',
          's': DateTime.utc(2026, 9, 1, 10),
        },
      );
    }
  }
}

Future<void> _seedCarpenterFixture(Db db) async {
  // The Md. Karim phone (+8801700004821) is what the bulk-import e2e CSV's VALID row matches.
  const carpenters = [
    (
      id: seedCarpenterKarimId,
      name: 'Md. Karim',
      phone: '+8801700004821',
      code: 'CARP-00004821',
      territory: seedTerritoryNorthId,
      dealer: 'Rahman Traders',
      // Task 8 (5a): a thumbnail gives CASE_E2E/CASE_CONFLICT's carpenter a
      // `referenceImageUrl` and makes the confirm's machine check see
      // hasReference=true (-> MEDIUM band, not NO_REFERENCE). No seeded
      // test or Maestro flow asserts CARP_E2E has NO thumbnail, and
      // attendance_capture.yaml (which also captures against this
      // carpenter) only asserts the client-local "Match processing" sync
      // label, which does not depend on the band -- see that flow's own
      // comment.
      thumbnail: 'thumb://carp-e2e',
    ),
    (
      id: seedCarpenterUddinId,
      name: 'Karim Uddin',
      phone: '+8801700007734',
      code: 'CARP-00007734',
      territory: seedTerritorySouthId,
      dealer: null,
      thumbnail: null,
    ),
  ];
  for (final c in carpenters) {
    await db.execute(
      'INSERT INTO carpenters '
      '(id, organization_id, full_name, phone, territory_id, '
      " dealer_context, display_code, source, sync_status, thumbnail_url) "
      "VALUES (@id, @org, @name, @phone, @territory, @dealer, @code, "
      "        'SEED', 'LOCAL_ONLY', @thumb)",
      params: {
        'id': c.id,
        'org': seedOrganizationId,
        'name': c.name,
        'phone': c.phone,
        'territory': c.territory,
        'dealer': c.dealer,
        'code': c.code,
        'thumb': c.thumbnail,
      },
    );
  }
}

/// Seeds the v1 consent notice in both languages the client bundles
/// (`assets/consent/notice_v1.json`) — the same content `GET
/// /consent/notices` reads back for its background refresh. `ON CONFLICT ...
/// DO NOTHING` rather than an unconditional insert because [_truncateEverything]
/// already clears the table on every reset; the guard just keeps this call
/// idempotent if it is ever invoked without a preceding truncate.
Future<void> _seedConsentNotices(Db db) async {
  await db.execute(
    "INSERT INTO consent_notices (version, language, title, body, content_hash) VALUES "
    "(1, 'en', 'Attendance consent', "
    " 'Your photo and attendance are recorded for verification.', 'seed-en-v1'), "
    "(1, 'bn', 'উপস্থিতি সম্মতি', "
    " 'যাচাইয়ের জন্য আপনার ছবি ও উপস্থিতি সংরক্ষণ করা হয়।', 'seed-bn-v1') "
    "ON CONFLICT (version, language) DO NOTHING",
  );
}

/// Seeds the two CRM verification cases `.maestro/flows/crm_case_decision.yaml`
/// and `crm_case_conflict.yaml` (Task 8, sub-project 5a) drive against the
/// real service, plus the dev launcher's `dev_open_crm_case`/
/// `dev_open_crm_case_conflict` entries. Both live on `seed-camp-1` (the sole
/// APPROVED campaign fixture) and its `seed-camp-1-session-1` session, and
/// both reference `CARP_E2E` (seeded with a thumbnail above, so `loadCase`
/// returns a `referenceImageUrl` and the confirm-time machine check would see
/// hasReference=true) -- see [_seedCarpenterFixture]'s comment. Must run
/// after both [_seedCampaignFixture] (campaign/session FKs) and
/// [_seedCarpenterFixture] (carpenter FK) and [_seedBaseline] (captured_by's
/// staff_users FK).
///
/// - `CASE_E2E`: open, in `CRM_REVIEW` at `version=1` -- the case
///   `crm_case_decision.yaml` opens and approves.
/// - `CASE_CONFLICT`: already decided (`APPROVED`, `version=2`) -- the CRM
///   client hard-codes an optimistic `If-Match` from whatever version it just
///   fetched (2), and the decision CAS
///   (`... WHERE version = @ifMatch AND status = 'CRM_REVIEW'`) matches zero
///   rows because the status guard fails, not the version -- so this closed
///   case can never be re-decided, and the route's re-check (row still
///   exists) reports it as the same 412 `PRECONDITION_FAILED` a genuine
///   stale-version race would produce. `crm_case_conflict.yaml` asserts
///   exactly that surfaces as the client's conflict/reload message.
///
/// Each case also gets a matching `media_objects` row (the evidence blob) so
/// its signed `capturedImageUrl` resolves through `GET /media/<id>`.
Future<void> _seedVerificationFixture(Db db) async {
  const campaignId = 'seed-camp-1';
  const sessionId = 'seed-camp-1-session-1';
  final capturedBy = seedUserId('field_user');
  final capturedAt = DateTime.utc(2026, 8, 1, 9, 30);
  final reasons = jsonEncode([
    'Face comparison inconclusive — manual review required.',
  ]);

  Future<void> seedCase({
    required String id,
    required String status,
    required int version,
  }) async {
    await db.execute(
      "INSERT INTO media_objects (id, content_type, bytes) "
      "VALUES (@id, 'image/png', @bytes)",
      params: {
        'id': id,
        // A tiny, deliberately fixed byte string -- the test/flow only
        // needs the evidence blob to exist and round-trip, not to decode as
        // a real image.
        'bytes': Uint8List.fromList(const [0x89, 0x50, 0x4e, 0x47]),
      },
    );
    await db.execute(
      'INSERT INTO attendance '
      '(id, organization_id, campaign_id, session_id, carpenter_id, '
      ' media_ref, status, captured_by, captured_at, machine_band, '
      ' machine_reference_src, machine_reasons, version) '
      "VALUES (@id, @org, @camp, @sess, @carp, @id, @status, @by, @at, "
      "        'MEDIUM', 'APPROVED_BASELINE_PHOTO', @reasons::jsonb, @v)",
      params: {
        'id': id,
        'org': seedOrganizationId,
        'camp': campaignId,
        'sess': sessionId,
        'carp': seedCarpenterKarimId,
        'status': status,
        'by': capturedBy,
        'at': capturedAt,
        'reasons': reasons,
        'v': version,
      },
    );
  }

  await seedCase(id: 'CASE_E2E', status: 'CRM_REVIEW', version: 1);
  await seedCase(id: 'CASE_CONFLICT', status: 'APPROVED', version: 2);
}

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
