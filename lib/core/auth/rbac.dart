/// Role-based access control (Guideline §12, PRD §11 RBAC). Client-side checks
/// drive UX (route guards, widget visibility, action enablement); the server
/// re-checks every call — client checks are convenience, not security.
enum AppRole {
  campaignCreator,
  marketingApprover,
  crmVerifier,
  crmSupervisor,
  fieldUser,
  admin,
  reportingViewer,
}

/// Fine-grained capabilities gated in the UI.
enum Permission {
  campaignCreate,
  campaignApprove,
  campaignCancel,
  bulkImport,
  attendanceCapture,
  verificationDecide,
  verificationOverride,
  sensitiveMediaView,
  nidReveal,
  configManage,
  export,
}

/// The signed-in user's scope: roles + the org/territory subtree they may act
/// within. Scope narrows every query and route.
class AccessScope {
  const AccessScope({
    required this.roles,
    required this.permissions,
    required this.organizationId,
    this.territoryIds = const {},
  });

  final Set<AppRole> roles;
  final Set<Permission> permissions;
  final String organizationId;
  final Set<String> territoryIds;

  bool can(Permission p) => permissions.contains(p);
  bool hasRole(AppRole r) => roles.contains(r);

  bool inTerritory(String territoryId) =>
      territoryIds.isEmpty || territoryIds.contains(territoryId);

  static const empty = AccessScope(
    roles: {},
    permissions: {},
    organizationId: '',
  );
}
