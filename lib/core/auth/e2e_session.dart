import 'rbac.dart';
import 'session.dart';

/// Builds a fake authenticated [Session] for E2E runs, bypassing the (still
/// unimplemented) auth service. Test-only: reachable only when
/// `AppConfig.e2e` is true. See TESTING_MAESTRO.md §3.2.
Session buildE2ESession(String role) {
  final appRole = switch (role) {
    'crm_verifier' => AppRole.crmVerifier,
    'campaign_creator' => AppRole.campaignCreator,
    'admin' => AppRole.admin,
    _ => AppRole.fieldUser,
  };

  final permissions = switch (appRole) {
    AppRole.fieldUser => {Permission.attendanceCapture},
    AppRole.crmVerifier => {
      Permission.verificationDecide,
      Permission.sensitiveMediaView,
    },
    AppRole.campaignCreator => {
      Permission.campaignCreate,
      Permission.bulkImport,
      Permission.export,
    },
    AppRole.admin => Permission.values.toSet(),
    _ => <Permission>{},
  };

  return Session(
    userId: 'e2e-$role',
    displayName: 'E2E $role',
    scope: AccessScope(
      roles: {appRole},
      permissions: permissions,
      organizationId: 'ORG_E2E',
    ),
    accessToken: 'e2e-token',
    refreshToken: 'e2e-refresh',
    expiresAt: DateTime(2999),
  );
}
