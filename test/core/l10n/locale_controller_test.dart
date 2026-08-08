import 'package:acsl_campaign/core/l10n/locale_controller.dart';
import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  ProviderContainer containerWith(LocaleStore store) {
    final c = ProviderContainer(
      overrides: [localeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    return c;
  }

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
}

class _ThrowingLocaleStore implements LocaleStore {
  @override
  Future<Locale?> read() async => throw StateError('storage unavailable');

  @override
  Future<void> write(Locale locale) async {}

  @override
  Future<void> clear() async {}
}
