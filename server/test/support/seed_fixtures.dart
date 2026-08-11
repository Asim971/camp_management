import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/auth/password.dart';
import 'package:campaign_service/src/db/pool.dart';

/// Inserts an organization, a territory, and one staff user with the given
/// roles and permissions. Returns the user id.
///
/// Roles and permissions MUST come from the vocabulary in
/// lib/core/auth/scope_claims.dart — the client rejects sign-in on any name it
/// does not recognise, so an invented one fails the whole login, not one route.
Future<String> seedOrganizationWithUser(
  Db db, {
  String orgId = 'org-1',
  String territoryId = 'terr-1',
  String userId = 'user-1',
  String username = 'creator',
  String password = 'pw',
  List<String> roles = const ['campaign_creator'],
  PasswordHasher hasher = const PasswordHasher(
    params: Argon2Params.fastForTests,
  ),
}) async {
  await db.execute(
    'INSERT INTO organizations (id, name) VALUES (@id, @name) '
    'ON CONFLICT (id) DO NOTHING',
    params: {'id': orgId, 'name': 'Org'},
  );
  await db.execute(
    'INSERT INTO territories (id, organization_id, name) '
    'VALUES (@id, @org, @name) ON CONFLICT (id) DO NOTHING',
    params: {'id': territoryId, 'org': orgId, 'name': 'Territory'},
  );
  await db.execute(
    'INSERT INTO staff_users '
    '(id, username, display_name, password_hash, organization_id) '
    'VALUES (@id, @u, @d, @h, @org)',
    params: {
      'id': userId,
      'u': username,
      'd': 'Test User',
      'h': await hasher.hash(password),
      'org': orgId,
    },
  );
  for (final role in roles) {
    await db.execute(
      'INSERT INTO staff_user_roles (user_id, role) VALUES (@u, @r)',
      params: {'u': userId, 'r': role},
    );
  }
  await db.execute(
    'INSERT INTO staff_user_territories (user_id, territory_id) '
    'VALUES (@u, @t)',
    params: {'u': userId, 't': territoryId},
  );
  return userId;
}

/// Inserts one campaign row, and its `campaign_territories` rows if
/// [territoryIds] is non-empty.
///
/// Defaults line up with [seedOrganizationWithUser]'s own defaults
/// (`org-1`/`user-1`), so a test that hasn't customised either fixture gets
/// a campaign the default caller's token can actually see.
Future<void> seedCampaign(
  Db db, {
  required String id,
  String name = 'Test Campaign',
  String type = 'ATTENDANCE',
  String organizationId = 'org-1',
  String ownerId = 'user-1',
  CampaignStatus status = CampaignStatus.draft,
  String? objective,
  String? venue,
  String? approverId,
  int targetAudience = 0,
  int version = 1,
  List<String> territoryIds = const [],
  DateTime? startAt,
  DateTime? endAt,
}) async {
  await db.execute(
    'INSERT INTO campaigns '
    '(id, organization_id, name, type, objective, status, owner_id, '
    ' approver_id, venue, target_audience, version, start_at, end_at) '
    'VALUES (@id, @org, @name, @type, @objective, @status, @owner, '
    ' @approver, @venue, @target, @version, @startAt, @endAt)',
    params: {
      'id': id,
      'org': organizationId,
      'name': name,
      'type': type,
      'objective': objective,
      'status': status.wireValue,
      'owner': ownerId,
      'approver': approverId,
      'venue': venue,
      'target': targetAudience,
      'version': version,
      'startAt': startAt,
      'endAt': endAt,
    },
  );
  for (final territoryId in territoryIds) {
    await db.execute(
      'INSERT INTO campaign_territories (campaign_id, territory_id) '
      'VALUES (@campaign, @territory)',
      params: {'campaign': id, 'territory': territoryId},
    );
  }
}

/// Inserts one `campaign_sessions` row directly, bypassing every route and
/// validator. [id] defaults to something unique enough for a handful of
/// sessions per test; pass an explicit one if a test needs to name it.
Future<void> seedCampaignSession(
  Db db, {
  required String id,
  required String campaignId,
  String? venue,
  int? capacity,
  DateTime? startAt,
  DateTime? endAt,
}) => db.execute(
  'INSERT INTO campaign_sessions '
  '(id, campaign_id, venue, capacity, start_at, end_at) '
  'VALUES (@id, @campaign, @venue, @capacity, @startAt, @endAt)',
  params: {
    'id': id,
    'campaign': campaignId,
    'venue': venue,
    'capacity': capacity,
    'startAt': startAt,
    'endAt': endAt,
  },
);

