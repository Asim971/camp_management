# ACSL Carpenter Campaign Management

Flutter application for campaign lifecycle management and carpenter attendance verification — a native extension of the **BMD Sales Ecosystem**. One codebase targets the mobile field app (Android/iOS), the web campaign admin, the CRM verification console, and management analytics.

> **Design & requirements:** [`ARCHITECTURE_Flutter.md`](ARCHITECTURE_Flutter.md) · [`TASK_BREAKDOWN.md`](TASK_BREAKDOWN.md) · [`Campaign_Management_Carpenter_Attendance_Verification_PRD.md`](Campaign_Management_Carpenter_Attendance_Verification_PRD.md) · [`ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md`](ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md)

## Quick start

> Requires Flutter ≥ 3.22 (Dart ≥ 3.4). This repo was scaffolded without a local Flutter SDK; run `flutter create .` once to (re)generate the platform folders (`android/`, `web/`, …) — it will not overwrite `lib/`.

```bash
flutter create . --platforms=android,web    # generate platform runners
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # freezed / json / drift / riverpod
flutter gen-l10n                              # generate AppL10n from lib/l10n/*.arb
flutter run -d chrome \
  --dart-define=FLAVOR=dev \
  --dart-define=API_BASE_URL=https://dev.api.example/campaign \
  --dart-define=MEDIA_HOST=https://dev.media.example
```

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

P0 foundation is scaffolded (theme, tokens, status vocabulary, core service seams, RBAC routing, DI, `campaign_list` reference feature, l10n, a domain test). Feature modules are tracked in [`lib/features/README.md`](lib/features/README.md) and [`TASK_BREAKDOWN.md`](TASK_BREAKDOWN.md).

Several tasks are blocked on server contracts (🔒 in the task breakdown): Sales Eco carpenter-master API, auth/RBAC service, media signed-URL/encryption, and server idempotency/audit. Resolve these before their dependent features.
# camp_management
