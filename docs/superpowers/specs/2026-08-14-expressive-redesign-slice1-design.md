# Expressive Redesign — Slice 1: foundation, motion, and the signature Dashboard

**Status:** design, ready for planning.

The first slice of an expressive UI/UX pivot for the ACSL campaign-management
app (single Flutter codebase serving mobile Android **and** responsive web). It
establishes a new **expressive visual language** and a **motion system**, then
proves both by building the currently-placeholder **Campaign Dashboard (`/`,
W-01)** as the showpiece. The other 14 screens inherit the new look through the
theme; per-screen polish, Analytics, a branded web shell, and illustration are
later slices.

**Design direction (user-chosen):** a *bolder, expressive* pivot — a confident
visual point of view — while keeping the BMD brand and the governance-tool
trust. "Award-winning through craft and moments," not decoration.

---

## 1. Context and current state

- Single Flutter codebase (`sdk >=3.12.0 <4.0.0`, `flutter >=3.44.0`), Material 3
  (`useMaterial3: true`). Platform folders: `android/` + `web/` only. "Web view"
  is Flutter-web of the same app; adaptation is breakpoint-driven
  (`lib/core/responsive/breakpoints.dart`, `adaptive_scaffold.dart` — bottom
  `NavigationBar` on mobile, `NavigationRail` on tablet/desktop, content capped
  at 1440px).
- A mature, guideline-driven design system exists: tokens in
  `lib/app/theme/tokens.dart` (`BmdColor`, `BmdSpace`, `BmdRadius`, `BmdSize`,
  `BmdElevation`, `BmdTokens` ThemeExtension), the theme in
  `lib/app/theme/bmd_theme.dart` (`bmdTheme(brightness)`), components in
  `lib/core/design_system/` (`BmdButton`, `BmdField`, `KpiCard`, `ExceptionCard`,
  `StatusChip`, `BmdDataTable`, `BmdBanner`, `LineageRail`, overlays), and a
  parallel CSS token mirror in `design/src/tokens.css` (kept in lockstep with
  the Dart tokens).
- Brand: BMD red `#E71E25` (primary600) + BMD navy `#2B3674` (ink700).
  Typography: **Inter** variable + **Noto Sans Bengali** variable, bundled OFL,
  set via `FontVariation('wght', …)`. Fully bilingual EN/BN.
- **Gaps this slice fills:** no motion/animation system at all (no `Hero`,
  `AnimatedX`, transitions, or animation packages); the Dashboard (`/`) and
  Analytics (`/analytics`) are `PlaceholderScreen`s; `fl_chart` is a dependency
  with zero usages; the aesthetic is deliberately flat (elevation-0 hairline
  borders).
- **The 52KB guideline** `ACSL_Carpenter_Campaign_Management_UI_UX_Design_
  Guideline_v1_0.md` is the design spine (§4 visual foundations, §5 component
  standards, §6 data-viz/dashboard, §8.1 the Dashboard). This slice **evolves
  §4 and adds a motion section**; §5 component contracts and §6 KPI rules still
  hold.

---

## 2. Decisions

### RD.D1 — Expressive palette on the BMD brand (dark-first)

Extend the token layer (`tokens.dart` + mirror `design/src/tokens.css`) with an
expressive, brand-derived palette, designed **dark-first** with a fully polished
light counterpart (still `ThemeMode.system`).

- **Surfaces (dark):** deep navy-tinted darks, not pure black — a base around
  `#0B1020` with 3–4 elevation layers. **Glass** elevated surfaces: translucent
  fill + a 1px gradient-tinted border + a soft ambient shadow + a faint top
  highlight. Light theme: airy near-white with navy-tinted surface layers and
  soft depth. This *replaces the flat elevation-0 model for hero surfaces only*;
  dense data surfaces (`BmdDataTable`, list rows) keep the restrained hairline
  treatment so legibility and density are preserved.
- **Gradient meshes:** tokenized `BmdGradient` set derived from brand — a hero
  mesh (`red → navy → cyan`), plus subtle radial glows. Theme-aware (separate
  light/dark stops), reusable.
- **Vivid accent — electric cyan `#22D3EE`** (a deeper cyan in light for AA):
  the "energy" layer for CTAs, selected data series, focus glows, and the hero
  gradient's third stop. **Brand red remains the primary-action color** per the
  guideline ("red highlights the main action, not every card"); cyan never
  replaces red for primary actions.
- All new colors/gradients are added as tokens (not inline), theme-aware, and
  pass the existing `design/PALETTE.md` AA-contrast + CVD (Machado–Oliveira–
  Fernandes) validation that the repo already runs on its palette.

