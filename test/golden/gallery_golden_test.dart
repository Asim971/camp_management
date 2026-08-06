import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/features/gallery/presentation/gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden.dart';

/// Section-level baselines across both themes and both surface widths.
///
/// Granularity is deliberate: one baseline per section rather than per
/// component-state keeps the file count manageable while a regression in any
/// single state still trips its section. The behavioural rules live in the
/// per-component tests; these catch geometry, spacing and colour.
const _viewports = <String, Size>{
  'desktop': Size(1280, 2600),
  'mobile': Size(390, 2600),
};

/// Sets the test binding's *physical* view directly.
///
/// `tester.binding.setSurfaceSize` does not drive `MediaQuery.sizeOf` on this
/// toolchain (Flutter 3.44.8): the reported logical size stays the 800x600
/// default regardless of the surface size requested, which would make every
/// viewport pair render identically despite several components (e.g.
/// `BmdButton`, `BmdIconButton`) sizing themselves from `Breakpoint.of`.
/// Setting `tester.view.physicalSize` with a unit `devicePixelRatio` instead
/// genuinely changes what `MediaQuery` reports.
void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: bmdTheme(brightness: brightness),
    home: Scaffold(
      body: SingleChildScrollView(
        // BmdButton(loading: true) renders an indeterminate
        // CircularProgressIndicator with no ticker-free equivalent, which
        // never settles and would hang pumpAndSettle forever. Muting the
        // TickerMode freezes it (and any other implicit animation) at one
        // deterministic paint after a single pump, regardless of how many
        // times the harness pumps — including a future harness that settles
        // by default instead of relying on everyone remembering a bare
        // pump().
        child: TickerMode(enabled: false, child: child),
      ),
    ),
  );
}

GallerySectionView _sectionFor(String id) =>
    gallerySections().firstWhere((s) => s.id == id);

void main() {
  for (final viewport in _viewports.entries) {
    for (final brightness in Brightness.values) {
      final suffix = '${viewport.key}-${brightness.name}';

      for (final id in GallerySection.all) {
        goldenTest('$id · $suffix', (tester) async {
          _setViewport(tester, viewport.value);

          await tester.pumpWidget(
            _host(_sectionFor(id), brightness: brightness),
          );
          // Not pumpAndSettle: the loading BmdButton's indeterminate spinner
          // never settles. TickerMode(enabled: false) above already froze it,
          // so one extra pump is enough for layout to catch up with the
          // viewport change.
          await tester.pump();

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/$id-$suffix.png'),
          );
        });
      }
    }
  }

  goldenTest('bengali copy wraps without clipping', (tester) async {
    // §13.2 requires Bangla and English notice layouts to be tested for
    // wrapping and equivalent meaning. Real Bengali glyphs are what make this
    // assertable; the placeholder test font cannot show it.
    _setViewport(tester, const Size(390, 900));

    await tester.pumpWidget(
      _host(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [BengaliCopySample()],
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/bengali-wrapping-mobile.png'),
    );
  });
}
