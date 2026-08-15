# Analytics Showpiece (Slice 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build A-02 Campaign Analytics — one server aggregate endpoint (`GET /analytics/summary`) and one shared `AnalyticsPanel` mounted at `/analytics` and in campaign detail's Analytics tab.

**Architecture:** Server-first: a new `analytics` module in campaign_service computes range-scoped aggregates (funnel, verified-per-day, band mix, drill rows) with mock-server parity; the client consumes it through the standard freezed-model → Dio-repo → AsyncNotifier-family stack; the panel renders four fl_chart zones with §6 defence lines and slice-1/2 primitives.

**Tech Stack:** Dart 3.12 / Flutter 3.44.8, shelf + shelf_router + postgres (server), freezed, Riverpod, fl_chart, GoRouter, Maestro.

**Spec:** `docs/superpowers/specs/2026-08-15-analytics-showpiece-design.md`

## Global Constraints

- Existing `Semantics(identifier:)` strings, routes, provider APIs and flows stay byte-identical. Additive identifiers ONLY: `analytics_trend`, `analytics_funnel`, `analytics_band_mix`, `analytics_table`, `analytics_range_d7`, `analytics_range_d30`, `analytics_range_d90`, `analytics_campaign_filter`. All existing Maestro flows and widget tests pass unmodified.
- Server permission string is `'export'` (wire snake); client enum is `Permission.export`. Org-scoped reads like every other module.
- All range filters use `captured_at`; every number on the screen shares one range (never lifetime + ranged mixed). `sample.small` ⇔ `totalAttendance < 30`.
- All motion through `motionOff`/`reduced` (`lib/core/motion/motion_tokens.dart`); cyan (`bmd.accent`) is data/accent only; red stays the only action color; `BmdDataTable` stays hairline-dense.
- Quality gates per task: `dart format` clean; `flutter analyze --fatal-infos` clean project-wide; the tests the task touches green. Server tasks additionally: `dart analyze server` clean and the server suite green (`dart test` in `server/`). Full sweeps in the final task.
- Goldens are Linux-gated (`test/support/golden.dart`); write golden tests but NEVER generate or commit `.png`s — baselines come from the `goldens.yml` workflow after the PR opens (controller handles it).
- Maestro: ASCII-only `inputText`; `scrollUntilVisible` for anything below the fold; new flow listed in `.maestro/config.yaml`.
- `ENABLE_TEST_SEEDING` never committed enabled. Branch: `feat/analytics-showpiece` off `main`.
- ENVIRONMENT: Flutter/Dart are NOT on the default shell PATH — prefix every command with `export PATH="/c/Users/Asim/flutter/bin:$PATH"`. (`dart` for server work comes from the same directory.)
- Widget tests set viewports via `tester.view.physicalSize` + `devicePixelRatio = 1.0` + `addTearDown(tester.view.reset)`.
- Server tests: get a database with `freshDb()` (`server/test/support/test_db.dart`); seed with the helpers in `server/test/support/seed_fixtures.dart` and the local `seedCrmReviewAttendance` pattern from `server/test/verification/verification_routes_test.dart` (copy that helper into your test file if needed — it is file-local, not shared).

---

## File map

| File | Task |
|---|---|
| `lib/domain/analytics/analytics_summary.dart` (+ generated) | 1 |
| `test/domain/analytics/analytics_summary_test.dart` | 1 |
| `server/lib/src/analytics/analytics_repo.dart` | 2 |
| `server/lib/src/analytics/analytics_routes.dart` | 2 |
| `server/lib/src/app.dart` | 2 |
| `server/test/analytics/analytics_routes_test.dart` | 2 |
| `tool/mock_server/bin/server.dart` | 3 |
| `server/test/contract/parity_test.dart` | 3 |
| `lib/data/analytics/analytics_repository_impl.dart` | 4 |
| `lib/features/analytics/application/analytics_notifier.dart` | 4 |
| `test/features/analytics/analytics_notifier_test.dart` | 4 |
| `lib/features/analytics/presentation/analytics_panel.dart` (+ 4 zone widgets in `widgets/`) | 5 |
| `test/features/analytics/analytics_panel_test.dart` | 5 |
| `lib/features/analytics/presentation/analytics_screen.dart` | 6 |
| `lib/app/router/app_router.dart` | 6 |
| `lib/features/campaign_detail/presentation/campaign_detail_screen.dart` | 6 |
| `test/features/analytics/analytics_screen_test.dart` | 6 |
| `test/golden/screens_golden_test.dart`, `.maestro/flows/analytics_summary.yaml`, `.maestro/config.yaml`, `.github/workflows/ci.yml` | 7 |

---

### Task 1: Domain models — `AnalyticsSummary`, `AnalyticsQuery`

**Files:**
- Create: `lib/domain/analytics/analytics_summary.dart`
- Test: `test/domain/analytics/analytics_summary_test.dart`

**Interfaces:**
- Consumes: `MatchBand` (from `package:campaign_contracts/campaign_contracts.dart`), `CampaignStatus` (`lib/domain/common/status.dart` re-export), freezed/json_serializable (already dev-deps; codegen via build_runner).
- Produces (exact — later tasks depend on these):

```dart
enum DateRangePreset { d7, d30, d90 }           // .days => 7|30|90
class AnalyticsQuery { final String? campaignId; final DateRangePreset range; }  // freezed, == by value
class AnalyticsFunnel { int target, registered, captured, inReview, approved, rejected, returned; }
class DailyCount { DateTime date; int count; }
class AnalyticsCampaignRow { String id, name; CampaignStatus status; int target, verified, inReview; }
class AnalyticsSample { int totalAttendance; bool small; }
class AnalyticsRange { DateTime from; DateTime to; }   // resolved inclusive dates, echoed by the server
class AnalyticsSummary {
  AnalyticsFunnel funnel;
  List<DailyCount> verifiedPerDay;
  Map<MatchBand, int> bandMix;
  List<AnalyticsCampaignRow> campaigns;
  AnalyticsSample sample;
  AnalyticsRange range;
  DateTime generatedAt;
  factory AnalyticsSummary.fromWire(Map<String, dynamic> json);
}
```