### RD.D2 — Expressive typography (Inter, no new font)

Keep the bundled Inter variable font; add a **display tier** to the scale for
hero headlines and hero numbers: a `displayXL` role ~72–96px, weight 800, tight
negative tracking, with dramatic scale jumps from body. Body/label scale
unchanged. **Noto Sans Bengali** mirrors the new display sizes (tuned per
script); Bengali wrapping at the large sizes is explicitly verified. No new font,
no licensing, no EN/BN parity risk.

### RD.D3 — A motion system (`lib/core/motion/`)

Introduce the missing motion layer, engined by **`flutter_animate`** (declarative,
lightweight, transform/opacity-based).

- **Motion tokens:** durations (`fast 120ms`, `base 240ms`, `slow 400ms`) and
  curves (Material 3 emphasized + a spring), as constants in a `motion_tokens`
  file so motion is consistent and tunable in one place.
- **Primitives (reusable across all screens):**
  - Route transitions via GoRouter `CustomTransitionPage` — shared-axis for
    forward/back navigation, fade-through for tab/peer switches.
  - Hero / shared-element morphs (list → detail).
  - **Staggered reveal** — a helper that fades-and-rises a list/grid of children
    with a per-item delay (KPI tiles, exception cards, list rows).
  - **KPI number count-up** — animates a numeric value from 0 → target on first
    paint.
  - **Skeleton shimmer** loaders — replace bare `CircularProgressIndicator`
    for content areas (spinners stay only for inline button-busy states).
  - Micro-interactions — button-press spring scale, hover-lift elevation on web.
- **Guardrails (mandatory):** every motion primitive honors reduced-motion —
  when `MediaQuery.disableAnimations` is true (OS "reduce motion" /
  `prefers-reduced-motion`), animations collapse to an instant state or a plain
  fade. Animations are transform/opacity-based to hold 60fps on the web
  (CanvasKit) renderer; blur is capped and used sparingly. Golden tests already
  freeze tickers (`TickerMode(enabled: false)`), so motion stays deterministic.

### RD.D4 — Re-theme, don't rewrite (component uplift through the theme)

The re-skin lands primarily in `tokens.dart` + `bmd_theme.dart` + `design/src/
tokens.css`, so all 15 screens pick up the new surfaces, gradients, depth, and
type through `ThemeData`. Component files (`BmdButton`, `KpiCard`,
`ExceptionCard`, cards, chips) get **visual** uplift (glass fills, gradient
borders, motion hooks) but keep their **public APIs and required fields**
unchanged — `KpiCard` still demands label/value/definition/source/freshness, the
`enabled:`-semantics workaround in `bmd_button.dart` stays. No component API is
removed or renamed.

### RD.D5 — The signature Dashboard (`/`, W-01), exception-first

Replace the `/` `PlaceholderScreen` with a real `dashboard` feature (a Riverpod
`AsyncNotifier` + screen), built **exception-first** per guideline §8.1, in the
new expressive language. Top-to-bottom:

1. **Hero header** — a full-bleed mesh-gradient band (red→navy→cyan) with a
   `displayXL` greeting + session context, a subtle animated glow, and the *one*
   primary CTA (brand red) the guideline reserves red for. Settles on load.
2. **Exception strip (first, before totals)** — a horizontally-scrollable row of
   glass `ExceptionCard`s: overdue verifications, rejected, pending-sync,
   no-reference, suspected-spoof, reconciliation — each with its colored
   left-accent, age-pressure bar, and a **count-up** count. Tapping a card
   deep-links to the relevant queue/screen.
3. **KPI tiles** — a responsive grid of glass `KpiCard`s (same required fields)
   with count-up values, a delta sparkline, and cyan for the selected/primary
   series. Staggered reveal.
4. **Data-viz row** — wire `fl_chart` + the pre-built CVD-safe categorical/funnel
   palettes: an attendance **funnel** (captured→match→CRM→approved) and a
   campaign-status **donut/bar**, with animated draw-in and hover tooltips.
5. **Responsive** — nav rail + multi-column on desktop/web; single-column,
   swipeable exception strip, bottom-nav on mobile — via the existing
   `AdaptiveScaffold`/`Breakpoint` system.

Data comes from existing endpoints/repositories (campaigns, verification queue
depth/bands/escalated, sessions, registrations, imports, sync) via the
established Riverpod pattern. Where a specific aggregate endpoint does not yet
exist, the Dashboard composes it from existing list/queue reads on the client;
no new server endpoint is required for this slice (a dedicated dashboard
aggregate API is a later concern). Every Dashboard widget carries a
`Semantics(identifier: …)` for a future Maestro flow.

