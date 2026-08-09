# Task Breakdown — ACSL Carpenter Campaign Management (Flutter)

> **Current execution backlog:** Use [`docs/ways-of-work/plan/PRIORITIZED_TASK_BREAKDOWN.md`](docs/ways-of-work/plan/PRIORITIZED_TASK_BREAKDOWN.md) for the priority-ordered remaining work derived from all 32 feature PRDs. This file remains the scaffold/phase history and original task map.

**Companion to:** [`ARCHITECTURE_Flutter.md`](ARCHITECTURE_Flutter.md)
**Basis:** PRD (Draft) + UI/UX Guideline v1.0
**Convention:** `T-<phase>.<epic>.<seq>`. Each task lists → PRD FR / design screen ID, dependencies, and a done-when line. Estimates are relative points (S=1, M=3, L=5, XL=8) for planning only; recalibrate after engineering sizing.

**Legend:** 🔒 = blocked by an external dependency (API/infra/legal). ⭐ = reusable across surfaces (build once, early). ✅ = scaffolded in the repo.

> **Implemented so far** (verified: analyze clean, `flutter test` 33/33, `flutter build web` OK, runs end-to-end vs the mock server):
> - **P0 foundation** — config, BMD tokens→theme, typed status vocabulary + `StatusChip`, `BmdButton`, virtualized `BmdDataTable`, responsive adaptive shell, `Result`/`Failure`, Dio client + auth interceptor, Drift offline DB, RBAC + guarded GoRouter, Riverpod DI, en/bn l10n.
> - **Offline `SyncEngine`** (T-2.1.1–2, 2.1.4–5) — backoff + platform-isolated evidence store + deterministic test harness. Background upload via `workmanager` (T-2.1.3) is **not implemented**: the dependency is declared in `pubspec.yaml` but nothing in `lib/` imports it.
> - **Field (P2)** — carpenter search (M-02), camera capture (M-03), offline queue (M-04).
> - **CRM (P3)** — verification case (C-02).
> - **Campaign admin (P1)** — list (W-02), wizard (W-03), approval (W-04), detail+sessions (W-05), registration (W-06), bulk import (W-07).
> - **Test/demo infra** — E2E build mode, Maestro flows, and a Dart `shelf` mock server (`tool/mock_server/`).
>
> **Not yet built:** W-01 dashboard, C-01 CRM queue, A-02 analytics, M-01 session readiness, A-01/A-03/AD-01. See per-module status in [`lib/features/README.md`](lib/features/README.md).

---

## Phase P0 — Foundation
*Exit: running app shell (web + mobile), component gallery, golden baselines, CI green.*

### Epic P0.1 — Project & tooling ⭐
| ID | Task | Est | Deps | Status (2026-07-30) |
|----|------|-----|------|---------------------|
| T-0.1.1 | `flutter create` with web + android platforms; adopt scaffold in this repo | S | — | ✅ web + android; runs on Chrome and Android emulator |
| T-0.1.2 | Configure flavors (dev/stg/prod) + `--dart-define` env (API base, media host) | M | 0.1.1 | ✅ Gradle flavors with distinct app IDs + `tool/scripts/run.ps1` |
| T-0.1.3 | `analysis_options.yaml` (strict lints), format + import-order rules | S | 0.1.1 | ✅ `analyze --fatal-infos` exits 0; `dart format --set-exit-if-changed` and `flutter analyze` both run in CI's `gate` job on every PR |
| T-0.1.4 | CI pipeline: analyze → test → build web + apk; artifact upload | M | 0.1.3 | ✅ `.github/workflows/ci.yml` `gate` job runs on every PR and is green (format → gen-l10n → codegen → analyze → test → build web → build apk-dev). There is no `e2e` job — Maestro/emulator E2E (Task 8) and a nightly suite (Task 9) were both cancelled, not deferred. **Correction (2026-08-07):** branch protection **is** enabled on `main`, with `gate` marked as a required status check and `strict: true` (up-to-date-before-merge enforcement); the earlier note in this row claiming the opposite was wrong. **Correction (2026-08-07, P0.5):** the E2E job cancellation is **reversed**. P0.5 adds an `e2e` job that boots an Android emulator, installs the dev debug APK and runs the `android`-tagged Maestro flows; a green `e2e` is a hard exit criterion for that epic. The nightly suite remains cancelled. *Implementation note:* the job is a 5-way **matrix** — one APK per `--dart-define` set, with flows selected by file path — because `ROLE`/`QUALITY`/`SEED`/`LOCALE` are compile-time constants that Maestro's runtime `launchApp: arguments:` could never reach. See TESTING_MAESTRO.md §7.1. |
| T-0.1.5 | Codegen wiring (`build_runner`, freezed, riverpod_generator, drift, l10n) | M | 0.1.1 | ✅ freezed + json_serializable + drift + gen-l10n. Riverpod codegen dropped — see ARCHITECTURE §6 amendment |

