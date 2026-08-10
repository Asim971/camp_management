import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth.dart';

/// One container builder for the whole suite, so a test writes only the
/// overrides it is actually ABOUT.
///
/// Before this existed, `authStateProvider` was overridden 13 times across 9
/// files through two different mechanisms (`overrideWith` and
/// `overrideWithValue`), and 15 files hand-rolled their own `ProviderContainer`
/// — 13 of which now come from here, the other 2 deliberately left alone
/// (`test/app/di/composition_root_test.dart` and
/// `test/core/storage/database_seam_test.dart`, both of which exist precisely to
/// exercise the un-overridden wiring this harness replaces). Every one of them
/// re-declared its own `AppConfig` and its own signed-in [Session] — which is
/// how test suites drift apart.
///
/// The database is deliberately in-memory here: feature tests should not pay
/// for real file I/O, and [appDatabaseProvider]'s real `AppDatabase.open()`
/// needs path_provider, which has no plugin under `flutter_test`. Only
/// `test/app/di/composition_root_test.dart` uses the real one — it overrides
/// nothing but `appConfigProvider` and the two directory seams, on purpose, so
/// that one test proves `open()` runs and the whole migration chain reaches the
/// current schema version. The harness trades exactly that guarantee for speed,
/// which is why BOTH exist. Do not "unify" them: routing the composition-root
/// test through this harness would delete the only proof that the composition
/// root works, and giving feature tests a real database would make every one of
/// them slower for a guarantee they already have.
///
/// Caller [overrides] are spliced in LAST so they win over every default —
/// pinned by `test/support/harness_test.dart`, because a harness whose defaults
/// silently beat a test's own override would be actively harmful rather than
/// merely convenient.
ProviderContainer buildTestContainer({
  Set<Permission>? permissions,
  AppConfig? config,
  List<Override> overrides = const [],
}) {
  // Built on first read rather than eagerly: most tests never touch the
  // database, and a test that overrides `appDatabaseProvider` itself would
  // otherwise make drift log its "created AppDatabase multiple times" warning
  // for a second instance nothing ever opens.
  AppDatabase? db;

  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        config ??
            const AppConfig(
              flavor: Flavor.dev,
              apiBaseUrl: 'https://example.invalid',
              mediaHost: 'https://example.invalid',
            ),
      ),
      appDatabaseProvider.overrideWith(
        (ref) => db ??= AppDatabase(NativeDatabase.memory()),
      ),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      if (permissions != null)
        authStateProvider.overrideWithValue(signedInWith(permissions)),
      // Caller overrides come LAST so they win over every default above.
      ...overrides,
    ],
  );

  // Order is deliberate and must not be "tidied": `addTearDown` runs LIFO, so
  // registering the close FIRST makes it run LAST — dispose the providers, then
  // close the database they hold. The other way round closes the executor while
  // providers that own it are still alive, so any dispose that actually awaits
  // the database would run against a closed connection. Harmless today (the
  // database is in-memory and `auditFlusherProvider`'s dispose is unawaited),
  // which is exactly why the next awaited dispose would find it the hard way.
  addTearDown(() async => db?.close());
  addTearDown(container.dispose);
  return container;
}

/// A signed-in [AuthState] holding exactly [permissions].
///
/// Exposed as well as used by [buildTestContainer] because a few tests need the
/// state itself — e.g. to pass it into a `ProviderScope` that is not built from
/// a container, or to compare two different scopes in one test.
AuthState signedInWith(Set<Permission> permissions) => AuthSignedIn(
  Session(
    userId: 'u-1',
    displayName: 'Rina Akter',
    scope: AccessScope(
      roles: const {AppRole.fieldUser},
      permissions: permissions,
      organizationId: 'ORG_1',
    ),
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  ),
);