### RD.D6 — Constraints preserved (identifiers, bilingual, a11y, perf)

- **Every existing `Semantics(identifier: …)` is preserved** — the re-skin
  changes pixels, not identifiers. 16 `lib/` files and 20 `.maestro/flows/*.yaml`
  select by them; none may break. New widgets add new identifiers only.
- **Bilingual EN/BN** preserved, including at the new display sizes; Bengali
  wrapping/truncation verified.
- **Accessibility:** AA contrast on all new gradient/glass surfaces (extend the
  `design/PALETTE.md` validators to the new tokens); focus-visible states;
  reduced-motion honored; touch targets unchanged.
- **Web/CanvasKit performance:** transform/opacity motion, capped blur, lazy
  chart build → 60fps target.

---

## 3. Files

**Tokens & theme (the foundation):**
- Modify `lib/app/theme/tokens.dart` — expressive dark-first surfaces, `BmdGradient`
  tokens, electric-cyan accent, glass/elevation tokens, `displayXL` type role
  additions to `BmdTokens`/scale.
- Modify `lib/app/theme/bmd_theme.dart` — wire the new tokens into `ThemeData`
  (surfaces, gradients-as-decoration helpers, the display text style, component
  theme overrides for glass cards).
- Modify `design/src/tokens.css` (+ `design/PALETTE.md` validators) — mirror the
  new tokens; extend AA/CVD validation.

**Motion (new):**
- Create `lib/core/motion/motion_tokens.dart` — durations + curves.
- Create `lib/core/motion/` primitives — route transitions, staggered reveal,
  count-up, shimmer, micro-interaction helpers.
- Modify `pubspec.yaml` — add `flutter_animate`.
- Modify `lib/app/router/app_router.dart` — apply `CustomTransitionPage`
  transitions.

**Component uplift (visual only, APIs unchanged):**
- Modify `lib/core/design_system/bmd_cards.dart`, `bmd_button.dart`,
  `status_chip.dart`, `bmd_feedback.dart` — glass/gradient/motion hooks.

**The Dashboard (new feature):**
- Create `lib/features/dashboard/application/dashboard_notifier.dart` +
  `presentation/dashboard_screen.dart` (+ hero, exception-strip, kpi-grid,
  data-viz widgets).
- Modify `lib/app/router/app_router.dart` — `/` builds `DashboardScreen` (drop
  the placeholder).

**Tests:**
- Modify `test/golden/gallery_golden_test.dart` + regenerate baselines under
  `test/golden/goldens/`; add Dashboard goldens (desktop/mobile × light/dark).
- Add widget tests for the Dashboard states (loading-shimmer / data / error /
  empty) and for the motion primitives' reduced-motion behavior.

---

## 4. Testing

- **Goldens** are the primary visual gate: the gallery suite (2 viewports × 2
  brightnesses) is regenerated *deliberately* (the token change is intentional),
  and new Dashboard goldens are added. A motion-frozen render (existing
  `TickerMode` freeze) keeps them deterministic.
- **Reduced-motion**: a test pumps a widget with `MediaQueryData(disableAnimations:
  true)` and asserts the motion primitives render their end-state without
  animating.
- **Dashboard**: widget tests for the four AsyncValue states, the exception-first
  ordering (exceptions render before KPI totals), and count-up reaching the
  target value.
- **Identifier preservation**: a test (or a grep-based check) asserting the set
  of `Semantics(identifier: …)` values referenced by `.maestro/flows/*.yaml`
  still all resolve to widgets after the re-skin.
- **Bilingual**: a Bengali golden at the new display sizes (the repo already has
  a `bengali-wrapping-mobile.png` golden pattern).
- The full `flutter test` + `flutter analyze --fatal-infos` stay green; the
  Maestro e2e flow suite is unaffected (identifiers preserved) and runs in CI.

---

## 5. Out of scope (named to be excluded)

- **Analytics screen (`/analytics`, A-02)** and the full data-viz suite beyond
  the Dashboard's two charts → a later slice.
- **Branded web shell / PWA** (custom `web/index.html`, favicon, manifest, meta,
  loading splash — all stock Flutter today) or a distinct marketing **landing**
  page → a later slice.
- **Per-screen expressive polish** across the other 14 screens beyond what they
  inherit from the theme → later slices.
- **Illustration / imagery / custom-icon identity** (hero art, empty-state
  illustrations) → a later slice.
- **A dedicated server-side dashboard aggregate API** — this slice composes the
  Dashboard from existing reads on the client.
- **A manual in-app theme toggle** — the app stays `ThemeMode.system`.