### Epic P0.2 — Design system & tokens ⭐
| ID | Task | Est | Deps | Design | Status |
|----|------|-----|------|--------|--------|
| T-0.2.1 | BMD tokens in Dart (color, space, radius, elevation, type) | M | 0.1.5 | §4 | ✅ |
| T-0.2.2 | `bmdTheme()` → Material 3 `ThemeData` for light + dark | M | 0.2.1 | §4 | ✅ |
| T-0.2.3 | Typed status vocabulary enums (campaign/registration/attendance/import/integrity) + labels | M | 0.2.1 | Appendix B | ✅ |
| T-0.2.4 | `StatusChip` single renderer (icon + label, never color-only) | M | 0.2.3 | §5.4 | ✅ |
| T-0.2.5 | `BmdButton` variants (primary/tonal/outlined/text/danger/icon) + one-primary assertion | M | 0.2.2 | §5.1 | ✅ |
| T-0.2.6 | `BmdField` / `BmdSearchField` (outlined, persistent label, inline validation) | M | 0.2.2 | §5.2 | ✅ |
| T-0.2.7 | `BmdDataTable` ⭐ — virtualized, sticky header + identity column, 44–48px rows, safe bulk-select | L | 0.2.2 | §5.5, §11 | ✅ |
| T-0.2.8 | KPI card, exception card, side sheet, bottom sheet, dialog primitives | L | 0.2.2 | §5.5, §5.6 | ✅ |
| T-0.2.9 | Component gallery route + golden test baselines | M | 0.2.4–0.2.8 | QA checklist | ✅ |

> **P0.2 complete** (2026-08-05). T-0.2.7 ships priority-flex columns rather
> than a frozen identity column: freezing splits each row into two widget
> subtrees, so a screen reader reads column-major, which would fail the
> T-3.4.1/T-3.4.2 accessibility gates. Overflow columns reach the user through
> the row-detail side sheet (§5.3). A mid-epic ruling changed what "overflow"
> covers: only `identity` columns are guaranteed to render (below their own
> `minWidth` if there is truly no room left); `primary` columns now drop into
> the row detail, last-declared first, once the viewport cannot fit them
> alongside identity, rather than always staying on screen. Goldens run on
> Linux only; regenerate via the `goldens` workflow (`gh workflow run
> goldens`), not locally.

### Epic P0.3 — Core services ⭐
| ID | Task | Est | Deps | Status (2026-08-06) |
|----|------|-----|------|---------------------|
| T-0.3.1 | `Result`/`Failure` types + error taxonomy | S | 0.1.5 | ✅ pure Dart |
| T-0.3.2 | Dio client + interceptors (auth, refresh, correlation-ID, retry, error→Failure) | L | 0.3.1 | ✅ 🔒 API base; `AuthInterceptor.refreshToken` delegates to `SessionManager.refresh()` (P0.4 closed this — it was a throwing seam through Task 8), and the 401 replay runs through an interceptor-free client (`buildReplayDio`) |
| T-0.3.3 | Drift DB (schema v1: sync_task, attendance_draft, cached_reference) + migrations | L | 0.1.5 | ✅ offline core; schema v2 (`audit_events`) added for T-0.3.6 |
| T-0.3.4 | Secure storage wrapper (tokens, encryption keys) | S | 0.1.5 | ✅ `SecureStore`/`FlutterSecureStore` + frozen `SecureStoreKeys` registry |
| T-0.3.5 | Responsive breakpoint system + adaptive scaffold (drawer/rail/bottom-nav) | M | 0.2.2 | ✅ §11 |
| T-0.3.6 | Client audit event emitter (correlation-ID, buffered) | M | 0.3.2 | ✅ §12 |