**Range echo (spec amendment, binding):** the wire envelope carries
`"range": {"from": "2026-07-17", "to": "2026-08-15"}` — the RESOLVED
inclusive dates the server aggregated over (after defaulting). All client
axes/range labels derive from this echo, never from a client-side
`DateTime.now()` — that is what keeps goldens deterministic.

- [ ] **Step 1: Write the failing test**

`test/domain/analytics/analytics_summary_test.dart`:

```dart
import 'package:acsl_campaign/domain/analytics/analytics_summary.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AnalyticsSummary.fromWire parses the full envelope', () {
    final s = AnalyticsSummary.fromWire({
      'funnel': {
        'target': 500, 'registered': 320, 'captured': 210,
        'inReview': 9, 'approved': 180, 'rejected': 12, 'returned': 6,
      },
      'verifiedPerDay': [
        {'date': '2026-08-01', 'count': 14},
        {'date': '2026-08-03', 'count': 2},
      ],
      'bandMix': {'HIGH': 120, 'MEDIUM': 60, 'LOW': 18, 'NO_REFERENCE': 12},
      'campaigns': [
        {'id': 'CAMP-1', 'name': 'ACSL Pilot Carpenter Drive',
         'status': 'ACTIVE', 'target': 500, 'verified': 180, 'inReview': 9},
      ],
      'sample': {'totalAttendance': 210, 'small': false},
      'range': {'from': '2026-07-17', 'to': '2026-08-15'},
      'generatedAt': '2026-08-15T17:20:00Z',
    });
    expect(s.range.from, DateTime.utc(2026, 7, 17));
    expect(s.funnel.captured, 210);
    expect(s.verifiedPerDay, hasLength(2));
    expect(s.verifiedPerDay.first.date, DateTime.utc(2026, 8, 1));
    expect(s.bandMix[MatchBand.high], 120);
    expect(s.campaigns.single.status, CampaignStatus.active);
    expect(s.sample.small, isFalse);
  });

  test('bandMix ignores unknown band keys instead of throwing', () {
    final s = AnalyticsSummary.fromWire({
      'funnel': {'target': 0, 'registered': 0, 'captured': 0,
                 'inReview': 0, 'approved': 0, 'rejected': 0, 'returned': 0},
      'verifiedPerDay': const [],
      'bandMix': {'HIGH': 1, 'FUTURE_BAND': 9},
      'campaigns': const [],
      'sample': {'totalAttendance': 1, 'small': true},
      'range': {'from': '2026-08-01', 'to': '2026-08-15'},
      'generatedAt': '2026-08-15T00:00:00Z',
    });
    expect(s.bandMix, {MatchBand.high: 1});
  });

  test('AnalyticsQuery equality drives provider family identity', () {
    expect(
      const AnalyticsQuery(campaignId: 'C1', range: DateRangePreset.d30),
      const AnalyticsQuery(campaignId: 'C1', range: DateRangePreset.d30),
    );
    expect(DateRangePreset.d90.days, 90);
  });
}
```

- [ ] **Step 2: Run it to verify it fails** — `flutter test test/domain/analytics/` → FAIL (file missing).

- [ ] **Step 3: Implement `lib/domain/analytics/analytics_summary.dart`**

Model on `lib/domain/verification/verification_case.dart` (freezed classes + hand-written `fromWire` where wire enums need `tryParseWire`). Concretely:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../common/status.dart';

part 'analytics_summary.freezed.dart';

/// The three range presets the analytics filter offers (spec RD3.D1); the
/// query sends explicit from/to dates computed from `days`.
enum DateRangePreset {
  d7(7), d30(30), d90(90);
  const DateRangePreset(this.days);
  final int days;
}

@freezed
class AnalyticsQuery with _$AnalyticsQuery {
  const factory AnalyticsQuery({
    String? campaignId,
    @Default(DateRangePreset.d30) DateRangePreset range,
  }) = _AnalyticsQuery;
}

@freezed
class AnalyticsFunnel with _$AnalyticsFunnel {
  const factory AnalyticsFunnel({
    required int target, required int registered, required int captured,
    required int inReview, required int approved,
    required int rejected, required int returned,
  }) = _AnalyticsFunnel;
}

@freezed
class DailyCount with _$DailyCount {
  const factory DailyCount({required DateTime date, required int count}) = _DailyCount;
}

@freezed
class AnalyticsCampaignRow with _$AnalyticsCampaignRow {
  const factory AnalyticsCampaignRow({
    required String id, required String name, required CampaignStatus status,
    required int target, required int verified, required int inReview,
  }) = _AnalyticsCampaignRow;
}

@freezed
class AnalyticsSample with _$AnalyticsSample {
  const factory AnalyticsSample({
    required int totalAttendance, required bool small,
  }) = _AnalyticsSample;
}

@freezed
class AnalyticsSummary with _$AnalyticsSummary {
  const factory AnalyticsSummary({
    required AnalyticsFunnel funnel,
    required List<DailyCount> verifiedPerDay,
    required Map<MatchBand, int> bandMix,
    required List<AnalyticsCampaignRow> campaigns,
    required AnalyticsSample sample,
    required DateTime generatedAt,
  }) = _AnalyticsSummary;

