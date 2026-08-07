import '../../core/auth/session_manager.dart';
import 'route_table.dart';

/// Pure guard logic (unit-testable, no Flutter imports). GoRouter's `redirect`
/// calls into these so role/scope is enforced BEFORE a route builds (§7).
class RouteGuards {
  const RouteGuards();

  static const String homePath = '/';
  static const String loginPath = '/login';
  static const String forbiddenPath = '/forbidden';

  /// Returns a redirect path, or null to allow.
  ///
  /// [fullPath] is the matched route TEMPLATE (`GoRouterState.fullPath`), not
  /// the concrete location: `/campaigns/:id/approve` cannot be compared to
  /// `/campaigns/CMP-1/approve` by equality, and matching on the template is
  /// what removes the need for prefix matching. [location] is carried only so
  /// an unauthenticated caller's intended destination can be preserved.
  String? evaluate({
    required AuthState auth,
    required String? fullPath,
    required String location,
    String? intended,
  }) {
    // Boot on a platform that persists tokens: the exchange is in flight and
    // we do not yet know whether there is a session. Redirecting now would
    // flash the login screen on every cold start.
    if (auth is AuthRestoring) return null;

    final access = accessFor(fullPath);

    if (access is Public) {
      // Already signed in and sitting on /login: go where they were headed.
      if (fullPath == loginPath && auth is AuthSignedIn) {
        return redirectTargetAfterSignIn(auth, intended);
      }
      return null;
    }

    if (auth is! AuthSignedIn) {
      if (fullPath == loginPath) return null;
      return loginPath;
    }

    // Undeclared route: fail CLOSED. Allowing it would undo the whole point of
    // the table, since an unregistered path would be reachable by anyone.
    if (access == null) return forbiddenPath;

    if (access is Requires && !auth.session.scope.can(access.permission)) {
      return forbiddenPath;
    }

    return null;
  }
}

/// Where to land after a successful sign-in.
///
/// The intended destination is re-checked rather than restored blindly:
/// sending a user who lacks the permission from login straight to /forbidden
/// reads as a broken sign-in rather than an answer about permissions. The value
/// is also validated against [routeTable] instead of being trusted as text,
/// because on web it is user-influenceable through the URL.
String? redirectTargetAfterSignIn(AuthState auth, String? intended) {
  if (auth is! AuthSignedIn || intended == null) return RouteGuards.homePath;

  final access = accessFor(intended);
  if (access == null) return RouteGuards.homePath;
  if (access is Requires && !auth.session.scope.can(access.permission)) {
    return RouteGuards.homePath;
  }
  return intended;
}
