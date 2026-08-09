# Maestro E2E Test Plan — ACSL Carpenter Campaign Management

**Scope:** UI end-to-end tests (Maestro) for the currently implemented screens.
**Companion to:** [`ARCHITECTURE_Flutter.md`](ARCHITECTURE_Flutter.md) §14 (testing strategy), [`TASK_BREAKDOWN.md`](TASK_BREAKDOWN.md).
**Status:** Flows in [`.maestro/`](.maestro), run by the `e2e` matrix job in CI (§7.1). The prerequisites in §3 are met. **The flows have never had a green run** — the `e2e` job is new in P0.5 and configuration reached the app for the first time with it, so treat any flow you have not personally seen pass as unproven.

---

## 1. Where Maestro fits

Maestro is the **top of the pyramid** — few, slow, high-confidence journeys driven through the real UI. It does **not** replace the fast layers already scaffolded; it proves the critical paths hold together.

```
        /  Maestro E2E  \      6–8 flows · critical journeys · real device/emulator
       / Widget + golden  \    per-screen render + states (flutter_test)
      / Integration (Dart)  \   sync engine, repos, offline matrix (in-memory DB)
     /     Unit (pure Dart)   \  status machine, backoff, mappers, RBAC
```

Already in the repo (keep these carrying the bulk of coverage):
- `test/domain/campaign_test.dart` — lifecycle state machine
- `test/core/backoff_test.dart` — backoff policy
- `test/core/sync_engine_test.dart` — offline queue matrix (idempotency, retry, conflict, backoff)

Maestro adds confidence that the **wired flows** (search → capture → queue; CRM decide) behave in the assembled app — things unit tests can't see: camera step, navigation, permission gates, offline toggling.

**Rule:** if a failure mode can be caught one layer down, test it there. Reserve Maestro for cross-screen journeys and device-level behavior (camera, airplane mode, app restart).

---

## 2. What is testable today

| Implemented surface | Screens | Maestro-testable now? |
|---|---|---|
| Mobile field — search | `carpenter_search` (M-02) | Yes (needs seeded roster) |
| Mobile field — capture | `camera_capture` (M-03) | Yes (needs fake camera + E2E quality) |
| Mobile field — queue | `offline_queue` (M-04) | Yes (needs airplane-mode toggle + mock upload) |
| CRM — case decision | `crm_case` (C-02) | Yes (needs mock case + signed image stubs) |
| Web — campaign list | `campaign_list` (W-02) | Smoke only (Maestro web is experimental) |

Not yet built (out of scope for this plan): session readiness (M-01), CRM queue (C-01), wizard/approval/registration/import (W-03/04/06/07), analytics, 360, config.

---

## 3. E2E enablement prerequisites

> **Status: app-side enablement is now implemented.** The `E2E=true` build mode (fake auth, `/dev` launcher, fake camera, fail-then-pass quality, local data seeding) and the `Semantics(identifier:)` test IDs are in the codebase (`lib/app/flavors.dart`, `lib/core/auth/e2e_session.dart`, `lib/features/dev/`, `lib/core/media/capture_source.dart`, `lib/core/dev/e2e_seeder.dart`). The **mock backend** (§3.4) is implemented too — `tool/mock_server/`. What remains is the real **ML Kit** quality impl (E2E uses `E2EQualityChecker`) and, until CI has had a green run, the flows' own accuracy. Flows needing only client state (`carpenter_search_confirm`, `field_capture_recapture`, the capture→queued portion, `offline_queue_retry`) run with no mock; the reconnect-sync transition and CRM flows need the mock server.

Maestro drives a *running* app. These were the blockers, each a small, well-scoped task:

### 3.1 Stable selectors (test IDs) — **highest priority**
Flutter renders text into the a11y tree, so text selectors work, but labels are localized (bn/en) and change. Add stable identifiers via Flutter's `Semantics(identifier: …)` (maps to Android `resource-id` / iOS `accessibilityIdentifier`, which Maestro matches with `id:`).

```dart
Semantics(identifier: 'capture_shutter', child: BmdButton(label: 'Capture', ...));
```

Minimum identifier set the scaffolded flows expect:

