import 'package:acsl_campaign/app/boot_diagnostics.dart';
import 'package:acsl_campaign/app/bootstrap.dart';
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/l10n/locale_controller.dart';
import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';

void main() {
  const config = AppConfig(
    flavor: Flavor.dev,
    apiBaseUrl: 'https://example.invalid',
    mediaHost: 'https://example.invalid',
  );

  /// The two seams every boot step that touches storage needs under
  /// `flutter_test`.
  ///
  /// `AppDatabase.open()` hands drift a `LazyDatabase` whose open future is
  /// created — and, on failure, REJECTED — inside its own constructor, with no
  /// caller awaiting it. There is no path_provider plugin here, so leaving the
  /// real provider in place makes a `MissingPluginException` escape as an
  /// unhandled async error and fail the test, even though every `await` in
  /// `bootstrap` is guarded. That is drift's plumbing, not a boot failure, so
  /// these tests use the in-memory executor the rest of the suite uses; the
  /// real `open()` path is covered by test/core/storage/database_seam_test.dart.
  ///
  /// Connectivity is stubbed for the same reason: `AuditFlusher.start()`
  /// subscribes to it, and `Connectivity().onConnectivityChanged` is an
  /// EventChannel with no plugin under `flutter_test`.
  List<Override> storageSeams() {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return [
      appDatabaseProvider.overrideWithValue(db),
      connectivityStreamProvider.overrideWithValue(const Stream<bool>.empty()),
    ];
  }

  test('a clean boot records nothing', () async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        ...storageSeams(),
      ],
    );
    addTearDown(container.dispose);

    await bootstrap(container: container);

    expect(container.read(bootDiagnosticsProvider).isClean, isTrue);
  });

  test('a throwing database degrades the boot instead of killing it', () async {
    // This is the WEB case, exactly: AppDatabase.open() threw ArgumentError on
    // web, and main.dart resolved the database before runApp, so nothing
    // rendered. bootstrap() must reach the end regardless.
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        appDatabaseProvider.overrideWith(
          (ref) => throw StateError('database unavailable'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(bootstrap(container: container), completes);

    // ...and the degradation is VISIBLE. A bare catch would pass the line above
    // while hiding the failure, which is precisely today's audit behaviour.
    final diagnostics = container.read(bootDiagnosticsProvider);
    expect(diagnostics.isClean, isFalse);
    expect(
      diagnostics.failures.map((f) => f.step),
      contains('auditFlusher.start'),
    );
  });

  test(
    'a throwing token store leaves the user signed out, not stuck',
    () async {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          tokenStoreProvider.overrideWithValue(ThrowingTokenStore()),
          ...storageSeams(),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(bootstrap(container: container), completes);

      expect(container.read(authStateProvider), isA<AuthSignedOut>());
      expect(
        container.read(bootDiagnosticsProvider).failures.map((f) => f.step),
        contains('sessionManager.restore'),
      );
    },
  );

  test('a store that reads but cannot write also lands signed out', () async {
    // The other half of the failing-store space, and the one that needs
    // restore()'s repair catch: the read succeeds, so restore() emits
    // AuthRestoring and only then fails inside _adopt's persist. step() can
    // record that but cannot undo the emitted state, so without the repair the
    // app boots into a permanent splash - recorded, still unusable.
    //
    // authServiceProvider is overridden so the refresh leg succeeds and the
    // failure is unambiguously the persist; the real DioAuthService would fail
    // first, against the network, and prove nothing about the write path.
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        tokenStoreProvider.overrideWithValue(WriteThrowingTokenStore()),
        authServiceProvider.overrideWithValue(ScriptedAuthService()),
        ...storageSeams(),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(bootstrap(container: container), completes);

    expect(container.read(authStateProvider), isA<AuthSignedOut>());
    // And still recorded: the repair must not have swallowed the error on its
    // way out, or we have traded a splash for a silent degradation.
    expect(
      container.read(bootDiagnosticsProvider).failures.map((f) => f.step),
      contains('sessionManager.restore'),
    );
  });

  test('a locale store failure is recorded, not silently dropped', () async {
    // LocaleController.load catches its own store fault and continues, so
    // step()'s catch can never fire for it. Before load() gained onDegraded,
    // the user's persisted Bengali choice was dropped with NOTHING in
    // `failures` - the guarded-but-silent shape this task exists to remove.
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        localeStoreProvider.overrideWithValue(_ThrowingLocaleStore()),
        ...storageSeams(),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(bootstrap(container: container), completes);

    expect(
      container.read(bootDiagnosticsProvider).failures.map((f) => f.step),
      contains('localeController.load'),
    );
    // Degraded, not aborted (spec D7): the locale falls back rather than
    // blocking startup, and every later step still ran.
    expect(container.read(localeControllerProvider), isNull);
    expect(container.read(authStateProvider), isA<AuthSignedOut>());
  });
}

class _ThrowingLocaleStore implements LocaleStore {
  @override
  Future<Locale?> read() async => throw StateError('locale store unavailable');

  @override
  Future<void> write(Locale locale) async {}

  @override
  Future<void> clear() async {}
}
