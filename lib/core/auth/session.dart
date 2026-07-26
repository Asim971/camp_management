import 'rbac.dart';

/// Authenticated session state. Tokens live in secure storage, never here in
/// plaintext beyond the in-memory access token used for the Authorization
/// header. Refresh is handled by the auth interceptor.
///
/// The unauthenticated state is represented as a `null` [Session] (see
/// `authControllerProvider` in di/providers.dart), not a sentinel object.
class Session {
  const Session({
    required this.userId,
    required this.displayName,
    required this.scope,
    required this.accessToken,
    required this.expiresAt,
  });

  final String userId;
  final String displayName;
  final AccessScope scope;
  final String accessToken;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