  /// Wire → domain. Unknown band keys are skipped (a future server band must
  /// not crash an older client); unknown campaign statuses fall back the way
  /// `campaignFromWire` handles them (use `CampaignStatus` tryParse + throw,
  /// matching the strictness of `lib/data/campaign/campaign_mapper.dart` —
  /// read it and mirror its exact status-parse behavior).
  factory AnalyticsSummary.fromWire(Map<String, dynamic> json) { /* build all six parts */ }
}
```

For `fromWire`, parse `funnel` field-by-field (`as int`), `verifiedPerDay` via `DateTime.parse('${e['date']}T00:00:00Z')` (dates are day-precision UTC), `bandMix` with `MatchBand.tryParseWire(key)` skipping nulls, `campaigns` with the same status parse `campaign_mapper.dart` uses, `sample` field-by-field, `range` via the same day-precision parse (`AnalyticsRange` freezed class with `from`/`to`), `generatedAt` with `DateTime.parse(...).toUtc()`.

- [ ] **Step 4: Codegen + run** — `dart run build_runner build --delete-conflicting-outputs`, then `flutter test test/domain/analytics/` → PASS (3 tests). Do not stage `*.freezed.dart` (git-ignored).

- [ ] **Step 5: Gates + commit**

```bash
dart format lib/domain/analytics test/domain/analytics
flutter analyze --fatal-infos
git add lib/domain/analytics/analytics_summary.dart test/domain/analytics/analytics_summary_test.dart
git commit -m "feat(analytics): AnalyticsSummary domain models + wire parsing (RD3.D1)"
```

---

### Task 2: Server — `analytics` module (repo + routes + mount)

**Files:**
- Create: `server/lib/src/analytics/analytics_repo.dart`, `server/lib/src/analytics/analytics_routes.dart`
- Modify: `server/lib/src/app.dart` (add an `analyticsHandler` leg to the Cascade, `_authenticateUnder(const {'analytics'}, ...)` — mirror the `verificationHandler` block at `app.dart:138-145`)
- Test: `server/test/analytics/analytics_routes_test.dart`

**Interfaces:**
- Consumes: `Db` (`server/lib/src/db/pool.dart`), `requirePermission`/`authOf` (`server/lib/src/auth/middleware.dart`), `ApiException`/`ApiErrorCode` (`server/lib/src/infra/error_envelope.dart`), schema: `attendance(campaign_id, session_id, status, captured_at, machine_band, organization_id)`, `campaigns(id, name, status, target_audience, organization_id)`, `registrations(campaign_id)`.
- Produces: `GET /analytics/summary?campaignId=&from=&to=` behind `requirePermission('export')`, returning the spec's exact envelope. `AnalyticsRepo.summary({required String organizationId, String? campaignId, required DateTime from, required DateTime to})` → `Map<String, Object?>`.

Response/semantics contract (from the spec, binding):
- `funnel.target` = SUM(`campaigns.target_audience`) over scope; `registered` = COUNT(`registrations`) over scope. These two are STRUCTURAL denominators (campaign/registration tables carry no ranged meaning); the spec's "every number shares one range" governs the attendance-derived counts. State exactly that in the route docstring and a repo comment — it is the ruling that resolves the spec's two sentences.
- `captured` = COUNT(attendance in scope AND `captured_at` in [from, to]]); `inReview|approved|rejected|returned` = same with `status = 'CRM_REVIEW'|'APPROVED'|'REJECTED'|'RETURNED'`.
- `verifiedPerDay` = APPROVED attendance grouped by `date_trunc('day', captured_at AT TIME ZONE 'UTC')`, ordered ascending, zero days omitted.
- `bandMix` = COUNT by `machine_band` (skip NULL bands) in range/scope, keys exactly `HIGH|MEDIUM|LOW|NO_REFERENCE`.
- `campaigns` = one row per campaign in scope: id, name, status (wire), target_audience, ranged APPROVED count, ranged CRM_REVIEW count; ordered by name.
- `sample.totalAttendance` = `captured`; `small` = `< 30`.
- Range validation: `from`/`to` must parse as ISO dates (`DateTime.tryParse`), `from <= to`, else `ApiException(ApiErrorCode.badRequest, message: 'Invalid analytics range.')`. Defaults: `to` = today UTC (end-of-day inclusive: pass `to + 1 day` exclusive in SQL), `from` = `to - 29 days`.
- `campaignId` outside the caller's org → empty aggregates (org scoping simply yields nothing), NOT a 404 — consistent with list-read behavior elsewhere.

- [ ] **Step 1: Write the failing route/repo tests**

`server/test/analytics/analytics_routes_test.dart` — copy the harness shape of `server/test/verification/verification_routes_test.dart` (build the app handler via `buildHandler`/`createApp` exactly as that file does — read its `setUp` and mirror it verbatim, including token minting for roles). Copy its file-local `seedCrmReviewAttendance` helper. Cases:

```dart
// 1. 403 without export: token for role 'field_user' → GET /analytics/summary → 403.
// 2. Happy path: seed org ORG_1 with campaign C1 (target_audience 500),
//    2 registrations, and attendance rows:
//      A1 APPROVED  captured_at 2026-08-01T10:00Z band HIGH
//      A2 APPROVED  captured_at 2026-08-01T15:00Z band MEDIUM
//      A3 APPROVED  captured_at 2026-08-03T09:00Z band HIGH
//      A4 CRM_REVIEW captured_at 2026-08-03T11:00Z band LOW
//      A5 REJECTED  captured_at 2026-08-04T08:00Z band NO_REFERENCE
//    GET /analytics/summary?from=2026-08-01&to=2026-08-31 as campaign_creator:
//    funnel == {target:500, registered:2, captured:5, inReview:1,
//               approved:3, rejected:1, returned:0}
//    verifiedPerDay == [{date:'2026-08-01',count:2},{date:'2026-08-03',count:1}]
//    bandMix == {HIGH:2, MEDIUM:1, LOW:1, NO_REFERENCE:1}
//    campaigns == [C1 row with verified:3, inReview:1]
//    sample == {totalAttendance:5, small:true}
// 3. Range edges: from=2026-08-03&to=2026-08-03 → captured:2 (A3,A4);
//    A row captured at 2026-08-03T23:59:59Z is INCLUDED (inclusive to-date).
// 4. campaignId filter: second campaign C2 with 1 APPROVED row; ?campaignId=C1
//    excludes it everywhere (funnel, perDay, bandMix, campaigns list length 1).
// 5. Org scoping: attendance in ORG_2 never appears for an ORG_1 token.
// 6. small threshold: with exactly 30 in-range rows small==false; with 29 true.
//    (Seed with a loop; keep bands constant to avoid combinatorial noise.)
// 7. Bad range: from=notadate → 400; from>to → 400.
```

Write these as real `test()` bodies asserting the decoded JSON (the file you are mirroring shows the request/assert idiom — reuse it).

- [ ] **Step 2: Run to verify failure** — from `server/`: `dart test test/analytics/` → FAIL (module missing).

- [ ] **Step 3: Implement the repo**

`server/lib/src/analytics/analytics_repo.dart` — one class, one public method, plain SQL via the `Db` API (`db.query`/`db.execute` — mirror `verification_repo.dart`'s call style exactly, including `Sql.named` usage):

```dart
class AnalyticsRepo {
  AnalyticsRepo(this._db);
  final Db _db;