> **P0.3 complete** (2026-08-06). T-0.3.2 ships correlation-ID and retry
> interceptors; the retry gate is an explicit idempotency key rather than HTTP
> method semantics, so no unsafe method is replayed without server-side dedupe.
> T-0.3.6's buffer is Drift schema v2 (`audit_events`) drained by a dedicated
> `AuditFlusher` — deliberately not the `SyncEngine`, whose give-up-after-8
> rule would silently discard compliance records. The flusher retries on a
> fixed interval (plus an immediate flush on reconnect), not exponential
> backoff, and sets a row aside only after repeated **permanent** rejections —
> a network failure never counts toward that threshold. Sensitive views go
> through `AuditSink.revealAudited`, which takes the reveal as a callback so it
> cannot fail open. Feature-level audit emission stays with the owning tasks
> (T-1.4.2, T-1.6.3, T-3.1.4); this epic emits only `evidenceKeyRotated`.
> `AuthInterceptor.refreshToken` delegates to `SessionManager.refresh()` as of
> P0.4's close (it was a throwing seam through Task 8), and the 401 replay now
> goes through an interceptor-free client.

### Epic P0.4 — Auth, RBAC & routing ⭐
| ID | Task | Est | Deps | Notes |
|----|------|-----|------|-------|
| T-0.4.1 | Session model + token lifecycle (login/refresh/logout) | M | 0.3.2, 0.3.4 | ✅ 🔒 format pending; `SessionManager` owns login/restore/refresh/signOut with single-flight refresh and a generation guard against post-sign-out resurrection |
| T-0.4.2 | RBAC scope model (role + org/territory) + permission checks | M | 0.4.1 | ✅ §12; `AccessScope`/`Permission` + `PermissionGate.hidden`/`.disabled` |
| T-0.4.3 | GoRouter config + redirect guards (role/scope before build) | L | 0.4.2, 0.3.5 | ✅ §7; one `routeTable` read by both the router and `RouteGuards`, keyed on `GoRouterState.fullPath` |
| T-0.4.4 | App shell wiring (nav map, breadcrumb, notifications slot) | M | 0.4.3 | ✅ §3.3; `AppShell` + `nav_destinations.dart`, permission-filtered |

> **P0.4 complete** (2026-08-07). T-0.4.1's lifecycle lives in a dedicated
> `SessionManager` with single-flight refresh: a 401-triggered refresh racing a
> proactive one would, under server-side rotation, leave the loser presenting a
> consumed token and sign the user out mid-task. `AuthState` is a sealed
> tri-state rather than `Session?`, because a nullable session conflates
> signed-out with not-yet-known and a mobile cold start would flash the login
> screen. Tokens: the refresh token persists to Keystore/Keychain on mobile and
> **not at all on web**, where `SecureStore` is `localStorage` rather than
> hardware-backed; the access token is never persisted anywhere. Changing the
> web behaviour needs a server-side httpOnly cookie, not a different client
> store. T-0.4.3 replaces prefix matching with one `routeTable` that both the
> router and the guard read, keyed on `GoRouterState.fullPath` so a
> parameterised template matches exactly; an undeclared path fails closed, and
> a test asserts the registered set equals the table with dev routes both on
> and off. T-0.4.2 adds `PermissionGate` (hidden for whole surfaces, disabled
> with a screen-reader-reachable reason for actions on a visible record);
> `AccessScope.inTerritory` remains modelled and unconsumed until P1/P3's
> territory-filtered queries. T-0.4.4's nav was previously inert — no caller
> passed `onDestinationSelected` — and its destinations were unfiltered, so a
> field user was offered four surfaces the guard then rejected. The auth wire
> format stays 🔒 pending the contract; `DioAuthService` and `scope_claims.dart`
> are the only places it lands.
>
> Expiry is checked on the *request* path, not the render path:
> `SessionManager.accessTokenForRequest()` proactively refreshes inside a 60s
> skew and signs out if refresh fails, so an idle signed-in user with an
> expired token is redirected on their next request rather than instantly —
> `authStateProvider` and `RouteGuards.evaluate` do not re-check
> `Session.expiresAt` on every render. That is a deliberate choice, not the
> gap it looks like at a glance: this epic's temporary bridge (Tasks 5–8) had
> dropped the old `RouteGuards`' `!session.isExpired` check, and closing this
> epic means confirming that omission is intentional rather than silently
> keeping it. `AuthInterceptor.refreshToken` now delegates to
> `SessionManager.refresh()` and `onAuthLost` to `SessionManager.signOut()`
> (both were seams/stubs through Task 8), so a 401 actually renews the session
> through the same single-flight path a proactive refresh uses. `main()`
> exchanges any persisted refresh token via `SessionManager.restore()` before
> the first frame, and — under E2E — awaits a real `signIn()` against
> `FakeAuthService` before `runApp`, so Maestro drives the same
> `SessionManager` path production does instead of starting pre-authenticated
> by construction. Closes T-0.4.1 through T-0.4.4.

