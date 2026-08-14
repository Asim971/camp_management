# Expressive Redesign — Slice 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish an expressive dark-first visual language + a motion system on the existing BMD design system, and prove both by building the placeholder Campaign Dashboard (`/`, W-01) as an exception-first showpiece.

**Architecture:** Re-theme, not rewrite. The look lands in the token layer (`lib/app/theme/tokens.dart`) + `bmd_theme.dart` + the CSS mirror (`design/src/tokens.css`), so all screens inherit it. A new `lib/core/motion/` layer (engined by `flutter_animate`) adds transitions, staggered reveals, count-up, and shimmer — all honoring reduced-motion. Components get visual/motion uplift with unchanged public APIs. A new `dashboard` feature composes existing Riverpod providers into an exception-first dashboard.

**Tech Stack:** Flutter 3.44 / Dart 3.12, Material 3, Riverpod, GoRouter, `flutter_animate` (new), `fl_chart` (already a dependency, currently unused), Inter + Noto Sans Bengali variable fonts. Golden tests via `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-14-expressive-redesign-slice1-design.md` (decisions RD.D1–RD.D6).

## Global Constraints

Every task's requirements implicitly include this section.

- **SDK floor `sdk: ">=3.12.0 <4.0.0"`, `flutter: ">=3.44.0"`.** Material 3 (`useMaterial3: true`) stays the base — this is a re-theme, not a framework change.
- **Preserve every `Semantics(identifier: …)` string.** 16 `lib/` files and 20 `.maestro/flows/*.yaml` select by them; the 20-flow Maestro CI suite breaks if any identifier changes. The re-skin changes pixels, never identifier strings. New widgets add NEW identifiers only. Keep the `enabled:`-semantics workaround in `bmd_button.dart:42-61` exactly as-is.
- **Component public APIs are unchanged.** `KpiCard` still requires `label/value/definition/source/freshness` (+ optional `denominator/delta/deltaDirection/deltaContext`); no component constructor field is removed or renamed. Visual/motion uplift only.
- **Tokens, not inline values.** New colors/gradients/durations are tokens in `tokens.dart` / `motion_tokens.dart`, mirrored to `design/src/tokens.css`. Never hard-code a raw value where a token exists.
- **Brand red `#E71E25` stays the primary-action color** (guideline: "red highlights the main action, not every card"). Electric cyan `#22D3EE` is the accent (CTAs' energy, selected series, focus glows, hero-gradient third stop) — it never replaces red for primary actions.
- **Bilingual EN/BN preserved.** Inter + Noto Sans Bengali via `FontVariation('wght', …)` (never `fontWeight` alone — it triggers synthetic bold that bakes into goldens). New display sizes must render Bengali; verify wrapping.
- **Reduced-motion is mandatory.** Every motion primitive collapses to an instant/fade end-state when `MediaQuery.disableAnimations` is true (OS reduce-motion / web `prefers-reduced-motion`). Animations are transform/opacity-based for 60fps on the web (CanvasKit); blur is capped.
- **Goldens are regenerated deliberately.** The gallery golden suite (`test/golden/gallery_golden_test.dart`, 2 viewports × 2 brightnesses) changes with the re-theme; each visual task regenerates the goldens it affects so `flutter test` stays green between tasks. The golden freeze already disables tickers (`TickerMode(enabled: false)`), so motion stays deterministic.
- **AA contrast + CVD** on new gradient/glass surfaces; extend `design/PALETTE.md`'s validation approach (the repo already validates its palette).
- **Windows note:** `flutter test` runs green; `dart run build_runner build --delete-conflicting-outputs` regenerates `*.freezed.dart` (do not stage generated files — they are git-ignored).

---

## File Structure

```
pubspec.yaml                                   + flutter_animate

lib/app/theme/tokens.dart                      expressive dark-first surfaces, cyan accent,
                                               glass tokens, BmdGradient, BmdTokens ext fields
lib/app/theme/bmd_theme.dart                   wire new tokens; displayHero text role; glass card theme
design/src/tokens.css                          mirror the new tokens

lib/core/motion/motion_tokens.dart             NEW — durations + curves + reduced-motion helper
lib/core/motion/reveal.dart                    NEW — staggered fade-and-rise
lib/core/motion/count_up.dart                  NEW — animated numeric value
lib/core/motion/shimmer.dart                   NEW — skeleton shimmer loader
lib/core/motion/transitions.dart              NEW — GoRouter CustomTransitionPage builders
lib/app/router/app_router.dart                 apply transitions to routes; / -> DashboardScreen

lib/core/design_system/bmd_cards.dart          KpiCard/ExceptionCard: glass + motion (API unchanged)
lib/core/design_system/bmd_button.dart         press-spring micro-interaction (API + a11y unchanged)

lib/features/dashboard/application/dashboard_notifier.dart   NEW — composes existing providers
lib/features/dashboard/presentation/dashboard_screen.dart    NEW — hero/exceptions/kpi/dataviz
lib/features/dashboard/presentation/widgets/*.dart           NEW — hero header, exception strip, kpi grid, funnel/status charts

test/golden/gallery_golden_test.dart + goldens/    regenerated + new dashboard goldens
test/core/motion/*_test.dart                    NEW — reduced-motion + primitive behavior
test/features/dashboard/*_test.dart             NEW — notifier + screen state tests
```

---

### Task 1: Motion foundation — tokens, engine, reduced-motion helper

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/motion/motion_tokens.dart`
- Create: `test/core/motion/motion_tokens_test.dart`

**Interfaces:**
- Produces: `abstract final class MotionDur { static const fast = Duration(milliseconds: 120); static const base = Duration(milliseconds: 240); static const slow = Duration(milliseconds: 400); }`; `abstract final class MotionCurve { static const emphasized = Curves.easeOutCubic; static const spring = Cubic(0.34, 1.56, 0.64, 1.0); }`; `bool motionOff(BuildContext) => MediaQuery.maybeOf(context)?.disableAnimations ?? false;` and `Duration reduced(BuildContext c, Duration d) => motionOff(c) ? Duration.zero : d;`.

- [ ] **Step 1: Add the animation engine**

In `pubspec.yaml` under `dependencies:` (alphabetical), add `flutter_animate: ^4.5.0`. Run `flutter pub get`.

- [ ] **Step 2: Write the failing test**

`test/core/motion/motion_tokens_test.dart`:

```dart
import 'package:acsl_campaign/core/motion/motion_tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('durations ascend fast<base<slow', () {
    expect(MotionDur.fast < MotionDur.base, isTrue);
    expect(MotionDur.base < MotionDur.slow, isTrue);
  });

  testWidgets('reduced() zeroes a duration when animations are disabled',
      (tester) async {
    late Duration got;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (c) {
        got = reduced(c, MotionDur.base);
        return const SizedBox();
      }),
    ));
    expect(got, Duration.zero);
  });

  testWidgets('reduced() keeps the duration when animations are enabled',
      (tester) async {
    late Duration got;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: false),
      child: Builder(builder: (c) { got = reduced(c, MotionDur.base); return const SizedBox(); }),
    ));
    expect(got, MotionDur.base);
  });
}
```

- [ ] **Step 3: Run — confirm failure**

Run: `flutter test test/core/motion/motion_tokens_test.dart`
Expected: FAIL — `motion_tokens.dart` missing.

- [ ] **Step 4: Implement**

`lib/core/motion/motion_tokens.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Motion durations. Kept in one place so the whole app moves at one tempo.
abstract final class MotionDur {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 400);
}