  Future<Map<String, Object?>> summary({
    required String organizationId,
    String? campaignId,
    required DateTime from,   // inclusive UTC date
    required DateTime to,     // inclusive UTC date
  }) async {
    final toExclusive = DateTime.utc(to.year, to.month, to.day).add(const Duration(days: 1));
    final fromUtc = DateTime.utc(from.year, from.month, from.day);
    // WHERE fragments share:
    //   a.organization_id = @org AND (@camp::text IS NULL OR a.campaign_id = @camp)
    //   AND a.captured_at >= @from AND a.captured_at < @to
    // Structural side (campaigns/registrations) filters org + optional campaign only.
    // Five queries, each small and indexed:
    //  q1 structural: SELECT COALESCE(SUM(c.target_audience),0) AS target,
    //       (SELECT COUNT(*) FROM registrations r JOIN campaigns c2 ON c2.id = r.campaign_id
    //         WHERE c2.organization_id = @org AND (@camp::text IS NULL OR r.campaign_id = @camp)) AS registered
    //     FROM campaigns c WHERE c.organization_id = @org AND (@camp::text IS NULL OR c.id = @camp)
    //  q2 statuses:  SELECT a.status, COUNT(*) FROM attendance a WHERE <ranged> GROUP BY a.status
    //  q3 per-day:   SELECT date_trunc('day', a.captured_at AT TIME ZONE 'UTC') AS d, COUNT(*)
    //                FROM attendance a WHERE <ranged> AND a.status = 'APPROVED' GROUP BY d ORDER BY d
    //  q4 bands:     SELECT a.machine_band, COUNT(*) FROM attendance a
    //                WHERE <ranged> AND a.machine_band IS NOT NULL GROUP BY a.machine_band
    //  q5 drill:     SELECT c.id, c.name, c.status, c.target_audience,
    //                  COUNT(*) FILTER (WHERE a.status = 'APPROVED') AS verified,
    //                  COUNT(*) FILTER (WHERE a.status = 'CRM_REVIEW') AS in_review
    //                FROM campaigns c
    //                LEFT JOIN attendance a ON a.campaign_id = c.id
    //                  AND a.captured_at >= @from AND a.captured_at < @to
    //                WHERE c.organization_id = @org AND (@camp::text IS NULL OR c.id = @camp)
    //                GROUP BY c.id, c.name, c.status, c.target_audience ORDER BY c.name
    // Assemble the exact envelope; captured = sum of q2 counts; totalAttendance = captured;
    // small = captured < 30; generatedAt = DateTime.now().toUtc().toIso8601String();
    // verifiedPerDay date serialized as 'yyyy-MM-dd' (10-char substring of toIso8601String());
    // range echoed as {'from': <fromUtc yyyy-MM-dd>, 'to': <to yyyy-MM-dd>} — the resolved
    // inclusive dates (Task 2's route computes defaults BEFORE calling summary, so the echo
    // always reflects what was aggregated).
  }
}
```

Write the real SQL strings (the comments above ARE the queries — transcribe them into `Sql.named` calls with `@org/@camp/@from/@to` parameters).

- [ ] **Step 4: Implement the routes + mount**

`server/lib/src/analytics/analytics_routes.dart` — mirror `verification_routes.dart`'s shape exactly (imports, `Router`, `Pipeline`, local `_json` helper):

```dart
/// `/analytics/summary` — range-scoped campaign-linked contribution
/// aggregates (A-02, slice 3 RD3.D1). Requires `export`. The range governs
/// attendance-derived numbers; funnel.target/registered are structural
/// denominators (campaign + registration tables, unranged by design).
Router analyticsRouter({required Db db}) {
  final router = Router();
  final repo = AnalyticsRepo(db);
  router.get(
    '/analytics/summary',
    const Pipeline()
        .addMiddleware(requirePermission('export'))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final qp = request.url.queryParameters;
          final now = DateTime.now().toUtc();
          final to = qp['to'] == null ? now : DateTime.tryParse(qp['to']!);
          final from = qp['from'] == null
              ? (to ?? now).subtract(const Duration(days: 29))
              : DateTime.tryParse(qp['from']!);
          if (from == null || to == null || from.isAfter(to)) {
            throw ApiException(ApiErrorCode.badRequest,
                message: 'Invalid analytics range.');
          }
          return _json(await repo.summary(
            organizationId: auth.organizationId,
            campaignId: qp['campaignId'],
            from: from, to: to,
          ));
        }),
  );
  return router;
}
```

In `server/lib/src/app.dart`, add after the verification leg (mirror it):

```dart
  final analyticsHandler = const Pipeline()
      .addMiddleware(_authenticateUnder(const {'analytics'}, db: db, tokens: tokens))
      .addHandler(analyticsRouter(db: db).call);
