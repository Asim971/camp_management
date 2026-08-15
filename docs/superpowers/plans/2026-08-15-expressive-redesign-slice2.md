# Expressive Redesign Slice 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the merged slice-1 expressive language to the four high-traffic operator screens — verification queue, CRM case, campaign list, campaign detail — via two new shared primitives (`ScreenHero`, `BmdStateView`), a uniform recipe, and one signature moment per screen.

**Architecture:** Purely presentational — no provider, domain, routing or wire changes. Two new design-system primitives are built and gallery-registered first; each screen then gets one task applying the shared recipe (hero header, capped `Reveal` stagger, designed states, glass on hero-adjacent surfaces only) plus its signature moment. Screen goldens land last.

**Tech Stack:** Flutter 3.44.8 / Dart 3.12, Material 3, Riverpod, GoRouter, flutter_animate 4.5.2 (all already in the lockfile — no new packages).

**Spec:** `docs/superpowers/specs/2026-08-15-expressive-redesign-slice2-design.md`

## Global Constraints

- **Frozen contracts:** every existing `Semantics(identifier:)` string, route path, provider API and interaction flow stays byte-identical. The ONLY additive identifier is `crm_zoom_sync`. All 20 Maestro flows and all existing widget tests must pass unmodified.
- **Reduced motion:** every animation added is gated through `motionOff(context)` / `reduced(context, d)` from `lib/core/motion/motion_tokens.dart` — single-frame final state when `MediaQuery.disableAnimations` is true.
- **Brand:** red `#E71E25` (`BmdColor.primary600`) remains the only primary-action color; cyan `#22D3EE` (`BmdTokens.accent`) is accent/data only (meter fill, glow, selected series).
- **Density:** `BmdDataTable` and dense rows keep hairline elevation-0 treatment (slice-1 RD.D1).
- **Quality gates per task:** `dart format` clean, `flutter analyze --fatal-infos` clean **project-wide**, and the tests the task touches green. Full `flutter test` in the final task.
- **Goldens:** `goldenTest` (from `test/support/golden.dart`) is Linux-gated — new golden tests are written but their `.png` baselines are NOT generated or committed in any task; they are produced by dispatching `.github/workflows/goldens.yml` on the branch and committing the `golden-baselines` artifact (the controller does this before merge, as in slice 1).
- `ENABLE_TEST_SEEDING` is never committed enabled anywhere.
- Work happens on branch `feat/expressive-redesign-slice2` off `main`.
- Widget-test note (Flutter 3.44.8): set viewport via `tester.view.physicalSize` + `devicePixelRatio = 1.0` + `addTearDown(tester.view.reset)`; `setSurfaceSize` does not drive `MediaQuery.sizeOf`.
- Token names (exact): `bmd.textHeading`, `bmd.textSecondary`, `bmd.textFaint`, `bmd.surfaceSunken`, `bmd.glassFill`, `bmd.glassBorder`, `bmd.accent`, `bmd.success/warning/error/info/neutral`, `bmd.tintSuccess/tintWarning/tintError/tintInfo/tintNeutral`. Spacing `BmdSpace.s1..s10` (4..64). Radius `BmdRadius.chip = 6`, `BmdRadius.card = 12`. Do NOT invent `textMuted` — the muted text token is `textSecondary`.

---

## File map

| File | Task | Change |
|---|---|---|
| `lib/app/theme/bmd_theme.dart` | 1 | add `displayTitle` to `BmdTextRoles` |
| `lib/core/design_system/screen_hero.dart` | 1 | new |
| `lib/core/design_system/bmd_state_view.dart` | 2 | new |
| `lib/features/gallery/presentation/gallery_screen.dart` | 1, 2 | register new sections |
| `lib/features/verification_queue/presentation/verification_queue_screen.dart` | 3 | recipe + S1 |
| `lib/features/crm_case/presentation/crm_case_screen.dart` | 4 | recipe + S2 |
| `lib/features/campaign_list/presentation/campaign_list_screen.dart` | 5 | recipe + S3 |
| `lib/features/campaign_detail/presentation/campaign_detail_screen.dart` | 6 | recipe + S4 |
| `test/golden/screens_golden_test.dart` | 7 | new — 8 screen baselines |

---

### Task 1: `displayTitle` text role + `ScreenHero` primitive + gallery section

**Files:**
- Modify: `lib/app/theme/bmd_theme.dart` (extension `BmdTextRoles`, ~line 315)
- Create: `lib/core/design_system/screen_hero.dart`
- Modify: `lib/features/gallery/presentation/gallery_screen.dart`
- Test: `test/core/design_system/screen_hero_test.dart`

**Interfaces:**
- Consumes: `BmdGradient.heroMesh(bool isDark)`, `BmdGradient.glow(bool isDark)`, `BmdTokens` via `Theme.of(context).bmd`, `BmdSpace`, `BmdRadius` (all in `lib/app/theme/tokens.dart`).
- Produces: `TextStyle get displayTitle` on `BuildContext` (via `BmdTextRoles`), and
  `ScreenHero({required String title, String? subtitle, List<Widget> summary = const [], List<Widget> actions = const [], Widget? meter, Key? key})` — Tasks 3–6 build against exactly this signature.

- [ ] **Step 1: Write the failing test**

Create `test/core/design_system/screen_hero_test.dart`:

```dart
import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/core/design_system/screen_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: bmdTheme(brightness: Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('displayTitle role is 30px, w700 via fontVariations, tight '
      'tracking', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            style = context.displayTitle;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(style.fontSize, 30);
    expect(style.fontVariations, contains(const FontVariation('wght', 700)));
    expect(style.letterSpacing, -0.5);
  });

  testWidgets('ScreenHero renders title in displayTitle size and every '
      'populated slot', (tester) async {
    await tester.pumpWidget(
      _host(
        ScreenHero(
          title: 'Campaigns',
          subtitle: 'All campaigns in scope',
          summary: const [Text('12 total')],
          actions: const [Text('Create')],
          meter: const Text('meter-slot'),
        ),
      ),
    );
    final title = tester.widget<Text>(find.text('Campaigns'));
    expect(title.style?.fontSize, 30);
    expect(find.text('All campaigns in scope'), findsOneWidget);
    expect(find.text('12 total'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('meter-slot'), findsOneWidget);
  });

  testWidgets('ScreenHero omits unpopulated slots', (tester) async {
    await tester.pumpWidget(_host(const ScreenHero(title: 'Queue')));
    expect(find.text('Queue'), findsOneWidget);
    // Only the title paints — no Wrap rows for empty summary/actions.
    expect(find.byType(Wrap), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/design_system/screen_hero_test.dart`
Expected: FAIL — `screen_hero.dart` does not exist / `displayTitle` undefined.

- [ ] **Step 3: Add `displayTitle` to `BmdTextRoles`**

In `lib/app/theme/bmd_theme.dart`, inside `extension BmdTextRoles on BuildContext` (directly after the `displayHero` getter):

