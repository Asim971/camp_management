# Design — Epic P0.2: Design System & Tokens

**Status:** Approved (design); implementation plan pending
**Date:** 2026-08-05
**Epic:** [`TASK_BREAKDOWN.md`](../../../TASK_BREAKDOWN.md) → Phase P0 → Epic P0.2 (T-0.2.1 … T-0.2.9)
**Basis:** [UI/UX Guideline v1.0](../../../ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md) §4, §5, §11, §13.2 · [`ARCHITECTURE_Flutter.md`](../../../ARCHITECTURE_Flutter.md)

---

## 1. Verified state of the epic

Epic P0.2 is roughly 70% built. The gaps are specific, not diffuse:

| Task | Verified state | Evidence |
|---|---|---|
| T-0.2.1 BMD tokens | **Done.** Colour, space, radius, size, elevation, plus a `BmdTokens` `ThemeExtension` carrying the semantic quartet, chip tints, a CVD-validated 6-slot series palette and a 5-step funnel ramp, in both modes. | `lib/app/theme/tokens.dart` (349 lines), `design/PALETTE.md` |
| T-0.2.2 `bmdTheme()` | **Done.** M3 `ColorScheme.fromSeed` with a brand override layer, full type scale per §4.3, component themes for app bar, card, input, three button roles, rail, nav bar, dialog, bottom sheet, divider, list tile, tooltip. Light + dark. | `lib/app/theme/bmd_theme.dart` |
| T-0.2.3 status vocabulary | **Done.** Five typed families with labels; covered by tests including the "green is reserved for outcomes" rule. | `lib/domain/common/status.dart`, `test/design_system/design_system_test.dart:81-140` |
| T-0.2.4 `StatusChip` | **Done.** Single renderer, icon paired with label for every family, announces itself as a status. | `lib/core/design_system/status_chip.dart` |
| T-0.2.5 `BmdButton` | **Partial.** Five variants (primary/tonal/outlined/text/danger), loading state preserving label width, responsive height, Maestro identifier. **Missing: the icon-button variant §5.1 requires, and the one-primary assertion the task names.** | `lib/core/design_system/bmd_button.dart:9` |
| T-0.2.6 `BmdField` / `BmdSearchField` | **Missing entirely.** 11 raw `TextField`/`TextFormField` call sites across 5 feature screens. `inputDecorationTheme` already supplies the visual half. | grep over `lib/features/**` |
| T-0.2.7 `BmdDataTable` | **Partial.** Vertically virtualized, sticky header, horizontal scroll, safe opt-in bulk select, one `Semantics` per row. **The frozen identity column is an admitted TODO in the file itself.** | `lib/core/design_system/bmd_data_table.dart:38-39` |
| T-0.2.8 primitives | **Partial.** `KpiCard` (label/value/denominator/definition/source/freshness) and `ExceptionCard` done. **Side sheet, bottom sheet and dialog primitives absent** — three screens hand-roll `AlertDialog` / `showModalBottomSheet`. | `lib/core/design_system/bmd_cards.dart`; grep for `showDialog` |
| T-0.2.9 gallery + goldens | **Missing entirely.** Zero `matchesGoldenFile` in the repo. | grep over `test/**` |

Two defects surfaced while verifying, both in files this epic touches:

- **The theme names two font families the app does not ship.** `bmdTheme()` sets `fontFamily: 'Inter'` with a `NotoSansBengali` fallback, but the `fonts:` block in `pubspec.yaml` is commented out and `assets/fonts/` does not exist. All text renders in the platform default at runtime and as Ahem boxes under `flutter test`. This directly bounds what any golden can assert.
- **`/dev` is registered unconditionally.** The route comment claims it is "only reachable in E2E builds"; only `initialLocation` is gated by `config.e2e`. The route itself is reachable by URL in a production web build.

## 2. Decisions taken

