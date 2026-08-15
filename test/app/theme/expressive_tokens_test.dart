import 'dart:math' as math;

import 'package:acsl_campaign/app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// WCAG relative luminance + contrast ratio, for the AA assertion.
double _lum(Color c) {
  double ch(int v) {
    final s = v / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * ch((c.r * 255).round()) +
      0.7152 * ch((c.g * 255).round()) +
      0.0722 * ch((c.b * 255).round());
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('electric-cyan accent is defined for both modes', () {
    expect(BmdColor.accentCyan, const Color(0xFF22D3EE));
    expect(BmdTokens.dark.accent, isNotNull);
    expect(BmdTokens.light.accent, isNotNull);
  });

  test('glass tokens exist and are translucent (alpha < 1)', () {
    expect(BmdTokens.dark.glassFill.a, lessThan(1.0));
    expect(BmdTokens.dark.glassBorder.a, lessThan(1.0));
  });

  test('hero mesh gradient has the brand + accent stops', () {
    final g = BmdGradient.heroMesh(true);
    expect(g.colors, contains(BmdColor.primary600)); // brand red
    expect(g.colors, contains(BmdColor.ink700)); // navy
    expect(g.colors.any((c) => c == BmdColor.accentCyan), isTrue);
  });

  test('BmdTokens.lerp handles the new fields (no crash, midpoint valid)', () {
    final mid = BmdTokens.light.lerp(BmdTokens.dark, 0.5);
    expect(mid.accent, isNotNull);
    expect(mid.glassFill, isNotNull);
  });

  test(
    'the dark cyan accent clears 3:1 on the dark base (large UI accent)',
    () {
      expect(
        _contrast(BmdColor.accentCyan, BmdColor.darkSurfaceBase),
        greaterThanOrEqualTo(3.0),
      );
    },
  );
}
