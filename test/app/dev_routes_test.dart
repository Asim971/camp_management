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
      tester.view.physicalSize = const Size(1280, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: bmdTheme(), home: const GalleryScreen()),
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