/// Easing. `emphasized` for entrances/exits; `spring` for tactile feedback.
abstract final class MotionCurve {
  static const emphasized = Curves.easeOutCubic;
  static const spring = Cubic(0.34, 1.56, 0.64, 1.0);
}

/// True when the OS "reduce motion" setting (or web prefers-reduced-motion) is on.
bool motionOff(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// A duration that collapses to zero under reduced-motion — the single guard
/// every motion primitive routes through.
Duration reduced(BuildContext context, Duration d) =>
    motionOff(context) ? Duration.zero : d;
```

- [ ] **Step 5: Run — must pass**

Run: `flutter test test/core/motion/motion_tokens_test.dart`
Expected: 3 tests pass.

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format --set-exit-if-changed lib/core/motion test/core/motion pubspec.yaml
flutter analyze --fatal-infos lib/core/motion
git add pubspec.yaml pubspec.lock lib/core/motion/motion_tokens.dart test/core/motion/motion_tokens_test.dart
git commit -m "feat(motion): motion tokens + reduced-motion guard + flutter_animate"
```

---

### Task 2: Expressive tokens — dark-first surfaces, cyan accent, glass, gradients

**Files:**
- Modify: `lib/app/theme/tokens.dart`
- Modify: `design/src/tokens.css`
- Create: `test/app/theme/expressive_tokens_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: on `BmdColor` — `accentCyan = Color(0xFF22D3EE)`, `accentCyanDeep = Color(0xFF0E7490)` (light-mode AA), `glassFillDark = Color(0x14FFFFFF)`, `glassBorderDark = Color(0x24FFFFFF)`, `glassFillLight = Color(0xC2FFFFFF)`, `glassBorderLight = Color(0x1F2B3674)`; new `BmdTokens` fields `accent`, `accentOn`, `glassFill`, `glassBorder`, `heroGlow`; `abstract final class BmdGradient { static LinearGradient heroMesh(bool isDark); static RadialGradient glow(bool isDark); }`.

**Context:** `BmdColor` is a static palette; `BmdTokens` is a `ThemeExtension` with `light`/`dark` const instances, `copyWith`, and `lerp` — ANY new field must be added to the constructor, the field list, both `light`/`dark` statics, `copyWith`, AND `lerp` (see `tokens.dart:142-347`). `BmdColor.darkSurfaceBase` is already the navy-black `#0D1020` — reuse it as the dark expressive base (no change needed there).

- [ ] **Step 1: Write the failing test**

`test/app/theme/expressive_tokens_test.dart`:

```dart
import 'dart:math' as math;

import 'package:acsl_campaign/app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// WCAG relative luminance + contrast ratio, for the AA assertion.
double _lum(Color c) {
  double ch(int v) {
    final s = v / 255.0;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
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
    expect(g.colors, contains(BmdColor.ink700));     // navy
    expect(g.colors.any((c) => c == BmdColor.accentCyan), isTrue);
  });

  test('BmdTokens.lerp handles the new fields (no crash, midpoint valid)', () {
    final mid = BmdTokens.light.lerp(BmdTokens.dark, 0.5);
    expect(mid.accent, isNotNull);
    expect(mid.glassFill, isNotNull);
  });

  test('the dark cyan accent clears 3:1 on the dark base (large UI accent)', () {
    expect(_contrast(BmdColor.accentCyan, BmdColor.darkSurfaceBase),
        greaterThanOrEqualTo(3.0));
  });
}
```

- [ ] **Step 2: Run — confirm failure**

Run: `flutter test test/app/theme/expressive_tokens_test.dart`
Expected: FAIL — the new members don't exist.

- [ ] **Step 3: Add the palette + gradient tokens**

In `tokens.dart` `BmdColor`, add (after the dark-mode block):

```dart
  // --- Expressive accent (slice 1) ----------------------------------------
  static const accentCyan = Color(0xFF22D3EE);   // electric cyan (dark hero)
  static const accentCyanDeep = Color(0xFF0E7490); // deeper cyan for AA on light
  // Glass surfaces: translucent fill + a brighter hairline, layered over the
  // tinted base. Dark uses white veils; light uses a navy-tinted veil.
  static const glassFillDark = Color(0x14FFFFFF);
  static const glassBorderDark = Color(0x24FFFFFF);
  static const glassFillLight = Color(0xC2FFFFFF);
  static const glassBorderLight = Color(0x1F2B3674);
```

Add the gradient token class (after `BmdElevation`):

```dart
/// Brand-derived gradients (spec RD.D1). Snap on a theme change rather than
/// lerp (a gradient does not belong in ColorScheme); the two variants are
/// tuned per brightness so neither sinks into its surface.
abstract final class BmdGradient {
  /// The hero mesh: red -> navy -> cyan, used behind hero headers/CTAs.
  static LinearGradient heroMesh(bool isDark) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      BmdColor.primary600,
      BmdColor.ink700,
      isDark ? BmdColor.accentCyan : BmdColor.accentCyanDeep,
    ],
    stops: const [0.0, 0.55, 1.0],
  );

  /// A soft radial glow placed behind key elements.
  static RadialGradient glow(bool isDark) => RadialGradient(
    colors: [
      (isDark ? BmdColor.accentCyan : BmdColor.accentCyanDeep)
          .withValues(alpha: isDark ? 0.22 : 0.14),
      const Color(0x00000000),
    ],
  );
}
```

- [ ] **Step 4: Extend the `BmdTokens` ThemeExtension**

Add fields `accent`, `accentOn`, `glassFill`, `glassBorder`, `heroGlow` to: the constructor (required), the field declarations, the `light` const (`accent: BmdColor.accentCyanDeep, accentOn: Colors.white, glassFill: BmdColor.glassFillLight, glassBorder: BmdColor.glassBorderLight, heroGlow: BmdColor.accentCyanDeep`), the `dark` const (`accent: BmdColor.accentCyan, accentOn: BmdColor.darkSurfaceBase, glassFill: BmdColor.glassFillDark, glassBorder: BmdColor.glassBorderDark, heroGlow: BmdColor.accentCyan`), `copyWith` (nullable params + `?? this.x`), and `lerp` (`Color.lerp(accent, other.accent, t)!` etc.). Follow the exact pattern already in the file for the other Color fields.

- [ ] **Step 5: Mirror to the CSS token layer**

In `design/src/tokens.css`, add the matching custom properties under the existing light/dark blocks: `--bmd-accent-cyan: #22D3EE;` (dark) / `#0E7490;` (light), `--bmd-glass-fill` / `--bmd-glass-border` (rgba), and a `--bmd-hero-mesh` gradient value. Match the naming convention already used in that file.

- [ ] **Step 6: Run — must pass**

Run: `flutter test test/app/theme/expressive_tokens_test.dart`
Expected: all pass. Also `flutter test test/` for the tokens' other consumers (no golden task touched yet, so nothing else should change).

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format --set-exit-if-changed lib/app/theme test/app/theme
flutter analyze --fatal-infos lib/app/theme
git add lib/app/theme/tokens.dart design/src/tokens.css test/app/theme/expressive_tokens_test.dart
git commit -m "feat(theme): expressive tokens — cyan accent, glass, brand gradients"
```

---

### Task 3: Theme wiring + display type role + regenerate gallery goldens

**Files:**
- Modify: `lib/app/theme/bmd_theme.dart`
- Modify: `test/golden/gallery_golden_test.dart` (regenerate baselines under `test/golden/goldens/`)

**Interfaces:**
- Consumes: the Task 2 tokens.
- Produces: `bmdTheme(brightness)` renders the expressive language; an extension `extension BmdTextRoles on BuildContext { TextStyle get displayHero; }` returning the hero display style (Inter, ~72px desktop, w800, tracking -1.5, color `bmd.textHeading`).

**Context:** `bmdTheme` builds `ColorScheme.fromSeed` then overrides, plus a hand-built `textTheme` (`bmd_theme.dart:60-136`), plus per-component themes. `displayLarge` is 48px. Fonts are set via `_wght(FontWeight)` → `FontVariation('wght', …)` — the display role MUST use `fontVariations`, not `fontWeight` alone.

- [ ] **Step 1: Add the `displayHero` role**

In `bmd_theme.dart`, add a top-level extension (below `bmdTheme`):

```dart
/// The expressive hero display role (spec RD.D2). Not a Material TextTheme slot
/// (those are full), so it is exposed on BuildContext. Desktop size; the
/// responsive layer steps it down on mobile like the rest of the scale.
extension BmdTextRoles on BuildContext {
  TextStyle get displayHero => TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const ['NotoSansBengali'],
    fontSize: 72,
    height: 76 / 72,
    fontWeight: FontWeight.w800,
    fontVariations: const [FontVariation('wght', 800)],
    letterSpacing: -1.5,
    color: Theme.of(this).bmd.textHeading,
  );
}
```

- [ ] **Step 2: Wire the expressive surfaces**

In `bmdTheme`, apply the expressive dark-first look through the existing override sites (do NOT restructure): confirm dark `scaffoldBackgroundColor`/`surfaceContainerLowest` use `BmdColor.darkSurfaceBase` (already navy-black — good). Add a reusable glass `CardThemeData` variant is NOT needed globally (dense cards keep hairlines); glass is applied per-widget in Task 5. Keep all existing component themes. This step is minimal by design — the palette does the heavy lifting; the visible change is the accent + gradients used by components/dashboard, not a wholesale surface swap.

- [ ] **Step 3: Regenerate the gallery goldens**

The token additions do not change existing component pixels yet (accent/gradient/glass are consumed in Tasks 5/7), so goldens likely still match. Run the golden suite; if any differ (e.g. a lerp/const change shifted a pixel), regenerate with `--update-goldens` and eyeball the diff to confirm it is intentional:

Run: `flutter test test/golden/gallery_golden_test.dart`
If mismatches: `flutter test test/golden/gallery_golden_test.dart --update-goldens`, then inspect `git diff --stat test/golden/goldens/` (only intentional changes).

- [ ] **Step 4: Verify the app builds + full suite**

Run: `flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs`, then `flutter analyze --fatal-infos`, then `flutter test`.
Expected: analyze clean; suite green.

- [ ] **Step 5: Format, commit**

```bash
dart format --set-exit-if-changed lib/app/theme
git add lib/app/theme/bmd_theme.dart test/golden/gallery_golden_test.dart test/golden/goldens
git commit -m "feat(theme): wire expressive tokens; add displayHero role; refresh goldens"
```

---

### Task 4: Motion primitives — transitions, staggered reveal, count-up, shimmer

**Files:**
- Create: `lib/core/motion/transitions.dart`, `reveal.dart`, `count_up.dart`, `shimmer.dart`
- Modify: `lib/app/router/app_router.dart`
- Create: `test/core/motion/primitives_test.dart`

**Interfaces:**
- Consumes: `MotionDur`, `MotionCurve`, `reduced`, `motionOff` (Task 1); `BmdTokens` glass/accent (Task 2).
- Produces:
  - `Page<T> fadeThroughPage<T>({required LocalKey key, required Widget child})` and `sharedAxisPage<T>(...)` — GoRouter `CustomTransitionPage` builders.
  - `class Reveal extends StatelessWidget { const Reveal({required this.index, required this.child}); }` — fades-and-rises `child` with a per-`index` stagger delay; instant under reduced-motion.
  - `class CountUp extends StatelessWidget { const CountUp(this.value, {this.style, this.suffix}); final num value; }` — animates 0→value; shows the final value instantly under reduced-motion.
  - `class Shimmer extends StatelessWidget { const Shimmer({required this.width, required this.height}); }` — a skeleton block with a moving highlight; a static block under reduced-motion.

- [ ] **Step 1: Write the failing tests**

`test/core/motion/primitives_test.dart` — assert reduced-motion behavior (the load-bearing guarantee):

```dart
// CountUp shows the final value immediately under reduced motion.
testWidgets('CountUp renders the target value instantly when motion is off',
    (tester) async {
  await tester.pumpWidget(_wrap(disableAnimations: true, child: const CountUp(42)));
  await tester.pump(); // no time advance
  expect(find.text('42'), findsOneWidget);
});

