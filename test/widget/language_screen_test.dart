import 'package:acsl_campaign/core/l10n/locale_controller.dart';
import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:acsl_campaign/features/settings/presentation/language_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// In-memory [LocaleStore] so the picker is driven by the REAL
/// [LocaleController] (the thing under test is the wiring between the tiles and
/// `select()`), with only persistence faked.
class _FakeLocaleStore implements LocaleStore {
  Locale? value;

  @override
  Future<Locale?> read() async => value;

  @override
  Future<void> write(Locale locale) async => value = locale;

  @override
  Future<void> clear() async => value = null;
}

/// Finds the [Semantics] node carrying a stable test id — the same
/// `Semantics(identifier: …)` convention Maestro flows key off (TESTING_MAESTRO
/// §3.1). Task 12's Bengali flow taps these exact ids, so the tests drive them
/// the same way rather than only through Flutter [Key]s, which Maestro cannot
/// see.
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

void main() {
  /// The picker under a MaterialApp that watches the controller, so a selection
  /// is observably applied to the tree (not merely recorded in a provider).
  Future<ProviderContainer> pumpPicker(
    WidgetTester tester,
    _FakeLocaleStore store, {
    bool load = false,
  }) async {
    final container = buildTestContainer(
      overrides: [localeStoreProvider.overrideWithValue(store)],
    );
    if (load) await container.read(localeControllerProvider.notifier).load();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(localeControllerProvider),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            // Scaffold, not a bare `home:` as the plan had it: the body is
            // designed to sit inside AppShell's scaffold, and RadioListTile
            // throws "No Material widget found" without one.
            home: const Scaffold(body: LanguageScreenBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('choosing Bengali applies and persists it', (tester) async {
    final store = _FakeLocaleStore();
    final container = await pumpPicker(tester, store);

    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();

    expect(container.read(localeControllerProvider), const Locale('bn'));
    expect(store.value, const Locale('bn'));
    // The choice reached the widget tree, not just the provider: a tap that
    // silently missed its target would leave both of these unchanged, so
    // assert the applied locale as well as the recorded one.
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('bn'),
    );
    final group = tester.widget<RadioGroup<String?>>(
      find.byType(RadioGroup<String?>),
    );
    expect(group.groupValue, 'bn');
  });

  testWidgets('offers a follow-the-system option that clears the choice', (
    tester,
  ) async {
    final store = _FakeLocaleStore()..value = const Locale('bn');
    final container = await pumpPicker(tester, store, load: true);
    expect(container.read(localeControllerProvider), const Locale('bn'));

    await tester.tap(find.byKey(const Key('locale_system')));
    await tester.pumpAndSettle();

    expect(container.read(localeControllerProvider), isNull);
    expect(store.value, isNull);
  });

  testWidgets(
    'every option carries the Semantics identifier Maestro drives, and '
    'tapping through that identifier applies the language',
    (tester) async {
      // Task 12's locale_bengali.yaml flow targets these by `id:`, which maps
      // to Semantics(identifier:) and NOT to Key. Shipping Keys alone would
      // leave the flow unable to tap anything, and that would only surface on
      // the CI Android emulator.
      final store = _FakeLocaleStore();
      final container = await pumpPicker(tester, store);

      // Asserted against the RENDERED semantics tree, not just the widget
      // tree: an identifier on a widget whose node gets merged away would
      // satisfy find.byWidgetPredicate while being invisible to Maestro.
      final semantics = tester.ensureSemantics();
      for (final id in ['locale_system', 'locale_en', 'locale_bn']) {
        expect(
          find.bySemanticsIdentifier(id),
          findsOneWidget,
          reason: 'Maestro taps id: "$id"',
        );
        expect(_byIdentifier(id), findsOneWidget);
      }
      // Disposed inline, not via addTearDown: the binding verifies that no
      // SemanticsHandle is live at the END OF THE TEST BODY, which runs before
      // tearDowns.
      semantics.dispose();

      await tester.tap(_byIdentifier('locale_en'));
      await tester.pumpAndSettle();

      expect(container.read(localeControllerProvider), const Locale('en'));
      expect(store.value, const Locale('en'));
    },
  );

  testWidgets(
    'each option is labelled in its own language, so a user stranded in a '
    'language they cannot read can still get out',
    (tester) async {
      await pumpPicker(tester, _FakeLocaleStore(), load: true);

      expect(find.text('English'), findsOneWidget);
      expect(find.text('বাংলা'), findsOneWidget);
      // The follow-the-system option has no single "own language", so it shows
      // both scripts rather than an English-only sentence that the Bengali-only
      // user this principle protects could not read.
      expect(
        find.textContaining('ডিভাইসের ভাষা'),
        findsOneWidget,
        reason: 'the system option must be readable in Bengali too',
      );
      // The labels are hardcoded, so nothing stops the picker from offering a
      // language this build cannot honour (MaterialApp would silently fall
      // back). Pin the two it offers against the generated supported set.
      expect(supportedLanguageCodes, containsAll(const ['en', 'bn']));
    },
  );
}