| # | Decision | Rejected alternatives |
|---|---|---|
| D1 | **Close all five gaps in one epic.** They are one layer, consumed by every downstream feature. | Field + sheets only; gallery-first. Both leave the design system and production drifting for an unbounded period. |
| D2 | **Bundle Inter + Noto Sans Bengali; gate goldens to Linux.** Both families are OFL and freely redistributable, so the pubspec's "licensed TTFs" note is moot. Real glyphs make the §13.2 Bangla-wrapping checklist item testable. | Default test font (typography and Bangla wrapping invisible; leaves the declared-but-missing font defect unfixed); goldens on both platforms (risks a flaky Windows/Linux sub-pixel split); no goldens (drops half of T-0.2.9). |
| D3 | **Migrate all 11 raw field sites in this epic.** A "single renderer" pays off only if there is exactly one renderer; a leftover raw field is the pattern the next screen copies. | Component-only (unbounded drift); search fields only (leaves plain form fields inconsistent). |
| D4 | **Delete the table's horizontal scroll rather than freeze a column.** Priority-weighted flexible columns; overflow collapses into a row-detail side sheet, which §5.3 already prescribes and D5 builds anyway. | Two linked panes (splits each row into two subtrees, so a screen reader reads column-major — a direct hit on the T-3.4.1/3.4.2 release gates); `two_dimensional_scrollables` `TableView` (native pinning and 2D virtualization, but row tap, selection highlight and row semantics must be rebuilt cell-wise, with the same column-major risk). |
| D5 | **Three overlay primitives, one of which encodes decision rules.** `showBmdConfirm` owns mandatory-reason, acknowledgement-gate and downstream-effect, so T-1.4.2 and T-3.1.4 inherit them instead of reimplementing them. | Thin wrappers over `AlertDialog` (every consuming screen re-derives the same three gates, and each gets one of them wrong). |
| D6 | **The one-primary rule is a test helper, not runtime machinery.** | A subtree-counting `InheritedWidget` false-positives the moment a dialog with its own primary sits over a page with one, and ships debug code into the app bundle. |

## 3. Deliverables

1. `assets/fonts/` + completed `pubspec.yaml` `fonts:` block — closes the font defect, prerequisite for D2
2. `test/flutter_test_config.dart` — loads both families for the whole test tree
3. `lib/core/design_system/bmd_field.dart` — `BmdField`, `BmdField.multiline`, `BmdField.masked`, `BmdSearchField` — closes T-0.2.6
4. `lib/core/design_system/bmd_overlays.dart` — `showBmdSideSheet`, `showBmdBottomSheet`, `showBmdConfirm` — closes T-0.2.8
5. `BmdIconButton` + `test/support/single_primary.dart` — closes T-0.2.5
6. `BmdDataTable` priority-flex rewrite — closes T-0.2.7 at D4's scope
7. `lib/features/gallery/presentation/gallery_screen.dart` + `/gallery` route + `test/golden/` baselines — closes T-0.2.9
8. Migrations: 11 field sites, 3 overlay sites, 2 table consumers
9. Router `/dev` + `/gallery` gating fix; CI golden-failure artifact upload

## 4. Component contracts

### 4.1 `BmdField` (§5.2)

`inputDecorationTheme` already gives outlined borders, persistent floating labels, error borders and helper styling. `BmdField` adds only what the theme cannot express.

```dart
BmdField({
  required String label,
  TextEditingController? controller,
  String? helper,        // format, policy, privacy text
  String? errorText,     // externally driven (controller state)
  String? Function(String?)? validator,  // Form-driven inline validation
  String? hint,
  TextInputType? keyboardType,
  bool enabled = true,
  bool required = false,
  String? identifier,    // a11y / Maestro id, matching BmdButton
  ValueChanged<String>? onChanged,
})

BmdField.multiline({ ... })                                  // min height 96px
BmdField.masked({ required String maskedValue, Future<String?> Function()? onReveal, ... })
```

- Height resolves from `Breakpoint.of(context)`: 44px web, 52px mobile — the same lookup `BmdButton` performs, so a field and a button on one row align.
- `required: true` contributes "required" to the **accessible name**, not merely an asterisk glyph. (`required` is legal as a Dart field name alongside the `required` keyword — verified by compiling it.)
- `errorText` and `validator` may both be supplied; **`errorText` wins when non-null.** Controller-driven errors (a server rejection, a duplicate detected asynchronously) must be able to override whatever a synchronous validator currently thinks.
- `BmdField.masked` never holds the unmasked value. It receives an already-masked display string plus `onReveal`, which the caller implements — the caller owns the permission check and the audit write (§10.2), so the widget keeps no dependency on RBAC or `core/audit` and stays trivially testable. When the caller cannot reveal it passes `onReveal: null` and **the affordance is absent, not disabled**: a disabled reveal button advertises data the user may not have.

### 4.2 `BmdSearchField` (§5.3)

```dart
BmdSearchField({
  required ValueChanged<String> onQueryChanged,
  required String scopeLabel,
  Duration debounce = const Duration(milliseconds: 300),
  String? hint,
  String? initialQuery,
  String? identifier,
})
```

`scopeLabel` is required and non-nullable. §5.3 states that search scope must be visible; a non-nullable parameter enforces that better than a QA checklist. It renders as persistent helper text ("Searches name, carpenter ID, phone suffix").

Debounce coalesces typing into one `onQueryChanged`; the timer is cancelled in `dispose`. Clearing bypasses the debounce and fires immediately, because a delayed clear reads as a broken control.

### 4.3 Overlays (§5.6)

§5.6 names four patterns; full-page is a route, so three primitives:

```dart
Future<T?> showBmdSideSheet<T>({ required BuildContext context, required String title,
    required WidgetBuilder builder, List<Widget> actions = const [], double width = 420 })

Future<T?> showBmdBottomSheet<T>({ required BuildContext context, required String title,
    required WidgetBuilder builder })

Future<BmdConfirmResult?> showBmdConfirm({ required BuildContext context,
    required String title, required String body, required String confirmLabel,
    String cancelLabel = 'Cancel', bool danger = false,
    String? reasonLabel, List<String> acknowledgements = const [], String? effect })
```

**Side sheet** uses `showGeneralDialog` + `SlideTransition`, not `Scaffold.endDrawer`: it must be callable from anywhere without the caller owning a Scaffold key, and it must return a value (filters applied vs. dismissed). Width is clamped to `screenWidth - 48` so it never covers a tablet whole. **Below the tablet breakpoint it delegates to `showBmdBottomSheet`** — §5.6 assigns side sheets to web and bottom sheets to mobile, so one call site is correct on both surfaces and the responsive layer honours the guideline automatically.

**Bottom sheet** carries a drag handle, a title row with close, `BmdRadius.sheet` top corners, safe-area padding, and `isScrollControlled` with view-inset awareness, because reason-code sheets contain a text field.

**`showBmdConfirm`** encodes three rules so no screen re-derives them:

- `reasonLabel` set → confirm disabled until the reason is non-empty (T-1.4.2, T-3.1.4)
- `acknowledgements` non-empty → confirm disabled until every box is checked (T-1.4.2, "approve disabled until ack")
- `effect` → rendered as an inline `BmdBanner`, so an irreversible action always states its downstream consequence (T-3.1.4, §2.1)
- `danger: true` → confirm renders as `BmdButtonVariant.danger`

It returns `null` on cancel or dismiss, and on confirm:

```dart
class BmdConfirmResult {
  const BmdConfirmResult({this.reason});
  final String? reason;   // non-null exactly when reasonLabel was supplied
}
```

A record type would do, but a named class gives the call sites a readable type and room to carry an acknowledgement timestamp later, which the audit trail (§12) will want.

### 4.4 `BmdIconButton` and the one-primary rule (§5.1)

`BmdIconButton` is a separate widget, not a sixth `BmdButtonVariant`: an icon button has no label, and folding it into the enum would make `BmdButton.label` meaningless. `tooltip` is required (§5.1: "tooltip on web"); target is 44px web / 48px mobile; `identifier` matches `BmdButton`.

`expectSinglePrimaryAction(WidgetTester)` in `test/support/single_primary.dart` walks the pumped tree for `BmdButton` instances with `variant == primary` and asserts at most one. Applied per screen test, it scopes naturally to the widget under test — which is why it does not false-positive on a dialog primary layered over a page primary, as a runtime counter would.

### 4.5 `BmdDataTable` priority-flex layout (§5.5, §11)

```dart
enum BmdColumnPriority { identity, primary, secondary }

BmdColumn<T>({
  required String id,
  required String label,
  required Widget Function(T row) cell,
  BmdColumnPriority priority = BmdColumnPriority.secondary,
  double minWidth = 96,
  int flex = 1,
  bool numeric = false,
})
```

`LayoutBuilder` measures the available width, then:

