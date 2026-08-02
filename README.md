# ACSL Carpenter Campaign Management

[![CI](https://github.com/Asim971/camp_management/actions/workflows/ci.yml/badge.svg)](https://github.com/Asim971/camp_management/actions/workflows/ci.yml)

Flutter application for campaign lifecycle management and carpenter attendance verification — a native extension of the **BMD Sales Ecosystem**. One codebase targets the mobile field app (Android/iOS), the web campaign admin, the CRM verification console, and management analytics.

> **Design & requirements:** [`design/`](design/README.md) (the built design system — foundations, components and all 17 screens) · [`ARCHITECTURE_Flutter.md`](ARCHITECTURE_Flutter.md) · [`TASK_BREAKDOWN.md`](TASK_BREAKDOWN.md) · [`Campaign_Management_Carpenter_Attendance_Verification_PRD.md`](Campaign_Management_Carpenter_Attendance_Verification_PRD.md) · [`ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md`](ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md)

## Quick start

> Verified on **Flutter 3.44.8 / Dart 3.12.2** (min Flutter ≥ 3.44 — the
> resolved lockfile's `file_selector_android` floor). Both the
> `web/` and `android/` runners are committed. Android additionally needs a JDK
> and the Android SDK; web and `flutter test` do not.

```bash
flutter pub get --enforce-lockfile   # lockfile is committed; fail loudly on drift
flutter gen-l10n                     # generate AppL10n from lib/l10n/*.arb
dart run build_runner build --delete-conflicting-outputs   # freezed / json / drift
flutter analyze --fatal-infos
```

Generated code is gitignored, so **this order matters** — analyze fails on a
clean clone until `gen-l10n` and `build_runner` have run.

Run the app through the flavor wrapper, which keeps the Gradle flavor and the
dart-defines in sync (they are independent, and mismatching them installs a dev
app pointed at production):

```powershell
./tool/scripts/run.ps1 -Flavor dev -Device chrome   # web
./tool/scripts/run.ps1 -Flavor dev                 # Android emulator
```

> **Note:** production auth isn't wired yet, so a plain `flutter run` lands on the
> login placeholder. For a working demo use **E2E mode + the mock server** — see
> ["Run it end-to-end"](#run-it-end-to-end-with-the-mock-backend) below.

Codegen must run before the first build: `freezed`/`json_serializable` (models), `drift_dev` (offline DB), and `gen-l10n` (localization). Providers are hand-written — there is no Riverpod code generation (see `ARCHITECTURE_Flutter.md` §6).

## Project layout

```
lib/
├── app/        bootstrap · router (+RBAC guards) · theme (BMD tokens→M3) · DI · flavors
├── core/       cross-cutting: network · storage(drift) · sync · auth/rbac · media · responsive · design_system · audit · result
├── domain/     pure Dart entities, typed status vocabulary, repository interfaces
├── data/       repository implementations, DTOs + mappers
├── features/   one module per screen family (see lib/features/README.md)
└── l10n/       en + bn ARB resources
test/           domain / data / state / widget / integration
```

## Run it end-to-end (with the mock backend)

Production auth/APIs aren't wired yet, so use **E2E mode** (fake auth + a `/dev`
screen launcher) pointed at the bundled mock server for a full working demo:

```bash
# 1) start the stub backend
cd tool/mock_server && dart pub get && dart run bin/server.dart

# 2) run the app in E2E mode against it (from repo root)
flutter run -d chrome \
  --dart-define=E2E=true \
  --dart-define=API_BASE_URL=http://localhost:8080
```

The `/dev` launcher opens every implemented screen — campaign list/detail/wizard/
approval, registration, bulk import, field capture, offline queue and CRM case —
all backed by the mock. See [`tool/mock_server/README.md`](tool/mock_server/README.md).

## Architecture at a glance

- **Layered, feature-first.** `features → domain ← data`; everything may use `core`. Domain has zero Flutter/IO imports (fast unit tests, and the seam that keeps any future web-native fallback contained).
- **State:** Riverpod v2 (`AsyncValue` for the mandated loading/data/error/empty states).
- **Routing:** GoRouter with redirect guards enforcing role + org/territory scope before a route builds.
- **Design system:** BMD tokens drive Material 3; status is a typed vocabulary rendered by one `StatusChip` — identical wording across every surface.
- **Offline-first capture:** durable Drift queue + idempotency keys + encrypted evidence; **capture success ≠ upload success**.
- **Privacy:** masked NID, permission-gated reveal, signed short-lived media URLs, audit-on-view; field users never see match scores.

## Status

**Verified:** `flutter analyze --fatal-infos` clean · `flutter test` 33/33 pass
(incl. the offline sync-engine harness and the design-system rule tests) ·
`flutter build web` succeeds · runs end-to-end against the mock server (campaign
list/detail render live data, RBAC guard and responsive shell confirmed in-browser).

### Implemented

- **Design system:** [`design/`](design/README.md) — 33 self-contained specimens
  covering foundations, components and the full §7 screen inventory, with a build
  that self-checks its own output. The data-series palette and funnel ramp were
  derived by enumeration and machine-checked for CVD and contrast in both light and
  dark against BMD's own surfaces ([`design/PALETTE.md`](design/PALETTE.md)).
- **Foundation (P0):** BMD tokens → Material 3 theme with a `BmdTokens` theme
  extension (semantic quartet, chip tints, validated series palette, funnel ramp;
  light + dark), typed status vocabulary + `StatusChip` covering all five status
  families, the `LineageRail` chain-of-custody component, `KpiCard`/`ExceptionCard`,
  `BmdBanner`/`OfflineBar`/`BmdState`/`BmdSkeleton`, `BmdButton`, virtualized
  `BmdDataTable`, responsive adaptive shell, `Result`/`Failure`, Dio client + auth
  interceptor, Drift offline DB, RBAC + guarded GoRouter, Riverpod DI, en/bn
  localization.
- **Offline sync engine:** durable Drift queue, idempotency keys, exponential backoff,
  platform-isolated evidence store — with a deterministic test harness.
- **Field (mobile):** carpenter search (offline-first), 5-step camera capture, offline queue.
- **CRM:** verification case (C-02) — 3-zone, machine result separate, optimistic locking.
- **Campaign admin:** list (W-02), create wizard (W-03), approval + SoD gate (W-04),
  detail + session ops (W-05), registration workspace (W-06), bulk import (W-07).
- **Test/demo infra:** E2E build mode (fake auth, `/dev` launcher, fake camera, seeder),
  Maestro flows (`.maestro/`), Dart `shelf` mock server (`tool/mock_server/`).

Per-module status: [`lib/features/README.md`](lib/features/README.md). Full task plan:
[`TASK_BREAKDOWN.md`](TASK_BREAKDOWN.md). E2E plan: [`TESTING_MAESTRO.md`](TESTING_MAESTRO.md).

### Not yet built

| Screen | ID | Notes |
|--------|----|-------|
| Campaign dashboard | W-01 | placeholder (mock endpoints ready) |
| CRM verification queue | C-01 | placeholder (feeds the built case screen) |
| Campaign analytics & ROI | A-02 | placeholder |
| Session readiness | M-01 | field pre-flight + roster cache warm |
| Carpenter 360 / Integrity / Config | A-01 / A-03 / AD-01 | later phases |

### Known gaps & blockers

- **Backend contracts (🔒):** Sales Eco carpenter-master API, auth/RBAC service, media
  signed-URL/encryption, server idempotency/audit. Repositories call placeholder
  endpoints; the mock server stands in until these land.
- **Drift-on-web assets:** offline-queue/cached-search on the **web** target need
  `sqlite3.wasm` + the drift worker dropped into `web/` (mobile is unaffected).
- **ML Kit quality:** capture uses a passthrough/E2E checker; the on-device face-quality
  impl (T-2.2.2) is unbuilt.
- **iOS:** no runner committed (gitignored by policy); Android is the field target.
