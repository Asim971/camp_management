import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/scope_claims.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> claims({
    List<String> roles = const ['campaign_creator'],
    List<String> permissions = const ['campaign_create'],
    String organizationId = 'ORG_1',
    List<String> territoryIds = const [],
    String userId = 'u-1',
    String displayName = 'Test User',
  }) => {
    'userId': userId,
    'displayName': displayName,
    'organizationId': organizationId,
    'roles': roles,
    'permissions': permissions,
    'territoryIds': territoryIds,
  };

  test('maps a well-formed claim set', () {
    final result = parseScopeClaims(
      claims(
        roles: ['crm_verifier', 'crm_supervisor'],
        permissions: ['verification_decide', 'sensitive_media_view'],
        territoryIds: ['T-1', 'T-2'],
      ),
    );

    final parsed = result.fold((c) => c, (_) => null)!;
    expect(parsed.userId, 'u-1');
    expect(parsed.displayName, 'Test User');
    expect(parsed.scope.roles, {AppRole.crmVerifier, AppRole.crmSupervisor});
    expect(parsed.scope.permissions, {
      Permission.verificationDecide,
      Permission.sensitiveMediaView,
    });
    expect(parsed.scope.organizationId, 'ORG_1');
    expect(parsed.scope.territoryIds, {'T-1', 'T-2'});
  });

  test('every AppRole has a wire mapping', () {
    // A role added to the enum without a wire string would silently become
    // unmappable, and every user holding it would fail to sign in.
    for (final role in AppRole.values) {
      expect(
        wireNameForRole(role),
        isNotEmpty,
        reason: 'AppRole.${role.name} has no wire name',
      );
    }
  });

  test('every Permission has a wire mapping', () {
    for (final p in Permission.values) {
      expect(
        wireNameForPermission(p),
        isNotEmpty,
        reason: 'Permission.${p.name} has no wire name',
      );
    }
  });

  group('unknown claims fail loudly', () {
    test('an unknown role is rejected, not dropped', () {
      // Dropping it would leave a user with a narrower scope than the server
      // granted, which presents as mysterious /forbidden redirects rather than
      // as the version mismatch it actually is.
      final result = parseScopeClaims(
        claims(roles: ['campaign_creator', 'galactic_overlord']),
      );

      expect(result.isOk, isFalse);
      final failure = result.fold((_) => null, (f) => f)!;
      expect(failure.kind, FailureKind.validation);
      expect(failure.message, contains('galactic_overlord'));
    });

    test('an unknown permission is rejected', () {
      final result = parseScopeClaims(
        claims(permissions: ['campaign_create', 'launch_missiles']),
      );

      expect(result.isOk, isFalse);
      expect(
        result.fold((_) => null, (f) => f.message),
        contains('launch_missiles'),
      );
    });

    test('all unknown names are reported together', () {
      // One sign-in attempt should reveal the whole mismatch, not the first
      // item of it.
      final result = parseScopeClaims(
        claims(roles: ['bad_role'], permissions: ['bad_perm']),
      );

      final message = result.fold((_) => null, (f) => f.message)!;
      expect(message, contains('bad_role'));
      expect(message, contains('bad_perm'));
    });

    test('an empty role set is rejected', () {
      // A user the server granted no role at all cannot use the app, and
      // silently admitting them produces an empty shell with no explanation.
      final result = parseScopeClaims(claims(roles: []));

      expect(result.isOk, isFalse);
    });

    test('a missing organizationId is rejected', () {
      // Scope narrows every query by org; an empty one would widen them.
      final result = parseScopeClaims(claims(organizationId: ''));

      expect(result.isOk, isFalse);
    });
  });

  group('I4: claim shape is a trust boundary too', () {
    test('a non-string entry inside roles is rejected, not silently '
        'filtered', () {
      // whereType<String>() used to drop this with no trace, leaving a user
      // with a narrower scope than the server granted.
      final result = parseScopeClaims({
        ...claims(),
        'roles': ['campaign_creator', 123],
      });

      expect(result.isOk, isFalse);
      final message = result.fold((_) => null, (f) => f.message)!;
      expect(message, contains('roles'));
    });

    test('permissions sent as a map (not a list) is rejected', () {
      final result = parseScopeClaims({
        ...claims(),
        'permissions': {'campaign_create': true},
      });

      expect(result.isOk, isFalse);
      final message = result.fold((_) => null, (f) => f.message)!;
      expect(message, contains('permissions'));
    });

    test('permissions absent entirely is rejected, not treated as empty', () {
      // Before this fix, _stringList's blanket `const []` fallback for ANY
      // non-List value - including a missing key - let this parse Ok with
      // permissions: {}, then bounce the user from every gated route with
      // no explanation of why.
      final withoutPermissions = claims()..remove('permissions');
      final result = parseScopeClaims(withoutPermissions);

      expect(result.isOk, isFalse);
      final message = result.fold((_) => null, (f) => f.message)!;
      expect(message, contains('permissions'));
    });

    test('permissions present but empty still succeeds', () {
      // An empty list is a legitimate answer (a role-only user); only a
      // missing or wrong-typed claim is a trust-boundary failure.
      final result = parseScopeClaims(claims(permissions: []));

      expect(result.isOk, isTrue);
      expect(result.fold((c) => c, (_) => null)!.scope.permissions, isEmpty);
    });
  });
}
