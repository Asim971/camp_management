import 'rbac.dart';

/// Authenticated session state.
///
/// Both tokens are held in memory here. The REFRESH token is additionally
/// persisted on mobile (see `TokenStore`); on web nothing is persisted, so a
/// reload signs the user out. The ACCESS token is never persisted anywhere -
/// it is short-lived and re-derivable from refresh.
///
/// Signed-out is represented by `AuthSignedOut`, not by a null Session (see
/// `AuthState` in session_manager.dart).
class Session {
  const Session({
    required this.userId,
    required this.displayName,
    required this.scope,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String userId;
  final String displayName;
  final AccessScope scope;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
