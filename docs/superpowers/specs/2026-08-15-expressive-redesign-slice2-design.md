# Expressive Redesign — Slice 2: high-traffic screen polish

**Status:** design, ready for planning.

The second slice of the expressive UI/UX pivot. Slice 1 (merged, PR #15)
established the language — expressive tokens (cyan accent, glass, brand
gradients), a motion system, and the signature Dashboard. Slice 2 applies that
language deeply to the four screens operators live in: **Verification queue
(C-01)**, **CRM case (C-02)**, **Campaign list (W-02)** and **Campaign detail
(W-05)**. Each gets a uniform recipe plus one crafted signature moment —
"award-winning through craft and moments," continuing slice 1's philosophy.

Deferred to later slices (unchanged from slice 1's list): the Analytics
showpiece (A-02), a branded web shell + login, and the illustration/empty-state
art pass. This slice's `BmdStateView` is typography-and-tone only, explicitly
leaving an illustration slot for that later slice.

---

## 1. Context and current state

- Slice 1 merged the full expressive foundation: `BmdColor.accentCyan` /
  glass tokens / `BmdGradient.heroMesh`+`glow` (`lib/app/theme/tokens.dart`),
  the `displayHero` text role (`bmd_theme.dart`), the motion system
  (`lib/core/motion/`: `MotionDur`, `MotionCurve`, `motionOff`/`reduced`,
  `Reveal`, `CountUp`, `Shimmer`, route transitions), glass variants of
  `KpiCard`/`ExceptionCard` (`glass: true`, false-path byte-identical), and
  the `BmdButton` press-spring.
- The four target screens are single-file, presentation-only
  (147–394 lines), state via existing Riverpod providers. None needs data
  or provider changes; this slice is purely presentational.
- Their empty/error states are bare centered `Text` widgets today.
- The 52KB guideline remains the spine: §5 component contracts, §6.3 "no
  bare numbers" (every KPI carries a defence line), §8.13 CRM case rules
  (fair comparison — same crop + scale; machine recommendation as a
  separate, clearly-labelled advisory; confirm downstream effect).
- 20 Maestro flows and the widget-test suite pin the interaction contracts
  of these exact screens (claim/release, decision submit, session ops,
  table row → side-sheet).

## 2. Decisions

### RD2.D1 — `ScreenHero`: a compact expressive header primitive

New `lib/core/design_system/screen_hero.dart`. A reusable header band for
operational screens — the Dashboard hero's little sibling.

- **Size:** content-hugging, ~96–120px typical; never full-bleed.
- **Background:** `BmdGradient.heroMesh(isDark)` painted at low opacity
  (0.12–0.18) over the surface color so it reads as a tinted band, with a
  faint `BmdGradient.glow` anchored to one corner. Theme-aware via the
  existing gradient tokens; no new colors.
- **API (all named, only `title` required):**
  `ScreenHero({required String title, String? subtitle, List<Widget> summary
  = const [], List<Widget> actions = const [], Widget? meter})` —
  `summary` renders as a `Wrap` of chips/labels (screens put live
  `CountUp` numbers here), `actions` as a trailing `Wrap` of buttons,
  `meter` as an optional full-width row under the title block (used by
  Campaign detail's progress meter, empty elsewhere).
- **Typography:** title uses a new `displayTitle` text role added to
  `BmdTextRoles` in `bmd_theme.dart`: Inter 30px, `FontVariation('wght',
  700)` (same `_wght()` helper as `displayHero` — never synthetic bold),
  letterSpacing −0.5, height 36/30. Subtitle: `bodyMedium` on
  `textMuted`.
- Static by construction — the band itself never animates; only slotted
  children (`CountUp`s) do, and those already respect `motionOff`.

### RD2.D2 — `BmdStateView`: designed empty/error states

New `lib/core/design_system/bmd_state_view.dart`, replacing the four
screens' bare-`Text` states.

- **Anatomy:** a tone-tinted icon inside a soft circle (48px icon, 96px
  circle at 12% tone color), title (`titleMedium`), body (`bodyMedium`,
  `textMuted`, constrained to ~480px so lines stay readable), optional
  action button. Entrance wrapped in `Reveal(index: 0)` (single, gentle;
  a no-op under reduced motion).
- **API:** `BmdStateView.empty({required String title, required String
  message, IconData icon = Icons.inbox_outlined, Widget? action})` and
  `BmdStateView.error({required String title, required String message,
  required VoidCallback onRetry})` — the error variant always renders an
  outlined Retry `BmdButton` and uses `StatusTone.error` tinting; empty
  uses neutral tinting.
- No illustration slot content in this slice; the icon circle is where a
  later slice's illustration drops in.

### RD2.D3 — The uniform recipe

Applied to all four screens, in this order of precedence:

1. `ScreenHero` replaces the screen's plain title/header row. The
   `AppShell` `title:` stays (app bar/nav unchanged); the hero lives at
   the top of the body.
2. Card/list entrances get staggered `Reveal`, stagger index capped at 8
   (`Reveal(index: min(i, 8))`) so long lists settle quickly.
3. Bare empty/error states become `BmdStateView`.
4. `glass: true` only on hero-adjacent surfaces (advisory card, KPI
   cards). **`BmdDataTable`, list rows and form surfaces keep the
   restrained hairline treatment** (slice 1 RD.D1: density and
   legibility win on data surfaces).

### RD2.D4 — Signature moment S1: queue urgency choreography

Verification queue (`verification_queue_screen.dart`):

- Each `_QueueTile` gets a 3px left accent bar tone-coded by match band,
  using the Dashboard `ExceptionStrip` tone mapping: `noReference`/`low`
  → warning, `medium` → info, `high` → success; drawn as a `Stack`
  overlay (the slice-1 `ExceptionCard` technique — never a
  `Border(left:)`, which Flutter requires uniform with a radius).
- **Urgency ramp:** when `item.age >= 24h` (the review-window SLA the
  Dashboard's "Overdue verification" bucket already uses), the "Waiting
  …" label and the accent bar switch to the error tone and the label
  gains `FontVariation('wght', 600)`. Below the threshold they render in
  the band tone / `labelMedium` exactly as today.
- Escalated chips get a one-time entrance glow: an `AnimatedOpacity`
  halo (accent-cyan at 24%, `MotionDur.slow`) that fades in and out once
  after build; entirely skipped when `motionOff` — the chip renders
  statically.
- Tiles enter with staggered `Reveal` per the recipe. Claim/release
  identifiers (`queue_claim_<id>`, `queue_release_<id>`,
  `queue_item_<id>`, `queue_tab_<name>`, `queue_escalated_<id>`) and the
  `_act` flow are untouched.

### RD2.D5 — Signature moment S2: synced evidence compare

CRM case (`crm_case_screen.dart`):

- Each `_EvidenceImage`'s `InteractiveViewer` gets a
  `TransformationController`. A parent `_EvidenceZone` (now stateful)
  owns both controllers and mirrors changes both ways with a re-entrancy
  guard (`bool _syncing` — set before writing the peer's `value`, cleared
  after; the listener returns early while set). Zooming/panning the
  captured photo moves the reference identically — §8.13's "same crop +
  scale" now holds at every zoom level.
- A "Synced zoom" row above the image pair: label + a small
  `Switch` (default ON) with **new additive identifier
  `crm_zoom_sync`**. Toggling OFF stops mirroring (controllers keep
  their current transforms); toggling ON re-syncs the reference to the
  captured transform. When either URL is null (no reference), the row is
  hidden and no sync occurs.
- The machine-advisory `Card` becomes glass (`ExceptionCard`-style
  container is NOT reused — it stays a `Card`-shaped container using
  `glassFill`/`glassBorder` tokens directly, keeping its §8.13 advisory
  framing), band chips gain their tone colors via `StatusChip` tones
  (High → success, Medium → info, Low/No reference → warning).
- The three zones enter with `Reveal` indices 0/1/2. All existing
  identifiers (`crm_outcome_<name>`, `crm_reason`,
  `crm_supervisor_override`, `crm_submit`) and the decision flow are
  untouched.

### RD2.D6 — Signature moment S3: living summary strip

Campaign list (`campaign_list_screen.dart`):

- `ScreenHero(title: 'Campaigns')` with `summary:` chips computed from
  the loaded page: total (`paged.total`), Active count, Pending-approval
  count — each a label + `CountUp` number pair. Rendered only in the
  `data` branch (loading/error show the hero with an empty summary).
- The "Create campaign" `PermissionGate` action moves into the hero's
  `actions` slot; the `AppShell` `actions:` list is emptied. The gate,
  tooltip, semantics and `onPressed` are byte-identical — only the
  placement moves. (The Maestro flows tap `login_*`/table identifiers,
  not this icon button, and the widget tests locate it by tooltip —
  placement is not part of any pinned contract.)
- The `BmdDataTable` itself is untouched except its row-detail sheet:
  the sheet's content column gains a 3px status-tone accent bar on the
  left (same overlay technique as S1).

### RD2.D7 — Signature moment S4: attendance progress meter

Campaign detail (`campaign_detail_screen.dart`):

- `_Header` becomes a `ScreenHero`: campaign name as `title` (ellipsized,
  1 line), status chip in `summary`, the contextual action buttons in
  `actions` (the existing `PermissionGate` wrappers move verbatim).
- **Progress meter** in the hero's `meter` slot: a rounded linear gauge
  (10px tall, `BmdRadius`-rounded, track at 12% outline color) filled
  with accent cyan to `verifiedAttendance / targetAudience` (clamped
  0–1; `targetAudience <= 0` renders the track with no fill and the
  defence line "No target set"). The fill sweeps from 0 with
  `MotionDur.slow` + `MotionCurve.emphasized` via
  `TweenAnimationBuilder`; under reduced motion it renders at its final
  width in one frame. Defence line beneath (§6.3): "N of M verified".
- `_OverviewTab`'s hand-rolled `_kpi` cards become design-system
  `KpiCard(glass: true)` with `CountUp`-equivalent
  `TweenAnimationBuilder` values (the Dashboard `KpiGrid` pattern),
  with defence metadata: definition per label, source 'Campaign
  service', freshness 'Live'.
- `_SessionCard`s get `Reveal` stagger and a status accent bar
  (readiness-warning → warning tone, over-capacity → warning, else
  info). Session action identifiers (`session_start`, `session_pause`,
  `session_close`) untouched.

## 3. Out of scope

- The other tabs' placeholders (Attendance/Analytics/Audit) stay
  placeholders — their content is other work packages (A-02, AD-01).
- No provider, domain, routing or wire changes anywhere.
- No illustration assets; no new fonts; no new packages.
- Login, bulk import, registration, capture, offline queue, settings —
  later slices.

## 4. Global constraints (binding, verbatim where inherited)

1. **Frozen contracts:** every existing `Semantics(identifier:)` string,
   route path, provider API and interaction flow stays byte-identical.
   The only additive identifier is `crm_zoom_sync` (RD2.D5). All 20
   Maestro flows and the existing widget tests must pass unmodified.
2. **Reduced motion:** every animation this slice adds is gated through
   `motionOff(context)` / `reduced(context, d)` — single-frame final
   state when off.
3. **Brand:** red `#E71E25` remains the only primary-action color; cyan
   `#22D3EE` is accent/data only (meter fill, glow, selected series).
4. **Density:** `BmdDataTable` and dense rows keep hairline elevation-0
   treatment (RD.D1).
5. **Quality gates:** `dart format` clean, `flutter analyze
   --fatal-infos` clean project-wide, full `flutter test` green.
6. **Goldens:** regenerated only via the Linux `goldens.yml` workflow
   (`workflow_dispatch` on the branch), committed from the
   `golden-baselines` artifact before merge.
7. `ENABLE_TEST_SEEDING` is never committed enabled anywhere.

## 5. Testing

- **Primitives:** widget tests for `ScreenHero` (slots render; title uses
  the 30px/700 role) and `BmdStateView` (variants, retry callback);
  two new gallery golden cases (`gallery_screen_hero`,
  `gallery_state_views`) in the existing gallery golden harness.
- **S1:** widget test — below-threshold tile renders label tone,
  ≥24h tile renders error tone; identifier sweep asserts all queue
  identifiers still resolve; reduced-motion renders in one pump.
- **S2:** widget test — panning the captured controller updates the
  reference controller (and vice versa); toggling `crm_zoom_sync` off
  stops mirroring; null-reference case renders no sync row; identifier
  sweep for the decision panel.
- **S3:** widget test — summary chips show the loaded counts; create
  action still permission-gated; row detail unchanged.
- **S4:** widget test — meter fraction math incl. `target == 0`;
  KPI defence lines present; identifier sweep for session ops;
  reduced-motion single-frame.
- **Goldens:** 8 new screen baselines — each of the four screens at
  desktop-dark and mobile-light, with seeded provider overrides (the
  `dashboard_golden_test.dart` pattern: physical-view sizing, fake
  notifier per screen), Linux-gated via `goldenTest`.

## 6. File map

| File | Change |
|---|---|
| `lib/core/design_system/screen_hero.dart` | new — RD2.D1 |
| `lib/core/design_system/bmd_state_view.dart` | new — RD2.D2 |
| `lib/app/theme/bmd_theme.dart` | add `displayTitle` to `BmdTextRoles` |
| `lib/features/verification_queue/presentation/verification_queue_screen.dart` | recipe + S1 |
| `lib/features/crm_case/presentation/crm_case_screen.dart` | recipe + S2 |
| `lib/features/campaign_list/presentation/campaign_list_screen.dart` | recipe + S3 |
| `lib/features/campaign_detail/presentation/campaign_detail_screen.dart` | recipe + S4 |
| `lib/features/gallery/presentation/gallery_screen.dart` | add hero/state-view sections |
| `test/...` | per §5 |
