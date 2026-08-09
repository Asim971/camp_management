# Epic P0.6 — Composition-root integrity and the storage plan (T-0.6.1)

**Date:** 2026-08-09
**Task:** T-0.6.1 — "Provider graph for core services (client, db, auth, storage, audit) + test overrides"
**Depends on:** P0.3.*, P0.4.1 (both complete). P0.5 is green on PR #3 and should merge first — this epic modifies `lib/app/di/providers.dart` and `lib/main.dart`.
**Sources reviewed:** all 32 feature PRDs under `docs/ways-of-work/plan/`, `PRIORITIZED_TASK_BREAKDOWN.md`, `ARCHITECTURE_Flutter.md` §6, `TASK_BREAKDOWN.md`.

---

## 1. Why this epic is not "add providers"

The **graph half of T-0.6.1 already exists**: 25 core providers in `lib/app/di/providers.dart`, plus ~13 controller providers co-located with their features. `riverpod_generator` was deliberately dropped (ARCHITECTURE §6 amendment, 2026-07-30) and stays dropped.

The **verification half does not exist**, and the **storage design has been planned around the five tables that happen to exist today** rather than the persistence the feature portfolio requires. Both gaps are this epic's subject.

### 1.1 Measured facts

Every row was measured in this repo, not inferred. These measurements are the spine of the design; re-measure the same way before doubting one.

| # | Finding | How it was established |
|---|---|---|
| F1 | **The composition root is exercised by no test.** | Replaced `appDatabaseProvider`'s body with `throw StateError(...)` → **all 367 tests still passed**. Restored byte-exact (`git diff` empty). |
| F2 | **An "every provider resolves" test would be nearly vacuous.** | All 24 core providers build with *only* `appConfigProvider` overridden — **zero** need an override. Riverpod construction is lazy in the relevant way. |
| F3 | **Construction is deferred; *using* the database is what fails.** | Querying the real `appDatabaseProvider` under `flutter_test` throws `MissingPluginException(No implementation found for method getTemporaryDirectory on channel plugins.flutter.io/path_provider)`. |
| F4 | **Drift on web was never wired up. The web build cannot start.** | `web/` has no `sqlite3.wasm` and no `drift_worker.js`. `AppDatabase.open()` is `super(driftDatabase(name: 'acsl_campaign'))` — **no `web:` argument**. `drift_flutter`'s `connect.dart` exports `web.dart` when `dart.library.js_interop` is set, and that opener begins `if (web == null) throw ArgumentError(...)`. The error string appears **once** in the compiled `build/web/main.dart.js`, so the throwing path is provably in the shipped bundle, and `main.dart` resolves the database before `runApp`. |
| F5 | **`main.dart` is covered by no test**, yet performs five container reads before `runApp`. | No file under `test/` references `main.dart`. |
| F6 | **Two unguarded failure paths.** | `_flushOnce()` (`audit_emitter.dart:175-186`) has no `try`/`catch` and is invoked as `unawaited(flush())` from a `Timer.periodic`, so a database failure becomes a recurring **unhandled async error** and no audit event is ever flushed. `restore()` does not wrap `await _tokens.read()` (`session_manager.dart:211`) and `main.dart` awaits it unguarded — on web `SecureStore` is `localStorage`, so an unavailable store means `runApp` is never reached. |
| F7 | **Overrides are ad-hoc.** | 12 test files hand-roll a `ProviderContainer`; `authStateProvider` is overridden 13 times across files through **two different mechanisms** (`overrideWith` ×8, `overrideWithValue` ×5). |
| F8 | **The offline roster cache cannot meet its own PRD.** | `registration_repository_impl.dart` stores an entire session roster as **one JSON blob** in `cached_reference`; `searchCached` decodes that whole blob and filters in Dart per query. P0.14 requires search "by name, carpenter ID and approved phone suffix" and to "return local search results quickly under offline field conditions" — a full parse per keystroke with no index will not hold at session scale. |
| F9 | **`cached_reference` serves two incompatible purposes.** | It holds evictable server caches (`session:<id>:registrations`) *and* a user preference that must never be evicted (`pref:locale`, added in P0.5). P0.5 mitigated this with a key-prefix convention and documented the risk; the arriving features make a convention insufficient. |