```dart
  /// Section-hero display role (slice 2 RD2.D1): [ScreenHero] titles. Between
  /// titleLarge and [displayHero]; w700 via fontVariations like the rest of
  /// the scale — never a synthetic bold.
  TextStyle get displayTitle => TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const ['NotoSansBengali'],
    fontSize: 30,
    height: 36 / 30,
    fontWeight: FontWeight.w700,
    fontVariations: const [FontVariation('wght', 700)],
    letterSpacing: -0.5,
    color: Theme.of(this).bmd.textHeading,
  );
```

(Also update the doc comment above the extension from "role" to "roles" if it reads singular.)

- [ ] **Step 4: Create `lib/core/design_system/screen_hero.dart`**

```dart
import 'package:flutter/material.dart';

import '../../app/theme/bmd_theme.dart';
import '../../app/theme/tokens.dart';

/// A compact expressive header band for operational screens (slice 2 RD2.D1)
/// — the Dashboard hero's little sibling. Content-hugging (~96–120px
/// typical), never full-bleed: [BmdGradient.heroMesh] painted at low opacity
/// over the surface color so it reads as a tinted band, with a faint
/// [BmdGradient.glow] in one corner.
///
/// Static by construction — the band itself never animates; only slotted
/// children (e.g. `CountUp`s in [summary]) do, and those already respect
/// `motionOff`.
class ScreenHero extends StatelessWidget {
  const ScreenHero({
    required this.title,
    this.subtitle,
    this.summary = const [],
    this.actions = const [],
    this.meter,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Live chips/labels (screens put `CountUp` numbers here). Rendered as a
  /// [Wrap] so they flow on narrow viewports.
  final List<Widget> summary;

  /// Buttons that belong to this screen's header. A [Wrap], for the same
  /// reason the campaign-detail header uses one: a Row squeezes the title to
  /// nothing once a second button appears on a narrow viewport.
  final List<Widget> actions;

  /// Optional full-width row under the title block (e.g. campaign detail's
  /// attendance progress meter).
  final Widget? meter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: bmd.glassBorder),
        borderRadius: BorderRadius.circular(BmdRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BmdRadius.card),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: theme.colorScheme.surface),
            ),
            // The mesh at band opacity — a tint, not a poster.
            Positioned.fill(
              child: Opacity(
                opacity: isDark ? 0.18 : 0.12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: BmdGradient.heroMesh(isDark),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -40,
              top: -40,
              width: 220,
              height: 220,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: BmdGradient.glow(isDark)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(BmdSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.displayTitle,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: BmdSpace.s1),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: bmd.textSecondary,
                      ),
                    ),
                  ],
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: BmdSpace.s3),
                    Wrap(
                      spacing: BmdSpace.s3,
                      runSpacing: BmdSpace.s2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: summary,
                    ),
                  ],
                  if (meter != null) ...[
                    const SizedBox(height: BmdSpace.s3),
                    meter!,
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: BmdSpace.s4),
                    Wrap(
                      spacing: BmdSpace.s2,
                      runSpacing: BmdSpace.s2,
                      children: actions,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/design_system/screen_hero_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Register the gallery section**

In `lib/features/gallery/presentation/gallery_screen.dart`:

1. Import: `import '../../../core/design_system/screen_hero.dart';`
2. In `abstract final class GallerySection`, add
   `static const screenHero = 'gallery_screen_hero';` and append
   `screenHero` to the `all` list.
3. In `gallerySections()`, append:

```dart
  GallerySectionView(
    id: GallerySection.screenHero,
    title: 'Screen hero',
    child: _ScreenHeroDemo(),
  ),
```

4. Add the demo widget at the end of the file:

```dart
class _ScreenHeroDemo extends StatelessWidget {
  const _ScreenHeroDemo();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHero(title: 'Verification queue'),
        const SizedBox(height: BmdSpace.s4),
        ScreenHero(
          title: 'Campaigns',
          subtitle: 'All campaigns in scope',
          summary: const [
            StatusChip(label: '12 total', tone: StatusTone.neutral),
            StatusChip(label: '7 active', tone: StatusTone.info),
          ],
          actions: [
            BmdButton(
              label: 'Create campaign',
              variant: BmdButtonVariant.outlined,
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }
}
```

NOTE: `gallerySections()` is currently declared `=> const [...]` — the new
entry keeps every element `const`-constructible except `_ScreenHeroDemo`'s
second hero (it takes a closure), so `_ScreenHeroDemo` itself is the only
non-const part and it is fine: the list literal stays `const` because
`GallerySectionView(... child: _ScreenHeroDemo())` with a const constructor
IS const. If the analyzer disagrees (the `onPressed: () {}` lives inside the
demo's build, not the list), keep the list `const` — the closure is inside
`_ScreenHeroDemo.build`, which does not affect the list's constness.

- [ ] **Step 7: Verify quality gates**

Run: `dart format lib/core/design_system/screen_hero.dart lib/app/theme/bmd_theme.dart lib/features/gallery/presentation/gallery_screen.dart test/core/design_system/screen_hero_test.dart`
Run: `flutter analyze --fatal-infos`
Run: `flutter test test/core/design_system/screen_hero_test.dart test/golden/ test/widget/`
Expected: all clean (goldens skip on Windows; the gallery golden test picks up the new section automatically — it iterates `GallerySection.all` — and will need Linux baselines later, which is expected).

- [ ] **Step 8: Commit**

```bash
git add lib/app/theme/bmd_theme.dart lib/core/design_system/screen_hero.dart lib/features/gallery/presentation/gallery_screen.dart test/core/design_system/screen_hero_test.dart
git commit -m "feat(ds): ScreenHero header band + displayTitle role (slice 2 RD2.D1)"
```

---

### Task 2: `BmdStateView` primitive + gallery section

**Files:**
- Create: `lib/core/design_system/bmd_state_view.dart`
- Modify: `lib/features/gallery/presentation/gallery_screen.dart`
- Test: `test/core/design_system/bmd_state_view_test.dart`

**Interfaces:**
- Consumes: `Reveal` (`lib/core/motion/reveal.dart` — `Reveal({required int index, required Widget child})`), `BmdButton` (`lib/core/design_system/bmd_button.dart`), `BmdTokens` tint/tone colors.
- Produces:
  `BmdStateView.empty({required String title, required String message, IconData icon = Icons.inbox_outlined, Widget? action, Key? key})` and
  `BmdStateView.error({required String title, required String message, required VoidCallback onRetry, Key? key})` — Tasks 3–6 build against exactly these.

- [ ] **Step 1: Write the failing test**

Create `test/core/design_system/bmd_state_view_test.dart`:

```dart
import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/core/design_system/bmd_state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: bmdTheme(brightness: Brightness.light),
  // disableAnimations so Reveal renders its final frame on the first pump.
  home: MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('empty variant renders icon, title, message and optional '
      'action', (tester) async {
    await tester.pumpWidget(
      _host(
        BmdStateView.empty(
          title: 'No cases in this view',
          message: 'Claimed and escalated cases appear under their tabs.',
          action: const Text('action-slot'),
        ),
      ),
    );
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('No cases in this view'), findsOneWidget);
    expect(find.text('action-slot'), findsOneWidget);
  });

