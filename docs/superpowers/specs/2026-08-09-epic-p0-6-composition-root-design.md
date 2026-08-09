# Epic P0.6 — Composition-root integrity (T-0.6.1)

**Date:** 2026-08-09
**Task:** T-0.6.1 — "Provider graph for core services (client, db, auth, storage, audit) + test overrides"
**Depends on:** P0.3.*, P0.4.1 (both complete). P0.5 is green on PR #3 and should merge first — this epic modifies `lib/app/di/providers.dart` and `lib/main.dart`.

---

## 1. Why this epic is not "add providers"

The **graph half of T-0.6.1 already exists**: 25 core providers in `lib/app/di/providers.dart`, plus ~13 controller providers co-located with their features. `riverpod_generator` was deliberately dropped (ARCHITECTURE §6 amendment, 2026-07-30) and stays dropped.

The **verification half does not exist**. Measuring that turned up four defects, one of which means the web build cannot start.

### 1.1 Measured facts

Every row below was measured in this repo, not inferred. The measurements are the spine of this design; anything a reader doubts should be re-measured the same way.

| # | Finding | How it was established |
|---|---|---|
| F1 | **The composition root is exercised by no test.** | Replaced `appDatabaseProvider`'s body with `throw StateError(...)` → **all 367 tests still passed**. Restored byte-exact (`git diff` empty). |
| F2 | **A "every provider resolves" test would be nearly vacuous.** | All 24 core providers build successfully with *only* `appConfigProvider` overridden — **zero** need an override. Riverpod construction is lazy in the relevant way. |
| F3 | **…because construction is deferred; *using* the DB is what fails.** | Querying the real `appDatabaseProvider` under `flutter_test` throws `MissingPluginException(No implementation found for method getTemporaryDirectory on channel plugins.flutter.io/path_provider)`. |
| F4 | **Drift on web was never wired up. The web build cannot start.** | `web/` contains no `sqlite3.wasm` and no `drift_worker.js`. `AppDatabase.open()` is `super(driftDatabase(name: 'acsl_campaign'))` — **no `web:` argument**. `drift_flutter`'s `connect.dart` exports `web.dart` when `dart.library.js_interop` is set, and that opener begins `if (web == null) throw ArgumentError(...)`. The error string appears **once** in the compiled `build/web/main.dart.js`, so the throwing path is provably in the shipped bundle. `main.dart`'s `container.read(auditFlusherProvider)` resolves the database, so the throw lands **before `runApp`**. |
| F5 | **`main.dart` is covered by no test**, yet performs five container reads before `runApp`. | No file under `test/` references `main.dart`. |
| F6 | **Two unguarded failure paths.** | `_flushOnce()` (`audit_emitter.dart:175-186`) has no `try`/`catch` and is invoked as `unawaited(flush())` from a `Timer.periodic`, so a DB failure becomes a recurring **unhandled async error** and no audit event is ever flushed. `restore()` does not wrap `await _tokens.read()` (`session_manager.dart:211`), and `main.dart` awaits it unguarded — on web, `SecureStore` is `localStorage`, so an unavailable store means `runApp` is never reached. |
| F7 | **Overrides are ad-hoc.** | 12 test files hand-roll a `ProviderContainer`; `authStateProvider` is overridden 13 times across files, through **two different mechanisms** (`overrideWith` ×8, `overrideWithValue` ×5). |

### 1.2 Consequences worth stating plainly

- **Web is the primary surface for P1 (campaign admin) and P3 (CRM)**, and F4 means it cannot start. CI's `flutter build web --release` passes because compiling is not running, and nothing in the repo has ever run the web build.
- **P0.5's per-device locale preference is also broken on web**, because it persists to `cached_reference` in the same database (`pref:locale`). Same root cause, one more consequence.
- F1 and F2 together are the trap this epic must avoid repeating: the obvious test (resolve every provider) passes today with nothing overridden, so writing it and stopping there would produce a green test that guards nothing.

---

## 2. Decisions