| id | Widget | Exists? |
|----|--------|---------|
| `capture_accept` / `capture_ready` / `capture_shutter` / `capture_submit` / `capture_recapture` | camera_capture steps | yes |
| `capture_done` | captured confirmation | yes |
| `search_field` / `search_result` / `confirm_ack` / `confirm_continue` | carpenter_search | yes |
| `queue_item_menu` / `queue_discard_confirm` | offline_queue | yes |
| `queue_pending_count` / `queue_retry` | offline_queue | **no — see below** |
| `crm_reason` / `crm_submit` / `crm_outcome_<outcome>` | crm_case | yes |
| `dev_launcher` / `dev_open_*` | dev launcher | yes |

Two entries in the original list never landed and one was misnamed:

- **`queue_pending_count` does not exist and cannot.** The count lives inside `OfflineBar`, which wraps its whole row in `Semantics(excludeSemantics: true)` — that drops every descendant node, so an identifier added under it would be invisible to Maestro. What *is* visible is the bar's own accessibility label, `"<n> captures waiting to upload. Last successful sync <ts>."`, and that is what `field_offline_capture` asserts.
- **`queue_retry` does not exist.** Retry is a `PopupMenuItem`, reached by tapping `queue_item_menu` and then the item text `"Retry"`.
- The CRM radios are `crm_outcome_${outcome.name}`, i.e. `crm_outcome_approved` — not `crm_outcome_approve`.

**`Semantics(identifier:)` and Maestro's `enabled:` filter.** A bare `Semantics(identifier: 'x', child: someButton)` compiles to its **own** semantics node, separate from the button's. Probed on Flutter 3.44.8, the identifier node carried `isEnabled: Tristate.none` (no enabled state at all) while the label and the real disabled state sat on a child node. Flutter's Android `AccessibilityBridge` reports a node with no enabled state as `enabled=true`, so `assertVisible: {id: …, enabled: false}` failed and its `enabled: true` counterpart passed *vacuously*. `BmdButton` therefore states `enabled:` on the identifier node itself (`lib/core/design_system/bmd_button.dart`, pinned by a mutation-checked test in `test/design_system/bmd_button_test.dart`). **Any new `Semantics(identifier:)` wrapper around a control whose enabled state a flow asserts must do the same.**

Until the remaining ids land, flows fall back to visible-text selectors, which is why the emulator builds are **English** — English is `AppConfig.locale`'s effective default when no `LOCALE` is supplied, and it is a property of the **build**, not of the flow.

> **Correction (P0.5).** This section used to end: *"which is why every flow sets `--dart-define=LOCALE=en`"*. That was factually wrong and stayed wrong for three epics. No flow has ever set a `--dart-define`. The flows set Maestro `launchApp: arguments:`, which are Android **intent extras** delivered at runtime; `AppConfig` reads `const String.fromEnvironment`, resolved at **compile time**. Nothing bridges them — `MainActivity.kt` is a bare five-line `FlutterActivity`, and `Intent`, `getExtra`, `MethodChannel` and `defaultRouteName` appear nowhere in `lib/` or `android/app/src/main/kotlin`. **Every `arguments:` block in `.maestro/` was inert.** They have been removed and replaced with a comment naming the build each flow requires. See §7.1.

### 3.2 E2E build mode (`--dart-define=E2E=true`)
A single flag that makes the app driveable without live backends:
- **Auto-authenticate** a fake `Session` with the roles a flow needs (bypasses the unimplemented auth service). Without this the app sits on `/login`.
- **Dev launcher route** (`/dev`) listing deep links to field/CRM screens, since the production nav has no path to `/search`, `/capture`, `/queue` yet. Alternatively enable app-link deep links so Maestro `openLink` can jump directly.
- **Fake camera source** — swap `CameraController` capture for a bundled asset image, so capture is deterministic on emulators (which show a synthetic scene).
- **Force `PassthroughQualityChecker`** (already the default) so quality always passes in E2E; add a variant flow that injects a *failing* fixture to exercise the recapture path.

### 3.3 Seeded data
- **Offline roster**: `carpenter_search` reads the Drift `cached_references` table. Seed it in E2E mode (a debug action or a mock `GET /sessions/:id/registrations` + a "warm cache" step) so search returns known rows.
- **CRM case + images**: `crm_case` needs a case payload and two short-lived image URLs. Point image URLs at the mock server serving static fixtures.

