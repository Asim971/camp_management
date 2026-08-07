import '../result/result.dart';
import 'rbac.dart';

/// The identity and scope carried by a token's claims.
class ScopeClaims {
  const ScopeClaims({
    required this.userId,
    required this.displayName,
    required this.scope,
  });

  final String userId;
  final String displayName;
  final AccessScope scope;
}

/// Wire vocabulary. Exhaustive switches (no `default`) so adding a value to
/// either enum is a compile error here rather than a silent unmappable role.
String wireNameForRole(AppRole role) => switch (role) {
  AppRole.campaignCreator => 'campaign_creator',
  AppRole.marketingApprover => 'marketing_approver',
  AppRole.crmVerifier => 'crm_verifier',
  AppRole.crmSupervisor => 'crm_supervisor',
  AppRole.fieldUser => 'field_user',
  AppRole.admin => 'admin',
  AppRole.reportingViewer => 'reporting_viewer',
};

String wireNameForPermission(Permission p) => switch (p) {
  Permission.campaignCreate => 'campaign_create',
  Permission.campaignApprove => 'campaign_approve',
  Permission.campaignCancel => 'campaign_cancel',
  Permission.bulkImport => 'bulk_import',
  Permission.attendanceCapture => 'attendance_capture',
  Permission.verificationDecide => 'verification_decide',
  Permission.verificationOverride => 'verification_override',
  Permission.sensitiveMediaView => 'sensitive_media_view',
  Permission.nidReveal => 'nid_reveal',
  Permission.configManage => 'config_manage',
  Permission.export => 'export',
};

final Map<String, AppRole> _rolesByWire = {
  for (final r in AppRole.values) wireNameForRole(r): r,
};
final Map<String, Permission> _permissionsByWire = {
  for (final p in Permission.values) wireNameForPermission(p): p,
};

/// Maps server claims to an [AccessScope].
///
/// This is a TRUST BOUNDARY. An unrecognised role or permission is rejected,
/// never dropped: a user with a silently narrowed scope is indistinguishable
/// from a legitimately restricted one, so the failure would surface as
/// mysterious `/forbidden` redirects instead of the client/server version
/// mismatch it actually is. All unknown names are reported together so one
/// sign-in reveals the whole mismatch.
Result<ScopeClaims> parseScopeClaims(Map<String, Object?> claims) {
  final unknown = <String>[];

  final roleNames = _stringListOrReport(claims, 'roles', unknown);
  final roles = <AppRole>{};
  for (final name in roleNames) {
    final role = _rolesByWire[name];
    if (role == null) {
      unknown.add('role "$name"');
    } else {
      roles.add(role);
    }
  }

  final permissionNames = _stringListOrReport(claims, 'permissions', unknown);
  final permissions = <Permission>{};
  for (final name in permissionNames) {
    final p = _permissionsByWire[name];
    if (p == null) {
      unknown.add('permission "$name"');
    } else {
      permissions.add(p);
    }
  }

  if (unknown.isNotEmpty) {
    return Err(
      Failure(
        FailureKind.validation,
        message:
            'This account has claims this app version does not recognise: '
            '${unknown.join(', ')}.',
      ),
    );
  }

  if (roles.isEmpty) {
    return const Err(
      Failure(
        FailureKind.validation,
        message: 'This account has no role assigned for this app.',
      ),
    );
  }

  final organizationId = claims['organizationId'];
  if (organizationId is! String || organizationId.isEmpty) {
    return const Err(
      Failure(
        FailureKind.validation,
        message: 'This account is not associated with an organization.',
      ),
    );
  }

  final userId = claims['userId'];
  if (userId is! String || userId.isEmpty) {
    return const Err(
      Failure(FailureKind.validation, message: 'This account has no user id.'),
    );
  }

  return Ok(
    ScopeClaims(
      userId: userId,
      displayName: claims['displayName'] is String
          ? claims['displayName']! as String
          : userId,
      scope: AccessScope(
        roles: roles,
        permissions: permissions,
        organizationId: organizationId,
        territoryIds: _stringList(claims['territoryIds']).toSet(),
      ),
    ),
  );
}

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const <String>[];

/// Reads [key] from [claims] as a list of strings, reporting any shape
/// problem into [unknown] instead of silently narrowing it.
///
/// This is the trust boundary [parseScopeClaims] exists to guard: a
/// non-`List` value (missing key, a map, a bare string, ...) or a
/// non-string entry inside an otherwise-valid list must both fail sign-in
/// loudly, not resolve to an empty, silently-narrowed scope. [_stringList]'s
/// `whereType<String>` would drop a non-string entry with no trace, and its
/// blanket `const []` fallback would turn a malformed or absent
/// `permissions` claim into a scope that parses `Ok` and then bounces the
/// user from every gated route with no explanation of why.
List<String> _stringListOrReport(
  Map<String, Object?> claims,
  String key,
  List<String> unknown,
) {
  final value = claims[key];
  if (value is! List) {
    unknown.add('$key (expected a list, got ${value.runtimeType})');
    return const <String>[];
  }
  final result = <String>[];
  for (final entry in value) {
    if (entry is String) {
      result.add(entry);
    } else {
      unknown.add('a non-string entry in $key: $entry');
    }
  }
  return result;
}
