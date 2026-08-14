import 'dart:convert';

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
  'import_job_rows',
  'import_jobs',
  'profile_requests',
  'registrations',
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
    ),
    (
      id: seedCarpenterUddinId,
      name: 'Karim Uddin',
      phone: '+8801700007734',
      code: 'CARP-00007734',
      territory: seedTerritorySouthId,
      dealer: null,
    ),
  ];
  for (final c in carpenters) {
    await db.execute(
      'INSERT INTO carpenters '
      '(id, organization_id, full_name, phone, territory_id, '
      " dealer_context, display_code, source, sync_status) "
      "VALUES (@id, @org, @name, @phone, @territory, @dealer, @code, "
      "        'SEED', 'LOCAL_ONLY')",
      params: {
        'id': c.id,
        'org': seedOrganizationId,
        'name': c.name,
        'phone': c.phone,
        'territory': c.territory,
        'dealer': c.dealer,
        'code': c.code,
      },
    );
  }
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
