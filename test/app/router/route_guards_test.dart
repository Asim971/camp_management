import 'package:acsl_campaign/app/router/route_guards.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const guards = RouteGuards();

  AuthState signedIn({Set<Permission> permissions = const {}}) => AuthSignedIn(
    Session(
      userId: 'u-1',
      displayName: 'Test User',
      scope: AccessScope(
        roles: const {AppRole.campaignCreator},
        permissions: permissions,
        organizationId: 'ORG_1',
      ),
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  group('unauthenticated', () {
    test('a protected route redirects to /login, carrying it as ?from=', () {
      // Without this, an unauthenticated deep link into a permitted route
      // always lands home after sign-in instead of where it was headed -
      // [location] arrived at evaluate() and went nowhere.
      expect(
        guards.evaluate(
          auth: const AuthSignedOut(),
          fullPath: '/campaigns',
          location: '/campaigns',
        ),
        '/login?from=%2Fcampaigns',
      );
    });

    test('the intended location is percent-encoded onto ?from=', () {
      expect(
        guards.evaluate(
          auth: const AuthSignedOut(),
          fullPath: '/campaigns/:id',
          location: '/campaigns/CMP-1',
        ),
        '/login?from=%2Fcampaigns%2FCMP-1',
      );
    });

    test('/login itself is allowed', () {
      expect(
        guards.evaluate(
          auth: const AuthSignedOut(),
          fullPath: '/login',
          location: '/login',
        ),
        isNull,
      );
    });
  });

  group('AuthRestoring', () {
    test('does NOT redirect', () {
      // Redirecting here is what would flash the login screen on every mobile
      // cold start and then bounce away from it.
      expect(
        guards.evaluate(
          auth: const AuthRestoring(),
          fullPath: '/campaigns',
          location: '/campaigns',
        ),
        isNull,
      );
    });
  });

  group('authenticated', () {
    test('an Authenticated route is allowed with no permissions', () {
      expect(
        guards.evaluate(
          auth: signedIn(),
          fullPath: '/campaigns',
          location: '/campaigns',
        ),
        isNull,
      );
    });

    test('signed-in user on /login goes home', () {
      expect(
        guards.evaluate(
          auth: signedIn(),
          fullPath: '/login',
          location: '/login',
        ),
        RouteGuards.homePath,
      );
    });

    test('a held permission allows the route', () {
      expect(
        guards.evaluate(
          auth: signedIn(permissions: {Permission.campaignCreate}),
          fullPath: '/campaigns/new',
          location: '/campaigns/new',
        ),
        isNull,
      );
    });

    test('a missing permission redirects to /forbidden', () {
      expect(
        guards.evaluate(
          auth: signedIn(),
          fullPath: '/campaigns/new',
          location: '/campaigns/new',
        ),
        '/forbidden',
      );
    });
  });

  group('parameterised routes resolve by template, not by location', () {
    test('two different ids both resolve to the same requirement', () {
      // Keying on the concrete location is why the old guard needed prefix
      // matching. Keying on the template makes matching exact.
      for (final id in ['CMP-1', 'CMP-2']) {
        expect(
          guards.evaluate(
            auth: signedIn(),
            fullPath: '/campaigns/:id/approve',
            location: '/campaigns/$id/approve',
          ),
          '/forbidden',
        );
        expect(
          guards.evaluate(
            auth: signedIn(permissions: {Permission.campaignApprove}),
            fullPath: '/campaigns/:id/approve',
            location: '/campaigns/$id/approve',
          ),
          isNull,
        );
      }
    });
  });

  group('unknown routes fail closed', () {
    test('a path absent from the table is forbidden, not allowed', () {
      // Failing open here would undo the whole exhaustiveness guarantee: an
      // unregistered path would be reachable by anyone signed in.
      expect(
        guards.evaluate(
          auth: signedIn(),
          fullPath: '/secret-admin',
          location: '/secret-admin',
        ),
        '/forbidden',
      );
    });
  });

  group('deep-link restoration', () {
    test('returns the intended destination when it is permitted', () {
      expect(
        redirectTargetAfterSignIn(
          signedIn(permissions: {Permission.verificationDecide}),
          '/verification',
        ),
        '/verification',
      );
    });

    test('falls back home when the intended destination is NOT permitted', () {
      // Restoring blindly would send the user from login straight to
      // /forbidden, which reads as a broken sign-in rather than an answer
      // about permissions.
      expect(
        redirectTargetAfterSignIn(signedIn(), '/verification'),
        RouteGuards.homePath,
      );
    });

    test('rejects an intended path that is not in the table', () {
      // On web this value is user-influenceable via the URL, so only paths
      // this app actually declares may be honoured.
      expect(
        redirectTargetAfterSignIn(signedIn(), 'https://evil.test/phish'),
        RouteGuards.homePath,
      );
      expect(
        redirectTargetAfterSignIn(signedIn(), '/not-a-route'),
        RouteGuards.homePath,
      );
    });

    test('falls back home when there is no intended destination', () {
      expect(redirectTargetAfterSignIn(signedIn(), null), RouteGuards.homePath);
    });
  });
}
