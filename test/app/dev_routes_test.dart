import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/features/gallery/presentation/gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/single_primary.dart';

void main() {
  group('devRoutesEnabled', () {
    AppConfig config({required Flavor flavor, bool e2e = false}) => AppConfig(
      flavor: flavor,
      apiBaseUrl: 'https://example.invalid',
      mediaHost: 'https://example.invalid',
      e2e: e2e,
    );

    test('production hides the dev launcher and the gallery', () {
      // /dev was registered unconditionally, so it was reachable by URL in a
      // production web build despite the comment claiming otherwise.
      expect(config(flavor: Flavor.prod).devRoutesEnabled, isFalse);
    });

    test('dev and staging expose them', () {
      expect(config(flavor: Flavor.dev).devRoutesEnabled, isTrue);
      expect(config(flavor: Flavor.stg).devRoutesEnabled, isTrue);
    });

    test('an E2E build exposes them whatever the flavor', () {
      // Maestro deep-links through /dev, including against a prod-flavoured
      // build.
      expect(config(flavor: Flavor.prod, e2e: true).devRoutesEnabled, isTrue);
    });

    test('AppConfig.fromEnvironment() with no --dart-define exposes them under '
        'flutter test/run, matching the documented dev fallback', () {
      // parseFlavor falls back to Flavor.dev when FLAVOR is absent, so a
      // bare `flutter test`/`flutter run` (no --dart-define at all) lands
      // here. This is the flavor-logic half of the devRoutesEnabled
      // contract: dev routes are reachable when nothing says otherwise.
      //
      // What this test cannot reach: kReleaseMode is always false under
      // `flutter test`, so the `&& !kReleaseMode` release-mode guard added
      // in devRoutesEnabled is structurally untestable from here. A real
      // `flutter build web --release` run with no FLAVOR define is the
      // only way to observe that guard firing — flavor alone would still
      // say Flavor.dev, and it is exactly that combination (release binary
      // + default-dev flavor) the guard exists for.
      final config = AppConfig.fromEnvironment();
      expect(config.flavor, Flavor.dev);
      expect(config.devRoutesEnabled, isTrue);
    });
  });

  group('GalleryScreen', () {
    testWidgets('renders every section and keeps one primary action', (
      tester,
    ) async {
      // tester.binding.setSurfaceSize() does not drive MediaQuery.sizeOf on
      // this Flutter version (3.44.8) — it leaves the reported size at the
      // 800x600 default, so Breakpoint.of(context) would resolve to tablet
      // and several components (BmdButton, BmdField, BmdSearchField) would
      // size themselves for the wrong breakpoint. Driving tester.view
      // directly is what actually changes MediaQuery.sizeOf.
      // Height tracks gallery growth (slice 1 + slice 2 sections); increase if
      // new sections are added.
      tester.view.physicalSize = const Size(1280, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: bmdTheme(),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: GalleryScreen(),
          ),
        ),
      );
      // Not pumpAndSettle: the buttons section deliberately includes a
      // BmdButton(loading: true), whose CircularProgressIndicator animates
      // indeterminately and never settles.
      await tester.pump();

      for (final id in GallerySection.all) {
        expect(
          find.byKey(ValueKey(id)),
          findsOneWidget,
          reason: '$id is missing from the gallery',
        );
      }

      expectSinglePrimaryAction(tester);
    });
  });
}
