# Expressive Redesign — Slice 3: the Analytics showpiece (A-02)

**Status:** design, ready for planning.

The third slice of the expressive pivot builds the platform's second signature
surface: **Campaign Analytics (A-02, guideline §8.15)**. Two placeholders die —
the global `/analytics` route and campaign detail's Analytics tab — replaced by
one shared, chart-driven panel fed by a new server aggregate endpoint. Strictly
P0 **"campaign-linked contribution"**: activity and verification analytics,
never sales impact — uplift/attribution/cost/ROI are P1/P2 per the guideline's
own firewall and are explicitly out of this slice (their data does not exist).

Deferred slices unchanged: branded web shell + login (slice 4), the
illustration/empty-state art pass (slice 5).

---

## 1. Context and current state

- `/analytics` renders `PlaceholderScreen` behind `Permission.export`
  (`lib/app/router/route_table.dart:73`); campaign detail's Analytics tab is a
  `_Placeholder('Analytics — see A-02')`.
- Slices 1–2 (merged, PRs #15/#16) provide everything visual this slice
  consumes: `ScreenHero`, `BmdStateView`, motion primitives
  (`Reveal`/`CountUp`/`Shimmer`, `motionOff`/`reduced`), glass tokens, the
  Dashboard's fl_chart funnel/donut patterns, and `BmdDataTable`/`BmdBanner`.
- The real server (`server/lib/src/`) follows a module pattern
  (`<area>/<area>_routes.dart` + `<area>_repo.dart`, mounted in `app.dart`);
  `tool/mock_server` mirrors every route and `server/test/contract/
  parity_test.dart` pins mock ≡ real. Attendance rows carry `status`,
  `captured_at`, `machine_band` and campaign linkage via sessions — enough for
  funnel, per-day trend and band mix.
- Guideline anchors: §6 (every KPI/chart carries a defence line: definition,
  source, freshness), §8.15 (layout, required states, the P0/P1 label
  firewall), RD.D1 (dense tables stay hairline).

## 2. Decisions

### RD3.D1 — One aggregate endpoint: `GET /analytics/summary`

New `server/lib/src/analytics/` module (`analytics_routes.dart`,
`analytics_repo.dart`), mounted like verification/campaign routes, mirrored in
`tool/mock_server`.

- **Query:** `campaignId` (optional; absent = all campaigns in the caller's
  org scope), `from`/`to` (optional ISO-8601 dates, inclusive; default = the
  30 days ending today).
- **Response shape (wire):**

```json
{
  "funnel": { "target": 500, "registered": 320, "captured": 210,
              "inReview": 9, "approved": 180, "rejected": 12, "returned": 6 },
  "verifiedPerDay": [ { "date": "2026-08-01", "count": 14 } ],
  "bandMix": { "high": 120, "medium": 60, "low": 18, "noReference": 12 },
  "campaigns": [ { "id": "CAMP-1", "name": "ACSL Pilot Carpenter Drive",
                   "status": "ACTIVE", "target": 500, "verified": 180,
                   "inReview": 9 } ],
  "sample": { "totalAttendance": 210, "small": false },
  "range": { "from": "2026-07-17", "to": "2026-08-15" },
  "generatedAt": "2026-08-15T17:20:00Z"
}
```

`range` echoes the RESOLVED inclusive dates the server actually aggregated
over (after defaulting). Clients render axes and range labels exclusively
from this echo — never from a client-side "today" — which keeps rendering
deterministic and the two sides agreed on what the numbers cover.

- **Semantics:** `funnel.target`/`registered` come from campaign + session
  tables; `captured` is the TOTAL attendance rows in range (any status);
  `inReview`/`approved`/`rejected`/`returned` count attendance rows by
  status within the range (all range filters use `captured_at`).
  `campaigns[].verified`/`inReview` are range-scoped the same way — every
  number on the screen shares one range, never mixing lifetime and ranged
  counts.
  `verifiedPerDay` groups APPROVED attendance by `captured_at` UTC date;
  days with zero approvals are omitted (the client renders gaps as zero).
  `bandMix` counts attendance by `machine_band` in range. `campaigns` is the
  drill list, filtered to the query scope. `sample.small` is
  `totalAttendance < 30`.
- **Authz:** requires `Permission.export` (the same permission already gating
  the `/analytics` route); org-scoped like every other read. 403 without it.
- **Client layering (the standard stack):** freezed wire models in
  `lib/domain/analytics/analytics_summary.dart`; Dio-backed
  `AnalyticsRepositoryImpl` in `lib/data/analytics/`;
  `analyticsSummaryProvider` — an autoDispose AsyncNotifier family keyed by an
  `AnalyticsQuery` value type `{String? campaignId, DateRangePreset range}`
  where `DateRangePreset { d7, d30, d90 }`.
- **Parity:** `server/test/contract/parity_test.dart` gains cases pinning the
  mock and real responses for: default query, campaign-filtered, ranged,
  permission-denied.

### RD3.D2 — One shared `AnalyticsPanel`, two mounts

`lib/features/analytics/presentation/analytics_panel.dart` renders the four
zones from one `AnalyticsSummary`. Mounts:

1. **Global `/analytics`** (`analytics_screen.dart`, replaces the
   placeholder): `ScreenHero(title: 'Campaign analytics', subtitle:
   'Campaign-linked contribution — activity, not sales impact')`. The filter
   header lives in the hero: a campaign selector (All campaigns + the
   `campaignListProvider` page's campaigns) and a 7d/30d/90d range chip set.
   Selector and chips re-key the provider family. Route gate unchanged.
2. **Campaign detail → Analytics tab:** the same panel pre-filtered
   (`campaignId` fixed, range chips only), no hero, no campaign selector, no
   drill table. The `_Placeholder` dies.

### RD3.D3 — The four zones (all fl_chart, §6 defence lines everywhere)

1. **Verification trend** — `LineChart` of `verifiedPerDay` over the range
   (zero-filled days), accent-cyan line with a soft below-line gradient fill,
   sweep-in animation via the standard motion tokens (full line on the first
   frame under reduced motion). Defence line: "Approved attendance per day ·
   Campaign service · <range label>".
2. **Funnel** — horizontal `BarChart` (`rotationQuarterTurns: 1`, the
   Dashboard pattern): target → registered → captured → in review → approved.
   Rejected/returned render as a muted text annotation row beneath — never as
   bars in the same series (§8.15 keeps outcomes distinct from progression).
3. **Band mix** — donut (`PieChart`) of `bandMix` with direct labels, using
   the validated data-series palette tokens.
4. **Drill table** — `BmdDataTable` of `campaigns`: name, status
   (`StatusChip`), target, verified, in review; row-tap →
   `/campaigns/<id>`. Hairline-dense (RD.D1). Global mount only.

New Semantics identifiers (additive only): `analytics_trend`,
`analytics_funnel`, `analytics_band_mix`, `analytics_table`,
`analytics_range_<preset>` (d7/d30/d90), `analytics_campaign_filter`.

### RD3.D4 — Required states (§8.15 mapped to what ships)

- **Small sample:** `sample.small` → `BmdBanner` (warning tone): "Fewer than
  30 attendance records in this range — read trends cautiously." Charts still
  render.
- **Empty:** zero attendance in range → `BmdStateView.empty(title: 'No
  attendance in this range', message: 'Widen the date range or pick another
  campaign.')`.
- **Error:** `BmdStateView.error` with retry (provider invalidate).
- **Loading:** a skeleton shaped like the four zones (`Shimmer`, the
  Dashboard skeleton pattern).
- **Explicitly out (no data source exists):** data-delayed, incomplete-cost,
  order-reconciliation-gap states, and every order/attribution/repeat/ROI
  panel. Recorded here so their absence reads as a decision, not a gap.

### RD3.D5 — Mobile behavior (§8.15: summary + limited trend)

Compact widths stack the zones vertically (trend → funnel → donut → table);
no separate mobile code beyond breakpoint stacking. Complex analysis remains
desktop-first by layout, not by feature removal.

## 3. Out of scope

- Export/download of the dataset (the guideline's "export authorized
  dataset" action) — needs product decisions on format/audit; later work.
- Campaign comparison overlays; A-03 integrity dashboard; anything ROI.
- Historical backfill or caching of summaries; the endpoint computes live.

## 4. Global constraints (binding)

1. Existing `Semantics(identifier:)` strings, routes, provider APIs and
   flows stay byte-identical; the only additions are RD3.D3's identifiers.
   All existing Maestro flows and widget tests pass unmodified.
2. New e2e coverage: one flow `analytics_summary.yaml` (realAuth sign-in as
   an export-holding role → `/analytics` → assert `analytics_trend`,
   `analytics_funnel`, `analytics_table` visible), listed in
   `.maestro/config.yaml` and the CI e2e matrix (5c precedent). ASCII-only
   inputText; scrollUntilVisible for anything below the fold.
3. All motion through `motionOff`/`reduced`; cyan stays accent/data-only;
   red stays the only action color; dense tables hairline (RD.D1).
4. `dart format` clean; `flutter analyze --fatal-infos` clean project-wide;
   server suite + contract parity green; full `flutter test` green.
5. Goldens regenerated only via the Linux `goldens.yml` workflow; no PNGs
   authored locally. `ENABLE_TEST_SEEDING` never committed enabled.
6. Work on `feat/analytics-showpiece` off `main`; merge only on explicit
   user go-ahead.

## 5. Testing

- **Server:** `analytics_repo` unit tests — funnel counts by status, per-day
  grouping (incl. range edges and zero-approval days omitted), campaign
  filter, org scoping, `sample.small` threshold at exactly 29/30/31; route
  tests — 403 without `Permission.export`, param validation (bad dates →
  400). Parity: default/filtered/ranged/denied.
- **Client:** widget tests — panel renders four zones from a seeded summary;
  banner at `small: true`; empty and error states; range chip re-keys the
  provider; detail-tab mount hides selector + table; reduced-motion renders
  the trend in a single pump; identifier sweep for the new identifiers.
- **Goldens:** `analytics-desktop-dark` + `analytics-mobile-light` via the
  seeded-notifier harness in `test/golden/screens_golden_test.dart`'s
  pattern.
- **E2E:** the flow per constraint 2, run in CI's emulator matrix.

## 6. File map

| File | Change |
|---|---|
| `server/lib/src/analytics/analytics_repo.dart` | new — RD3.D1 aggregates |
| `server/lib/src/analytics/analytics_routes.dart` | new — route + authz |
| `server/lib/src/app.dart` | mount analytics routes |
| `tool/mock_server/bin/server.dart` | mirror `/analytics/summary` |
| `server/test/contract/parity_test.dart` | parity cases |
| `lib/domain/analytics/analytics_summary.dart` | new — freezed models + query |
| `lib/data/analytics/analytics_repository_impl.dart` | new — Dio repo |
| `lib/features/analytics/application/analytics_notifier.dart` | new — provider family |
| `lib/features/analytics/presentation/analytics_panel.dart` | new — RD3.D2/D3 |
| `lib/features/analytics/presentation/analytics_screen.dart` | new — global mount |
| `lib/app/router/app_router.dart` | `/analytics` → AnalyticsScreen |
| `lib/features/campaign_detail/presentation/campaign_detail_screen.dart` | Analytics tab mounts panel |
| `.maestro/flows/analytics_summary.yaml` + `.maestro/config.yaml` + `.github/workflows/ci.yml` | e2e flow + matrix |
| `test/...` | per §5 |
