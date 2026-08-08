import 'package:acsl_campaign/app/app.dart';
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/l10n/locale_controller.dart';
import 'package:acsl_campaign/core/l10n/locale_store.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/common/status_labels.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';

/// The guard that was missing for three epics. `AppL10n.localizationsDelegates`
/// and `AppL10n.supportedLocales` sat COMMENTED OUT in `AcslCampaignApp` from
/// P0.2 through P0.4 and every test stayed green, because the only localization
/// tests (test/l10n/l10n_render_test.dart) build their own `MaterialApp` and
/// register the delegates themselves — proving the ARB -> codegen -> delegate ->
/// glyph chain, but nothing about `app.dart`. These assertions read the
/// configuration of the `MaterialApp` that `AcslCampaignApp` actually builds, so
/// re-commenting those lines fails the suite.
void main() {
  late ProviderContainer lastContainer;

  Future<MaterialApp> pumpApp(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
    Future<void> Function(ProviderContainer container)? beforePump,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            flavor: Flavor.dev,
            apiBaseUrl: 'https://example.invalid',
            mediaHost: 'https://example.invalid',
          ),
        ),
        // Same in-memory fake the rest of the suite uses, so this stays a pure
        // widget test with no Keystore/localStorage dependency. It starts
        // empty, so the router lands on /login — irrelevant here: every
        // assertion below is about MaterialApp configuration, not the route.
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        ...overrides,
      ],
    );
    lastContainer = container;
    addTearDown(container.dispose);
    await container.read(sessionManagerProvider).restore();
    // Boot-order fidelity: main() adopts the persisted locale *before* runApp,
    // so the first frame is already in the right language.
    await beforePump?.call(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AcslCampaignApp(),
      ),
    );
    await tester.pumpAndSettle();

    // MaterialApp.router is a named constructor on MaterialApp, so the widget
    // AcslCampaignApp builds has runtimeType MaterialApp and this matches.
    return tester.widget<MaterialApp>(find.byType(MaterialApp));
  }

  testWidgets('AcslCampaignApp registers the generated AppL10n delegate', (
    tester,
  ) async {
    final app = await pumpApp(tester);

    // The specific regression: AppL10n.delegate absent means the generated
    // localizations are never applied and a Bengali device gets English.
    expect(app.localizationsDelegates, contains(AppL10n.delegate));
  });

  testWidgets('AcslCampaignApp offers exactly the generated supportedLocales', (
    tester,
  ) async {
    final app = await pumpApp(tester);

    expect(app.supportedLocales, AppL10n.supportedLocales);
  });

  testWidgets('an unsupported device locale falls back to English, not Bengali', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final app = await pumpApp(tester);

    // Regression guard for the codegen alphabetization trap: without an
    // explicit callback this resolves to supportedLocales.first == Locale('bn').
    expect(
      app.localeListResolutionCallback!(const [
        Locale('fr', 'FR'),
      ], AppL10n.supportedLocales),
      const Locale('en'),
    );
    // ...and the same fact observed through the real resolution pipeline rather
    // than by calling the callback directly, so this still holds if the
    // callback is ever replaced by a different mechanism.
    expect(_resolvedLocale(tester), const Locale('en'));
  });

  testWidgets('a Bengali device still resolves to Bengali', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('bn', 'BD')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final app = await pumpApp(tester);

    expect(
      app.localeListResolutionCallback!(const [
        Locale('bn', 'BD'),
      ], AppL10n.supportedLocales),
      const Locale('bn'),
    );
    expect(_resolvedLocale(tester), const Locale('bn'));
  });

  testWidgets('an English device still resolves to English', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final app = await pumpApp(tester);

    expect(
      app.localeListResolutionCallback!(const [
        Locale('en', 'US'),
      ], AppL10n.supportedLocales),
      const Locale('en'),
    );
    expect(_resolvedLocale(tester), const Locale('en'));
  });

  testWidgets('an empty or null device locale list resolves to English', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    final callback = app.localeListResolutionCallback!;

    // Flutter passes null when the platform reports no preferred locales at
    // all; an empty list is the same situation via a different path.
    expect(callback(null, AppL10n.supportedLocales), const Locale('en'));
    expect(
      callback(const <Locale>[], AppL10n.supportedLocales),
      const Locale('en'),
    );
  });

  // The whole point of the epic, end to end: a preference sitting in the store
  // reaches MaterialApp.router's `locale:`, survives the trip *through* the
  // localeListResolutionCallback above (WidgetsApp passes [widget.locale!] as
  // the preferred list, so the choice goes through that code rather than round
  // it), and lands as a real Bengali bundle in the Localizations scope. Nothing
  // covered this composition: the controller tests stop at the Notifier's state
  // and the callback tests stop at the callback.
  testWidgets('a persisted Bengali preference drives the resolved locale and '
      'the strings that render', (tester) async {
    // Device is English. Any Bengali observed below can only have come from the
    // stored preference, never from the platform locale.
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final app = await pumpApp(
      tester,
      overrides: [
        localeStoreProvider.overrideWithValue(
          _StubLocaleStore(const Locale('bn')),
        ),
      ],
      beforePump: (container) =>
          container.read(localeControllerProvider.notifier).load(),
    );

    expect(app.locale, const Locale('bn'), reason: 'locale: must be wired');
    expect(_resolvedLocale(tester), const Locale('bn'));

    // Read the bundle the app's own Localizations scope hands out, so this is
    // the delegate that actually loaded, not one this test registered.
    final l10n = AppL10n.of(tester.element(find.byType(Navigator).first));
    expect(l10n.appTitle, 'ক্যাম্পেইন ব্যবস্থাপনা');
    expect(CampaignStatus.draft.label(l10n), 'খসড়া');
    // A partial fallback (bn locale, English bundle) would otherwise read as
    // success, so assert the English strings are absent rather than only that
    // the Bengali ones are present.
    expect(l10n.appTitle, isNot('Campaign Management'));
    expect(CampaignStatus.draft.label(l10n), isNot('Draft'));
  });

  testWidgets('selecting a locale at runtime re-resolves the live app', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await pumpApp(
      tester,
      overrides: [localeStoreProvider.overrideWithValue(_StubLocaleStore())],
    );
    expect(_resolvedLocale(tester), const Locale('en'));

    // What the language picker will do. `locale:` must be watched, not read
    // once at first build, or the app would need a restart to change language.
    await lastContainer
        .read(localeControllerProvider.notifier)
        .select(const Locale('bn'));
    await tester.pumpAndSettle();

    expect(_resolvedLocale(tester), const Locale('bn'));
    expect(
      AppL10n.of(tester.element(find.byType(Navigator).first)).appTitle,
      'ক্যাম্পেইন ব্যবস্থাপনা',
    );
  });
}

/// In-memory [LocaleStore], so pumping the app here never opens a database.
class _StubLocaleStore implements LocaleStore {
  _StubLocaleStore([this.value]);
  Locale? value;

  @override
  Future<Locale?> read() async => value;

  @override
  Future<void> write(Locale locale) async => value = locale;

  @override
  Future<void> clear() async => value = null;
}

/// The locale that `WidgetsApp`'s `Localizations` scope actually settled on,
/// read from a context below it.
Locale _resolvedLocale(WidgetTester tester) =>
    Localizations.localeOf(tester.element(find.byType(Navigator).first));
