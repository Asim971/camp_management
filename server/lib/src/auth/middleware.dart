import 'package:shelf/shelf.dart';

import '../db/pool.dart';
import 'auth_context.dart';
import 'tokens.dart';

const String _contextKey = 'auth';

/// Resolves a Bearer token to an [AuthContext], or answers 401.
///
/// The user's row is re-read on every request, so deactivation takes effect
/// immediately instead of waiting out the access token's 15 minutes. That costs
/// one indexed query per request and removes a whole class of "revoked user is
/// still working" incident.
Middleware authenticate({required Db db, required TokenService tokens}) {
  return (Handler inner) {
    return (Request request) async {
      final header = request.headers['authorization'] ?? '';
      if (!header.startsWith('Bearer ')) return _unauthorized();

      final userId = tokens.userIdFromAccessToken(header.substring(7));
      if (userId == null) return _unauthorized();

      final res = await db.execute(
        'SELECT u.id, u.organization_id, '
        '  COALESCE(array_agg(DISTINCT r.role) '
        '    FILTER (WHERE r.role IS NOT NULL), ARRAY[]::text[]) AS roles, '
        '  COALESCE(array_agg(DISTINCT t.territory_id) '
        '    FILTER (WHERE t.territory_id IS NOT NULL), ARRAY[]::text[]) '
        '    AS territory_ids '
        'FROM staff_users u '
        'LEFT JOIN staff_user_roles r ON r.user_id = u.id '
        'LEFT JOIN staff_user_territories t ON t.user_id = u.id '
        'WHERE u.id = @id AND u.is_active '
        'GROUP BY u.id, u.organization_id',
        params: {'id': userId},
      );
      if (res.isEmpty) return _unauthorized();

      final r = row(res.single);
      final roles = (r['roles']! as List).cast<String>().toSet();
      final context = AuthContext(
        userId: r['id']! as String,
        organizationId: r['organization_id']! as String,
        roles: roles,
        permissions: {for (final role in roles) ...?permissionsByRole[role]},
        territoryIds: (r['territory_ids']! as List).cast<String>().toSet(),
      );

      return inner(request.change(context: {_contextKey: context}));
    };
  };
}

/// The [AuthContext] for [request].
///
/// Throws if [authenticate] did not run. Returning an anonymous context would
/// let a protected handler execute unauthenticated and pass its tests.
AuthContext authOf(Request request) {
  final value = request.context[_contextKey];
  if (value is! AuthContext) {
    throw StateError(
      'authOf() called on a request that did not pass through authenticate(). '
      'Wire the route behind the authenticate middleware.',
    );
  }
  return value;
}

Middleware requirePermission(String permission) {
  return (Handler inner) {
    return (Request request) async {
      if (!authOf(request).can(permission)) {
        return Response.forbidden(null);
      }
      return inner(request);
    };
  };
}

Response _unauthorized() => Response.unauthorized(null);