  testWidgets('error variant renders a Retry button wired to onRetry',
      (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      _host(
        BmdStateView.error(
          title: "Couldn't load campaigns",
          message: 'Check your connection and try again.',
          onRetry: () => retried++,
        ),
      ),
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/design_system/bmd_state_view_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Create `lib/core/design_system/bmd_state_view.dart`**

```dart
import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../motion/reveal.dart';
import 'bmd_button.dart';

/// Designed empty/error states (slice 2 RD2.D2), replacing bare centered
/// [Text]s. Typography, tone and spacing only — the icon circle is where a
/// later slice's illustration drops in.
class BmdStateView extends StatelessWidget {
  const BmdStateView.empty({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  }) : _error = false,
       onRetry = null;

  const BmdStateView.error({
    required this.title,
    required this.message,
    required VoidCallback this.onRetry,
    super.key,
  }) : _error = true,
       icon = Icons.error_outline,
       action = null;

  final String title;
  final String message;
  final IconData icon;

  /// Optional call-to-action for the empty variant (e.g. a create button).
  final Widget? action;

  /// The error variant always renders an outlined Retry button wired here.
  final VoidCallback? onRetry;

  final bool _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final toneColor = _error ? bmd.error : bmd.neutral;
    final tint = _error ? bmd.tintError : bmd.tintNeutral;

    return Center(
      child: Reveal(
        index: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
                child: Icon(icon, size: 48, color: toneColor),
              ),
              const SizedBox(height: BmdSpace.s4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: BmdSpace.s2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: bmd.textSecondary,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: BmdSpace.s4),
                BmdButton(
                  label: 'Retry',
                  variant: BmdButtonVariant.outlined,
                  onPressed: onRetry,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: BmdSpace.s4),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/design_system/bmd_state_view_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Register the gallery section**

In `lib/features/gallery/presentation/gallery_screen.dart`:

1. Import: `import '../../../core/design_system/bmd_state_view.dart';`
2. In `GallerySection`: add `static const states = 'gallery_state_views';`
   and append `states` to `all`.
3. In `gallerySections()`, append:

```dart
  GallerySectionView(
    id: GallerySection.states,
    title: 'Empty and error states',
    child: _StateViewsDemo(),
  ),
```

4. Demo widget at the end of the file:

```dart
class _StateViewsDemo extends StatelessWidget {
  const _StateViewsDemo();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(
          height: _kStateHeight,
          child: BmdStateView.empty(
            title: 'No cases in this view',
            message: 'Claimed and escalated cases appear under their tabs.',
          ),
        ),
        SizedBox(
          height: _kStateHeight,
          child: BmdStateView.error(
            title: "Couldn't load the verification queue",
            message: 'Check your connection and try again.',
            onRetry: () {},
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Verify quality gates**

Run: `dart format lib/core/design_system/bmd_state_view.dart lib/features/gallery/presentation/gallery_screen.dart test/core/design_system/bmd_state_view_test.dart`
Run: `flutter analyze --fatal-infos`
Run: `flutter test test/core/design_system/ test/widget/`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add lib/core/design_system/bmd_state_view.dart lib/features/gallery/presentation/gallery_screen.dart test/core/design_system/bmd_state_view_test.dart
git commit -m "feat(ds): BmdStateView designed empty/error states (slice 2 RD2.D2)"
```

---

### Task 3: Verification queue — recipe + S1 urgency choreography

**Files:**
- Modify: `lib/features/verification_queue/presentation/verification_queue_screen.dart`
- Test: `test/widget/verification_queue_screen_test.dart` (extend the existing file; reuse its existing fakes/harness)

**Interfaces:**
- Consumes: `ScreenHero` (Task 1), `BmdStateView` (Task 2), `Reveal`, `motionOff`, `MotionDur`, `BmdColor.accentCyan`, `BmdTokens` tones.
- Produces: nothing new for later tasks. FROZEN identifiers this task must keep byte-identical: `queue_tab_<name>`, `queue_item_<id>`, `queue_escalated_<id>`, `queue_claim_<id>`, `queue_release_<id>`.

Overview of the change (spec RD2.D4):

1. A `ScreenHero(title: 'Verification queue', subtitle: 'Prioritised by SLA and risk')` at the top of the body `Column`, padded `EdgeInsets.fromLTRB(BmdSpace.s4, BmdSpace.s4, BmdSpace.s4, 0)`; `_FilterTabs`' own top padding drops from `s4` to `s3` so the rhythm stays.
2. Each `_QueueTile` gets a 3px left accent bar (Stack overlay inside the `Card`, clipped to the card radius — the `ExceptionCard` technique from `bmd_cards.dart:305-323`; NEVER `Border(left:)` beside a radius on a uniform-border widget).
3. **Urgency ramp:** `overdue = item.age >= const Duration(hours: 24)`. Accent bar color: `overdue ? bmd.error : bandTone`. The "Waiting …" label: when overdue, `labelMedium.copyWith(color: bmd.error, fontVariations: const [FontVariation('wght', 600)])`; otherwise unchanged.
4. Band tone mapping: `high → bmd.success`, `medium → bmd.info`, `low`/`noReference → bmd.warning`.
5. Escalated chip gets a one-time entrance glow halo, skipped entirely under `motionOff`.
6. List items wrap in `Reveal(index: i < 8 ? i : 8)`.
7. `_EmptyState`/`_ErrorState` bodies become `BmdStateView.empty(...)` / `BmdStateView.error(...)`.

- [ ] **Step 1: Write the failing tests**

Append to `test/widget/verification_queue_screen_test.dart` (reuse the file's existing fake notifier + pump helper; construct `VerificationQueueItem`s exactly as the existing tests do):

```dart
  testWidgets('S1 urgency ramp: a tile past the 24h window renders its '
      '"Waiting" label in the error tone at wght 600; a fresh tile does not',
      (tester) async {
    // Two items: one at 25h (overdue), one at 2h (fresh). Use the file's
    // existing seeding pattern for verificationQueueProvider(QueueFilter.all).
    // ... pump ...
    final overdue = tester.widget<Text>(find.text('Waiting 1d'));
    final fresh = tester.widget<Text>(find.text('Waiting 2h 0m'));
    final errorColor =
        bmdTheme(brightness: Brightness.light).extension<BmdTokens>()!.error;
    expect(overdue.style?.color, errorColor);
    expect(
      overdue.style?.fontVariations,
      contains(const FontVariation('wght', 600)),
    );
    expect(fresh.style?.color, isNot(errorColor));
  });

  testWidgets('frozen identifiers survive the redesign', (tester) async {
    // Seed one unassigned item CASE_A and pump with disableAnimations: true.
    for (final id in [
      'queue_tab_all',
      'queue_tab_mine',
      'queue_tab_unassigned',
      'queue_item_CASE_A',
      'queue_claim_CASE_A',
    ]) {
      expect(
        find.bySemanticsIdentifier(id),
        findsOneWidget,
        reason: 'identifier $id must survive (Maestro contract)',
      );
    }
  });

  testWidgets('reduced motion renders the full list in a single pump',
      (tester) async {
    // Pump with MediaQueryData(disableAnimations: true) wrapped around the
    // screen (or via tester.platformDispatcher accessibility flags — follow
    // the file's existing reduced-motion pattern if one exists; otherwise
    // wrap the host in MediaQuery). One pump() — NOT pumpAndSettle — then:
    expect(find.bySemanticsIdentifier('queue_item_CASE_A'), findsOneWidget);
  });
```

(If `find.bySemanticsIdentifier` is unavailable on this Flutter version, use the file's existing identifier-locating helper — the suite already asserts identifiers, e.g. `test/widget/registration_workspace_screen_test.dart`; follow that pattern.)

- [ ] **Step 2: Run to verify the new tests fail**

Run: `flutter test test/widget/verification_queue_screen_test.dart`
Expected: the new tests FAIL (no error-tone label yet); existing tests PASS.

- [ ] **Step 3: Implement the screen changes**

In `verification_queue_screen.dart`:

Add imports:

```dart
import 'dart:ui' show FontVariation;

import '../../../app/theme/bmd_theme.dart';
import '../../../core/design_system/bmd_state_view.dart';
import '../../../core/design_system/screen_hero.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/motion/reveal.dart';
```

In the body `Column`, before `_FilterTabs`:

```dart
          const Padding(
            padding: EdgeInsets.fromLTRB(BmdSpace.s4, BmdSpace.s4, BmdSpace.s4, 0),
            child: ScreenHero(
              title: 'Verification queue',
              subtitle: 'Prioritised by SLA and risk',
            ),
          ),
```

and change `_FilterTabs`' padding top from `BmdSpace.s4` to `BmdSpace.s3`.

Item builder becomes:

```dart
                      itemBuilder: (_, i) => Reveal(
                        index: i < 8 ? i : 8,
                        child: _QueueTile(
                          item: items[i],
                          userId: userId,
                          filter: filter,
                        ),
                      ),
```

In `_QueueTile.build`, compute the tones before the return:

```dart
    final bmd = Theme.of(context).bmd;
    final overdue = item.age >= const Duration(hours: 24);
    final bandTone = switch (item.band) {
      MatchBand.high => bmd.success,
      MatchBand.medium => bmd.info,
      MatchBand.low || MatchBand.noReference => bmd.warning,
    };
    final accent = overdue ? bmd.error : bandTone;
```

Wrap the Card's child in the accent-bar Stack (the `InkWell` and everything inside it stays byte-identical):

```dart
      child: Card(
        child: Stack(
          children: [
            InkWell(
              // ... existing content, unchanged ...
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(BmdRadius.card),
                  bottomLeft: Radius.circular(BmdRadius.card),
                ),
                child: ColoredBox(color: accent),
              ),
            ),
          ],
        ),
      ),
```

The "Waiting" text becomes:

```dart
                    Text(
                      'Waiting ${_formatAge(item.age)}',
                      style: overdue
                          ? Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: bmd.error,
                              fontVariations: const [
                                FontVariation('wght', 600),
                              ],
                            )
                          : Theme.of(context).textTheme.labelMedium,
                    ),
```

The escalated chip wraps in the glow (Semantics identifier stays on the same node it is on today — the glow goes OUTSIDE the `Semantics` wrapper):

```dart
                        child: _EscalatedGlow(
                          child: Semantics(
                            identifier: 'queue_escalated_${item.attendanceId}',
                            child: const StatusChip(
                              label: 'Escalated',
                              tone: StatusTone.error,
                              icon: Icons.priority_high,
                            ),
                          ),
                        ),
```

Add at the end of the file:

```dart
/// One-time entrance halo for the Escalated chip (S1): accent-cyan glow that
/// rises and fades once. Entirely skipped under reduced motion — the chip
/// renders statically.
class _EscalatedGlow extends StatelessWidget {
  const _EscalatedGlow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (motionOff(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MotionDur.slow * 2,
      builder: (context, t, c) {
        final pulse = 1 - (2 * t - 1).abs(); // 0 → 1 → 0
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BmdRadius.chip),
            boxShadow: [
              BoxShadow(
                color: BmdColor.accentCyan.withValues(alpha: 0.24 * pulse),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: c,
        );
      },
      child: child,
    );
  }
}
```

Replace the `_EmptyState`/`_ErrorState` bodies:

```dart
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const BmdStateView.empty(
    title: 'No cases in this view',
    message: 'Claimed and escalated cases appear under their own tabs.',
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => BmdStateView.error(
    title: "Couldn't load the verification queue",
    message: 'Check your connection and try again.',
    onRetry: onRetry,
  );
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/widget/verification_queue_screen_test.dart`
Expected: ALL pass — new tests AND every pre-existing test unmodified. If a pre-existing test fails, the screen change broke a frozen contract: fix the screen, never the old test.

- [ ] **Step 5: Verify quality gates**

Run: `dart format lib/features/verification_queue/presentation/verification_queue_screen.dart test/widget/verification_queue_screen_test.dart`
Run: `flutter analyze --fatal-infos`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/verification_queue/presentation/verification_queue_screen.dart test/widget/verification_queue_screen_test.dart
git commit -m "feat(queue): expressive recipe + S1 urgency choreography (slice 2 RD2.D4)"
```

---

### Task 4: CRM case — recipe + S2 synced evidence compare

**Files:**
- Modify: `lib/features/crm_case/presentation/crm_case_screen.dart`
- Test: `test/widget/crm_case_screen_test.dart` (extend; reuse its existing case fixture + pump helper)

**Interfaces:**
- Consumes: `Reveal`, `BmdStateView`, `StatusChip` (`lib/core/design_system/status_chip.dart` — `StatusChip({required String label, required StatusTone tone, IconData? icon})`), glass tokens, `BmdElevation.level2`.
- Produces: NEW additive identifier `crm_zoom_sync` (the only one this slice adds). FROZEN identifiers kept byte-identical: `crm_outcome_<name>`, `crm_reason`, `crm_supervisor_override`, `crm_submit`.

Overview (spec RD2.D5):

1. `_EvidenceZone` becomes stateful, owning two `TransformationController`s mirrored both ways with a re-entrancy guard. "Synced zoom" `Switch` (default ON, identifier `crm_zoom_sync`) shown only when a reference image exists.
2. Machine-advisory `Card` → glass container (stays `Card`-shaped; keeps its "(advisory)" label — §8.13 framing intact). Band/PAD/low-quality `Chip`s → `StatusChip`s with tones: band `high → success`, `medium → info`, `low`/`noReference → warning`; `PAD review` and `Low quality` → warning.
3. The three zones enter with `Reveal` indices 0/1/2 (both wide and narrow layouts).
4. The bare-`BmdButton` error branch → `BmdStateView.error`.

- [ ] **Step 1: Write the failing tests**

Append to `test/widget/crm_case_screen_test.dart` (reuse its fixture; seed a case WITH `referenceImageUrl` for the sync tests and grant NO `verificationOverride` permission so the evidence-zone `Switch` is the only `Switch` in the tree):

```dart
  testWidgets('S2: panning the captured image mirrors onto the reference',
      (tester) async {
    // ... pump a case with both image URLs ...
    final viewers = tester
        .widgetList<InteractiveViewer>(find.byType(InteractiveViewer))
        .toList();
    expect(viewers, hasLength(2));
    final captured = viewers[0].transformationController!;
    final reference = viewers[1].transformationController!;

    captured.value = Matrix4.identity()..translateByDouble(-40, -20, 0, 1);
    await tester.pump();
    expect(reference.value, captured.value);
  });

  testWidgets('S2: toggling crm_zoom_sync off stops mirroring; back on '
      're-syncs', (tester) async {
    // ... pump ...
    final viewers = tester
        .widgetList<InteractiveViewer>(find.byType(InteractiveViewer))
        .toList();
    final captured = viewers[0].transformationController!;
    final reference = viewers[1].transformationController!;

    await tester.tap(find.byType(Switch));
    await tester.pump();
    captured.value = Matrix4.identity()..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    expect(reference.value, isNot(captured.value));

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(reference.value, captured.value); // re-synced on re-enable
  });

  testWidgets('S2: no reference image → no sync row', (tester) async {
    // ... pump a case with referenceImageUrl: null ...
    expect(find.text('Synced zoom'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('frozen decision identifiers survive', (tester) async {
    // ... pump ...
    for (final id in [
      'crm_outcome_approved',
      'crm_outcome_rejected',
      'crm_reason',
      'crm_submit',
    ]) {
      expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
    }
  });
```

(Matrix mutation calls: if `translateByDouble`/`scaleByDouble` don't exist on this vector_math version, use `Matrix4.translationValues(-40, -20, 0)` and `Matrix4.diagonal3Values(2, 2, 1)` — any distinct non-identity matrices work.)

- [ ] **Step 2: Run to verify the new tests fail**

Run: `flutter test test/widget/crm_case_screen_test.dart`
Expected: new tests FAIL (`transformationController` is null / no Switch); existing tests PASS.

- [ ] **Step 3: Implement**

Imports to add in `crm_case_screen.dart`:

```dart
import '../../../app/theme/tokens.dart';
import '../../../core/design_system/bmd_state_view.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../core/motion/reveal.dart';
import '../../../domain/common/status.dart';
```

Zone wrapping (both layouts):

```dart
          final evidence = Reveal(index: 0, child: _EvidenceZone(vcase: c));
          final context0 = Reveal(index: 1, child: _ContextZone(vcase: c));
          final decision = Reveal(
            index: 2,
            child: _DecisionPanel(attendanceId: attendanceId),
          );
```

Error branch:

```dart
        error: (_, __) => BmdStateView.error(
          title: "Couldn't load this case",
          message: 'Check your connection and try again.',
          onRetry: () =>
              ref.invalidate(crmCaseControllerProvider(attendanceId)),
        ),
```

`_EvidenceZone` → stateful with synced controllers:

```dart
class _EvidenceZone extends StatefulWidget {
  const _EvidenceZone({required this.vcase});
  final VerificationCase vcase;

  @override
  State<_EvidenceZone> createState() => _EvidenceZoneState();
}

class _EvidenceZoneState extends State<_EvidenceZone> {
  final _captured = TransformationController();
  final _reference = TransformationController();
  bool _synced = true;

  /// Re-entrancy guard: writing the peer's value fires ITS listener, which
  /// would write back and recurse forever without this.
  bool _mirroring = false;

  @override
  void initState() {
    super.initState();
    _captured.addListener(() => _mirror(_captured, _reference));
    _reference.addListener(() => _mirror(_reference, _captured));
  }

  void _mirror(TransformationController from, TransformationController to) {
    if (!_synced || _mirroring) return;
    _mirroring = true;
    to.value = from.value.clone();
    _mirroring = false;
  }

  @override
  void dispose() {
    _captured.dispose();
    _reference.dispose();
    super.dispose();
  }

  bool get _hasReference => widget.vcase.referenceImageUrl != null;

  @override
  Widget build(BuildContext context) {
    final vcase = widget.vcase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Evidence',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_hasReference) ...[
              Text('Synced zoom', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(width: BmdSpace.s1),
              Semantics(
                identifier: 'crm_zoom_sync',
                child: Switch(
                  value: _synced,
                  onChanged: (v) {
                    setState(() => _synced = v);
                    // Re-enabling re-syncs the reference to the captured view.
                    if (v) _reference.value = _captured.value.clone();
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _EvidenceImage(
                label: 'Captured',
                url: vcase.capturedImageUrl,
                controller: _captured,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EvidenceImage(
                label: _refLabel(vcase.machine.referenceSource),
                url: vcase.referenceImageUrl,
                controller: _reference,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _refLabel(ReferenceSource s) => switch (s) {
    ReferenceSource.verifiedProfilePhoto => 'Verified profile photo',
    ReferenceSource.authorizedNidPhoto => 'Authorized NID photo',
    ReferenceSource.approvedBaselinePhoto => 'Approved baseline photo',
    ReferenceSource.unavailable => 'No reference available',
  };
}
```

`_EvidenceImage` gains the controller (passed through; null-url branch unchanged):

```dart
class _EvidenceImage extends StatelessWidget {
  const _EvidenceImage({
    required this.label,
    required this.url,
    required this.controller,
  });
  final String label;
  final String? url;
  final TransformationController controller;
  // ... in build, the InteractiveViewer becomes:
  //   InteractiveViewer(
  //     maxScale: 4,
  //     transformationController: controller,
  //     child: Image.network( ... unchanged ... ),
  //   )
}
```

Advisory card → glass + toned chips (in `_ContextZone`):

```dart
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).bmd.glassFill,
            border: Border.all(color: Theme.of(context).bmd.glassBorder),
            borderRadius: BorderRadius.circular(BmdRadius.card),
            boxShadow: BmdElevation.level2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Machine recommendation (advisory)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  StatusChip(label: 'Band: ${_band(m.band)}', tone: _bandTone(m.band)),
                  if (m.padReview)
                    const StatusChip(label: 'PAD review', tone: StatusTone.warning),
                  if (m.lowQuality)
                    const StatusChip(label: 'Low quality', tone: StatusTone.warning),
                ],
              ),
              if (m.reasons.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final r in m.reasons) Text('• $r'),
              ],
            ],
          ),
        ),
```

with the tone helper added to `_ContextZone`:

```dart
  StatusTone _bandTone(MatchBand b) => switch (b) {
    MatchBand.high => StatusTone.success,
    MatchBand.medium => StatusTone.info,
    MatchBand.low || MatchBand.noReference => StatusTone.warning,
  };
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/widget/crm_case_screen_test.dart`
Expected: ALL pass, old and new. A pre-existing failure means a frozen contract broke — fix the screen.

- [ ] **Step 5: Quality gates**

Run: `dart format lib/features/crm_case/presentation/crm_case_screen.dart test/widget/crm_case_screen_test.dart`
Run: `flutter analyze --fatal-infos`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/crm_case/presentation/crm_case_screen.dart test/widget/crm_case_screen_test.dart
git commit -m "feat(crm): synced evidence compare + glass advisory (slice 2 RD2.D5)"
```

---

### Task 5: Campaign list — recipe + S3 living summary strip

**Files:**
- Modify: `lib/features/campaign_list/presentation/campaign_list_screen.dart`
- Test: `test/features/campaign_list/presentation/campaign_list_screen_test.dart` (extend; reuse its existing fakes)

**Interfaces:**
- Consumes: `ScreenHero`, `BmdStateView`, `CountUp` (`lib/core/motion/count_up.dart` — `CountUp(num value, {TextStyle? style, String? suffix})`).
- Produces: nothing new. FROZEN: the `BmdDataTable` config, row → side-sheet behavior, and `PermissionGate.disabled(Permission.campaignCreate, ...)` semantics (the existing tests find it by `find.byTooltip('Create campaign')` — the tooltip must survive the move into the hero).

Overview (spec RD2.D6):

1. `AppShell(title: 'Campaigns', actions: [...])` loses its `actions:`; the same `PermissionGate.disabled(...)` widget moves verbatim into the hero's `actions` slot.
2. `ScreenHero(title: 'Campaigns')` at the top of a new body `Column`; `summary` chips computed from `async.valueOrNull` (empty until data): total (`paged.total`), Active, Pending approval (both counted from `paged.items` — page-scoped by design).
3. The row-detail side sheet's content gains a 3px status-tone left bar (plain `Border(left:)` is fine here — no borderRadius on that container).
4. Empty/error → `BmdStateView`.
5. The `BmdDataTable` itself is untouched (RD.D1 density rule).

- [ ] **Step 1: Write the failing tests**

Append to `test/features/campaign_list/presentation/campaign_list_screen_test.dart` (reuse its existing container/pump pattern; seed 3 campaigns — 2 `active`, 1 `pendingApproval`, total 3):

```dart
  testWidgets('S3: hero summary chips show page-scoped counts', (tester) async {
    // ... pump with seeded data, MediaQueryData(disableAnimations: true) so
    // CountUp renders final values on the first frame ...
    expect(find.text('3'), findsWidgets); // total
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Pending approval'), findsOneWidget);
    expect(find.text('2'), findsWidgets); // active count
  });

  testWidgets('S3: create action still permission-gated inside the hero',
      (tester) async {
    // ... pump WITHOUT Permission.campaignCreate ...
    expect(find.byTooltip('Create campaign'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `flutter test test/features/campaign_list/presentation/campaign_list_screen_test.dart`
Expected: new tests FAIL; existing PASS.

- [ ] **Step 3: Implement**

Imports to add:

```dart
import '../../../core/design_system/bmd_state_view.dart';
import '../../../core/design_system/screen_hero.dart';
import '../../../core/motion/count_up.dart';
```

The build restructures to:

```dart
    final paged = async.valueOrNull;
    final active = paged?.items
        .where((c) => c.status == CampaignStatus.active)
        .length;
    final pending = paged?.items
        .where((c) => c.status == CampaignStatus.pendingApproval)
        .length;

    return AppShell(
      title: 'Campaigns',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHero(
            title: 'Campaigns',
            summary: paged == null
                ? const []
                : [
                    _SummaryStat(label: 'Total', value: paged.total),
                    _SummaryStat(label: 'Active', value: active!),
                    _SummaryStat(label: 'Pending approval', value: pending!),
                  ],
            actions: [
              PermissionGate.disabled(
                Permission.campaignCreate,
                reason: 'Only a Campaign Creator can create a campaign.',
                label: 'Create campaign',
                child: IconButton(
                  tooltip: 'Create campaign',
                  icon: const Icon(Icons.add),
                  onPressed: () => context.go('/campaigns/new'),
                ),
              ),
            ],
          ),
          const SizedBox(height: BmdSpace.s4),
          Expanded(
            child: async.when(
              // loading/error/data as before, with:
              //   empty  -> BmdStateView.empty(
              //               title: 'No campaigns in scope',
              //               message: 'Create one to get started.')
              //   error  -> BmdStateView.error(
              //               title: "Couldn't load campaigns",
              //               message: 'Check your connection and try again.',
              //               onRetry: () =>
              //                   ref.read(campaignListProvider.notifier).refresh())
              //   data   -> the existing BmdDataTable, byte-identical except
              //             the rowDetailBuilder below
            ),
          ),
        ],
      ),
    );
```

(The `AppShell` `actions:` parameter is REMOVED — the gate moves, not copies.)

Row-detail accent bar — wrap the existing detail `Column` in:

```dart
                rowDetailBuilder: (c) => Container(
                  padding: const EdgeInsets.only(left: BmdSpace.s3),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: switch (_toneFor(c.status)) {
                          StatusTone.success => Theme.of(context).bmd.success,
                          StatusTone.warning => Theme.of(context).bmd.warning,
                          StatusTone.error => Theme.of(context).bmd.error,
                          StatusTone.info => Theme.of(context).bmd.info,
                          StatusTone.neutral => Theme.of(context).bmd.neutral,
                        },
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column( /* existing children, unchanged */ ),
                ),
```

NOTE: `rowDetailBuilder` runs inside a side-sheet route under a different `Navigator` — resolve the theme from the builder's own context, and keep the existing captured-`l10n` pattern for the chips (see the comment at the top of the file). Add `import '../../../app/theme/bmd_theme.dart';` for the `.bmd` extension.

Add the stat widget at the end of the file:

```dart
/// A hero-summary stat: count-up number + label, in a quiet pill.
class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BmdSpace.s3,
        vertical: BmdSpace.s1,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: theme.bmd.glassBorder),
        borderRadius: BorderRadius.circular(BmdRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountUp(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontVariations: const [FontVariation('wght', 600)],
            ),
          ),
          const SizedBox(width: BmdSpace.s1),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.bmd.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
```

(`import 'dart:ui' show FontVariation;` if not already imported.)

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/campaign_list/presentation/campaign_list_screen_test.dart`
Expected: ALL pass — especially the pre-existing tooltip-based permission tests, unmodified.

- [ ] **Step 5: Quality gates**

Run: `dart format lib/features/campaign_list/presentation/campaign_list_screen.dart test/features/campaign_list/presentation/campaign_list_screen_test.dart`
Run: `flutter analyze --fatal-infos`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/campaign_list/presentation/campaign_list_screen.dart test/features/campaign_list/presentation/campaign_list_screen_test.dart
git commit -m "feat(campaigns): hero summary strip + designed states (slice 2 RD2.D6)"
```

---

### Task 6: Campaign detail — recipe + S4 attendance progress meter

**Files:**
- Modify: `lib/features/campaign_detail/presentation/campaign_detail_screen.dart`
- Test: `test/features/campaign_detail/presentation/campaign_detail_screen_test.dart` (create if absent; if a detail test file already exists elsewhere — check `test/widget/` — extend that one instead)

**Interfaces:**
- Consumes: `ScreenHero` (uses `meter:` slot — the only screen that does), `KpiCard` (`lib/core/design_system/bmd_cards.dart` — `KpiCard({required String label, required String value, required String definition, required String source, required String freshness, bool glass = false, ...})`), `Reveal`, `reduced`/`MotionDur`/`MotionCurve`, `BmdStateView`.
- Produces: nothing new. FROZEN identifiers: `session_start`, `session_pause`, `session_close`.

Overview (spec RD2.D7):

1. `_Header` → `ScreenHero(title: c.name, summary: [status chip], actions: [the existing PermissionGate-wrapped buttons, moved verbatim], meter: _ProgressMeter(...))`.
2. `_ProgressMeter`: rounded linear gauge, cyan (`bmd.accent`) fill to `verified/target` clamped 0–1, animated with `reduced(context, MotionDur.slow)` + `MotionCurve.emphasized`; `target <= 0` → track only + "No target set"; else defence line "N of M verified" (§6.3).
3. `_OverviewTab._kpi` → `KpiCard(glass: true)` at width 260 with animated values (the dashboard `KpiGrid` `TweenAnimationBuilder` pattern) and defence metadata per label.
4. `_SessionCard` gains a status accent bar (Stack-in-Card, as Task 3) — tone: `!readinessOk` or `overCapacity` → `warning`, else `info` — and `_SessionsTab` list items get `Reveal` stagger.
5. Error branch → `BmdStateView.error`.

- [ ] **Step 1: Write the failing tests**

In the detail test file (seed via `campaignDetailProvider('CAMP-1').overrideWith(...)` with a fake `CampaignDetailController` returning `CampaignDetailData`; pump with `disableAnimations: true`):

```dart
  testWidgets('S4: meter renders the defence line and clamps', (tester) async {
    // campaign: targetAudience: 500, verifiedAttendance: 320
    expect(find.text('320 of 500 verified'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.64, 0.001));
  });

  testWidgets('S4: zero target renders "No target set" and an empty track',
      (tester) async {
    // campaign: targetAudience: 0
    expect(find.text('No target set'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.0);
  });

  testWidgets('S4: overview KPIs are glass KpiCards with defence lines',
      (tester) async {
    // sessions summing to registered: 45
    expect(find.byType(KpiCard), findsNWidgets(4));
    expect(find.text('REGISTERED'), findsOneWidget); // KpiCard uppercases
    expect(find.textContaining('Campaign service'), findsWidgets);
  });

  testWidgets('frozen session-op identifiers survive', (tester) async {
    // seed one upcoming session, switch to the Sessions tab:
    await tester.tap(find.text('Sessions'));
    await tester.pump();
    expect(find.bySemanticsIdentifier('session_start'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `flutter test <detail test file>`
Expected: FAIL (no LinearProgressIndicator / KpiCard yet).

- [ ] **Step 3: Implement**

Imports to add in `campaign_detail_screen.dart`:

```dart
import '../../../app/theme/bmd_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/design_system/bmd_cards.dart';
import '../../../core/design_system/bmd_state_view.dart';
import '../../../core/design_system/screen_hero.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/motion/reveal.dart';
```

`_Header.build` returns (the `actions` list construction above it stays byte-identical):

```dart
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ScreenHero(
        title: c.name,
        summary: [
          StatusChip(
            label: c.status.label(AppL10n.of(context)),
            tone: StatusTone.info,
          ),
        ],
        actions: actions,
        meter: _ProgressMeter(
          verified: c.verifiedAttendance,
          target: c.targetAudience,
        ),
      ),
    );
```

Add:

```dart
/// S4: verified attendance vs target as a rounded linear gauge (§6.3 — the
/// defence line beneath says exactly what the number is). Cyan is the data
/// accent (never an action color). Under reduced motion the fill renders at
/// its final width in one frame ([reduced] collapses the duration; see
/// CountUp's note on TweenAnimationBuilder and zero durations).
class _ProgressMeter extends StatelessWidget {
  const _ProgressMeter({required this.verified, required this.target});
  final int verified;
  final int target;

  @override
  Widget build(BuildContext context) {
    final bmd = Theme.of(context).bmd;
    final fraction = target <= 0
        ? 0.0
        : (verified / target).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction),
          duration: reduced(context, MotionDur.slow),
          curve: MotionCurve.emphasized,
          builder: (context, f, _) => ClipRRect(
            borderRadius: BorderRadius.circular(BmdRadius.chip),
            child: LinearProgressIndicator(
              value: f,
              minHeight: 10,
              backgroundColor: bmd.surfaceSunken,
              valueColor: AlwaysStoppedAnimation(bmd.accent),
            ),
          ),
        ),
        const SizedBox(height: BmdSpace.s1),
        Text(
          target <= 0 ? 'No target set' : '$verified of $target verified',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: bmd.textSecondary,
          ),
        ),
      ],
    );
  }
}
```

`_OverviewTab._kpi` is replaced by:

```dart
  Widget _kpi(BuildContext context, String label, int value) => SizedBox(
    width: 260,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: reduced(context, MotionDur.slow),
      curve: MotionCurve.emphasized,
      builder: (context, v, _) => KpiCard(
        label: label,
        value: '${v.round()}',
        definition: _definitionFor(label),
        source: 'Campaign service',
        freshness: 'Live',
        glass: true,
      ),
    ),
  );

  String _definitionFor(String label) => switch (label) {
    'Registered' => 'Participants registered across all sessions.',
    'Pending sync' => 'Captures waiting to upload from field devices.',
    'In review' => 'Attendance records awaiting CRM verification.',
    'Approved' => 'Attendance approved by verification.',
    _ => label,
  };
```

`_SessionsTab` items get stagger:

```dart
      children: [
        for (final (i, s) in data.sessions.indexed)
          Reveal(
            index: i < 8 ? i : 8,
            child: _SessionCard(session: s, controller: c),
          ),
      ],
```

`_SessionCard`'s `Card` child wraps in the same Stack-accent-bar as Task 3, with:

```dart
    final bmd = Theme.of(context).bmd;
    final accent = (!session.readinessOk || session.overCapacity)
        ? bmd.warning
        : bmd.info;
```

Error branch of the screen:

```dart
        error: (_, __) => BmdStateView.error(
          title: "Couldn't load this campaign",
          message: 'Check your connection and try again.',
          onRetry: () => ref.invalidate(campaignDetailProvider(campaignId)),
        ),
```

- [ ] **Step 4: Run the tests**

Run: `flutter test <detail test file> test/widget/`
Expected: ALL pass.

- [ ] **Step 5: Quality gates**

Run: `dart format lib/features/campaign_detail/presentation/campaign_detail_screen.dart <detail test file>`
Run: `flutter analyze --fatal-infos`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/campaign_detail/presentation/campaign_detail_screen.dart <detail test file>
git commit -m "feat(campaign-detail): hero + attendance progress meter + glass KPIs (slice 2 RD2.D7)"
```

---

### Task 7: Screen goldens + final sweep

**Files:**
- Create: `test/golden/screens_golden_test.dart`

**Interfaces:**
- Consumes: everything above; `goldenTest` (`test/support/golden.dart`), `buildTestContainer` (`test/support/harness.dart`), the physical-view sizing pattern and GoRouter host from `test/golden/dashboard_golden_test.dart`.
- Produces: 8 golden cases whose baselines are generated on Linux CI (see Global Constraints) — `queue-desktop-dark.png`, `queue-mobile-light.png`, `crm_case-…`, `campaign_list-…`, `campaign_detail-…`.

- [ ] **Step 1: Write the golden test**

Create `test/golden/screens_golden_test.dart`, following `dashboard_golden_test.dart`'s structure exactly (physical-view `_setViewport`, `buildTestContainer` + `UncontrolledProviderScope` + single-route `GoRouter` + `MaterialApp.router`, `goldenTest` wrapper). Two variants per screen: `desktop-dark` `Size(1280, 2600)` and `mobile-light` `Size(390, 2600)`.

Seed data — deterministic fakes, one per screen, each a subclass of the real notifier overriding `build`:

```dart
// Queue: three tiles exercising every S1 state — one overdue+escalated
// (error ramp + glow), one fresh medium unassigned (Claim button), one
// fresh high assigned-to-me (Release button; harness userId is 'u-1').
class _SeededQueue extends VerificationQueueNotifier {
  @override
  Future<List<VerificationQueueItem>> build(QueueFilter filter) async => [
    VerificationQueueItem(
      attendanceId: 'CASE_OVERDUE',
      carpenterName: 'Md. Karim',
      campaignName: 'ACSL Pilot Carpenter Drive',
      age: const Duration(hours: 25),
      band: MatchBand.low,
      referenceSource: ReferenceSource.verifiedProfilePhoto,
      escalatedAt: DateTime(2026, 8, 14),
    ),
    const VerificationQueueItem(
      attendanceId: 'CASE_FRESH',
      carpenterName: 'Karim Uddin',
      campaignName: 'ACSL Pilot Carpenter Drive',
      age: Duration(hours: 2),
      band: MatchBand.medium,
      referenceSource: ReferenceSource.verifiedProfilePhoto,
    ),
    const VerificationQueueItem(
      attendanceId: 'CASE_MINE',
      carpenterName: 'Rahim Mia',
      campaignName: 'Chattogram Contractor Meet',
      age: Duration(minutes: 40),
      band: MatchBand.high,
      referenceSource: ReferenceSource.authorizedNidPhoto,
      assigneeId: 'u-1',
    ),
  ];
}
```

CRM case fake returns a `VerificationCase` with `capturedImageUrl: 'https://example.invalid/cap.png'` and `referenceImageUrl: 'https://example.invalid/ref.png'` — `flutter_test` blocks real HTTP, so both images deterministically render their `errorBuilder` ('Image unavailable'), which is fine for geometry/spacing baselines. `machine: MachineResult(band: MatchBand.medium, referenceSource: ReferenceSource.verifiedProfilePhoto, padReview: true, reasons: ['Pose differs from reference'])`, `status: AttendanceStatus.crmReview`, `version: 1`, names/dates as constants.

Campaign list fake returns `Paged(items: [3 campaigns — active/active/pendingApproval, with targets and verified counts], total: 3)`.

Campaign detail fake returns `CampaignDetailData(campaign: Campaign(... status: CampaignStatus.active, targetAudience: 500, verifiedAttendance: 320 ...), sessions: [one active over-capacity session, one upcoming])`.

Screen hosts (per screen, the dashboard pattern):

```dart
final _screens = <String, Widget Function()>{
  'queue': () => const VerificationQueueScreen(),
  'crm_case': () => const CrmCaseScreen(attendanceId: 'CASE_OVERDUE'),
  'campaign_list': () => const CampaignListScreen(),
  'campaign_detail': () => const CampaignDetailScreen(campaignId: 'CAMP-1'),
};
```

with per-screen overrides lists (family providers need the exact argument):

```dart
List<Override> _overridesFor(String id) => switch (id) {
  'queue' => [
    verificationQueueProvider(QueueFilter.all).overrideWith(_SeededQueue.new),
  ],
  'crm_case' => [
    crmCaseControllerProvider('CASE_OVERDUE').overrideWith(_SeededCase.new),
  ],
  'campaign_list' => [campaignListProvider.overrideWith(_SeededList.new)],
  'campaign_detail' => [
    campaignDetailProvider('CAMP-1').overrideWith(_SeededDetail.new),
  ],
  _ => throw StateError('unknown screen $id'),
};
```

Permissions for the container: `const {}` (no `verificationOverride` — no Escalated tab, no override switch; the CRM sync `Switch` is the only Switch). Pump with `await tester.pumpAndSettle()` EXCEPT the queue screen if the escalated glow's TweenAnimationBuilder never settles — it does settle (one-shot, 800ms), so `pumpAndSettle` is fine everywhere.

Baseline names: `goldens/<id>-<viewport>-<brightness>.png` for the 8 combinations of `{queue, crm_case, campaign_list, campaign_detail} × {desktop-dark, mobile-light}`.

- [ ] **Step 2: Run the golden file on Windows**

Run: `flutter test test/golden/screens_golden_test.dart`
Expected: all SKIPPED (`goldenTest` is Linux-gated). The point of this step is that the file compiles and the harness constructs — a compile error fails even a skipped suite.

- [ ] **Step 3: Full-suite sweep**

Run: `dart format --output=none --set-exit-if-changed .`
Run: `flutter analyze --fatal-infos`
Run: `flutter test`
Expected: all clean/green (goldens skipped on Windows).

- [ ] **Step 4: Commit**

```bash
git add test/golden/screens_golden_test.dart
git commit -m "test(golden): slice-2 screen baselines (queue, crm case, campaigns) — Linux-generated"
```

---

## After all tasks (controller, not an implementer subagent)

1. Final whole-branch code review, then push and open the PR.
2. Dispatch `.github/workflows/goldens.yml` on the branch (`gh workflow run goldens.yml --ref feat/expressive-redesign-slice2`), download the `golden-baselines` artifact, copy into `test/golden/goldens/`, commit. Expect ~16 new PNGs (8 screen + 8 gallery: 2 new sections × 4 variants) and NO modified existing baselines (no existing component changed its default rendering) — a modified existing baseline is a red flag to investigate, not commit.
3. CI green → merge only on explicit user go-ahead.