/// A DRAFT campaign written straight into the database with two
/// deliberately overlapping sessions — the shape a malicious or stale
/// client could send if the wizard were the only thing enforcing session
/// non-overlap. `submit`'s server-side [validateForSubmit] revalidation
/// (D6) must catch it exactly as it would client-side, with the same
/// field-keyed errors, even though this row never touched a validator on
/// its way in.
Future<String> seedInvalidDraft(
  Db db, {
  String id = 'invalid-draft',
  String organizationId = 'org-1',
  String ownerId = 'user-1',
  String approverId = 'user-2',
}) async {
  await seedCampaign(
    db,
    id: id,
    name: 'Bypassed The Wizard',
    organizationId: organizationId,
    ownerId: ownerId,
    approverId: approverId,
    targetAudience: 10,
    territoryIds: const ['terr-1'],
  );
  await seedCampaignSession(
    db,
    id: '$id-session-0',
    campaignId: id,
    venue: 'Hall A',
    capacity: 50,
    startAt: DateTime.utc(2026, 9, 1, 9),
    endAt: DateTime.utc(2026, 9, 1, 12),
  );
  await seedCampaignSession(
    db,
    id: '$id-session-1',
    campaignId: id,
    venue: 'Hall A',
    capacity: 50,
    // Starts before the first session ends: an overlap validateForSubmit
    // must reject.
    startAt: DateTime.utc(2026, 9, 1, 11),
    endAt: DateTime.utc(2026, 9, 1, 14),
  );
  return id;
}

/// Inserts [count] campaigns (`seed-0` .. `seed-<count-1>`), all owned by
/// [ownerId] in [organizationId] — enough rows to exercise real paging
/// without every test hand-writing its own loop.
Future<void> seedCampaigns(
  Db db, {
  required int count,
  String organizationId = 'org-1',
  String ownerId = 'user-1',
  CampaignStatus status = CampaignStatus.draft,
}) async {
  for (var i = 0; i < count; i++) {
    await seedCampaign(
      db,
      id: 'seed-$i',
      name: 'Seed Campaign $i',
      organizationId: organizationId,
      ownerId: ownerId,
      status: status,
    );
  }
}

/// Inserts one carpenter. Defaults line up with [seedOrganizationWithUser]
/// (`org-1`/`terr-1`), so an uncustomised test's token can see the row.
Future<void> seedCarpenter(
  Db db, {
  required String id,
  String name = 'Md. Karim',
  String phone = '+8801700004821',
  String displayCode = 'CARP-00004821',
  String organizationId = 'org-1',
  String? territoryId = 'terr-1',
  String? nid,
  String? dealerContext,
  String source = 'SEED',
  String syncStatus = 'LOCAL_ONLY',
  bool eligible = true,
}) => db.execute(
  'INSERT INTO carpenters '
  '(id, organization_id, full_name, phone, nid, territory_id, '
  ' dealer_context, display_code, source, sync_status, eligible) '
  'VALUES (@id, @org, @name, @phone, @nid, @territory, @dealer, @code, '
  '        @source, @sync, @eligible)',
  params: {
    'id': id,
    'org': organizationId,
    'name': name,
    'phone': phone,
    'nid': nid,
    'territory': territoryId,
    'dealer': dealerContext,
    'code': displayCode,
    'source': source,
    'sync': syncStatus,
    'eligible': eligible,
  },
);

/// Inserts one registration row directly, bypassing the route.
Future<void> seedRegistration(
  Db db, {
  required String campaignId,
  required String carpenterId,
  String status = 'REGISTERED',
  String registeredBy = 'user-1',
}) => db.execute(
  'INSERT INTO registrations '
  '(campaign_id, carpenter_id, status, registered_by) '
  'VALUES (@campaign, @carpenter, @status, @by)',
  params: {
    'campaign': campaignId,
    'carpenter': carpenterId,
    'status': status,
    'by': registeredBy,
  },
);
