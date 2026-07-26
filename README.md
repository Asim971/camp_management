# ACSL Carpenter Campaign Management

Flutter application for campaign lifecycle management and carpenter attendance verification — a native extension of the **BMD Sales Ecosystem**. One codebase targets the mobile field app (Android/iOS), the web campaign admin, the CRM verification console, and management analytics.

> **Design & requirements:** [`ARCHITECTURE_Flutter.md`](ARCHITECTURE_Flutter.md) · [`TASK_BREAKDOWN.md`](TASK_BREAKDOWN.md) · [`Campaign_Management_Carpenter_Attendance_Verification_PRD.md`](Campaign_Management_Carpenter_Attendance_Verification_PRD.md) · [`ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md`](ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md)

## Quick start

> Verified on **Flutter 3.44.8 / Dart 3.12.2** (min Flutter ≥ 3.22). The `web/`
> runner is committed; run `flutter create . --platforms=android` if you also
> need the Android runner (it won't overwrite `lib/`).

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # freezed / json / drift / riverpod
flutter gen-l10n                              # generate AppL10n from lib/l10n/*.arb
flutter run -d chrome \
  --dart-define=FLAVOR=dev \
  --dart-define=API_BASE_URL=https://dev.api.example/campaign \
  --dart-define=MEDIA_HOST=https://dev.media.example
```

> **Note:** production auth isn't wired yet, so a plain `flutter run` lands on the
> login placeholder. For a working demo use **E2E mode + the mock server** — see
> ["Run it end-to-end"](#run-it-end-to-end-with-the-mock-backend) below.

Codegen must run before the first build: `freezed`/`json_serializable` (models), `drift_dev` (offline DB), `riverpod_generator` (if you adopt annotated providers), and `gen-l10n` (localization).

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

**Verified:** `flutter analyze` clean of errors · `flutter test` 15/15 pass (incl. the
offline sync-engine harness) · `flutter build web` succeeds · runs end-to-end against
the mock server (campaign list/detail render live data, RBAC guard and responsive
shell confirmed in-browser).

### Implemented

- **Foundation (P0):** BMD tokens → Material 3 theme, typed status vocabulary +
  `StatusChip`, `BmdButton`, virtualized `BmdDataTable`, responsive adaptive shell,
  `Result`/`Failure`, Dio client + auth interceptor, Drift offline DB, RBAC + guarded
  GoRouter, Riverpod DI, en/bn localization.
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
- **Android/iOS:** needs a JDK + Android SDK (not required for web or `flutter test`).
