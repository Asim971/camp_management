import '../../core/auth/rbac.dart';
import '../../core/auth/session.dart';

/// Pure guard logic (unit-testable, no Flutter imports). GoRouter's `redirect`
/// calls into these so role/scope is enforced BEFORE a route builds (§7).
class RouteGuards {
  const RouteGuards();

  /// Returns a redirect path, or null to allow. [required] is the permission
  /// the destination demands (null == any authenticated user).
  String? evaluate({
    required Session? session,
    required String location,
    Permission? required,
  }) {
    final isAuthed = session != null && !session.isExpired;

    if (!isAuthed) {
      return location == '/login' ? null : '/login';
    }
    if (location == '/login') return '/'; // already signed in

    if (required != null && !session.scope.can(required)) {
      return '/forbidden';
    }
    return null;
  }
}
