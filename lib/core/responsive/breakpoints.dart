import 'package:flutter/widgets.dart';

/// Responsive breakpoints from UI/UX Guideline §11.
enum Breakpoint {
  mobileS, // 320–374
  mobileL, // 375–599
  tablet, // 600–1023
  desktop, // 1024–1439
  largeDesktop; // >=1440

  static Breakpoint of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static Breakpoint fromWidth(double w) {
    if (w < 375) return Breakpoint.mobileS;
    if (w < 600) return Breakpoint.mobileL;
    if (w < 1024) return Breakpoint.tablet;
    if (w < 1440) return Breakpoint.desktop;
    return Breakpoint.largeDesktop;
  }

  bool get isMobile => this == mobileS || this == mobileL;
  bool get isTabletUp => index >= Breakpoint.tablet.index;
  bool get isDesktopUp => index >= Breakpoint.desktop.index;
}

/// Max working width 1440px; 24px gutter at 1280–1439, 32px at >=1440 (§3.1).
class ContentConstraints {
  const ContentConstraints._();
  static const double maxWorkingWidth = 1440;

  static double gutter(Breakpoint bp) => bp == Breakpoint.largeDesktop ? 32 : 24;
}
