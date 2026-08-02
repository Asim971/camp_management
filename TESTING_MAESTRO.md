# Maestro E2E Test Plan — ACSL Carpenter Campaign Management

**Scope:** UI end-to-end tests (Maestro) for the currently implemented screens.
**Companion to:** [`ARCHITECTURE_Flutter.md`](ARCHITECTURE_Flutter.md) §14 (testing strategy), [`TASK_BREAKDOWN.md`](TASK_BREAKDOWN.md).
**Status:** Plan + scaffolded flows in [`.maestro/`](.maestro). Flows are runnable once the enablement prerequisites in §3 are met.

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

> **Status: app-side enablement is now implemented.** The `E2E=true` build mode (fake auth, `/dev` launcher, fake camera, fail-then-pass quality, local data seeding) and the `Semantics(identifier:)` test IDs are in the codebase (`lib/app/flavors.dart`, `lib/core/auth/e2e_session.dart`, `lib/features/dev/`, `lib/core/media/capture_source.dart`, `lib/core/dev/e2e_seeder.dart`). What remains before every flow is green: the **mock backend** (§3.4) and the real **ML Kit** quality impl. Flows needing only client state (`carpenter_search_confirm`, `field_capture_recapture`, the capture→queued portion, `offline_queue_retry`) run with no mock; the reconnect-sync transition and CRM flows need the mock server.

Maestro drives a *running* app. These were the blockers, each a small, well-scoped task:

### 3.1 Stable selectors (test IDs) — **highest priority**
Flutter renders text into the a11y tree, so text selectors work, but labels are localized (bn/en) and change. Add stable identifiers via Flutter's `Semantics(identifier: …)` (maps to Android `resource-id` / iOS `accessibilityIdentifier`, which Maestro matches with `id:`).

```dart
Semantics(identifier: 'capture_shutter', child: BmdButton(label: 'Capture', ...));
```

Minimum identifier set the scaffolded flows expect:

| id | Widget |
|----|--------|
| `capture_accept` / `capture_ready` / `capture_shutter` / `capture_submit` / `capture_recapture` | camera_capture steps |
| `capture_done` | captured confirmation |
| `search_field` / `search_result` / `confirm_ack` / `confirm_continue` | carpenter_search |
| `queue_pending_count` / `queue_item_menu` / `queue_retry` / `queue_discard_confirm` | offline_queue |
| `crm_reason` / `crm_outcome_approve` / `crm_submit` | crm_case |

Until these land, flows fall back to visible-text selectors (English), which is why every flow sets `--dart-define=LOCALE=en`.

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

**Target E2E count: 8 flows.** Deliberately small — every added flow is real device wall-clock and maintenance.

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

- **Where:** Maestro Cloud or a self-hosted Android emulator runner. Offline flows require Android (airplane mode).
- **When:** not on every PR (too slow). Run the full suite nightly and on release-candidate branches; run a 2-flow smoke (`field_online_capture`, `crm_case_decision`) on PRs touching those features.
- **Artifacts:** Maestro records video + screenshots per step; upload on failure.
- **Data isolation:** each flow starts with `clearState` and re-seeds; never share state between flows.

```bash
# local run (Android emulator, E2E build installed)
maestro test .maestro/flows/field_offline_capture.yaml
# whole suite
maestro test .maestro/
```

Build the E2E app first:
```bash
flutter build apk --debug \
  --dart-define=E2E=true \
  --dart-define=LOCALE=en \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

**App ID and tags:** since the Android flavors (Task 2) gave `dev` its own application ID
(`com.acsl.campaign.dev`), flows no longer carry a literal app ID — every `appId:` field
reads `appId: ${APP_ID}` and must be supplied at run time:

```bash
maestro test --env APP_ID=com.acsl.campaign.dev --include-tags pr-smoke .maestro/
```

Selection uses two tags: `pr-smoke` marks the 2 flows (`field_online_capture`,
`crm_case_decision`) run on every PR, and `android` marks the 7 flows run nightly on the
emulator. `campaign_list_smoke` carries neither — it's a web flow that needs the mock
server restarted with different `MOCK_CAMPAIGNS` values, so it can't run in the Android
job. Whether Maestro actually interpolates `${APP_ID}` inside `appId` is not yet verified
here; the CI E2E job (Task 8) is what confirms it.

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
