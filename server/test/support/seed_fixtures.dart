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
  int targetAudience = 0,
  List<String> territoryIds = const [],
  DateTime? startAt,
  DateTime? endAt,
}) async {
  await db.execute(
    'INSERT INTO campaigns '
    '(id, organization_id, name, type, objective, status, owner_id, '
    ' venue, target_audience, start_at, end_at) '
    'VALUES (@id, @org, @name, @type, @objective, @status, @owner, '
    ' @venue, @target, @startAt, @endAt)',
    params: {
      'id': id,
      'org': organizationId,
      'name': name,
      'type': type,
      'objective': objective,
      'status': status.wireValue,
      'owner': ownerId,
      'venue': venue,
      'target': targetAudience,
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