// Reveal shows its child at full opacity immediately under reduced motion.
testWidgets('Reveal shows child instantly when motion is off', (tester) async {
  await tester.pumpWidget(_wrap(disableAnimations: true,
      child: const Reveal(index: 3, child: Text('hi'))));
  await tester.pump();
  final op = tester.widget<Opacity>(find.ancestor(
      of: find.text('hi'), matching: find.byType(Opacity)).first);
  expect(op.opacity, 1.0);
});

// With motion on, CountUp starts below the target and reaches it.
testWidgets('CountUp animates to the target when motion is on', (tester) async {
  await tester.pumpWidget(_wrap(disableAnimations: false, child: const CountUp(42)));
  await tester.pump(const Duration(milliseconds: 10));
  expect(find.text('42'), findsNothing); // mid-flight
  await tester.pumpAndSettle();
  expect(find.text('42'), findsOneWidget);
});
```

Provide the `_wrap({required bool disableAnimations, required Widget child})` helper wrapping the child in `MaterialApp` + `MediaQuery(disableAnimations:)` + the theme.

- [ ] **Step 2: Run — confirm failure**

Run: `flutter test test/core/motion/primitives_test.dart`
Expected: FAIL — primitives missing.

- [ ] **Step 3: Implement the primitives**

Build each in its file. `CountUp` uses `TweenAnimationBuilder<double>` with `duration: reduced(context, MotionDur.slow)` and `curve: MotionCurve.emphasized`, formatting `value.round()` (or with `suffix`). `Reveal` uses `flutter_animate` (`.animate().fadeIn(duration: reduced(context, MotionDur.base), delay: reduced(context, Duration(milliseconds: 40*index))).slideY(begin: 0.08, end: 0)`), wrapped so under reduced-motion it renders the child at opacity 1 / offset 0 (guard with `motionOff(context)`). `Shimmer` is a `DecoratedBox` skeleton with a `flutter_animate` shimmer effect gated on `!motionOff`. `transitions.dart` returns `CustomTransitionPage` with a `FadeTransition`/`SlideTransition` using `MotionDur.base` and `MotionCurve.emphasized`.

- [ ] **Step 4: Apply route transitions**

In `app_router.dart`, wrap each `GoRoute`'s `builder` result in a `pageBuilder` returning `fadeThroughPage(key: state.pageKey, child: <screen>)` (peer/tab routes) or `sharedAxisPage(...)` (drill-down routes like `/verification/cases/:id`). Preserve every existing route path, guard, and the screens themselves. Do not change any `Semantics(identifier:)`.

- [ ] **Step 5: Run tests + full suite**

Run: `flutter test test/core/motion/primitives_test.dart`, then `flutter test`.
Expected: primitive tests pass; suite green (route transitions don't change widget-test assertions, which pump-and-settle).

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format --set-exit-if-changed lib/core/motion lib/app/router test/core/motion
flutter analyze --fatal-infos lib/core/motion lib/app/router
git add lib/core/motion lib/app/router/app_router.dart test/core/motion/primitives_test.dart
git commit -m "feat(motion): route transitions, staggered Reveal, CountUp, Shimmer (reduced-motion safe)"
```

