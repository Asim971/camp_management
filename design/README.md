# ACSL Carpenter Campaign Management — design system

A BMD-themed Material 3 design system for the campaign management and attendance
verification module: foundations, components, and the complete screen inventory
from §7 of the UI/UX guideline. Every page is a self-contained HTML document with
no external requests, so it renders identically in a browser, in the Claude
Design System pane, and in a print-to-PDF handoff.

This is the practical stand-in for the Figma file the guideline's §12 describes,
and it is the visual reference the Flutter app in `lib/` is built against.

## Layout

```
design/
├── build.mjs          assembles dist/ from src/, then self-checks the output
├── PALETTE.md         derivation and evidence for every machine-checked colour
├── scripts/           the palette derivation + validation scripts
├── src/
│   ├── tokens.css     the token layer — colour, space, radius, elevation, type
│   ├── system.css     the component layer (bmd- prefixed)
│   ├── docs.css       documentation chrome (ds- prefixed)
│   ├── partials/      shared markup, spliced in with <!--@include ...-->
│   └── pages/         one body fragment per specimen
└── dist/              generated — 33 specimens + an index
```

## Build

```bash
node design/build.mjs
```

Emits `design/dist/` and runs a self-check that fails the build on: a missing or
malformed `@dsCard` marker, any external `src`/`href`, unbalanced markup, or a raw
hex used as a value in a style attribute where a token exists. It warns on thin
specimens and inline `<script>`.

Review the whole set in a browser by opening `design/dist/index.html`.

## The 33 specimens

| Group | Contents |
|---|---|
| Foundations | Colour · Typography · Space, radius & elevation · Status vocabulary · Accessibility & privacy |
| Components | Lineage rail · Buttons · Forms · Chips · Tables & KPIs · Filters · Overlays · Evidence · States · Charts · Shell |
| Web · Campaign | W-01 Dashboard · W-02 List · W-03 Wizard · W-04 Approval · W-05 Detail & sessions · W-06 Registration · W-07 Bulk import |
| Mobile · Field | M-01 Readiness · M-02 Search · M-03 Notice & capture · M-04 Offline queue |
| CRM | C-01 Verification queue · C-02 Verification case |
| Analytics | A-01 Carpenter 360 · A-02 Analytics & ROI · A-03 Integrity & operations |
| Administration | AD-01 Configuration & audit |

## The three decisions worth knowing

**The lineage rail is the signature component.** An attendance record moves
through an irreversible chain — captured, queued, uploaded, matched, decided,
counted. The guideline's two hardest requirements are both about position in that
chain rather than final state: capture success is not upload success (§8.11), and
the machine's opinion is not the human's decision (§8.13). Both are lost when a
record collapses to one status chip, so the chain itself is a component and it
renders identically on the mobile queue, the CRM case, Carpenter 360 and the audit
trail. It is the one component that never wears brand red, because red means
"press this" and the rail is a report.

**Dashboards open on the action backlog, not on totals.** Guideline §6.1 requires
exceptions before aggregates, so the KPI row does not lead any dashboard in this
system. Exception cards carry a count, a hairline age bar and a route to the queue
that resolves them.

**Colour is assigned by job and validated, not chosen.** Categorical slots carry
identity, the navy ordinal ramp carries sequence, the reserved semantic quartet
carries state. The categorical order was derived by enumeration and clears every
CVD and normal-vision gate in both light and dark mode against BMD's own surfaces.
See [`PALETTE.md`](PALETTE.md) — including the four slots that sit below 3:1 and
the direct-label / table-view obligation that makes them legal.

## Token parity with the Flutter app

`src/tokens.css` and `lib/app/theme/tokens.dart` describe the same system and use
the same names (`brand.primary.600`, `space.4`, `radius.3`, `semantic.success`).
When one changes, change both — the CSS file is the source of truth for values,
and `PALETTE.md` is the source of truth for why.

## Publishing

The bundle is designed to be pushed to a Claude Design project with `DesignSync`.
Each page's first line carries a `@dsCard` marker with its group, name, subtitle
and viewport, which is what builds the Design System pane's card index — so
`dist/` uploads as-is with no separate registration step.
