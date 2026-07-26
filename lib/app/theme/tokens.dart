import 'package:flutter/material.dart';

/// BMD design tokens — the single source of truth for color, spacing, radius,
/// elevation and type. Mirrors the UI/UX Guideline §4 and the Figma variable
/// collections (§12.2). Never hard-code a raw value where a token exists.
abstract final class BmdColor {
  // Brand (confirmed from Figma)
  static const primary600 = Color(0xFFE71E25); // BMD red
  static const ink700 = Color(0xFF2B3674); // BMD navy
  static const deepRed = Color(0xFF831D1D);

  // Tonal / surfaces (proposed)
  static const red50 = Color(0xFFFFF2F3);
  static const navy50 = Color(0xFFF4F5FB);
  static const surfaceBase = Color(0xFFF8F9FC);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const borderDefault = Color(0xFFD9DDE8);

  // Semantic — kept distinct from brand red so risk != brand
  static const success = Color(0xFF1F7A4D);
  static const warning = Color(0xFFB54708);
  static const error = Color(0xFFB42318);
  static const info = Color(0xFF175CD3);

  // Text
  static const textPrimary = Color(0xFF1C2036);
  static const textSecondary = Color(0xFF4A5069);
  static const textFaint = Color(0xFF737A94);
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

abstract final class BmdRadius {
  static const double field = 8;
  static const double card = 12;
  static const double sheet = 16;
  static const double hero = 24;
}

/// Field 44px web / 52px mobile; camera & confirm 52–56px (§5.1, §5.2).
abstract final class BmdSize {
  static const double controlHeightWeb = 44;
  static const double controlHeightMobile = 52;
  static const double rowHeight = 46; // 44–48 operational tables
  static const double touchTargetMin = 48;
}
