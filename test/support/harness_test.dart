import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('a caller override wins over the harness default', () {
    // If defaults won, a test could silently exercise the wrong dependency -
    // the harness would be actively harmful rather than merely convenient.
    final mine = AppDatabase(NativeDatabase.memory());
    addTearDown(mine.close);

    final c = buildTestContainer(
      overrides: [appDatabaseProvider.overrideWithValue(mine)],
    );

    expect(c.read(appDatabaseProvider), same(mine));
  });

  test('a caller override wins for authStateProvider too', () {
    // The specific seam this harness exists to consolidate, and the one where a
    // losing override would be hardest to notice: `permissions:` and an
    // explicit override both target authStateProvider, so if the default came
    // last a test asking for signed-OUT would silently run signed-IN and its
    // permission assertions would pass for the wrong reason.
    final c = buildTestContainer(
      permissions: {Permission.campaignCreate},
      overrides: [authStateProvider.overrideWithValue(const AuthSignedOut())],
    );

    expect(c.read(authStateProvider), isA<AuthSignedOut>());
  });

  test('permissions: yields a signed-in session holding exactly those', () {
    final c = buildTestContainer(permissions: {Permission.campaignCreate});

    final auth = c.read(authStateProvider) as AuthSignedIn;
    expect(auth.session.scope.can(Permission.campaignCreate), isTrue);
    expect(auth.session.scope.can(Permission.campaignApprove), isFalse);
  });

  test('omitting permissions: leaves the real auth chain in place', () {
    // Not the same as passing an empty set: an empty set is a signed-IN user
    // with no permissions, while omitting it means authStateProvider is not
    // overridden at all, so a test can drive the real SessionManager.
    final c = buildTestContainer();

    expect(c.read(authStateProvider), isA<AuthSignedOut>());
  });

  test('config: replaces the default AppConfig wholesale', () {
    final c = buildTestContainer(
      config: const AppConfig(
        flavor: Flavor.prod,
        apiBaseUrl: 'https://prod.invalid',
        mediaHost: 'https://prod.invalid',
      ),
    );

    expect(c.read(appConfigProvider).flavor, Flavor.prod);
  });
}