### Epic P0.5 — Localization ⭐
| ID | Task | Est | Deps | Notes |
|----|------|-----|------|-------|
| T-0.5.1 | `flutter_localizations` + ARB scaffolding (en, bn) + Noto Sans Bengali fallback | M | 0.1.5 | ✅ ARB + gen-l10n **and now actually applied**. The delegates were registered but **commented out** at `app.dart:26-27` from P0.2 until P0.5, so the generated localizations were never used — a Bengali user got English everywhere. Fonts landed in P0.2 (2026-08-05); the delegates, a per-device locale preference and a language picker landed here. |
| T-0.5.2 | Versioned consent/purpose-notice content model (bn/en parity + version record) | M | 0.5.1 | ✅ **client-side model complete**, 🔒 **content still pending Legal §10.3**. `ConsentNotice`/`ConsentRecord` + a length-prefixed SHA-256 content hash, a bundled bilingual floor, Drift schema v3 (`consent_notices` + four columns on `attendance_drafts`), and the record written with every capture and onto the sync payload. Both bundled bodies say `PLACEHOLDER` in-text; the server-override seam (`refreshInBackground`) is deliberately **unwired** pending the contract. |

> **P0.5 complete** (2026-08-09). The headline defect: `AppL10n.localizationsDelegates`
> and `supportedLocales` sat **commented out** from P0.2 until now, so three epics
> shipped with localization inert and nothing noticed — because no test rendered a
> non-English string and no screen consumed `AppL10n`. Closing it needed a test that
> pumps the real `AcslCampaignApp` rather than a self-built `MaterialApp`; the
> first attempt asserted the chain in a harness that registered the delegates
> itself, and so passed before the fix.
>
> Two related traps were removed. The five `l10nKey` getters returned runtime
> strings (`'campaignStatus_$name'`) that could never resolve against gen-l10n's
> named getters, and advertised keys for three families the ARB never contained;
> they are replaced by exhaustive `label(AppL10n)` extensions with no `default`,
> so a new status value is a **compile error** until it has a label. And every
> status chip rendered `<enum>.name`, so users were shown raw camelCase
> identifiers (`pendingApproval`); all five call sites now render localized
> labels, which is also what made the Bengali E2E assertion possible at all.
>
> **Locale is per device, not per user** (a shared field phone in a
> Bengali-speaking territory stays Bengali regardless of who signs in), persisted
> in `cached_reference` under a reserved `pref:` key. Precedence is stored choice
> → `LOCALE` dart-define → system. An **unsupported** device locale resolves to
> English via an explicit `localeListResolutionCallback`: codegen emits
> `supportedLocales` alphabetically as `[bn, en]`, and Flutter falls back to
> `.first`, so a French phone would otherwise have got Bengali by accident of
> alphabetization.
>
> **Consent fails closed; locale degrades.** No notice means no capture — the one
> place in this epic where blocking the user is correct. Every locale fault
> (corrupt row, unsupported code, unreadable store) falls back and continues. The
> consent record stores a **hash over a length-prefixed pre-image**, so it proves
> the wording shown rather than pointing at a version number; the format is a
> contract, pinned in a test against a digest derived independently rather than
> from the code under test. Verified end to end on a device: the stored hash
> recomputed byte-for-byte from the bundled Bengali asset.
>
> **Still open, tracked here rather than only in the ledger:** the **24 Bengali
> values added by this epic are unreviewed machine drafts**, each carrying
> `UNREVIEWED` `@`-metadata and guarded by a parity test — they need native
> review before pilot. A published notice version must be **immutable**, which is
> a requirement on Legal/backend that the client cannot enforce. `~150`
> screen-specific strings remain hardcoded English (T-4.2). Follow-ups recorded
> by the final review: `BmdIconButton` and `BmdField` still carry bare
> `Semantics(identifier:)` nodes without `enabled`, so the vacuous-assertion
> hazard `BmdButton` fixed survives for those families; `PermissionGate.disabled`
> wraps its child in `ExcludeSemantics`, which would erase a `BmdButton`
> identifier if ever combined (no call site does today); and the notice screen's
> language toggle is a dead end when one language fails to resolve.
>
> **T-0.1.4's E2E reversal is real:** the `e2e` job exists and is green across all
> five matrix configs — the Maestro suite's first passing run ever. Getting there
> exposed that every per-flow `launchApp: arguments:` had been **inert since the
> flows were written**, because `ROLE`/`QUALITY`/`SEED`/`LOCALE` are compile-time
> constants that Android intent extras cannot reach. Hence one APK per
> configuration. Closes T-0.5.1 and the client half of T-0.5.2.