### 1.2 Consequences worth stating plainly

- **Web is the primary surface for P1 (campaign admin) and P3 (CRM)**, and F4 means it cannot start. CI's `flutter build web --release` passes because compiling is not running, and nothing in the repo has ever *run* the web build.
- **P0.5's per-device locale preference is also broken on web**, since it persists into the same database. Same root cause, one more consequence.
- F1 with F2 is the trap this epic must not repeat: the obvious test (resolve every provider) passes today with nothing overridden, so writing it and stopping would produce a green test guarding nothing.

---

## 2. What the feature portfolio actually requires of local storage

Derived from the PRDs, not from the current schema. "Platform" is where the requirement lands.

| Backlog item | Must persist locally | Platform | Today | Verdict |
|---|---|---|---|---|
| P0.3 Notices | approved active versions cached for offline use; historical rendering retained | mobile | `consent_notices` | adequate |
| P0.3.3 Presentation outcome | notice version, language, presented time, **acceptance / refusal / manual-route outcome**, correlation ID | mobile | 4 columns on `attendance_drafts` | models acceptance only; refusal and manual route are unrepresented |
| P0.4.2 Audit | buffered delivery **and reconciliation** for capture, evidence open, reveal, decision, export, override, settings | both | `audit_events` | adequate; reconciliation status absent |
| P0.4.3 Protected media | "expire viewer sessions and clear protected cached media according to policy" | both | evidence files on disk | no retention owner |
| P0.7 Campaign authoring | "preserve draft input across refresh and recoverable failures"; step progress; unsaved-state handling | **web** | server-side draft only | undecided (see §3 D7) |
| P0.9 / P0.13 Session readiness | cached assignment + offline queue capacity, so a valid session is *Offline-ready* rather than blocked | mobile | nothing | new |
| P0.14 Carpenter selection | authorized registration snapshot, searchable by name / ID / phone suffix, with freshness | mobile | one JSON blob (F8) | broken as designed |
| P0.15 Capture | encrypted evidence + participant/session/user/device/time/location metadata, atomically | mobile | `attendance_drafts` + evidence store | adequate |
| P0.16 Sync | durable queue; **real last-successful-sync timestamp**; restart/background resume | mobile | `sync_tasks` | queue adequate; timestamp not persisted |
| P0.19 Decision / recapture | attempt lineage, remaining-attempt count, new-attempt lineage | mobile | nothing | new |
| P1.5 Configuration | effective configuration version pinned on governed business events; historical resolution | **web** + pinning on mobile events | nothing | new |
| P0.5 Locale (done) | device language preference | both | `cached_reference` under `pref:` | works; tier is wrong (F9) |

**Conclusion.** The schema will roughly double. Planning storage around today's five tables — as this spec's first draft did — was the wrong frame. But building all of it now would be worse: the contracts behind P0.11, P0.16, P0.22 and P1.5 are still 🔒 blocked, so their shapes would be guesses. What is needed now is the **tiering and the conventions**, so each feature adds its table without reinventing the rules.

---

## 3. Decisions

