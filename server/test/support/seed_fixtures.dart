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
