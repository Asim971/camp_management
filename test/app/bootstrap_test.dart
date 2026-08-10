import 'package:acsl_campaign/app/boot_diagnostics.dart';
import 'package:acsl_campaign/app/bootstrap.dart';
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/l10n/locale_controller.dart';
import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';
import '../support/harness.dart';

void main() {
  /// The one seam `buildTestContainer` does not already supply.
  ///
  /// The harness covers the database: `AppDatabase.open()` hands drift a
  /// `LazyDatabase` whose open future is created — and, on failure, REJECTED —
  /// inside its own constructor, with no caller awaiting it. There is no
  /// path_provider plugin here, so leaving the real provider in place makes a
  /// `MissingPluginException` escape as an unhandled async error and fail the
  /// test, even though every `await` in `bootstrap` is guarded. That is drift's
  /// plumbing, not a boot failure, so these tests use the harness's in-memory
  /// executor; the real `open()` path is covered by
  /// test/core/storage/database_seam_test.dart and
  /// test/app/di/composition_root_test.dart.
  ///
  /// Connectivity is stubbed for DETERMINISM, not necessity — and it is not in
  /// the harness because only the boot path touches it (`AuditFlusher.start()`).
  ///
  /// An earlier version of this comment claimed the stub was required, on the
  /// theory that `Connectivity().onConnectivityChanged` is an EventChannel with
  /// no plugin under `flutter_test`. That is wrong, and measurably so: building
  /// `connectivityStreamProvider` only calls `.map()` on the channel's stream,
  /// which cannot throw, and subscribing produces neither a recorded failure nor
  /// an unhandled async error — every test here passes with the override removed
  /// entirely. Keep the seam anyway (one line, and it keeps these tests off a
  /// real platform channel whose no-plugin behaviour is not ours to depend on),
  /// but do not treat it as the thing making a test meaningful.
  Override connectivitySeam() =>
      connectivityStreamProvider.overrideWithValue(const Stream<bool>.empty());

  test('a clean boot records nothing', () async {
    final container = buildTestContainer(overrides: [connectivitySeam()]);

    await bootstrap(container: container);

    expect(container.read(bootDiagnosticsProvider).isClean, isTrue);
  });

  test('a throwing database degrades the boot instead of killing it', () async {
    // This is the WEB case, exactly: AppDatabase.open() threw ArgumentError on
    // web, and main.dart resolved the database before runApp, so nothing
    // rendered. bootstrap() must reach the end regardless.
    // The harness's in-memory database default is deliberately overridden here,
    // which only works because caller overrides come last - see
    // test/support/harness_test.dart.
    final container = buildTestContainer(
      overrides: [
        appDatabaseProvider.overrideWith(
          (ref) => throw StateError('database unavailable'),
        ),
        connectivitySeam(),
      ],
    );

    await expectLater(bootstrap(container: container), completes);

    // ...and the degradation is VISIBLE. A bare catch would pass the line above
    // while hiding the failure, which is precisely today's audit behaviour.
    final diagnostics = container.read(bootDiagnosticsProvider);
    expect(diagnostics.isClean, isFalse);
    // Assert on the recorded ERROR, not only the step. `BootFailure` carries
    // both, so a step-only assertion says "something degraded auditFlusher.start"
    // when what this test exists to prove is "the DATABASE fault degraded it" -
    // any future error reaching the same step would satisfy the weaker form.
    expect(
      diagnostics.failures
          .singleWhere((f) => f.step == 'auditFlusher.start')
          .error,
      contains('database unavailable'),
    );
  });

  test(
    'a throwing token store leaves the user signed out, not stuck',
    () async {
      final container = buildTestContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(ThrowingTokenStore()),
          connectivitySeam(),
        ],
      );

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
    final container = buildTestContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(WriteThrowingTokenStore()),
        authServiceProvider.overrideWithValue(ScriptedAuthService()),
        connectivitySeam(),
      ],
    );

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
    final container = buildTestContainer(
      overrides: [
        localeStoreProvider.overrideWithValue(_ThrowingLocaleStore()),
        connectivitySeam(),
      ],
    );

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