---

### Task 5: Component uplift — glass KPI/Exception cards + button spring

**Files:**
- Modify: `lib/core/design_system/bmd_cards.dart`
- Modify: `lib/core/design_system/bmd_button.dart`
- Modify: `test/golden/gallery_golden_test.dart` (regenerate affected goldens)

**Interfaces:**
- Consumes: `BmdTokens.glassFill/glassBorder/accent` (Task 2); `MotionCurve.spring`, `reduced`, `motionOff` (Tasks 1/4).
- Produces: no API change. `KpiCard`/`ExceptionCard` gain an optional `bool glass = false` param (default false → existing look; true → glass surface). `BmdButton` gains an internal press-spring (no new param).

**Context:** `KpiCard`/`ExceptionCard` are in `bmd_cards.dart`; their required fields must stay. `BmdButton` has 5 variants and the documented `enabled:`-semantics workaround (`bmd_button.dart:42-61`) — DO NOT alter the Semantics/enabled wiring. The gallery golden renders both at 2 viewports × 2 brightnesses.

- [ ] **Step 1: Add the `glass` option to the cards**

Add `this.glass = false` to `KpiCard` and `ExceptionCard` constructors (optional, defaulted → zero behavior change for existing callers). When `glass` is true, render the card's container with `color: bmd.glassFill`, `border: Border.all(color: bmd.glassBorder)`, `BmdElevation.level2` (soft ambient), and the existing radius/padding. When false, the current look is unchanged. Keep every required field and all existing sub-content (delta arrow, definition tooltip, source/freshness footer, age-pressure bar).