1. always renders `identity` columns — the only priority permitted to render below its own `minWidth` when there is truly no room to spare; `primary` columns are dropped into the row detail, last-declared first, before that happens (a mid-epic ruling: round 1 shipped "always renders identity and primary," but squeezing primary below its minWidth to keep it on-screen violates §5.4's "never shrink a column to force a fit," so dropping replaced squeezing);
2. admits `secondary` columns in declaration order while their `minWidth` still fits;
3. distributes remaining width across rendered columns by `flex`.

Dropped columns reach the user through a per-row detail affordance opening `showBmdSideSheet` with the full row, supplied by a new `rowDetailBuilder`. An `assert` fires when columns would be dropped and no `rowDetailBuilder` was given — the failure is loud in dev rather than silent data loss in production.

Removed: `_horizontal`, `Scrollbar`, `SingleChildScrollView`, `_totalWidth`, `BmdColumn.width`.
Retained: `ListView.builder` with fixed `itemExtent`, sticky header, opt-in bulk select, one `Semantics` node per row, `InkWell` row tap.

This is a breaking API change, contained to two in-repo consumers (campaign list, bulk import results).

## 5. Fonts, gallery and goldens

**Fonts.** `assets/fonts/` receives Inter (Regular, Medium, SemiBold, Bold) and Noto Sans Bengali (Regular, SemiBold); the `fonts:` block in `pubspec.yaml` is completed with weight mappings. Independent of goldens, this fixes the theme naming families the app does not ship.

**Test font loading.** `test/flutter_test_config.dart` loads both families once via `FontLoader` for every test beneath `test/`. The existing widget tests become more faithful as a side effect.

**Gallery.** One section per component, each showing every variant and state side by side — the gallery's purpose is to serve as the golden fixture, not to be a catalogue. Sections carry stable keys so a golden can target one section. The `/gallery` route registers only when `config.e2e || !kReleaseMode`; the same gate is applied to `/dev`, fixing the unconditional registration noted in §1.

**Goldens.** `test/support/golden.dart` exposes `goldenTest()`, which passes `skip: !Platform.isLinux` with a stated reason. `flutter test` therefore stays green and honest on Windows (goldens report as skipped) and is authoritative on the `ubuntu-latest` CI runner. No new CI job is needed — the existing `gate` job already runs `flutter test`.

Baselines are captured **per gallery section × {light, dark} × {1280px, 390px}**, not per component-state: section granularity keeps the file count manageable while a regression in any single state still trips the section. One additional Bangla golden covers the text-heavy sections with Bengali copy fed through the components, satisfying the §13.2 item on Bangla/English wrapping — which real Bengali glyphs make testable and the default test font cannot.

One CI change: upload `test/**/failures/` as an artifact when the gate fails. A golden diff nobody can look at is nearly impossible to act on.

## 6. Testing

Goldens catch pixels. These catch rules:

| Unit | Assertions |
|---|---|
| `BmdField` | "required" reaches the accessible name; a masked field never renders the unmasked value without a reveal; `multiline` is at least 96px tall; `onReveal: null` omits the affordance entirely |
| `BmdSearchField` | rapid input coalesces into one `onQueryChanged`; clear fires immediately; `scopeLabel` is rendered |
| `showBmdConfirm` | confirm disabled until reason non-empty; disabled until all acknowledgements checked; `effect` rendered; `danger` uses the danger variant |
| `showBmdSideSheet` | returns its value; delegates to a bottom sheet below the tablet breakpoint |
| `BmdDataTable` | drops secondary columns when narrow, then primary (last-declared first) if identity still cannot fit alongside them, and never identity; asserts when dropping with no `rowDetailBuilder`; existing selection and semantics tests still pass |
| screens | `expectSinglePrimaryAction` on the two existing screen tests and on gallery sections |

Existing coverage that must stay green: `test/design_system/design_system_test.dart` (tokens, `StatusChip`, `LineageRail`, `KpiCard`, feedback), `test/widget/bulk_import_screen_test.dart`, `test/widget/crm_case_screen_test.dart`.

## 7. Sequence

Each step ends with analyze clean and tests green.

1. Fonts + `test/flutter_test_config.dart`
2. `bmd_field.dart` + tests → migrate all 11 raw field sites
3. `bmd_overlays.dart` + tests → migrate the 3 hand-rolled overlay sites (offline queue, registration, carpenter search)
4. `BmdIconButton` + `expectSinglePrimaryAction`
5. `BmdDataTable` priority-flex rewrite → migrate campaign list and bulk import
6. Gallery route + `/dev` gate fix + golden baselines + CI failure-artifact upload

Fonts lead because every golden captured before them would have to be regenerated after.

## 8. Risks

| Risk | Mitigation |
|---|---|
| **Font binaries must be obtained.** If the implementation environment has no network access, step 1 stalls. | Name it immediately and ask for the TTFs to be dropped into `assets/fonts/`. Steps 2–6 proceed regardless; goldens are captured with the default test font and regenerated once the fonts land. |
| **Migrating 11 field sites shifts layout** in the wizard, registration workspace and approval screens, none of which have widget tests today. | Those three lean on the new section goldens plus a manual pass; the two screens that do have tests (bulk import, CRM case) catch structural breakage. |
| **`BmdColumn.width` removal is breaking.** | Contained to two in-repo consumers, migrated in the same step. |
| **Section-level goldens can mask a small regression** inside a busy section. | Behavioural tests in §6 cover the rules that matter; goldens are a geometry and colour net, not the primary contract. |

## 9. Out of scope

- Frozen/pinned columns and `two_dimensional_scrollables` — reconsider only if a real screen (Carpenter 360, analytics drill) needs more columns than priority-flex can honestly fit (D4).
- Saved views and the filter side sheet's *contents* (§5.3) — T-3.1.2 owns those; this epic ships only the sheet primitive.
- Date/time pickers with timezone and conflict guidance (§5.2) — T-1.2.3 owns the conflict semantics; `BmdField` ships without a date variant.
- Chart primitives and the `series`/`funnel` token consumers — T-3.3.1.
- Mobile card variants of wide tables (§5.5) — T-1.3.4.