### Epic P0.6 — Riverpod DI baseline ⭐
| ID | Task | Est | Deps |
|----|------|-----|------|
| T-0.6.1 | Provider graph for core services (client, db, auth, storage, audit) + test overrides | M | 0.3.*, 0.4.1 |

---

## Phase P1 — Campaign Administration (Web)
*Exit: UAT-ready admin surface. → PRD FR-001..008, design W-02..W-07.*

### Epic P1.1 — Domain & data (campaign, registration, import)
| ID | Task | Est | → PRD | Notes |
|----|------|-----|-------|-------|
| T-1.1.1 | Campaign entity, lifecycle status machine, value objects | M | FR-001/002 | pure Dart, unit-tested |
| T-1.1.2 | Campaign repo interface + Dio impl + DTO mappers | M | FR-001 | 🔒 API |
| T-1.1.3 | Registration + CampaignParticipant entities + repo | M | FR-003 | no shadow master |
| T-1.1.4 | Import job entity + lifecycle + repo (async job polling) | M | FR-004 | — |

### Epic P1.2 — Create/Edit Campaign Wizard (W-03)
| ID | Task | Est | → | Done when |
|----|------|-----|---|-----------|
| T-1.2.1 | 5-step stepper shell + persistent draft save | L | FR-002 | draft survives reload |
| T-1.2.2 | Step 1 Basics/objective + Step 2 Audience/territory forms | L | FR-001/003 | inline validation |
| T-1.2.3 | Step 3 Sessions/venue/geofence (conflict + tolerance guidance) | L | FR-001 | schedule-conflict state |
| T-1.2.4 | Step 4 Targets/budget/approver + Step 5 read-only review | M | FR-006 | submit disabled until valid |
| T-1.2.5 | Wizard states: unsaved/validation-error/conflict/missing-approver/submitted/returned | M | — | all states covered |

### Epic P1.3 — Campaign List & Dashboard (W-02, W-01)
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-1.3.1 | Campaign list via `BmdDataTable` (sticky filter bar, active-filter chips) | M | FR-001 | default sort: exception-first |
| T-1.3.2 | Row actions (view/edit draft/submit/duplicate/cancel) under permission | M | FR-007 | — |
| T-1.3.3 | Campaign dashboard: exception cards → funnel → contribution → table | L | FR-014 | KPI definition + refresh visible |
| T-1.3.4 | Mobile read-only card variant of list + dashboard | M | — | §8.1/8.2 mobile |

### Epic P1.4 — Approval (W-04)
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-1.4.1 | Two-column approval screen (plan + decision panel) | M | FR-007 | — |
| T-1.4.2 | Approve/return/reject actions; mandatory reason; SoD guard; ack-warnings gate | M | FR-007 | approve disabled until ack |
| T-1.4.3 | Change-request diff highlighting | M | — | §8.4 |