```

and `.add(analyticsHandler)` in the Cascade beside the others.

- [ ] **Step 5: Run** — from `server/`: `dart test test/analytics/` → all 7 cases PASS; then the whole server suite `dart test` → no regressions.

- [ ] **Step 6: Gates + commit**

```bash
dart format server/lib/src/analytics server/test/analytics server/lib/src/app.dart
dart analyze server --fatal-infos
git add server/lib/src/analytics server/test/analytics server/lib/src/app.dart
git commit -m "feat(server): GET /analytics/summary — ranged contribution aggregates (RD3.D1)"
```

---

### Task 3: Mock parity — `/analytics/summary` in the mock + parity cases

**Files:**
- Modify: `tool/mock_server/bin/server.dart`
- Modify: `server/test/contract/parity_test.dart`

**Interfaces:**
- Consumes: the Task 2 envelope; the mock's existing in-memory fixtures (its campaigns list CAMP-1/CAMP-2, its seeded verification cases with bands/ages); the parity harness (`ParityTarget`, its seeding of the real DB to MATCH the mock's fixtures — read the existing carpenter/queue parity cases and follow their seed-to-match approach).
- Produces: mock `GET /analytics/summary` computing from the mock's own fixture state (never hardcoded envelope constants disconnected from its campaigns/cases), gated on the mock's `export` permission check exactly as its other routes gate.

- [ ] **Step 1: Write the failing parity cases** (in `parity_test.dart`, alongside the existing groups)

```dart
// group('/analytics/summary parity'):
// 1. default query (no params): both backends return the envelope with the
//    same KEY SET (funnel/verifiedPerDay/bandMix/campaigns/sample/range/generatedAt),
//    same funnel field names, and integer types throughout. Seed the real DB
//    (freshDb harness) to numerically MATCH the mock's fixtures the same way
//    existing parity cases seed carpenters to match CARP_E2E — assert the
//    numbers equal across backends, not just shapes.
// 2. ?campaignId=CAMP-1: campaigns list filters to one row on both.
// 3. ?from=2020-01-01&to=2020-01-02 (empty range): captured==0, small==true,
//    verifiedPerDay==[] on both.
// 4. denied: a token without export → 403 envelope parity (same error shape).
```

- [ ] **Step 2: Run to verify failure** — from `server/`: `dart test test/contract/parity_test.dart` → new group FAILS (mock 404s).

- [ ] **Step 3: Implement the mock route**

In `tool/mock_server/bin/server.dart`, add `r.get('/analytics/summary', ...)` beside the other reads: check the caller's role permissions the way the mock's gated routes do (its role→permissions map at ~line 569 already includes `export`); compute the envelope from the mock's in-memory campaigns + verification-case fixtures (statuses, bands, capturedAt), applying the same range/default logic as the real route (share the semantics by transcription; the mock has no SQL). Keep determinism: the mock's fixture timestamps are fixed, so a fixed `from/to` yields fixed numbers.

- [ ] **Step 4: Run** — parity group PASSES; whole `dart test test/contract/` green.

- [ ] **Step 5: Gates + commit**

```bash
dart format tool/mock_server server/test/contract
dart analyze server tool/mock_server --fatal-infos
git add tool/mock_server/bin/server.dart server/test/contract/parity_test.dart
git commit -m "feat(mock): /analytics/summary parity with campaign_service (RD3.D1)"
```

---

### Task 4: Client data + application layer

**Files:**
- Create: `lib/data/analytics/analytics_repository_impl.dart`
- Create: `lib/features/analytics/application/analytics_notifier.dart`
- Test: `test/features/analytics/analytics_notifier_test.dart`

**Interfaces:**
- Consumes: Task 1 models; `dioProvider` and repo wiring conventions from `lib/data/campaign/campaign_repository_impl.dart` + `lib/app/di/providers.dart` (read how `campaignRepositoryProvider` is declared and mirror); `Result`/`Failure` (`lib/core/result/result.dart`, `mapDioError`).
- Produces:

```dart
abstract interface class AnalyticsRepository {           // lib/domain/analytics/ addition or alongside impl per repo convention — FOLLOW the campaign module: interface in domain, impl in data.
  Future<Result<AnalyticsSummary>> summary(AnalyticsQuery query);
}
final analyticsRepositoryProvider = Provider<AnalyticsRepository>(...);
final analyticsSummaryProvider = AsyncNotifierProvider.autoDispose
    .family<AnalyticsNotifier, AnalyticsSummary, AnalyticsQuery>(AnalyticsNotifier.new);
