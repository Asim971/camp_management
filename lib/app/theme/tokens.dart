import 'package:flutter/material.dart';

/// BMD design tokens — the single source of truth for colour, spacing, radius,
/// elevation and type. Mirrors the UI/UX Guideline §4 and the Figma variable
/// collections (§12.2). Never hard-code a raw value where a token exists.
///
/// This file is the Dart half of a two-language token layer; `design/src/
/// tokens.css` is the other. The names match deliberately, so a change in one
/// is findable in the other. Derived values (the data-series slots and the
/// funnel ramp) were produced by enumeration and machine-checked — see
/// `design/PALETTE.md` for the evidence, and re-run
/// `design/scripts/derive_palette.mjs` rather than editing a hex by hand.
///
/// Mode-dependent values live on [BmdTokens], a [ThemeExtension], because they
/// differ between light and dark. The statics below are the light-mode values
/// and the brand constants that do not change.
abstract final class BmdColor {
  // --- Brand (confirmed from Figma) ---------------------------------------
  static const primary600 = Color(0xFFE71E25); // BMD red
  static const primary700 = Color(0xFFCF1A20); // pressed / hover step
  static const ink700 = Color(0xFF2B3674); // BMD navy
  static const deepRed = Color(0xFF831D1D);

  // --- Tonal / surfaces (light) -------------------------------------------
  static const red50 = Color(0xFFFFF2F3);
  static const navy50 = Color(0xFFF4F5FB);
  static const surfaceBase = Color(0xFFF8F9FC);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const surfaceSunken = Color(0xFFF1F3F9);
  static const borderDefault = Color(0xFFD9DDE8);
  static const borderStrong = Color(0xFFBFC5D6);

  // --- Semantic (light) ---------------------------------------------------
  // Kept distinct from brand red so risk and brand stay distinguishable (§4.2).
  // Text contrast on surfaceElevated: 5.32 / 5.43 / 6.57 / 5.99 : 1.
  static const success = Color(0xFF1F7A4D);
  static const warning = Color(0xFFB54708);
  static const error = Color(0xFFB42318);
  static const info = Color(0xFF175CD3);

  // --- Text (light) -------------------------------------------------------
  static const textHeading = Color(0xFF2B3674);
  static const textPrimary = Color(0xFF1C2036);
  static const textSecondary = Color(0xFF4A5069);
  static const textFaint = Color(0xFF737A94);

  /// Ink on the neutral dark veil that covers sensitive media. Fixed in both
  /// themes — the veil is always dark, so this pair never flips (§10.2).
  static const inkOnVeil = Color(0xFFE7E9F4);
  static const inkOnVeilMuted = Color(0xFFA8AEC8);
  static const veil = Color(0xDD0D1020);

  // --- Dark mode ----------------------------------------------------------
  static const darkSurfaceBase = Color(0xFF0D1020);
  static const darkSurfaceElevated = Color(0xFF161A2E);
  static const darkSurfaceSunken = Color(0xFF1D2238);
  static const darkBorderDefault = Color(0xFF2B3152);
  static const darkBorderStrong = Color(0xFF3A4166);
  static const darkNavy50 = Color(0xFF1A1F36);

  static const darkTextPrimary = Color(0xFFE7E9F4);
  static const darkTextSecondary = Color(0xFFB4B9D0);
  static const darkTextFaint = Color(0xFF8A90AC);

  // Lifted so each state clears AA text contrast on the dark surface. The
  // light values would fail there.
  static const darkSuccess = Color(0xFF4ADE80);
  static const darkWarning = Color(0xFFFDBA4D);
  static const darkError = Color(0xFFFF8A80);
  static const darkInfo = Color(0xFF7DB0FF);
}

/// 8px primary rhythm; 4px only for tightly related metadata (§4.4).
abstract final class BmdSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;
  static const double s8 = 40;
  static const double s9 = 48;
  static const double s10 = 64;
}

/// Radius encodes the surface class, so it is a signal rather than a style
/// preference: a 16px corner says "temporary and dismissible", a 12px corner
/// says "part of the page".
abstract final class BmdRadius {
  static const double chip = 6;
  static const double field = 8;
  static const double card = 12;
  static const double sheet = 16;
  static const double hero = 24;
  static const double pill = 999;
}