| # | Decision | Alternatives considered |
|---|---|---|
| **D1** | **Two directory seams in `lib/`** make the real database usable from a test: `AppDatabase.open({Future<Object> Function()? databaseDirectory, Future<String?> Function()? tempDirectoryPath})` forwards both to `DriftNativeOptions`, and two leaf providers (each defaulting to `null` → today's production behaviour) are what `appDatabaseProvider` reads. **Corrected while planning:** one seam is not enough. The measured failure was `getTemporaryDirectory`, and `drift_flutter`'s `native.dart:66` defaults `tempDirectoryPath` to exactly that call — so seaming only `databaseDirectory` would have shipped a seam that does not work. The upstream types are also `Future<Object>` (a String *or* a Directory) and `Future<String?>`, not `Future<Directory>` as first written here. | Faking `PathProviderPlatform.instance` needs no production change and would exercise `drift_flutter`'s real path resolution — including the `getTemporaryDirectory` call that actually throws. **Rejected by the user with that tradeoff on the record.** Accepted consequence: the boot test does **not** cover real path resolution; that guarantee stays with the emulator E2E, which did verify it (`PRAGMA user_version` = 3 on a device). What the seam does cover is our own code — `open()`, the v1→v2→v3 chain, schema shape — against a real **on-disk** file rather than in-memory. |
| **D2** | **Bundle the Drift web assets.** Commit `sqlite3.wasm` and `drift_worker.js` into `web/`; pass `web: DriftWebOptions(...)` from `AppDatabase.open()`. | Dropping Drift on web for platform-specific shims (locale → `localStorage`, audit → direct send) costs no payload but means two behavioural code paths — and §2 shows web's needs *grow*: audit buffering, configuration versions, possibly authoring drafts. The shim cost is paid once per future feature. Using a remote database (e.g. Postgres) directly from the client is not an alternative at all: a browser cannot speak the Postgres wire protocol, client-shipped credentials cannot enforce per-user RBAC, and the local store exists precisely to work **offline**, which no remote store can. Reaching the server is already the API's job. Payload (~1.5–2 MB, web only) accepted; T-4.6's performance pass revisits size. |
| **D3** | **`bootstrap()` never throws.** Every pre-frame step degrades rather than aborting. | Letting a boot step abort startup. Rejected: a user facing a blank screen can neither sign in nor generate audit, so aborting is strictly worse than degrading for every step in the current sequence. |
| **D4** | **A degraded boot must be observable.** Each failure is recorded on a `BootDiagnostics` value exposed by a provider. | A bare `catch` + `debugPrint`. Rejected: that is exactly today's audit behaviour (F6) — silent, continuous, invisible — and it is the failure mode this epic exists to remove. "Guarded" must not come to mean "silent". |
| **D5** | **One shared test harness** (`buildTestContainer`) with sensible fakes. | Leaving each test to assemble its own. Rejected: F7 shows the duplication already produced two override mechanisms for one provider, which is how test suites drift apart. |
| **D6** | **Five storage tiers, with `cached_reference` split by tier.** Preferences move to a `pref:`-only surface distinct from evictable caches, so a future cache sweep cannot take a user's settings with it. | Keeping one table with a key-prefix convention (P0.5's mitigation). Rejected on the strength of §2: with configuration caches, assignment snapshots and rosters arriving, a convention that only a comment enforces will be broken by whoever adds the sweep. |
| **D7** | **Web authoring drafts stay server-side for now.** P0.7's "preserve draft input across refresh" is satisfied by the server draft the PRD already mandates ("Create a unique Draft campaign"); a local unsaved-edit buffer is **not** added speculatively. | Adding a local draft buffer in P0.6. Rejected as premature — whether unsaved edits must survive a refresh is a P0.7 product question, and D2 means the storage is there when P0.7 decides it needs it. Recorded so P0.7 makes the call deliberately instead of discovering the gap. |

---

## 4. Deliverables

### D-A. Database-directory seam
`AppDatabase.open({Future<Directory> Function()? databaseDirectory})` forwarded as `DriftNativeOptions(databaseDirectory: ...)`. New leaf `databaseDirectoryProvider` defaulting to `null`. Production behaviour byte-identical when the override is absent, and a test asserts that default is `null` so a test directory can never ship.