### 3.4 Mock backend
APIs are placeholders (🔒). Run E2E against a **stub server** (WireMock/Prism/small shelf app) via `--dart-define=API_BASE_URL=http://<mock>`. Canned endpoints needed: `/campaigns`, `/media/presign`, `PUT <upload-url>`, `/attendance/:id/confirm`, `/sessions/:id/registrations`, `/verification/cases/:id`, `/verification/cases/:id/decision` (incl. a 409 fixture for the concurrent-decision flow).

### 3.5 Network control
Offline flows use Maestro `setAirplaneMode` (Android). iOS has no equivalent Maestro command — run offline flows on **Android** (matches the field-device target anyway).

---

## 4. Flow inventory

Located in [`.maestro/flows/`](.maestro/flows). Shared steps in [`.maestro/subflows/`](.maestro/subflows).

| Flow file | Journey | Prototype (design §13.1) | Key prerequisites |
|-----------|---------|--------------------------|-------------------|
| `campaign_list_smoke.yaml` | List loads, shows rows / empty / retry | — | mock `/campaigns`, web |
| `carpenter_search_confirm.yaml` | Search → pick → second-cue confirm → capture opens | part of P-02/P-04 | seeded roster |
| `field_online_capture.yaml` | Search → capture → quality pass → submit → queued | **P-04** | fake camera, mock upload |
| `field_capture_recapture.yaml` | Capture → quality fail → recapture → pass → submit | P-04 (quality path) | failing quality fixture |
| `field_offline_capture.yaml` | Airplane ON → capture → queued; ON→OFF → syncs | **P-05** | airplane mode, mock upload |
| `offline_queue_retry.yaml` | Failed item → Retry; Discard needs confirm dialog | P-05 (recovery) | mock 500 then 200 |
| `crm_case_decision.yaml` | Open case → machine block visible → reason required → submit | part of **P-06** | mock case + images |
| `crm_case_conflict.yaml` | Submit → 409 → "another reviewer" message + reload | P-06 (concurrency §9.4) | mock 409 |
| `locale_bengali.yaml` | Bengali notice (bundled) + Bengali status chip on the list | P0.5 | `LOCALE=bn` build, mock `/campaigns` with a DRAFT row |

**Target E2E count: 9 flows.** Deliberately small — every added flow is real device wall-clock and maintenance.

---

## 5. Coverage targets

| Layer | Target | Rationale |
|-------|--------|-----------|
| Unit (pure Dart) | ~90% of `domain/` + `core/sync`, `core/result` | fast, deterministic, cheap |
| Integration (Dart) | Every sync-engine failure-recovery row (§9.4); every repo mapper | data integrity is the risk |
| Widget/golden | Every implemented screen × its designed states (loading/empty/error/data) | matches QA checklist §13.2 |
| Maestro E2E | The 8 journeys above | critical paths only; not a coverage metric |

E2E is measured by **journeys green**, not line coverage. All 8 must pass on the reference Android device before a field pilot.

---

## 6. Example test cases (detailed)

**TC-E2E-01 — Offline attendance survives and syncs (P-05, highest value)**
1. E2E launch as Field User; open `/search/SESSION_E2E`.
2. `setAirplaneMode: enabled`.
3. Search "kar", select first result, confirm second cue, Continue to capture.
4. Accept notice → I'm ready → shutter → (quality passes) → Submit.
5. Assert "Attendance captured and queued".
6. Open `/queue`; assert item present with state **Pending sync**; assert pending count = 1.
7. Kill and relaunch app (durability); assert item still present, still Pending sync.
8. `setAirplaneMode: disabled`; wait; assert item transitions to **Match processing** and pending count → 0.
   *Verifies: capture ≠ upload, durable queue across restart, auto-drain on reconnect, idempotency (no duplicate row).*

**TC-E2E-02 — Quality gate forces recapture then succeeds**
Inject failing fixture → assert "Review required before submitting" + issue list + Submit hidden; tap Recapture → inject passing fixture → Submit → queued.

**TC-E2E-03 — Second identity cue is mandatory**
In confirm sheet, assert "Continue to capture" is disabled until the "I confirmed…" checkbox is ticked.

**TC-E2E-04 — Discard is guarded**
Queue item → menu → Discard… → assert confirmation dialog copy → Cancel keeps item; Discard removes it.