/// Field 44px web / 52px mobile; camera & confirm 52–56px (§5.1, §5.2).
abstract final class BmdSize {
  static const double controlHeightWeb = 44;
  static const double controlHeightMobile = 52;
  static const double controlHeightCamera = 56;
  static const double rowHeight = 46; // 44–48 operational tables
  static const double touchTargetMin = 48;
  static const double appBarWeb = 64;
  static const double appBarMobile = 56;
  static const double drawerExpanded = 264;
  static const double drawerCollapsed = 76;
}

/// Elevation is tinted to the ink hue so shadows read as part of the brand
/// rather than as grey fog. Default to [none]; never stack two high levels.
abstract final class BmdElevation {
  static const List<BoxShadow> none = [];

  /// Cards and sticky bars.
  static const List<BoxShadow> level1 = [
    BoxShadow(color: Color(0x142B3674), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Menus, popovers and side sheets.
  static const List<BoxShadow> level2 = [
    BoxShadow(color: Color(0x1F2B3674), offset: Offset(0, 4), blurRadius: 12),
  ];

  /// Dialogs only.
  static const List<BoxShadow> level3 = [
    BoxShadow(color: Color(0x292B3674), offset: Offset(0, 12), blurRadius: 28),
  ];
}

/// Mode-dependent tokens that Material's [ColorScheme] has no slot for:
/// the semantic quartet, chip tints, the validated data-series palette and the
/// ordinal funnel ramp. Read with `Theme.of(context).bmd`.
@immutable
class BmdTokens extends ThemeExtension<BmdTokens> {
  const BmdTokens({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.neutral,
    required this.tintSuccess,
    required this.tintWarning,
    required this.tintError,
    required this.tintInfo,
    required this.tintNeutral,
    required this.tintBrand,
    required this.textHeading,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.surfaceSunken,
    required this.borderStrong,
    required this.series,
    required this.funnel,
  });

  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color neutral;

  /// 10% tints of each state's own hue — quiet enough for a forty-row table
  /// while the label keeps its AA contrast on top.
  final Color tintSuccess;
  final Color tintWarning;
  final Color tintError;
  final Color tintInfo;
  final Color tintNeutral;
  final Color tintBrand;

  final Color textHeading;
  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;
  final Color surfaceSunken;
  final Color borderStrong;

  /// Categorical identity, in fixed order. Assigned in sequence, never cycled.
  /// Slot 0 is brand red: the guideline's one principal chart series (§4.2).
  ///
  /// Worst adjacent CVD ΔE 15.9 light / 14.8 dark (target ≥ 8); worst adjacent
  /// normal-vision ΔE 32.6 / 29.4 (floor ≥ 15). Four slots sit below 3:1
  /// against their surface, which is legal ONLY because every chart ships
  /// visible direct labels and a table view — see `design/PALETTE.md`.
  final List<Color> series;

  /// Ordinal ramp — one hue, monotone lightness. The conversion funnel is a
  /// sequence, so colour has to carry the order. The dark ramp reverses anchor
  /// so no stage sinks into the surface.
  final List<Color> funnel;

  static const light = BmdTokens(
    success: BmdColor.success,
    warning: BmdColor.warning,
    error: BmdColor.error,
    info: BmdColor.info,
    neutral: BmdColor.textSecondary,
    tintSuccess: Color(0x1A1F7A4D),
    tintWarning: Color(0x1AB54708),
    tintError: Color(0x1AB42318),
    tintInfo: Color(0x1A175CD3),
    tintNeutral: Color(0x122B3674),
    tintBrand: Color(0x14E71E25),
    textHeading: BmdColor.textHeading,
    textPrimary: BmdColor.textPrimary,
    textSecondary: BmdColor.textSecondary,
    textFaint: BmdColor.textFaint,
    surfaceSunken: BmdColor.surfaceSunken,
    borderStrong: BmdColor.borderStrong,
    series: [
      Color(0xFFE71E25), // brand red — principal
      Color(0xFF3B4A96), // navy, lifted into the lightness band
      Color(0xFFCA8A04), // ochre — 2.94:1, needs a visible label
      Color(0xFF6D28D9), // violet
      Color(0xFF4D7C0F), // olive
      Color(0xFFE85D95), // magenta
    ],
    funnel: [
      Color(0xFF97A2DC),
      Color(0xFF7382CC),
      Color(0xFF5566C4),
      Color(0xFF3B4A96),
      Color(0xFF2B3674),
    ],
  );

  static const dark = BmdTokens(
    success: BmdColor.darkSuccess,
    warning: BmdColor.darkWarning,
    error: BmdColor.darkError,
    info: BmdColor.darkInfo,
    neutral: BmdColor.darkTextSecondary,
    tintSuccess: Color(0x244ADE80),
    tintWarning: Color(0x24FDBA4D),
    tintError: Color(0x24FF8A80),
    tintInfo: Color(0x247DB0FF),
    tintNeutral: Color(0x14E7E9F4),
    tintBrand: Color(0x29E71E25),
    textHeading: BmdColor.darkTextPrimary,
    textPrimary: BmdColor.darkTextPrimary,
    textSecondary: BmdColor.darkTextSecondary,
    textFaint: BmdColor.darkTextFaint,
    surfaceSunken: BmdColor.darkSurfaceSunken,
    borderStrong: BmdColor.darkBorderStrong,
    series: [
      Color(0xFFE71E25),
      Color(0xFF4657AE),
      Color(0xFFB87309),
      Color(0xFF6D28D9),
      Color(0xFF65A30D),
      Color(0xFFBE185D),
    ],
    funnel: [
      Color(0xFFC3CAEE),
      Color(0xFFA3ADE1),
      Color(0xFF7E8CD1),
      Color(0xFF5A6BC7),
      Color(0xFF4657AE),
    ],
  );

  /// Categorical slots are assigned in fixed order and never cycled. Past the
  /// last slot, fold into "Other" or facet — a generated hue would not have
  /// been through the CVD gates.
  Color seriesAt(int index) => index < series.length ? series[index] : neutral;

  @override
  BmdTokens copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? neutral,
    Color? tintSuccess,
    Color? tintWarning,
    Color? tintError,
    Color? tintInfo,
    Color? tintNeutral,
    Color? tintBrand,
    Color? textHeading,
    Color? textPrimary,
    Color? textSecondary,
    Color? textFaint,
    Color? surfaceSunken,
    Color? borderStrong,
    List<Color>? series,
    List<Color>? funnel,
  }) {
    return BmdTokens(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
      tintSuccess: tintSuccess ?? this.tintSuccess,
      tintWarning: tintWarning ?? this.tintWarning,
      tintError: tintError ?? this.tintError,
      tintInfo: tintInfo ?? this.tintInfo,
      tintNeutral: tintNeutral ?? this.tintNeutral,
      tintBrand: tintBrand ?? this.tintBrand,
      textHeading: textHeading ?? this.textHeading,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textFaint: textFaint ?? this.textFaint,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      borderStrong: borderStrong ?? this.borderStrong,
      series: series ?? this.series,
      funnel: funnel ?? this.funnel,
    );
  }

  @override
  BmdTokens lerp(covariant BmdTokens? other, double t) {
    if (other == null) return this;
    List<Color> lerpAll(List<Color> a, List<Color> b) => [
      for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
    ];
    return BmdTokens(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      tintSuccess: Color.lerp(tintSuccess, other.tintSuccess, t)!,
      tintWarning: Color.lerp(tintWarning, other.tintWarning, t)!,
      tintError: Color.lerp(tintError, other.tintError, t)!,
      tintInfo: Color.lerp(tintInfo, other.tintInfo, t)!,
      tintNeutral: Color.lerp(tintNeutral, other.tintNeutral, t)!,
      tintBrand: Color.lerp(tintBrand, other.tintBrand, t)!,
      textHeading: Color.lerp(textHeading, other.textHeading, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      series: lerpAll(series, other.series),
      funnel: lerpAll(funnel, other.funnel),
    );
  }
}

/// `Theme.of(context).bmd` — the brand token set for the current brightness.
extension BmdThemeAccess on ThemeData {
  BmdTokens get bmd => extension<BmdTokens>() ?? BmdTokens.light;
}