### D-B. Web persistence
- `web/sqlite3.wasm` and `web/drift_worker.js` committed, with the `drift` version they came from recorded beside them.
- `AppDatabase.open()` passes `web: DriftWebOptions(...)`.
- A test asserting both files exist, so they cannot silently vanish.

### D-C. Composition-root test
A container overriding **only** `appConfigProvider` and `databaseDirectoryProvider`, which then:
- **uses** the database — asserts `user_version == 3` — so `open()` and the migration chain execute against a real file;
- resolves the full core provider set. This half is **explicitly labelled weak in its own comment**, citing F2: it passes today with nothing overridden, so it guards wiring and cycle breakage only.

### D-D. Guarded, testable bootstrap
Extract `main()`'s pre-frame sequence into `bootstrap()`, returning the container and never throwing.

`BootDiagnostics` holds one entry per degraded step — the step plus a rendered error string; no stack traces, since it is read for "what came up degraded", not for debugging. Empty means a clean boot. Exposed through a provider so a later task can surface it in-app; this epic requires only that it be **recorded and asserted**.

| Step | Policy | Cost when it fails |
|---|---|---|
| `appConfigProvider` | pure; cannot fail | — |
| E2E seeding | already best-effort | fixtures missing → flows fail loudly (correct for a test build) |
| `localeController.load()` | already guarded internally | falls back to system locale |
| `auditFlusher.start()` | safe as-is; **`flush()` gains its own guard** | audit not flushed — recorded, not silent |
| `sessionManager.restore()` | **new guard** → degrade to `AuthSignedOut` | user signs in again |
| E2E `signIn()` | guard | run lands on `/login`, flow fails loudly |

### D-E. Shared test harness
`buildTestContainer({...})` in `test/support/`, composing the existing fakes (`fake_auth.dart`, `in_memory_secure_store.dart`, `recording_audit_sink.dart`, `scripted_adapter.dart`). It must: default the database to `NativeDatabase.memory()`, default auth to a signed-in session whose permission set the caller specifies, accept extra overrides that win over the defaults, and register its own teardown — so a caller writes only the overrides its test is *about*. Migrate the 12 hand-rolled containers, collapsing the 13-way `authStateProvider` duplication onto one mechanism.

Deliberate asymmetry with D-C: this harness **fakes** the database, because feature tests should not pay for real I/O; **only** the composition-root test uses the real one. Both are needed — the harness for speed, D-C for the guarantee the harness gives up.

### D-F. Storage plan (documentation + the tier split)

**Tiers.** Every persisted thing belongs to exactly one:

| Tier | Contents | Eviction | Encrypted | Platform |
|---|---|---|---|---|
| **Durable outbound** | `sync_tasks`, `audit_events` | never automatically; only after server confirmation, or after the documented permanent-rejection rule | payload-level where it carries personal data | both |
| **Evidence** | encrypted capture files + `attendance_drafts` rows | only after server confirmation **and** retention policy (P0.4.3 owner: media/security) | yes, at rest (Keystore key) | mobile |
| **Evictable cache** | server-derived reads: rosters, assignments, configuration versions | freely, with a freshness stamp so staleness is visible | no | both |
| **Preference** | device settings such as `pref:locale` | **never** | no | both |
| **Secret** | tokens, evidence keys — `SecureStore`, never Drift | on sign-out per the existing generation rules | platform-backed | both |

**Rule for table vs blob.** A thing earns its own Drift table when it is **searched, sorted, or counted**, or when more than one access pattern reads it. Otherwise a `cached_reference` row is enough. F8 is exactly this rule violated: the roster is searched by three fields, so it needed a table from the start.

**The split.** `cached_reference` keeps evictable server caches only. Preferences move to their own surface so that a future cache sweep — which P0.4.3 and P1.7 both imply — cannot delete a user's settings. Migration carries the existing `pref:locale` row across, and a test asserts a cache sweep leaves preferences intact.

**Forward-flagged, not built here** (each lands with its feature, against these tiers):

