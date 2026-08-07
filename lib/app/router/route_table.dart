import '../../core/auth/rbac.dart';

/// What a route demands of the caller.
sealed class Access {
  const Access();
}

/// Reachable without a session (`/login`, `/forbidden`).
final class Public extends Access {
  const Public();
}

/// Any signed-in user.
final class Authenticated extends Access {
  const Authenticated();
}

/// A signed-in user holding [permission].
final class Requires extends Access {
  const Requires(this.permission);
  final Permission permission;
}

class RouteEntry {
  const RouteEntry(this.path, this.access);

  /// The route TEMPLATE as registered with GoRouter (e.g.
  /// `/campaigns/:id/approve`), matched against `GoRouterState.fullPath`.
  final String path;
  final Access access;
}

/// Paths registered only when `AppConfig.devRoutesEnabled`. They still carry an
/// [Access] so the exhaustiveness test can account for them in both builds.
const Set<String> devOnlyPaths = {'/dev', '/gallery'};

/// THE single source of truth for route access.
///
/// Both the router and [RouteGuards] read this list, so a route cannot exist
/// without an access decision - `route_table_test` asserts the registered set
/// and this table are identical. The previous design kept a separate
/// prefix-matching function, so a new route matched no prefix and shipped
/// ungated with nothing to notice.
const List<RouteEntry> routeTable = [
  RouteEntry('/login', Public()),
  RouteEntry('/forbidden', Public()),

  RouteEntry('/dev', Authenticated()),
  RouteEntry('/gallery', Authenticated()),

  RouteEntry('/', Authenticated()),

  RouteEntry('/campaigns', Authenticated()),
  RouteEntry('/campaigns/new', Requires(Permission.campaignCreate)),
  RouteEntry('/campaigns/:id', Authenticated()),
  RouteEntry('/campaigns/:id/approve', Requires(Permission.campaignApprove)),
  RouteEntry('/campaigns/:id/register', Requires(Permission.campaignCreate)),
  RouteEntry('/campaigns/:id/import', Requires(Permission.bulkImport)),

  RouteEntry('/verification', Requires(Permission.verificationDecide)),
  RouteEntry(
    '/verification/cases/:id',
    Requires(Permission.verificationDecide),
  ),

  RouteEntry('/search/:sessionId', Requires(Permission.attendanceCapture)),
  RouteEntry(
    '/capture/:sessionId/:carpenterId',
    Requires(Permission.attendanceCapture),
  ),
  RouteEntry('/queue', Requires(Permission.attendanceCapture)),

  RouteEntry('/analytics', Requires(Permission.export)),
];

final Map<String, Access> _byPath = {
  for (final e in routeTable) e.path: e.access,
};

/// Resolves the access rule for a route template. Null means the path is not
/// declared, which the guard treats as forbidden rather than allowed.
Access? accessFor(String? fullPath) =>
    fullPath == null ? null : _byPath[fullPath];
