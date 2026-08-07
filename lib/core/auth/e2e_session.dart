import '../result/result.dart';
import 'auth_service.dart';
import 'rbac.dart';
import 'scope_claims.dart';

/// [AuthService] that mints a valid token pair for a named role, for E2E runs
/// and the dev launcher. Test-only: reachable only when `AppConfig.e2e` is true
/// (see TESTING_MAESTRO.md §3.2).
///
/// Deliberately an AuthService rather than a pre-built Session: E2E then drives
/// the same SessionManager path production does, instead of skipping it.
class FakeAuthService implements AuthService {
  FakeAuthService(this.role);

  final String role;

  @override
  Future<Result<AuthTokens>> login(String username, String password) async =>
      Ok(_tokens());

  @override
  Future<Result<AuthTokens>> refresh(String refreshToken) async =>
      Ok(_tokens());

  @override
  Future<Result<void>> logout(String refreshToken) async => const Ok(null);

  AuthTokens _tokens() {
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

    return AuthTokens(
      accessToken: 'e2e-token',
      refreshToken: 'e2e-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 12)),
      claims: {
        'userId': 'e2e-$role',
        'displayName': 'E2E $role',
        'organizationId': 'ORG_E2E',
        'roles': [wireNameForRole(appRole)],
        'permissions': [for (final p in permissions) wireNameForPermission(p)],
        'territoryIds': <String>[],
      },
    );
  }
}