| Coming | Tier | Owner | Requirement it must satisfy |
|---|---|---|---|
| Session assignment / readiness snapshot | evictable cache | P0.13 | offline-ready rather than blocked with no network |
| **Indexed roster table (replacing the blob)** | evictable cache | P0.14 | searchable by name / ID / phone suffix, fast offline — **fixes F8** |
| Notice outcome: refusal + manual route | evidence | P0.3.3 / P0.15 | every capture resolves to the exact version *and outcome* presented |
| Attempt lineage | evidence | P0.19 | remaining-attempt count and new-attempt lineage |
| Configuration version cache + event pinning | evictable cache | P1.5 | historical resolution of the effective version |
| Audit reconciliation status | durable outbound | P0.4.2 | buffered events reconcile with the server |
| Media retention / cleanup | evidence | P0.4.3 | protected cached media cleared per policy |

---

## 5. Testing

| Test | Asserts |
|---|---|
| Composition root | the real database reaches `user_version == 3` on disk; every core provider resolves (weak half, labelled) |
| Bootstrap resilience | `bootstrap()` **completes** with a throwing `appDatabaseProvider` — the exact web case — **and records** the failure. The probe that found F1 becomes this regression test. |
| Web assets | `web/sqlite3.wasm` and `web/drift_worker.js` exist |
| `restore()` guard | a throwing token store degrades to `AuthSignedOut` rather than propagating |
| `flush()` guard | a database failure is caught and recorded; the timer keeps retrying |
| Seam default | `databaseDirectoryProvider` defaults to `null` (the production path) |
| Tier split | a cache sweep removes cached rows and leaves preferences intact; `pref:locale` survives the migration |

**Baseline to hold:** 367 passing / **29 skipped**. The 29 are Linux-gated goldens; the skip count is how a broken golden gets noticed locally and must not change.

**Unverifiable in Dart tests**, said rather than implied: real `path_provider` path resolution (D1's accepted consequence), and web runtime behaviour. The latter must be confirmed by loading the web build in a browser once D-B lands — the one check that would have caught F4 at any point in the last four epics.

---

## 6. Non-goals

- Restructuring the provider graph or splitting `providers.dart`.
- Adopting `riverpod_generator` (ARCHITECTURE §6 amendment stands).
- Reworking the `authService → dio → authState → sessionManager` cycle. It works, it is documented in place, and a verification epic is not where it changes.
- **Building** the forward-flagged tables in §4 D-F. Their contracts are 🔒 blocked, so their shapes would be guesses; each lands with its feature against the agreed tiers.
- A non-Drift audit fallback for browsers lacking the wasm/OPFS features Drift needs. D-B makes audit durable on web wherever Drift can open at all; `WasmDatabaseResult.missingFeatures` reports the degraded cases and handling them is its own task. (Stated this way deliberately: "make audit durable on web" is *not* a non-goal — D-B does exactly that.)

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| The boot test passes while proving little (F2's trap). | The database assertion is a *query*, not a resolve. The weak half is labelled weak in code, so no future reader mistakes it for coverage. |
| Bundled wasm assets go stale against a future `drift` upgrade. | The existence test catches deletion, not staleness — so the drift version is recorded beside the assets, giving an upgrade an obvious checkpoint. |
| `bootstrap()`'s guards hide a real regression. | D4: every failure is recorded, and the test asserts the recording, not merely completion. |
| The tier split breaks the P0.5 locale preference. | A migration test asserts `pref:locale` survives, and a sweep test asserts preferences are not evictable. |
| The forward-flagged table list rots as PRDs change. | It is a pointer to each PRD's requirement, not a schema. If a requirement moves, the PRD stays the source of truth. |
| F8 stays unfixed because P0.14 is only marked VERIFY. | It is recorded here as a **required** P0.14 fix with the PRD line it violates, so a "verify" pass cannot close over it. |