- [ ] **Step 2: Add the button press-spring**

In `bmd_button.dart`, wrap the button child in a tap-scale micro-interaction: on tap-down scale to 0.97 with `MotionCurve.spring` over `MotionDur.fast`, back on release — but ONLY when `!motionOff(context)`. This must not change the tap target, the `onPressed` wiring, or any `Semantics`/`enabled:` behavior (the workaround lines stay verbatim). Under reduced-motion the scale is fixed at 1.0.

- [ ] **Step 3: Show the glass variant in the gallery + regenerate goldens**

In `GalleryScreen` (rendered by the golden test — find it under `lib/features/gallery/`), add a glass `KpiCard`/`ExceptionCard` example to the cards section so the new look is golden-covered. Then:

Run: `flutter test test/golden/gallery_golden_test.dart --update-goldens`, and `git diff --stat test/golden/goldens/` — confirm the diffs are the intended card/button changes only.

- [ ] **Step 4: Run the full suite**

Run: `flutter analyze --fatal-infos lib/core/design_system`, then `flutter test`.
Expected: analyze clean; suite green (existing card/button tests still pass — APIs unchanged; goldens updated).

- [ ] **Step 5: Format, commit**

```bash
dart format --set-exit-if-changed lib/core/design_system
git add lib/core/design_system/bmd_cards.dart lib/core/design_system/bmd_button.dart lib/features/gallery test/golden/gallery_golden_test.dart test/golden/goldens
git commit -m "feat(ds): glass KPI/Exception cards + button press-spring (APIs unchanged)"
```