### Epic P1.5 — Registration Workspace (W-06)
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-1.5.1 | Sales Eco search panel + results (photo, masked phone, territory, freshness) | L | FR-003 | 🔒 Sales Eco API |
| T-1.5.2 | Registration basket + eligibility/duplicate warnings | M | FR-005 | — |
| T-1.5.3 | "Request new profile" → Pending profile sync (no local master) | M | — | §9.4 |

### Epic P1.6 — Bulk Import (W-07)
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-1.6.1 | Template download + file upload (file_selector, csv) | M | FR-004 | — |
| T-1.6.2 | Dry-run summary + row-level validation table (valid/warning/dup/needs-profile/error) | L | FR-005 | per-row outcome, no generic fail |
| T-1.6.3 | Idempotent commit of valid rows + masked result download | M | FR-004 | replay-safe |
| T-1.6.4 | Job lifecycle states (uploading→…→partial/completed/failed) | M | — | §8.7 |

### Epic P1.7 — Campaign Detail & Sessions (W-05)
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-1.7.1 | Detail header (lifecycle status + primary next action) + tabbed body | M | FR-008 | Overview/Sessions/Reg/Attendance/Analytics/Audit |
| T-1.7.2 | Session cards + start/close/pause actions under permission | M | FR-008 | — |
| T-1.7.3 | Session readiness panel (camera/version/network/assignment/venue/geofence) | M | FR-008 | gates activation |

---

## Phase P2 — Field Capture (Mobile, offline-first)
*Exit: field usability test passed under weak network + bright light. → PRD FR-009, design M-01..M-04.*

### Epic P2.1 — Sync engine ⭐ (highest risk)
| ID | Task | Est | → | Done when |
|----|------|-----|---|-----------|
| T-2.1.1 | Sync task model + durable Drift queue + idempotency key generation | L | — | survives process kill |
| T-2.1.2 | Connectivity-aware scheduler + exponential backoff + retry/pause | L | — | offline→online drains queue |
| T-2.1.3 | Background upload (workmanager) + progress + confirm | L | 2.1.1 | uploads resume after restart |
| T-2.1.4 | Status polling/SSE: pendingSync→matchProcessing→crmReview→approved/rejected/returned | M | 2.1.3 | statuses reflect server |
| T-2.1.5 | **Offline integration test harness** ⭐ (failure injection matrix §9.4) | L | 2.1.1–2.1.4 | all error-recovery rows pass |

### Epic P2.2 — Media & capture
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-2.2.1 | Camera pipeline (camera-only, gallery disabled) | M | FR-009 | §8.10 |
| T-2.2.2 | On-device quality checks (ML Kit: face count/blur/light/orientation) | L | 2.2.1 | no score shown to user |
| T-2.2.3 | Local AES encryption of evidence (Keystore key) + media ref persistence | M | 2.2.1, 0.3.4 | encrypted at rest |
| T-2.2.4 | Pre-signed upload flow (short-lived URL) | M | 2.1.3 | 🔒 media API |

### Epic P2.3 — Field screens
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-2.3.1 | Session readiness/overview mobile (M-01) checklist + Start gate | M | FR-008 | blocking vs optional checks |
| T-2.3.2 | Carpenter search & selection (M-02) + second identity cue | M | FR-003 | no full NID/phone |
| T-2.3.3 | Purpose notice + camera capture flow (M-03) 5 steps | L | FR-009 | language-selectable notice |
| T-2.3.4 | Offline queue & capture status (M-04) — capture≠upload copy | M | — | never prompt recapture on delay |
| T-2.3.5 | Mobile field shell (≤4 nav items, offline banner, session-focused home) | M | — | §3.2 |

---

## Phase P3 — CRM Verification & Analytics (Web)
*Exit: metric definitions + accessibility sign-off. → PRD FR-010..014, design C-01, C-02, A-01, A-02, A-03.*