class AnalyticsNotifier extends AutoDisposeFamilyAsyncNotifier<AnalyticsSummary, AnalyticsQuery> {
  @override Future<AnalyticsSummary> build(AnalyticsQuery query);
}
```

The repo impl GETs `/analytics/summary` with query params: `campaignId` when non-null, and computed `from`/`to` — `to` = today UTC date, `from` = `to - (range.days - 1)`, both serialized `yyyy-MM-dd` (substring 0,10 of `toIso8601String()`). The notifier unwraps `Result` (throw the `Failure` into the async error channel the way `campaign_list_notifier.dart` does — read and mirror it).

- [ ] **Step 1: Failing test** — `test/features/analytics/analytics_notifier_test.dart` using `buildTestContainer` with `analyticsRepositoryProvider.overrideWithValue(fake)`:

```dart
// 1. build() returns the fake's summary for the query it was called with
//    (fake records the AnalyticsQuery — assert campaignId/range pass through).
// 2. A Failure from the repo surfaces as AsyncError.
// 3. Distinct queries are distinct family entries (read both providers,
//    fake counts 2 calls).
```

- [ ] **Step 2: Verify failure**, **Step 3: implement**, **Step 4: pass** — `flutter test test/features/analytics/`.

- [ ] **Step 5: Gates + commit**

```bash
dart format lib/data/analytics lib/features/analytics lib/domain/analytics test/features/analytics
flutter analyze --fatal-infos
git add lib/domain/analytics lib/data/analytics lib/features/analytics test/features/analytics
git commit -m "feat(analytics): repository + summary provider family (RD3.D1 client)"
```

---

### Task 5: `AnalyticsPanel` — four zones + states

**Files:**
- Create: `lib/features/analytics/presentation/analytics_panel.dart`
- Create: `lib/features/analytics/presentation/widgets/verification_trend_chart.dart`, `widgets/analytics_funnel_chart.dart`, `widgets/band_mix_chart.dart`, `widgets/analytics_drill_table.dart`
- Test: `test/features/analytics/analytics_panel_test.dart`

**Interfaces:**
- Consumes: Task 4 provider; `BmdBanner` (`lib/core/design_system/bmd_feedback.dart` — read for exact API), `BmdStateView`, `Shimmer`, `Reveal`, `motionOff`/`reduced`/`MotionDur`/`MotionCurve`, `bmd` tokens (`accent`, `funnel` ramp, `series` palette — check `BmdTokens` for the data-series field name used by `campaign_status_chart.dart` and reuse it), `BmdDataTable`/`BmdColumn`/`StatusChip`, `Breakpoint.of`.
- Produces: `AnalyticsPanel({required AnalyticsQuery query, bool showDrillTable = true, Key? key})` — watches `analyticsSummaryProvider(query)` itself. Zone identifiers per Global Constraints.

Panel structure (data branch): a `Column` (stacked; wide layouts place trend full-width, then `Row[Expanded(funnel), s6, Expanded(bandMix)]` when `Breakpoint.of(context).isDesktopUp`, else stacked — the Dashboard's `_DataVizRow` pattern), each zone wrapped `Reveal(index: 0..3)` and `Semantics(identifier: ...)`. Above the zones: the small-sample `BmdBanner` when `summary.sample.small` (copy: "Fewer than 30 attendance records in this range — read trends cautiously."). Empty state when `summary.funnel.captured == 0` → `BmdStateView.empty(title: 'No attendance in this range', message: 'Widen the date range or pick another campaign.')`. Error → `BmdStateView.error(title: "Couldn't load analytics", message: 'Check your connection and try again.', onRetry: invalidate)`. Loading → four `Shimmer` blocks shaped like the zones (Dashboard `_DashboardSkeleton` pattern).

**Trend zone** (`verification_trend_chart.dart`) — the one genuinely new chart; complete implementation:

```dart
/// §8.15 centerpiece: approved attendance per day as an accent-cyan line
/// with a soft under-fill. Days without approvals render as zero (the wire
/// omits them). Sweep-in via TweenAnimationBuilder clipping the chart
/// horizontally 0→1 (reduced-motion: full line first frame — reduced()
/// collapses the duration and TweenAnimationBuilder snaps, same note as
/// CountUp).
class VerificationTrendChart extends StatelessWidget {
  const VerificationTrendChart({
    required this.perDay, required this.from, required this.to,
    required this.rangeLabel, super.key,
  });
  // from/to come from summary.range (the server's echoed resolved dates) —
  // NEVER from DateTime.now(); rangeLabel from the panel, e.g.
  // '01/08 – 15/08' built from the same echoed dates.
  final List<DailyCount> perDay;
  final DateTime from; final DateTime to; final String rangeLabel;

  List<FlSpot> _spots() {
    final byDay = {for (final d in perDay) DateTime.utc(d.date.year, d.date.month, d.date.day): d.count};
    final days = to.difference(from).inDays + 1;
    return [
      for (var i = 0; i < days; i++)
        FlSpot(i.toDouble(),
          (byDay[DateTime.utc(from.year, from.month, from.day).add(Duration(days: i))] ?? 0).toDouble()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final spots = _spots();
    final maxY = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verification trend', style: theme.textTheme.titleMedium),
        const SizedBox(height: BmdSpace.s3),
        SizedBox(
          height: 240,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: reduced(context, MotionDur.slow),
            curve: MotionCurve.emphasized,
            builder: (context, t, child) => ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                stops: [0, t, t],
                colors: const [Colors.white, Colors.white, Colors.transparent],
              ).createShader(rect),
              child: child,
            ),
            child: LineChart(
              LineChartData(
                minY: 0, maxY: maxY == 0 ? 1 : maxY * 1.2,
                gridData: FlGridData(show: true, drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: theme.dividerColor, strokeWidth: 0.5)),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, reservedSize: 32)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, interval: (spots.length / 4).ceilToDouble(),
                    getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta,
                      child: Text(
                        _dayLabel(from.add(Duration(days: v.toInt()))),
                        style: theme.textTheme.bodySmall)),
                  )),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots, isCurved: true, curveSmoothness: 0.25,
                    color: bmd.accent, barWidth: 3, dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [bmd.accent.withValues(alpha: 0.25),
                                 bmd.accent.withValues(alpha: 0.0)])),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: BmdSpace.s1),
        Text('Approved attendance per day · Campaign service · $rangeLabel',
            style: theme.textTheme.bodySmall?.copyWith(color: bmd.textSecondary)),
      ],
    );
  }

  String _dayLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