| # | Decision | Alternatives considered |
|---|---|---|
| **D1** | **A `databaseDirectory` seam in `lib/`** makes the real database usable from a test: `AppDatabase.open({Future<Directory> Function()? databaseDirectory})` forwards to `DriftNativeOptions`, and a leaf `databaseDirectoryProvider` (default `null` → today's production behaviour) is what `appDatabaseProvider` reads. | Faking `PathProviderPlatform.instance` in the test needs no production change and would exercise `drift_flutter`'s real path resolution — including the `getTemporaryDirectory` call that actually throws. **Rejected by the user with that tradeoff on the record.** Consequence, accepted: the boot test does **not** cover real path resolution; that guarantee stays solely with the emulator E2E, which did verify it (`PRAGMA user_version` = 3 on a device). What the seam *does* cover is our own code — `open()`, the v1→v2→v3 migration chain, and schema shape — against a real **on-disk** file rather than in-memory. |
| **D2** | **Bundle the Drift web assets.** Commit `sqlite3.wasm` and `drift_worker.js` into `web/`, and pass `web: DriftWebOptions(...)` from `AppDatabase.open()`. | Dropping Drift on web and using platform-specific light stores (locale → `localStorage`, audit → direct send with an in-memory retry queue) costs no payload, but means **two behavioural code paths** and audit losing durability across a tab reload — a compliance record lost on refresh. Rejected. Using a remote database (e.g. Postgres) directly from the client is not an alternative at all: a browser cannot speak the Postgres wire protocol, client-shipped credentials cannot enforce per-user RBAC, and the local database exists precisely to work **offline**, which no remote store can do. Reaching the server is already the API's job. Payload cost (~1.5–2 MB on web) is accepted; T-4.6's web performance pass is where size gets revisited. |
| **D3** | **`bootstrap()` never throws.** Every pre-frame step degrades rather than aborting. | Letting a boot step abort startup. Rejected: a user facing a blank screen can neither sign in nor generate audit, so aborting is strictly worse than degrading — for *every* step in the current sequence. |
| **D4** | **A degraded boot must be observable.** Each failure is recorded on a `BootDiagnostics` value exposed by a provider. | Guarding with a bare `catch` + `debugPrint`. Rejected: that is exactly today's audit behaviour (F6) — silent, continuous, invisible — and it is the failure mode this epic exists to remove. "Guarded" must not come to mean "silent". |
| **D5** | **One shared test harness** (`buildTestContainer`) with sensible fakes, replacing the hand-rolled containers. | Leaving each test to assemble its own. Rejected: F7 shows the duplication has already produced two different override mechanisms for the same provider, which is how tests drift apart. |

---

## 3. Deliverables

### D-A. Database-directory seam
`AppDatabase.open({Future<Directory> Function()? databaseDirectory})`, forwarded as `DriftNativeOptions(databaseDirectory: ...)`. New leaf `databaseDirectoryProvider` defaulting to `null`. Production behaviour byte-identical when the override is absent, and a test asserts that default is `null` so a test directory can never ship.

### D-B. Web persistence
- `web/sqlite3.wasm` and `web/drift_worker.js` committed.
- `AppDatabase.open()` passes `web: DriftWebOptions(sqlite3Wasm: ..., driftWorker: ...)`.
- A test asserting both files exist, so they cannot silently vanish — the same class of guard the epic keeps needing.

### D-C. Composition-root test
Builds a container overriding **only** `appConfigProvider` and `databaseDirectoryProvider`, then:
- **uses** the database — asserts `user_version == 3` — so `open()` and the migration chain actually execute on a real file;
- resolves the full core provider set. This half is **explicitly labelled weak** in the test's own comment, citing F2: it passes today with nothing overridden, so it guards wiring/cycle breakage only.

### D-D. Guarded, testable bootstrap
Extract `main()`'s pre-frame sequence into `bootstrap()`, which returns the container and never throws.

`BootDiagnostics` holds one entry per degraded step: which step, and the error it degraded on
(`step` plus a rendered error string is enough — no stack traces, since these are read for
"what came up degraded", not for debugging). Empty means a clean boot. It is exposed through a
provider so a later task can surface it in-app; this epic only requires that it be **recorded
and asserted**, not displayed.

| Step | Policy | Cost when it fails |
|---|---|---|
| `appConfigProvider` | pure; cannot fail | — |
| E2E seeding | already best-effort | fixtures missing → flows fail loudly (correct for a test build) |
| `localeController.load()` | already guarded internally | falls back to system locale |
| `auditFlusher.start()` | safe as-is; **`flush()` gains its own guard** | audit not flushed — recorded, not silent |
| `sessionManager.restore()` | **new guard** → degrade to `AuthSignedOut` | user signs in again |
| E2E `signIn()` | guard | run lands on `/login`, flow fails loudly |

### D-E. Shared test harness
`buildTestContainer({...})` in `test/support/`, composing the existing fakes (`fake_auth.dart`, `in_memory_secure_store.dart`, `recording_audit_sink.dart`, `scripted_adapter.dart`). It must: default the database to `NativeDatabase.memory()`, default auth to a signed-in session whose permission set the caller can specify, accept arbitrary extra overrides that win over the defaults, and register its own teardown — so a caller writes only the overrides its test is *about*. Migrate the 12 hand-rolled containers, collapsing the 13-way `authStateProvider` duplication onto one mechanism.

Note the deliberate asymmetry with D-C: this harness fakes the database, because feature tests should not pay for real I/O. **Only** the composition-root test uses the real one. Both are needed — the harness for speed, D-C for the guarantee the harness necessarily gives up.

---

## 4. Testing

| Test | Asserts |
|---|---|
| Composition root | real DB reaches `user_version == 3` on disk; every core provider resolves (weak half, labelled) |
| Bootstrap resilience | `bootstrap()` **completes** with a throwing `appDatabaseProvider` — the exact web case — **and records** the failure. The probe that found F1 becomes this regression test. |
| Web assets | `web/sqlite3.wasm` and `web/drift_worker.js` exist |
| `restore()` guard | a throwing token store degrades to `AuthSignedOut` rather than propagating |
| `flush()` guard | a DB failure is caught and recorded; the timer keeps retrying |
| Seam default | `databaseDirectoryProvider` defaults to `null` (production path) |

**Baseline to hold:** 367 passing / **29 skipped**. The 29 are Linux-gated goldens; the skip count is how a broken golden gets noticed locally and must not change.

**What remains unverifiable in Dart tests**, and must be said rather than implied: real `path_provider` path resolution (D1's accepted consequence) and web runtime behaviour. The latter should be confirmed by actually loading the web build in a browser once D-B lands — the one check that would have caught F4 at any point in the last four epics.

---

## 5. Non-goals

- Restructuring the provider graph or splitting `providers.dart`.
- Adopting `riverpod_generator` (ARCHITECTURE §6 amendment stands).
- Reworking the `authService → dio → authState → sessionManager` cycle, which is held together by explicit type annotations and documented in place. It works; a verification epic is not where it changes.
- A non-Drift audit fallback for browsers where the wasm/OPFS features Drift needs are
  unavailable. D-B makes audit durable on web wherever Drift can open at all;
  `WasmDatabaseResult.missingFeatures` reports the degraded cases, and handling those is
  its own task. (Stated this way deliberately: "make audit durable on web" is *not* a
  non-goal — D-B does exactly that. Only the sub-wasm fallback is out of scope.)

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| The boot test passes while proving little (F2's trap). | The DB assertion is a *query*, not a resolve. The weak half is labelled as weak in the code, so no future reader mistakes it for coverage. |
| Bundled wasm assets go stale against a future `drift` upgrade. | The asset-existence test catches deletion, not staleness. Record the drift version the assets came from beside them, so an upgrade has an obvious checkpoint. |
| `bootstrap()`'s guards hide a real regression. | D4: every failure is recorded on `BootDiagnostics`, and the bootstrap test asserts the recording, not just the completion. |
| Migrating 12 test files to the shared harness churns unrelated tests. | Migrate mechanically, one file per commit, with test counts unchanged at each step. |
