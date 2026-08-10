/// The caller's identity and scope for one request.
class AuthContext {
  const AuthContext({
    required this.userId,
    required this.organizationId,
    required this.roles,
    required this.permissions,
    required this.territoryIds,
  });

  final String userId;
  final String organizationId;
  final Set<String> roles;
  final Set<String> permissions;
  final Set<String> territoryIds;

  bool can(String permission) => permissions.contains(permission);
}