**TC-E2E-05 — CRM reason is mandatory**
Open case → assert "Machine recommendation (advisory)" block is present and separate → select Approve → assert Submit disabled until reason non-empty → enter reason → Submit → assert "Decision recorded".

**TC-E2E-06 — Concurrent CRM decision**
Mock returns 409 on decide → assert "Another reviewer already decided. Reloaded." and the case reloads (no silent overwrite).

**TC-E2E-07 — Campaign list states (web smoke)**
Mock empty → assert empty copy; mock error → assert "Couldn't load campaigns." + Retry; mock rows → assert table headers + a known row.

---

## 7. CI integration

- **Where:** the `e2e` job in `.github/workflows/ci.yml`, on a hosted Android emulator (`reactivecircus/android-emulator-runner`, api-level 34 / x86_64 / google_apis). Offline flows require Android (airplane mode).
- **When:** on every PR and every push to `main`, after `gate` passes. Booting an emulator to test code that does not compile wastes ~15 minutes.
- **Artifacts:** Maestro writes a screenshot and view hierarchy per step to `~/.maestro/tests`; uploaded always, per configuration. The mock server log is uploaded too.
- **Data isolation:** each flow starts with `clearState` and re-seeds; never share state between flows.

### 7.1 One APK per configuration — the `e2e` matrix

**Read this before adding or editing a flow.** `AppConfig` reads `E2E`, `ROLE`, `QUALITY`,
`SEED`, `LOCALE` and `API_BASE_URL` through `const String.fromEnvironment` /
`const bool.fromEnvironment`. Those are **compile-time** constants: the value is baked into
the APK. Maestro's `launchApp: arguments:` sends Android **intent extras** at **runtime**,
and this app has no bridge between the two — `MainActivity.kt` is a bare five-line
`FlutterActivity`. **A Maestro argument cannot configure this app. It never could.**

So the suite is not "one APK, filter by tag". CI builds **one APK per distinct dart-define
set** and runs only the flows that build suits:

| Matrix key | Extra dart-defines | Flows |
|---|---|---|
| `field` | *(none — defaults `ROLE=field_user`, `QUALITY=pass`, no `SEED`)* | `carpenter_search_confirm`, `field_online_capture`, `field_offline_capture` |
| `crm` | `ROLE=crm_verifier` | `crm_case_decision`, `crm_case_conflict` |
| `recapture` | `QUALITY=fail` | `field_capture_recapture` |
| `queue` | `SEED=queue` | `offline_queue_retry` |
| `locale` | `LOCALE=bn` | `locale_bengali` |

Every configuration also gets `--dart-define=E2E=true` and
`--dart-define=API_BASE_URL=http://10.0.2.2:8080` (`10.0.2.2` is how an Android emulator
reaches the host loopback). `fail-fast: false`, so one red configuration does not mask the
other four.

Why each split is load-bearing, not tidiness:

- **`crm`** — with the default `field_user` the session has no `verificationDecide`, so
  `/verification/cases/:id` redirects to `/forbidden` and both CRM flows die before their
  first assertion.
- **`recapture`** — `E2EQualityChecker(failFirst: true)` fails exactly once *per app
  process*, so it cannot share an APK with a flow whose first capture must pass.
- **`queue`** — `SEED=queue` seeds one pending sync task. `field_offline_capture` asserts an
  *exact* pending count of one, so it must NOT run on this APK. `e2e_seeder.dart` says so at
  the seed site.
- **`locale`** — every other flow falls back to English visible-text selectors and would
  break against a Bengali build.

**Flows are selected by file path, never by `--include-tags`.** `field_offline_capture` is
tagged `field, critical, offline` with **no `android` tag**, yet §3.5 makes offline flows
Android-only — a tag filter would silently skip the highest-value flow in the suite.
`campaign_list_smoke` is `web`-tagged and stays out of the emulator job.

**If total runtime becomes a problem**, the documented fallback is `pr-smoke`
(`field_online_capture`, `crm_case_decision`) on PRs with the full matrix nightly. Propose
that; do not delete coverage. Note the five configurations run **in parallel**, so wall
clock is roughly one configuration (~10–15 min), not five.

### 7.2 Running it locally

Start the mock backend first and leave it running — five flows need it:

```bash
cd tool/mock_server && dart pub get && dart run bin/server.dart &
# fixture variants for the web smoke flow:
#   MOCK_CAMPAIGNS=empty dart run bin/server.dart
```

Then build the configuration you need and run its flows:

```bash
flutter build apk --flavor dev --debug \
  --dart-define=E2E=true \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080 \
  --dart-define=ROLE=crm_verifier          # ← the per-configuration part
adb install -r build/app/outputs/flutter-apk/app-dev-debug.apk
maestro test --env APP_ID=com.acsl.campaign.dev .maestro/flows/crm_case_decision.yaml
```

`.maestro/config.yaml` lists every flow, but running the whole file against a single APK
fails five flows for configuration reasons alone. It is kept current for inventory and for
single-configuration local runs.

**App ID:** since the Android flavors (Task 2) gave `dev` its own application ID
(`com.acsl.campaign.dev`), flows carry no literal app ID — every `appId:` field reads
`appId: ${APP_ID}`, supplied at run time. Confirmed rather than assumed: Maestro supports
`appId: ${APP_ID}` and resolves it from `maestro test --env APP_ID=…` (or `-e`) — documented
Maestro env-injection behavior. Two caveats: the value must arrive through `--env`/`-e` (a
bare shell environment variable does not reach a flow unless it is prefixed `MAESTRO_`); and
there is an open upstream Maestro bug where **web** platform detection reads `appId` before
env expansion, which affects `campaign_list_smoke.yaml`, the one web flow — already outside
the emulator job.

**Cleartext HTTP:** `android/app/src/debug/AndroidManifest.xml` sets
`android:usesCleartextTraffic="true"`. Android blocks cleartext by default for apps
targeting API 28+ and this app targets 36, so without it every mock-backed request fails and
surfaces as a *designed error state* ("Couldn't load campaigns.", the CRM case Retry button)
— which reads like a flaky flow rather than a transport policy. It is scoped to the debug
source set; release and profile builds keep the secure default. Do not move it to `src/main`.

**Correction (P0.5):** this section previously recorded that neither an emulator E2E job
(Task 8) nor a nightly suite (Task 9) would be built — "cancelled, not deferred". **The E2E
job half of that is reversed**: the `e2e` job above exists and a green `e2e` is a hard exit
criterion for Epic P0.5. The nightly suite remains cancelled. `TASK_BREAKDOWN.md`'s T-0.1.4
row carries the same correction.

---

## 8. Maintenance

- Prefer `id:` selectors over text (survives bn/en and copy changes) — drives §3.1.
- Keep flows journey-level; push assertions about specific states down to widget/golden tests.
- One behavior per flow; compose shared steps as subflows (`runFlow`).
- When a flow gets flaky, first suspect a missing explicit wait/assert, not a `sleep`.

---

## 9. Gap summary (ordered)

1. ~~No stable test IDs~~ — **done** (`Semantics(identifier:)` + `BmdButton.identifier`).
2. ~~No E2E build mode~~ — **done** (`E2E=true`: fake auth, `/dev` launcher, fake camera, seeder).
3. ~~No mock backend~~ — **done**: `tool/mock_server/` (Dart `shelf`) implements every endpoint incl. the `CASE_CONFLICT` 409 and the presign→upload→confirm sync path. Run it and point `API_BASE_URL` at it.
4. **ML Kit quality impl** — E2E uses `E2EQualityChecker`; the real on-device checker (T-2.2.2) is still unbuilt.
5. **Flutter-web selection is experimental** — treat `campaign_list` as smoke only; real web E2E coverage may need Playwright instead.
6. **iOS offline** — not covered by Maestro; Android is the field target so acceptable.
7. ~~No CI job~~ — **done** (P0.5): the `e2e` matrix job, §7.1. Note the corollary: no flow in this file had ever been executed by anything before that job, so several carried assertions on text the app does not render. Four were corrected against source in P0.5 (`offline_queue_retry`'s dialog title and cancel label, the queue empty-state full stop, `field_offline_capture`'s `"1 pending"` and `"All items synced"`). **Expect more.** A literal in a flow is only as good as the last run that exercised it.
8. **Nightly suite** — still cancelled (T-0.1.4), and the full matrix now runs per-PR instead.