```

(If `SideTitleWidget`'s parameter name differs on fl_chart's pinned version, adapt to the version in `pubspec.lock` — check how existing charts pass axis titles.)

**Funnel zone**: same structure as `attendance_funnel_chart.dart` (horizontal `rotationQuarterTurns: 1` BarChart over the ordinal `bmd.funnel` ramp) with stages `[('Target', target), ('Registered', registered), ('Captured', captured), ('In review', inReview), ('Approved', approved)]`, plus a muted annotation row beneath: `Text('Rejected $rejected · Returned $returned', style: bodySmall/textSecondary)`. Defence line: 'Attendance progression · Campaign service · <rangeLabel> (target/registered are campaign totals)'.

**Band mix zone**: donut like `campaign_status_chart.dart` (PieChart, direct labels, series palette), entries only for non-zero bands, defence line 'Machine match bands · advisory only · <rangeLabel>'.

**Drill table zone** (shown only when `showDrillTable`): `BmdDataTable<AnalyticsCampaignRow>` with columns Campaign(name, identity, minWidth 200 flex 3) / Status(StatusChip via the `_toneFor` mapping copied from `campaign_list_screen.dart` — copy the switch, do not import a private member) / Target(numeric) / Verified(numeric) / In review(numeric); `onRowTap: (r) => context.go('/campaigns/${r.id}')`.

- [ ] **Step 1: Failing widget tests** (`analytics_panel_test.dart`, `buildTestContainer` + provider override with a seeded `AnalyticsSummary`, `MediaQuery(disableAnimations: true)` host, physical-view sizing):

```dart
// 1. renders all four zone identifiers (analytics_trend/funnel/band_mix/table)
//    and the defence lines ('Approved attendance per day', 'advisory only').
// 2. showDrillTable:false hides analytics_table.
// 3. sample.small:true shows the banner copy; false hides it.
// 4. funnel.captured == 0 → BmdStateView.empty copy visible, no charts.
// 5. error override → BmdStateView.error, retry invalidates (fake counts builds).
// 6. reduced motion renders the trend in ONE pump (find analytics_trend after
//    a single tester.pump(), not pumpAndSettle).
```

- [ ] **Step 2: verify failure. Step 3: implement (code above + zones). Step 4: pass** — `flutter test test/features/analytics/`.

- [ ] **Step 5: Gates + commit**

```bash
dart format lib/features/analytics test/features/analytics
flutter analyze --fatal-infos
git add lib/features/analytics test/features/analytics
git commit -m "feat(analytics): AnalyticsPanel — trend, funnel, band mix, drill (RD3.D2/D3/D4)"
```

---

### Task 6: Mounts — `/analytics` screen + campaign-detail tab

**Files:**
- Create: `lib/features/analytics/presentation/analytics_screen.dart`
- Modify: `lib/app/router/app_router.dart:175-185` (swap PlaceholderScreen → AnalyticsScreen; keep `fadeThroughPage` and the path)
- Modify: `lib/features/campaign_detail/presentation/campaign_detail_screen.dart` (Analytics tab `_Placeholder` → panel)
- Test: `test/features/analytics/analytics_screen_test.dart`

**Interfaces:**
- Consumes: `AnalyticsPanel` (Task 5), `ScreenHero`, `campaignListProvider` (for the campaign selector's options), `AppShell`.
- Produces: `AnalyticsScreen` (ConsumerStatefulWidget holding `AnalyticsQuery` state). New identifiers `analytics_range_<preset>` on the chips and `analytics_campaign_filter` on the selector.

Screen: `AppShell(title: 'Campaign analytics', body: ListView(children: [ScreenHero(...), s4, AnalyticsPanel(query: _query)]))` — hero `title: 'Campaign analytics'`, `subtitle: 'Campaign-linked contribution — activity, not sales impact'`, `summary:` the three range `ChoiceChip`s (labels '7d'/'30d'/'90d', each in `Semantics(identifier: 'analytics_range_${preset.name}')`, selected == `_query.range`, onSelected rebuilds `_query`), `actions:` the campaign selector — a `DropdownMenu<String?>` (or `DropdownButton` if `DropdownMenu` misbehaves in tests; either way wrapped `Semantics(identifier: 'analytics_campaign_filter')`) with 'All campaigns' (null) + entries from `campaignListProvider`'s `valueOrNull?.items` (absent while loading — selector shows only 'All campaigns').

Detail tab: replace `const _Placeholder('Analytics — see A-02')` with `AnalyticsPanel(query: AnalyticsQuery(campaignId: campaignId), showDrillTable: false)` wrapped in a `ListView`/padding consistent with the other tabs, PLUS a compact range chip row above it (same three chips + identifiers — the panel needs a range; hold the preset in a small StatefulWidget wrapper `_DetailAnalyticsTab(campaignId)`).

- [ ] **Step 1: Failing tests** (`analytics_screen_test.dart`):

```dart
// 1. /analytics screen renders hero title + panel zones with seeded provider.
// 2. Tapping analytics_range_d7 re-keys the family (fake repo records the
//    second query with range d7).
// 3. Campaign selector lists 'All campaigns' + seeded campaign names; picking
//    one re-keys with its id (fake records campaignId).
// 4. Detail tab: pump CampaignDetailScreen with seeded detail + analytics
//    overrides; switch to Analytics tab; panel zones render; analytics_table
//    absent; campaign selector absent.
// 5. Identifier sweep: session_start etc. still resolve on the Sessions tab
//    (frozen contract).
```

- [ ] **Step 2: verify failure. Step 3: implement. Step 4: pass** — `flutter test test/features/analytics/ test/features/campaign_detail/ test/app/` (router tests must still pass; `/analytics` remains gated by `Permission.export` in `route_table.dart` — UNTOUCHED).

- [ ] **Step 5: Gates + commit**

```bash
dart format lib/features/analytics lib/app/router test/features
flutter analyze --fatal-infos
git add lib/features/analytics lib/app/router/app_router.dart lib/features/campaign_detail/presentation/campaign_detail_screen.dart test/features/analytics
git commit -m "feat(analytics): mount panel at /analytics + campaign detail tab (RD3.D2)"
```

---

### Task 7: Goldens + e2e flow + full sweep

**Files:**
- Modify: `test/golden/screens_golden_test.dart` (add the analytics screen entries)
- Create: `.maestro/flows/analytics_summary.yaml`
- Modify: `.maestro/config.yaml` (add the flow to `flows:`), `.github/workflows/ci.yml` (new e2e matrix entry)

**Interfaces:**
- Consumes: everything above; the goldens file's `_screens`/`_variants`/`_overridesFor` structure; the CI matrix entry shape (`key/defines/useMock/flows`, see the `crm` entry at ci.yml ~line 266).
- Produces: 2 golden cases `analytics-desktop-dark` / `analytics-mobile-light`; one CI matrix entry `analytics`.

- [ ] **Step 1: Goldens** — extend `screens_golden_test.dart`: add `'analytics': () => const AnalyticsScreen()` to `_screens` and a `_SeededAnalytics` notifier override (family: override at whole-family level, the file's established pattern) returning a fixed `AnalyticsSummary`: funnel {500,320,210,9,180,12,6}, 14 days of perDay counts (mix of zeros and peaks, e.g. [0,3,8,5,0,12,14,9,4,0,6,11,7,2] ending today — dates computed from a FIXED anchor passed via the summary itself, NOT Date.now: use `DateTime.utc(2026, 8, 15)` and matching from/to in the seeded query), bandMix {high:120, medium:60, low:18, noReference:12}, 3 drill rows, sample {210,false}, generatedAt fixed. Also override `campaignListProvider` with 3 campaigns so the selector renders. Run `flutter test test/golden/screens_golden_test.dart` → the 2 new cases SKIP on Windows but the file compiles.

  NOTE (design detail that avoids nondeterminism): the only `DateTime.now()` in the feature lives in the REPOSITORY (computing default from/to for the request); presentation renders exclusively from `summary.range`'s echoed dates. The golden overrides the provider above that computation with a summary whose `range` is fixed (`2026-08-02 .. 2026-08-15`), so it is date-stable. Grep before committing: no `DateTime.now()` in any `lib/features/analytics/presentation/` file.

- [ ] **Step 2: The Maestro flow** — `.maestro/flows/analytics_summary.yaml`:

```yaml
# Slice 3 (A-02): the analytics summary renders real aggregates from the
# seeded campaign_service data. Requires the realAuth APK; signs in as
# campaign_creator (holds `export` — server/lib/src/auth/tokens.dart).
# Seeded data guarantees a non-empty summary: CASE_CONFLICT is APPROVED at
# seed time (verified >= 1) and CASE_E2E is CRM_REVIEW (in review >= 1).
appId: ${APP_ID}
tags:
  - analytics
  - critical
  - android