---

### Task 6: Dashboard data — the compose-from-existing notifier

**Files:**
- Create: `lib/features/dashboard/application/dashboard_notifier.dart`
- Create: `test/features/dashboard/dashboard_notifier_test.dart`

**Interfaces:**
- Consumes: existing Riverpod providers/repositories for campaigns, verification queue, sessions, registrations, imports, sync (discover the exact provider names under `lib/app/di/providers.dart` and each feature's `application/`).
- Produces:
  - `class DashboardView { final List<DashboardException> exceptions; final List<DashboardKpi> kpis; final AttendanceFunnel funnel; final CampaignStatusBreakdown statusBreakdown; }` (+ the small value types).
  - `class DashboardNotifier extends AutoDisposeAsyncNotifier<DashboardView>` and `final dashboardProvider = AutoDisposeAsyncNotifierProvider<DashboardNotifier, DashboardView>(DashboardNotifier.new);`.

**Context:** This slice composes the dashboard on the client from existing reads (spec RD.D5 — no new server endpoint). Model the notifier on an existing one (e.g. `lib/features/verification_queue/application/verification_queue_notifier.dart` or `campaign_list_notifier.dart`) — fold the source Results, throw on Err → AsyncError. The **exception-first** ordering is a hard requirement: `exceptions` lists overdue/rejected/pending-sync/no-reference/suspected-spoof/reconciliation categories, computed from the source reads, and the view exposes them as a distinct list ahead of `kpis`.

- [ ] **Step 1: Write the failing tests**

`test/features/dashboard/dashboard_notifier_test.dart` — override the source providers with fakes returning known data; assert the notifier composes the view: the exceptions list is populated and ordered (a seeded overdue-verification count appears as an exception), the KPIs carry required fields, and an error from a source surfaces as `AsyncError`. Model the ProviderContainer + overrides setup on an existing notifier test in `test/features/`.

- [ ] **Step 2: Run — confirm failure**

Run: `flutter test test/features/dashboard/dashboard_notifier_test.dart`
Expected: FAIL — notifier missing.

- [ ] **Step 3: Implement the notifier**

Build `DashboardView` + the value types and `DashboardNotifier.build()` composing the source providers (read each via `ref.watch`, combine, throw on any Err). Compute the exception categories from the queue/sync/campaign reads. Keep it a pure composition — no new network calls beyond the existing providers.

- [ ] **Step 4: Run — must pass**

Run: `flutter test test/features/dashboard/dashboard_notifier_test.dart`
Expected: pass.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format --set-exit-if-changed lib/features/dashboard test/features/dashboard
flutter analyze --fatal-infos lib/features/dashboard
git add lib/features/dashboard/application test/features/dashboard/dashboard_notifier_test.dart
git commit -m "feat(dashboard): compose an exception-first DashboardView from existing reads"
```

---

### Task 7: The signature Dashboard screen (`/`) + data-viz + router

**Files:**
- Create: `lib/features/dashboard/presentation/dashboard_screen.dart` + `presentation/widgets/{hero_header,exception_strip,kpi_grid,attendance_funnel_chart,campaign_status_chart}.dart`
- Modify: `lib/app/router/app_router.dart` (`/` → `DashboardScreen`)
- Create: `test/features/dashboard/dashboard_screen_test.dart`
- Modify: `test/golden/gallery_golden_test.dart` OR add `test/golden/dashboard_golden_test.dart` (new dashboard goldens)

**Interfaces:**
- Consumes: `dashboardProvider` (Task 6); `context.displayHero`, `BmdGradient.heroMesh`, `BmdTokens.accent/glassFill` (Tasks 2/3); `Reveal`, `CountUp`, `Shimmer` (Task 4); glass `KpiCard`/`ExceptionCard` (Task 5); `AdaptiveScaffold`/`Breakpoint` (existing); `fl_chart`.
- Produces: `class DashboardScreen extends ConsumerWidget`, wired at `/`.

**Context:** `/` currently builds `PlaceholderScreen(title:'Campaign Dashboard', screenId:'W-01')` (`app_router.dart`). The screen sits inside `AppShell`/`AdaptiveScaffold`. Exception-first per §8.1. `fl_chart` is a dependency, unused today — a funnel is drawn as horizontal bars (`BarChart`) using `BmdTokens.funnel`; the status breakdown as a `PieChart`/`BarChart` using `BmdTokens.series`.

- [ ] **Step 1: Write the failing widget tests**

`test/features/dashboard/dashboard_screen_test.dart` — pump `DashboardScreen` with `dashboardProvider` overridden (loading → shimmer visible; data → hero + exceptions + KPIs render; error → error state). Assert **exception-first ordering**: the exception strip's first widget appears above the KPI grid in the widget tree / vertical position. Assert the hero uses `context.displayHero` text and a primary CTA with a `Semantics(identifier:)`. Give the screen's key widgets identifiers: `dashboard_hero`, `dashboard_exception_<key>`, `dashboard_kpi_<key>`, `dashboard_cta`.

- [ ] **Step 2: Run — confirm failure**

Run: `flutter test test/features/dashboard/dashboard_screen_test.dart`
Expected: FAIL — screen missing.

- [ ] **Step 3: Build the screen + widgets**

Compose top-to-bottom: `HeroHeader` (a `Container` with `BmdGradient.heroMesh(isDark)` decoration + a `BmdGradient.glow` layer, the `displayHero` greeting + session context, and the single red primary CTA), then `ExceptionStrip` (horizontally-scrollable `Reveal`-staggered glass `ExceptionCard`s with `CountUp` counts, each tappable → deep link), then `KpiGrid` (responsive grid of glass `KpiCard`s with `CountUp` values + sparkline), then the data-viz row (`AttendanceFunnelChart` + `CampaignStatusChart` via `fl_chart`, animated draw-in, hover tooltips). Loading → `Shimmer` skeletons; error/empty → the designed states pattern used elsewhere. Responsive via `Breakpoint.of(context)`.

- [ ] **Step 4: Wire the route**

In `app_router.dart`, change the `/` `GoRoute` builder from `PlaceholderScreen(...)` to `const DashboardScreen()` (keep it inside the shell, keep the route guard). Import the screen.

- [ ] **Step 5: Run tests + add dashboard goldens**

Run: `flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs`, then `flutter test test/features/dashboard/dashboard_screen_test.dart`. Then add dashboard golden coverage (desktop/mobile × light/dark) and generate baselines: `flutter test <dashboard golden file> --update-goldens`; inspect the PNGs.

- [ ] **Step 6: Full suite + analyze**

Run: `flutter analyze --fatal-infos`, then `flutter test`.
Expected: analyze clean; suite green; `/` renders the real Dashboard.

- [ ] **Step 7: Format, commit**

```bash
dart format --set-exit-if-changed lib/features/dashboard lib/app/router test/features/dashboard
git add lib/features/dashboard/presentation lib/app/router/app_router.dart test/features/dashboard test/golden
git commit -m "feat(dashboard): exception-first expressive Dashboard (hero, exceptions, KPIs, fl_chart)"
```

---

### Task 8: Bilingual + reduced-motion verification, and the final sweep

**Files:**
- Create: `test/features/dashboard/dashboard_reduced_motion_test.dart`
- Create/Modify: a Bengali display golden (follow the existing `bengali-wrapping-mobile.png` pattern in the gallery golden)
- Modify: any golden baselines still stale

**Interfaces:**
- Consumes: everything.

**Context:** the app is bilingual (EN/BN); the new `displayHero` size must render Bengali without clipping. Reduced-motion must hold end-to-end on the Dashboard.

- [ ] **Step 1: Reduced-motion end-to-end test**

`dashboard_reduced_motion_test.dart` — pump `DashboardScreen` (data overridden) inside `MediaQuery(disableAnimations: true)`; assert the KPI `CountUp`s show their final values on the first frame (no pump-and-settle) and no `Reveal` leaves a child at <1 opacity. This proves the guardrail across the composed screen.

- [ ] **Step 2: Bengali display golden**

Add a golden that renders `context.displayHero` (and a hero header) under `Locale('bn')` at a mobile viewport; generate the baseline (`--update-goldens`) and eyeball that Bengali glyphs render at the large size without clipping/synthetic-bold. (The Noto fallback + `fontVariations` handle this; the golden pins it.)

- [ ] **Step 3: Full verification**

Run: `flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs`, `flutter analyze --fatal-infos`, `flutter test` (whole suite). Confirm all goldens are committed and green, and that no `Semantics(identifier:)` string was changed across the slice (grep the diff of the whole branch for removed `identifier:` lines — there should be none, only additions).

- [ ] **Step 4: Commit**

```bash
dart format --set-exit-if-changed lib test
git add test lib
git commit -m "test(redesign): reduced-motion + Bengali display goldens; final sweep"
```

---

## Self-Review

**1. Spec coverage.** Every decision maps to a task:
- RD.D1 (expressive palette / dark-first / gradients / cyan) → Task 2 (tokens) + Task 3 (theme).
- RD.D2 (expressive Inter display type) → Task 3 (`displayHero`) + Task 8 (Bengali golden).
- RD.D3 (motion system) → Task 1 (tokens/engine/reduced-motion) + Task 4 (primitives).
- RD.D4 (re-theme not rewrite; component uplift, APIs unchanged) → Task 3 (theme) + Task 5 (components).
- RD.D5 (exception-first Dashboard, compose client-side) → Task 6 (notifier) + Task 7 (screen).
- RD.D6 (identifiers, bilingual, a11y, perf preserved) → Global Constraints + Task 4/5 (reduced-motion in primitives/button) + Task 8 (reduced-motion e2e + Bengali + identifier-diff check).
- Testing §4 → goldens regenerated per visual task (3/5/7), reduced-motion tests (1/4/8), dashboard state tests (6/7), Bengali golden (8).
- Out-of-scope (Analytics, web shell/landing, per-screen polish, illustration, dashboard aggregate API, manual theme toggle) → not implemented, named in the spec.

**2. Placeholder scan.** Each code step carries concrete Dart + concrete token values (hexes, durations). The one scaffold-y block (the `_lum` luminance helper in Task 2's test) is explicitly flagged to be replaced with a real `dart:math` `pow` implementation + one concrete AA assertion; the four behavior tests around it are concrete. Creative pixel values (exact glass opacity, chart sizing) are bounded by the goldens + AA/CVD gates rather than left vague.

**3. Type consistency.** `MotionDur`/`MotionCurve`/`reduced`/`motionOff` (Task 1) are used by Tasks 4/5/7/8. `BmdColor.accentCyan`, `BmdTokens.accent/glassFill/glassBorder/heroGlow`, `BmdGradient.heroMesh/glow` (Task 2) are consumed by Tasks 3/5/7. `context.displayHero` (Task 3) is used by Task 7/8. `Reveal`/`CountUp`/`Shimmer` (Task 4) are used by Task 7/8. `dashboardProvider`/`DashboardView` (Task 6) feeds Task 7. Component `glass` params (Task 5) are used by Task 7. Every `Semantics(identifier:)` is additive (new `dashboard_*` ids); none renamed.
