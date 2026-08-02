import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the BMD-themed Material 3 [ThemeData] for a given [brightness].
///
/// The design system is Material 3 with a BMD brand layer on top (UI/UX
/// Guideline §1 "Design position"): M3 supplies the interaction primitives, the
/// token layer supplies the identity. Typography uses Inter with a Noto Sans
/// Bengali fallback — add the licensed fonts under `assets/fonts`.
///
/// Brand tokens Material has no slot for — the semantic quartet, chip tints,
/// the data-series palette and the funnel ramp — ride along as a [BmdTokens]
/// theme extension, so they lerp on a theme change like everything else.
ThemeData bmdTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  final bmd = isDark ? BmdTokens.dark : BmdTokens.light;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: BmdColor.primary600,
        brightness: brightness,
      ).copyWith(
        primary: BmdColor.primary600,
        onPrimary: Colors.white,
        primaryContainer: isDark ? BmdColor.darkNavy50 : BmdColor.red50,
        onPrimaryContainer: BmdColor.primary600,
        secondary: BmdColor.ink700,
        error: bmd.error,
        onError: isDark ? BmdColor.darkSurfaceBase : Colors.white,
        errorContainer: bmd.tintError,
        onErrorContainer: bmd.error,
        surface: isDark
            ? BmdColor.darkSurfaceElevated
            : BmdColor.surfaceElevated,
        onSurface: bmd.textPrimary,
        onSurfaceVariant: bmd.textSecondary,
        surfaceContainerLowest: isDark
            ? BmdColor.darkSurfaceBase
            : BmdColor.surfaceBase,
        surfaceContainerLow: isDark ? BmdColor.darkNavy50 : BmdColor.navy50,
        surfaceContainerHighest: bmd.surfaceSunken,
        outline: isDark ? BmdColor.darkBorderDefault : BmdColor.borderDefault,
        outlineVariant: bmd.borderStrong,
      );

  const fontFamily = 'Inter';
  const fallback = ['NotoSansBengali'];

  final base = ThemeData(brightness: brightness).textTheme.apply(
    fontFamily: fontFamily,
    fontFamilyFallback: fallback,
    bodyColor: bmd.textPrimary,
    displayColor: bmd.textHeading,
  );

  // Guideline §4.3. Desktop values; the mobile step-down is applied by the
  // responsive layer rather than by swapping the whole theme.
  final textTheme = base.copyWith(
    displayLarge: base.displayLarge?.copyWith(
      fontSize: 48,
      height: 56 / 48,
      fontWeight: FontWeight.w700,
      color: bmd.textHeading,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontSize: 28,
      height: 36 / 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.28,
      color: bmd.textHeading,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 22,
      height: 30 / 22,
      fontWeight: FontWeight.w700,
      color: bmd.textHeading,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w600,
      color: bmd.textHeading,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontSize: 16,
      height: 24 / 16,
      color: bmd.textSecondary,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: 14,
      height: 20 / 14,
      color: bmd.textSecondary,
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
    ),
    // The micro-label role: the only uppercase in the system. 12px caps need
    // tracking to stay legible at a glance.
    labelSmall: base.labelSmall?.copyWith(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.72,
      color: bmd.textFaint,
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12,
      height: 18 / 12,
      color: bmd.textFaint,
    ),
  );

  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(BmdRadius.field),
    borderSide: BorderSide(color: scheme.outline),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    fontFamily: fontFamily,
    fontFamilyFallback: fallback,
    textTheme: textTheme,
    extensions: [bmd],

    appBarTheme: AppBarTheme(
      toolbarHeight: BmdSize.appBarWeb,
      backgroundColor: scheme.surface,
      foregroundColor: bmd.textHeading,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: scheme.outline)),
      titleTextStyle: textTheme.titleMedium,
    ),

    // Elevation 0 by default: separation comes from the hairline border against
    // the tinted page, so a dense table does not read as clutter (§4.4).
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BmdRadius.card),
        side: BorderSide(color: scheme.outline),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BmdSpace.s3,
        vertical: BmdSpace.s3,
      ),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
        borderSide: const BorderSide(color: BmdColor.primary600, width: 2),
      ),
      errorBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: bmd.error),
      ),
      focusedErrorBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: bmd.error, width: 2),
      ),
      // Labels stay visible once a value is entered — a half-filled campaign
      // form with floating labels is unauditable (§5.2).
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: textTheme.labelMedium?.copyWith(color: bmd.textSecondary),
      helperStyle: textTheme.bodySmall,
      errorStyle: textTheme.bodySmall?.copyWith(color: bmd.error),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, BmdSize.controlHeightWeb),
        padding: const EdgeInsets.symmetric(horizontal: BmdSpace.s4),
        backgroundColor: BmdColor.primary600,
        foregroundColor: Colors.white,
        disabledBackgroundColor: bmd.surfaceSunken,
        disabledForegroundColor: bmd.textFaint,
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BmdRadius.field),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, BmdSize.controlHeightWeb),
        padding: const EdgeInsets.symmetric(horizontal: BmdSpace.s4),
        foregroundColor: bmd.textHeading,
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.outline),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BmdRadius.field),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, BmdSize.controlHeightWeb),
        foregroundColor: BmdColor.ink700,
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BmdRadius.field),
        ),
      ),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: const IconThemeData(color: BmdColor.primary600),
      unselectedIconTheme: IconThemeData(color: bmd.textSecondary),
      selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
        color: BmdColor.primary600,
      ),
      unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
        color: bmd.textSecondary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? textTheme.bodySmall?.copyWith(color: BmdColor.primary600)
            : textTheme.bodySmall,
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? BmdColor.primary600
              : bmd.textSecondary,
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BmdRadius.sheet),
      ),
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20, height: 1.4),
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BmdRadius.sheet),
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outline,
      space: 1,
      thickness: 1,
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: BmdSpace.s2,
      titleTextStyle: textTheme.labelLarge?.copyWith(color: bmd.textPrimary),
      subtitleTextStyle: textTheme.bodySmall,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: BmdColor.ink700,
        borderRadius: BorderRadius.circular(BmdRadius.chip),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
    ),
  );
}