---
- clearState
- launchApp
- assertVisible:
    id: "login_username"
- tapOn:
    id: "login_username"
- inputText: "campaign_creator"
- tapOn:
    id: "login_password"
- inputText: "Test1234!"
- hideKeyboard
- tapOn:
    id: "login_submit"
- assertVisible:
    id: "dev_launcher"
# Navigate via the nav destination (Analytics appears for export holders).
- tapOn: ".*Analytics.*"
- assertVisible:
    id: "analytics_trend"
- scrollUntilVisible:
    element:
      id: "analytics_funnel"
    direction: DOWN
    waitToSettleTimeoutMs: 1000
- scrollUntilVisible:
    element:
      id: "analytics_table"
    direction: DOWN
    waitToSettleTimeoutMs: 1000
    visibilityPercentage: 40
- assertVisible: ".*ACSL Pilot Carpenter Drive.*"
```

Add `- flows/analytics_summary.yaml` to `.maestro/config.yaml`'s list. In `ci.yml`'s e2e matrix add (mirror the `crm` entry's comment style):

```yaml
          # Slice 3: A-02 analytics against the real campaign_service.
          - key: analytics
            defines: '--dart-define=E2E_REAL_AUTH=true --dart-define=ROLE=campaign_creator'
            useMock: '0'
            flows: >-
              .maestro/flows/analytics_summary.yaml
```

VERIFY the nav tap: if the dev launcher lacks a direct Analytics path and the shell nav is how `/analytics` is reached, check `nav_destinations.dart` for the label/visibility rule; if the nav rail on the emulator collapses Analytics behind overflow, use the launcher instead — check for a `dev_open_*` entry or navigate via deep link pattern other flows use. Adjust the flow to whichever navigation is actually reachable, keeping the three analytics asserts unchanged.

- [ ] **Step 3: Full sweep**

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
(cd server && dart test)
```
All green (goldens skipped on Windows; server suite includes parity).

- [ ] **Step 4: Commit**

```bash
git add test/golden/screens_golden_test.dart .maestro/flows/analytics_summary.yaml .maestro/config.yaml .github/workflows/ci.yml
git commit -m "test(analytics): goldens + analytics_summary e2e flow in CI matrix"
```

---

## After all tasks (controller)

1. Final whole-branch review; push; open the PR.
2. Dispatch `goldens.yml` on the branch; commit the `golden-baselines` artifact (expect 2 new PNGs: `analytics-desktop-dark`, `analytics-mobile-light`; no modified existing baselines).
3. CI green (including the new `analytics` e2e job) → merge only on explicit user go-ahead.