### Epic P3.1 — CRM verification
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-3.1.1 | Verification domain (case, decision, machine-result-as-separate-object) + repo | M | FR-010/011 | — |
| T-3.1.2 | Verification queue (C-01): SLA/risk sort, saved views, bulk-assign (not bulk-approve) | L | FR-010 | default sort = SLA/risk |
| T-3.1.3 | Verification case (C-02): 3-zone evidence/context/decision, same crop+scale, zoom | XL | FR-011 | machine vs human separate |
| T-3.1.4 | Decision actions (approve/reject/return/escalate) + mandatory reason + downstream-effect confirm | M | FR-011 | — |
| T-3.1.5 | Optimistic locking / concurrent-decision handling | M | — | §9.4 |
| T-3.1.6 | Sensitive-image controls: blur-until-open, audit-on-view, signed URL, no download | M | — | §10.2 |

### Epic P3.2 — Carpenter 360 (A-01)
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-3.2.1 | 360 header + tabs (Overview/Campaigns/Attendance/Orders/Sites/Rewards/Audit) | L | FR-013 | 🔒 orders API |
| T-3.2.2 | Canonical-pieces rendering; all-orders vs campaign-attributed separation | M | — | one order, one count |

### Epic P3.3 — Analytics & integrity (A-02, A-03)
| ID | Task | Est | → | Notes |
|----|------|-----|---|-------|
| T-3.3.1 | Analytics dashboard: funnel, verification trend, mix, attribution, ROI panels (fl_chart) | XL | FR-014 | definitions + freshness visible |
| T-3.3.2 | Drill-down (national→campaign→territory→session→carpenter) under permission | L | — | §6.3 |
| T-3.3.3 | Integrity & operations dashboard (exception cards/queues, explainable signals) | L | — | no opaque fraud score |

### Epic P3.4 — Accessibility gate ⭐
| ID | Task | Est | Notes |
|----|------|-----|-------|
| T-3.4.1 | Semantics wrappers + keyboard/focus + shortcuts across CRM/admin | L | release gate |
| T-3.4.2 | Automated a11y checks in CI + manual screen-reader audit pass | M | WCAG 2.2 AA |

---

## Phase P4 — Hardening & Pilot
*Exit: pilot report; design QA checklist green.*

| ID | Task | Est | → |
|----|------|-----|---|
| T-4.1 | Configuration & audit screens (AD-01): versioned config, effective dating, audit table | L | FR-015 |
| T-4.2 | Complete every screen's empty/loading/partial/failed/permission-denied/delayed states | L | QA checklist |
| T-4.3 | Retention/policy metadata UX for authorized admins | M | §10.2 |
| T-4.4 | Full golden + integration coverage on 7 prototype paths (design §13.1) | L | — |
| T-4.5 | Field validation (weak network, bright light, real Android) + CRM real-image test | L | §14.1 |
| T-4.6 | Performance pass (deferred web modules, list virtualization, image caching) | M | §11 |
| T-4.7 | Security/legal review: notice, NID masking, media access, retention, audit cues | M | 🔒 §14.1 |

---

## Later — AI Face-Match (feasibility-gated)
| ID | Task | Notes |
|----|------|-------|
| T-L.1 | Implement automated verification behind the existing verification adapter | no client rearchitecture; advisory result slots already present |
| T-L.2 | Confidence band + human-override UX; bias/consent governance | separately governed |

---

## Cross-cutting external dependencies (🔒 — resolve before dependent tasks)
| Dep | Blocks | Owner |
|-----|--------|-------|
| Sales Eco carpenter-master API contract & availability | T-1.1.2, T-1.5.1, T-3.2.1 | Data/Integration |
| Auth/RBAC service contract | T-0.4.1 | Engineering |
| Media store: signed-URL + encryption + retention contract | T-2.2.4, T-3.1.6 | Engineering |
| Server idempotency + audit contracts | T-1.6.3, T-2.1.1, T-0.3.6 | Engineering |
| Orders/attribution facts API | T-3.2.1, T-3.3.1 | Data/Integration |
| Legal: consent-notice versioning + retention policy | T-0.5.2, T-4.7 | Security/Legal |

## Critical path
`P0.1 → P0.2 (esp. BmdDataTable) → P0.3/0.4 → P1.1 → {P1 admin}` ‖ `P2.1 sync engine (start as early as P0 permits) → P2.2/2.3` → `P3.1 CRM case → P3.4 a11y gate` → `P4`.
The offline **sync engine (P2.1)** and **BmdDataTable (P0.2.7)** are the two long-lead, highest-reuse items — start both before their consuming features.
