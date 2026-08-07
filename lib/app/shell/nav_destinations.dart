import 'package:flutter/material.dart';

import '../../core/auth/rbac.dart';
import '../../core/auth/session_manager.dart';

/// A top-level navigation target.
class NavDestinationSpec {
  const NavDestinationSpec({
    required this.path,
    required this.label,
    required this.icon,
    this.permission,
  });

  final String path;
  final String label;
  final IconData icon;

  /// Null means every signed-in user sees it.
  final Permission? permission;
}

/// Every possible destination. What a given user sees is the filtered subset -
/// see [visibleDestinations].
const List<NavDestinationSpec> allNavDestinations = [
  NavDestinationSpec(
    path: '/',
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
  ),
  NavDestinationSpec(
    path: '/campaigns',
    label: 'Campaigns',
    icon: Icons.campaign_outlined,
  ),
  NavDestinationSpec(
    path: '/verification',
    label: 'Verification',
    icon: Icons.how_to_reg_outlined,
    permission: Permission.verificationDecide,
  ),
  NavDestinationSpec(
    path: '/queue',
    label: 'Queue',
    icon: Icons.cloud_upload_outlined,
    permission: Permission.attendanceCapture,
  ),
  NavDestinationSpec(
    path: '/analytics',
    label: 'Analytics',
    icon: Icons.insights_outlined,
    permission: Permission.export,
  ),
];

/// The destinations this user may actually reach.
///
/// Filtering matters because the previous shell offered all four web surfaces
/// to everyone, and the route guard then bounced a field user out of every one
/// of them - the shell advertised what the guard forbade.
List<NavDestinationSpec> visibleDestinations(AuthState auth) => switch (auth) {
  AuthSignedIn(:final session) => [
    for (final d in allNavDestinations)
      if (d.permission == null || session.scope.can(d.permission!)) d,
  ],
  _ => const [],
};

/// Which destination owns [location].
///
/// Derived rather than passed: filtering shifts indices per user, so a
/// hardcoded index can highlight the wrong item or point past the end of the
/// list. Longest match wins so a nested section beats its parent, and `/` only
/// matches itself rather than prefixing everything.
int? selectedIndexFor(List<NavDestinationSpec> destinations, String location) {
  var bestIndex = -1;
  var bestLength = -1;
  for (var i = 0; i < destinations.length; i++) {
    final path = destinations[i].path;
    final matches = path == '/'
        ? location == '/'
        : location == path || location.startsWith('$path/');
    if (matches && path.length > bestLength) {
      bestIndex = i;
      bestLength = path.length;
    }
  }
  return bestIndex == -1 ? null : bestIndex;
}
