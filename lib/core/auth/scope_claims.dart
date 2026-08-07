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

  final roleNames = _stringList(claims['roles']);
  final roles = <AppRole>{};
  for (final name in roleNames) {
    final role = _rolesByWire[name];
    if (role == null) {
      unknown.add('role "$name"');
    } else {
      roles.add(role);
    }
  }

  final permissionNames = _stringList(claims['permissions']);
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
