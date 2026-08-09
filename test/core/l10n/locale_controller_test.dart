import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/l10n/locale_controller.dart';
import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

/// In-memory [LocaleStore] so the controller is tested without a database.
class _FakeLocaleStore implements LocaleStore {
  _FakeLocaleStore([this.value]);
  Locale? value;
  int writes = 0;
  int clears = 0;

  @override
  Future<Locale?> read() async => value;

  @override
  Future<void> write(Locale locale) async {
    writes++;
    value = locale;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

void main() {
  // Typed on the interface, not on _FakeLocaleStore: _ThrowingLocaleStore is a
  // LocaleStore but not a _FakeLocaleStore, and the plan's signature would not
  // compile for the read-failure test.
  //
  // The config is always passed explicitly through the harness's `config:`,
  // never left to the real fromEnvironment(): load() now reads
  // AppConfig.locale, and the real config would let a
  // `flutter test --dart-define=LOCALE=bn` invocation change what these tests
  // assert. `defineLocale` defaults to '' — what an absent LOCALE produces.
  ProviderContainer containerWith(
    LocaleStore store, {
    String defineLocale = '',
  }) => buildTestContainer(
    config: AppConfig(
      flavor: Flavor.dev,
      apiBaseUrl: 'https://example.invalid',
      mediaHost: 'https://example.invalid',
      locale: defineLocale,
    ),
    overrides: [localeStoreProvider.overrideWithValue(store)],
  );

  test('starts null, meaning follow the system', () {
    final c = containerWith(_FakeLocaleStore());

    expect(c.read(localeControllerProvider), isNull);
  });

  test('load adopts a persisted preference', () async {
    final c = containerWith(_FakeLocaleStore(const Locale('bn')));

    await c.read(localeControllerProvider.notifier).load();

    expect(c.read(localeControllerProvider), const Locale('bn'));
  });

  test('load leaves null when nothing is persisted', () async {
    final c = containerWith(_FakeLocaleStore());

    await c.read(localeControllerProvider.notifier).load();

    expect(c.read(localeControllerProvider), isNull);
  });

  // The three precedence edges of stored choice -> LOCALE define -> system,
  // pinned one at a time. Every Maestro flow passes LOCALE and the app ignored
  // it until P0.5.
  test('load honours the LOCALE define when nothing is persisted', () async {
    final c = containerWith(_FakeLocaleStore(), defineLocale: 'bn');

    await c.read(localeControllerProvider.notifier).load();

    expect(c.read(localeControllerProvider), const Locale('bn'));
  });

  test('a persisted choice beats the LOCALE define', () async {
    // The rule most easily written backwards. Both values are supported
    // languages and they differ, so whichever source wins is unambiguous —
    // a test using an unsupported define would pass under either ordering.
    final c = containerWith(
      _FakeLocaleStore(const Locale('en')),
      defineLocale: 'bn',
    );

    await c.read(localeControllerProvider.notifier).load();

    expect(c.read(localeControllerProvider), const Locale('en'));
  });

  test('an absent or unsupported LOCALE define follows the system', () async {
    // Protects every ordinary production build, where no LOCALE is passed at
    // all: '' must not become Locale('').
    final absent = containerWith(_FakeLocaleStore());
    final unsupported = containerWith(_FakeLocaleStore(), defineLocale: 'fr');

    await absent.read(localeControllerProvider.notifier).load();
    await unsupported.read(localeControllerProvider.notifier).load();

    expect(absent.read(localeControllerProvider), isNull);
    expect(unsupported.read(localeControllerProvider), isNull);
  });

  test('select persists and applies', () async {
    final store = _FakeLocaleStore();
    final c = containerWith(store);

    await c.read(localeControllerProvider.notifier).select(const Locale('bn'));

    expect(c.read(localeControllerProvider), const Locale('bn'));
    expect(store.value, const Locale('bn'));
    expect(store.writes, 1);
  });

  test('selecting null clears the preference and returns to system', () async {
    final store = _FakeLocaleStore(const Locale('bn'));
    final c = containerWith(store);
    await c.read(localeControllerProvider.notifier).load();

    await c.read(localeControllerProvider.notifier).select(null);

    expect(c.read(localeControllerProvider), isNull);
    expect(store.value, isNull);
    expect(store.clears, 1);
  });

  test(
    'a store read failure leaves the system locale rather than throwing',
    () async {
      // Spec D7: locale faults degrade and continue.
      final c = containerWith(_ThrowingLocaleStore());

      await expectLater(
        c.read(localeControllerProvider.notifier).load(),
        completes,
      );
      expect(c.read(localeControllerProvider), isNull);
    },
  );

  test('a store read failure still lands the LOCALE define', () async {
    // load()'s catch falls through to the define rather than returning, so a
    // storage fault on a LOCALE-provisioned device degrades to the build's
    // intended language, not to the system's. Pins the comment in load().
    final c = containerWith(_ThrowingLocaleStore(), defineLocale: 'bn');

    await expectLater(
      c.read(localeControllerProvider.notifier).load(),
      completes,
    );
    expect(c.read(localeControllerProvider), const Locale('bn'));
  });
}

class _ThrowingLocaleStore implements LocaleStore {
  @override
  Future<Locale?> read() async => throw StateError('storage unavailable');

  @override
  Future<void> write(Locale locale) async {}

  @override
  Future<void> clear() async {}
}
