import 'dart:io';

import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The theme names two font families. If the app does not actually ship them,
/// every surface silently renders in the platform default and the Bangla
/// fallback does not exist — a failure that looks fine on a developer's machine
/// and wrong on a field device.
void main() {
  group('bundled fonts', () {
    test('every family the theme names is shipped as an asset', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      const families = {
        'Inter': 'assets/fonts/Inter-Variable.ttf',
        'NotoSansBengali': 'assets/fonts/NotoSansBengali-Variable.ttf',
      };

      for (final entry in families.entries) {
        expect(
          pubspec,
          contains('family: ${entry.key}'),
          reason:
              'bmdTheme() names "${entry.key}" but pubspec.yaml does not '
              'declare it, so it is never bundled.',
        );
        expect(
          File(entry.value).existsSync(),
          isTrue,
          reason: '${entry.value} is declared but missing from the repo.',
        );
      }
    });

    test('every weighted text style also drives the variable wght axis', () {
      // Inter and Noto Sans Bengali ship only as variable fonts. fontWeight
      // alone makes the engine synthesise a fake bold; the real cut requires
      // the wght axis to be set too.
      final theme = bmdTheme();
      final styles = <String, TextStyle?>{
        'displayLarge': theme.textTheme.displayLarge,
        'headlineMedium': theme.textTheme.headlineMedium,
        'titleLarge': theme.textTheme.titleLarge,
        'titleMedium': theme.textTheme.titleMedium,
        'bodyLarge': theme.textTheme.bodyLarge,
        'bodyMedium': theme.textTheme.bodyMedium,
        'labelLarge': theme.textTheme.labelLarge,
        'labelMedium': theme.textTheme.labelMedium,
        'labelSmall': theme.textTheme.labelSmall,
        'bodySmall': theme.textTheme.bodySmall,
      };

      for (final entry in styles.entries) {
        final style = entry.value;
        expect(style, isNotNull, reason: '${entry.key} is missing');
        final weight = style!.fontWeight;
        if (weight == null || weight == FontWeight.w400) continue;

        final axis = (style.fontVariations ?? const <FontVariation>[])
            .where((v) => v.axis == 'wght')
            .toList();
        expect(
          axis,
          hasLength(1),
          reason:
              '${entry.key} sets fontWeight ${weight.value} but no wght '
              'variation, so it renders as a synthetic bold.',
        );
        expect(
          axis.single.value,
          weight.value.toDouble(),
          reason: '${entry.key} wght axis disagrees with its fontWeight.',
        );
      }
    });

    testWidgets('real fonts are loaded, not the placeholder test font', (
      tester,
    ) async {
      // The default test font renders every glyph as an identical box, so equal
      // code-point counts measure to equal widths. Real fonts do not.
      TextPainter measure(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: bmdTheme().textTheme.bodyMedium),
          textDirection: TextDirection.ltr,
        )..layout();
        return painter;
      }

      final latin = measure('abcde').width;
      final bengali = measure('অআইঈউ').width;

      expect(
        bengali,
        isNot(closeTo(latin, 0.01)),
        reason:
            'Bengali and Latin strings of five code points measured the same '
            'width, which means the placeholder test font is in use and '
            'test/flutter_test_config.dart is not loading the real families.',
      );
    });
  });
}
