import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the BMD-themed Material 3 [ThemeData] for a given [brightness].
///
/// The design system is Material 3 with a BMD brand layer on top
/// (UI/UX Guideline §1 "Design position"). Typography uses Inter with a
/// Noto Sans Bengali fallback — add the licensed fonts under assets/fonts and
/// pass the family name via [fontFamily]/[fontFamilyFallback].
ThemeData bmdTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: BmdColor.primary600,
    brightness: brightness,
  ).copyWith(
    primary: BmdColor.primary600,
    error: BmdColor.error,
    surface: isDark ? const Color(0xFF161A2E) : BmdColor.surfaceElevated,
    surfaceContainerLowest:
        isDark ? const Color(0xFF0D1020) : BmdColor.surfaceBase,
    outline: isDark ? const Color(0xFF2B3152) : BmdColor.borderDefault,
  );

  const fontFamily = 'Inter';
  const fallback = ['NotoSansBengali'];

  final baseText = ThemeData(brightness: brightness).textTheme.apply(
        fontFamily: fontFamily,
        fontFamilyFallback: fallback,
        bodyColor: isDark ? const Color(0xFFE7E9F4) : BmdColor.textPrimary,
        displayColor: isDark ? const Color(0xFFE7E9F4) : BmdColor.textPrimary,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    fontFamily: fontFamily,
    fontFamilyFallback: fallback,
    textTheme: baseText.copyWith(
      // Guideline §4.3 type scale (desktop values).
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontSize: 28,
        height: 36 / 28,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 22,
        height: 30 / 22,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 14, height: 20 / 14),
      labelMedium: baseText.labelMedium?.copyWith(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BmdRadius.field),
      ),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, BmdSize.controlHeightWeb),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BmdRadius.field),
        ),
      ),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BmdRadius.card),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    dividerColor: scheme.outline,
  );
}
