# Campaign Management Service — foundation and campaign vertical slice

**Status:** approved for planning, 2026-08-10.
**Scope:** sub-project 1 of 8 (see §2). Everything else is named here only to be excluded.
**Overrides:** PRD governing decision #2 and `ARCHITECTURE_Flutter.md` §1/§10 on carpenter
identity — see **D1**. Read that before "fixing" the data model back.

---

## 1. Why this exists

The Flutter app is complete enough to run five end-to-end journeys, and has no backend.
`ARCHITECTURE_Flutter.md` §3 already names the missing piece — a **Campaign Management
Service** owning a reference/hybrid DB, media store, verification adapter, import jobs,
audit and auth — and §3 states the principle it exists to enforce:

> The Flutter clients are **thin over a well-defined API**. All authority (source of
> truth, verification decisions, attribution counting, retention) lives server-side.

So this is not a new architectural direction. It is the unbuilt half of the documented one.

### What already exists, and what it actually specifies

`tool/mock_server/bin/server.dart` implements **25 routes**. Client code references 23
paths across five repositories plus auth, audit, sync and consent. The green e2e matrix
exercises them. That is a real contract with real consumers — and a much better starting
point than a blank page.

It is also a **stub, not a specification**, in ways that matter to every later slice:

| Gap | Evidence | Consequence |
|---|---|---|
| Pagination and filtering unimplemented | `GET /campaigns` ignores `q`, `status`, `page`, `pageSize`; returns everything with `total = items.length` | the client *sends* all four; both sides believe a contract neither honours |
| No status machine | `store.setStatus(id, …)` is unconditional | a `DRAFT` can be approved without being submitted |
| No SoD gate | no owner/approver comparison anywhere | W-04's core governance control is absent |
| No org/territory scope check | no auth middleware on any campaign route | scope isolation is untested end to end |
| No optimistic concurrency | `PUT /campaigns/<id>` has no version | "another reviewer completed this" is unimplementable client-side |
| Ad-hoc errors | `{'error': 'boom'}` | there is no error envelope to map to typed `Failure`s |
| Inconsistent wire naming | statuses are `PENDING_APPROVAL`; decisions send Dart enum names (`returnForCorrection`) | two conventions inside one feature |
| `/consent/notices` implemented nowhere | absent from the mock; referenced by `NoticeRepository.fetchLatest` | latent 404 — survives only because P0.5 left `refreshInBackground` deliberately unwired |

### One client defect this slice must close

`lib/data/campaign/campaign_dto.dart:62` resolves an unrecognised status with
`orElse: () => CampaignStatus.draft`. A `COMPLETED` or `CANCELLED` campaign arriving with
an unexpected value renders as an **editable draft** — silent misclassification in the most
consequential field on the record, in the direction that grants more permission rather
than less.

---

## 2. Decomposition: eight sub-projects

32 feature PRDs across 9 epics is not one project. Each row below gets its own
spec → plan → implementation cycle.

| # | Sub-project | Owns | Depends on |
|---|---|---|---|
| **1** | **Service foundation + campaign slice** — *this spec* | Postgres, migrations, auth/RBAC, org scope, error envelope, idempotency, audit write path, shared contracts package, campaign CRUD and lifecycle | — |
| 2 | Identity and participants | carpenters (local master, per D1), profile requests, registrations, bulk import and dry-run jobs | 1 |
| 3 | Campaign lifecycle depth | session operations, changed-field diff endpoint, correction history | 1 |
| 4 | Attendance and evidence | idempotent submission, media presign/encryption/retention, consent records, attempt lineage | 2, 3 |
| 5 | Verification | queue prioritisation, evidence access with audit-on-view, decision/return/recapture, optimistic locking | 4 |
| 6 | Analytics and attribution | funnel, canonical contribution, ROI, dashboards | 4, 5, 8 |
| 7 | Config, audit, integrity, **staff access administration** | versioned config, approval/activation/rollback, audit search and retention, integrity signals, staff user/role/territory administration | 1 |
| 8 | BMD Sales integration | anti-corruption layer: carpenter reconciliation, order facts | 2 |

Sub-project 7 gained *staff access administration* from **D3**. The 32 PRDs never
accounted for it because they assumed Sales Eco supplied it.

---

## 3. Decisions

### D1 — We own carpenter master data locally, and reconcile with BMD Sales later

**This overrides a governing product decision.** PRD decision #2 states the module
"does not create a local shadow master", and `ARCHITECTURE_Flutter.md` §10 requires
Sales Eco master data be "read/link only". Recorded as a deliberate, dated override on
2026-08-10, not an oversight.

Rationale accepted: Sales Eco API readiness is an unknown (PRD R3), and blocking the
entire backend on an external contract with no date is worse than owning the data and
reconciling later.

Four consequences become **required** design work in sub-projects 2 and 8, not optional
hardening:

1. **Conflict resolution** — the same human existing in both systems, and which side wins
   per field.
2. **Reconciliation** — matching on NID/phone with a confidence threshold, plus a
   human-adjudication queue for ambiguous matches.
3. **Duplicate suppression for counting** — PRD decision #5 ("one order, one count")
   assumes one canonical identity. A carpenter present twice locally can double-count
   verified contribution, which is a reporting-integrity defect, not a data-tidiness one.
4. **`Pending profile sync` changes meaning** — it currently means "awaiting an
   authoritative Sales Eco identity". With a local master it must mean something else, and
   analytics filter on it.

### D2 — Dart + Postgres, on `shelf`/`shelf_router`, no ORM, no codegen

Dart uniquely allows the service and the app to depend on **one shared contracts package**,
which turns PRD decision #6 — a controlled vocabulary identical across web, mobile,
notifications and analytics — from a discipline into a compile-time property.

`shelf` over `dart_frog`: the mock server is already `shelf_router`, so its handlers port
almost directly and become the first draft rather than a discard; and `dart_frog` adds a
code generator to a repo whose README already warns "this order matters" about
`gen-l10n` → `build_runner` → `analyze`. This codebase hand-writes its Riverpod providers
specifically to avoid codegen. No ORM for the same reason: SQL is the thing being reasoned
about.

### D3 — We own staff authentication permanently

No federation with BMD SSO. Our service is the identity provider for campaign staff
(field officers, CRM reviewers, admins — not carpenters).

Accepted cost, stated for the record: staff carry two logins within one ecosystem, and
role/territory changes must be maintained in two places, which tends to drift.

Consequence: **staff access administration is now our feature** — user creation, role and
territory assignment, credential reset, and offboarding. Offboarding matters most, because
the sensitive-access-monitoring PRDs assume revocation works. Filed into sub-project 7;
this slice builds only what login requires.

### D4 — `server/` and `packages/campaign_contracts/` are siblings in this repo

```
Camp_man/
├── lib/                          Flutter app (unchanged except DTO imports)
├── packages/campaign_contracts/  shared wire vocabulary — pure Dart, no Flutter
├── server/
│   ├── bin/server.dart
│   ├── lib/{api,domain,data,auth,infra}/
│   ├── migrations/               numbered, forward-only SQL
│   └── test/
└── tool/mock_server/             retained until parity, then deleted (see §9)
```

Path dependencies, no melos. A contract change lands in **one commit** touching the DTO,
the server and the app together — which is the entire reason for a shared package. A
separate repo would make every contract change two PRs and a version bump, reintroducing
the drift the package exists to prevent.

Known cost: root `analysis_options.yaml` needs excludes so `flutter analyze` does not walk
`server/`, and CI gains a Dart-server job.

### D5 — The shared package holds the wire, not the domain

**Shared:** status vocabulary (enums plus `wireValue`), wire DTOs, error codes.
**Not shared:** domain entities, validation, the status machine.

The boundary is load-bearing. The server's campaign carries org scope, audit columns, a
`version`, and an owner/approver distinction; the app's `Campaign` carries
`verifiedAttendance` and presentation concerns. Sharing entities would drag each side's
incidental needs into the other. Sharing the *wire* prevents drift exactly where it hurts:
the field values crossing the network.

Required refactor. The five status enums and their `wireValue` getters move out of
`lib/domain/common/status.dart` into the package; `StatusTone` stays, because tone is
presentation. `lib/data/campaign/campaign_dto.dart` is deleted and its `toDomain()` becomes
a mapper extension in `lib/data`.

**28 files import that path today** — including `lib/core/design_system/status_chip.dart`,
eight feature screens and two tests. They do not all need to change: the enum *names* are
unchanged, so `lib/domain/common/status.dart` becomes a re-export of the package plus the
retained `StatusTone`, and the blast radius is **one file instead of 28**. Import sites can
be migrated to the package path later, or never; a shim that costs nothing is preferable to
a 28-file diff whose only effect is import lines.

### D6 — Server-side revalidation on submit is mandatory

The authoring PRD requires "domain-level validation independent of Flutter UI **and server
revalidation on submit**". Submit re-runs every rule — mandatory fields, dates and
timezone, overlapping sessions, capacity, ownership, budget reference, approver — and
returns a **field-keyed** error list, because the wizard renders errors inline per field.
A single opaque message would satisfy the endpoint and fail the screen.

### D7 — Out-of-scope resources return 404, not 403

A campaign outside the caller's org or territory scope must not be confirmed to exist.
`403` leaks that an ID is real; `404` does not. Authentication failures remain `401` and
capability failures within scope remain `403`.

---

## 4. Deliverables

| | Deliverable |
|---|---|
| **D-A** | `packages/campaign_contracts` — status vocabulary, wire DTOs, error codes; app refactored onto it |
| **D-B** | Service skeleton: `shelf` router, config, structured logging, health endpoint, `Dockerfile`, `docker-compose` for local Postgres |
| **D-C** | Migration runner (transactional, see §8) and the slice-1 schema |
| **D-D** | Auth: argon2id, JWT issuance with the claims `scope_claims.dart` already parses, refresh rotation with reuse detection |
| **D-E** | Enforcement middleware: authenticate → authorise → scope, in that order |
| **D-F** | Infra middleware: error envelope, idempotency, correlation propagation, audit write path |
| **D-G** | Campaign endpoints: list (paged, filtered), get, create, update, submit, decide — with the status machine and SoD |
| **D-H** | Test-only seeding path, gated so it cannot exist in a production build |
| **D-I** | CI: Dart-server job; `e2e` job runs the real service |

**On phasing.** Nine deliverables is large for one implementation plan, and the honest
reading is that this is two phases, not one: **D-A**–**D-F** (contracts, skeleton,
migrations, auth, enforcement, infra) stand alone and are verifiable by unit and
integration tests, while **D-G**–**D-I** (campaign endpoints, seeding, e2e cut-over) are
what make the foundation falsifiable. Splitting the *plan* that way is expected. Splitting
the *spec* is not, because the second half is the only thing that proves the first half
works — which is the whole argument for a vertical slice over a foundation-only slice.

---

## 5. API conventions

Every later sub-project inherits these, so they are decided once, here.

| Concern | Decision |
|---|---|
| **Error envelope** | `{"error":{"code":"CAMPAIGN_INVALID_TRANSITION","message":…,"details":{…},"traceId":…}}`. `code` is stable and machine-readable; clients map codes to typed `Failure`s and never string-match `message`. |
| **Pagination** | The app's existing `page`/`pageSize` → `{items,total}`. Implemented for real, with a server-side `pageSize` cap. No cursors — nothing needs them. |
| **Filtering** | `q` (free text) and repeatable `status`. Implemented, because the client already sends them and they are silently ignored today. |
| **Idempotency** | `Idempotency-Key` header **required on state-mutating domain POSTs** — create, submit, decide — and *not* on `/auth/*`, where replaying a token response would be a defect rather than a courtesy. Stored per `(user, key)` with a hash of the request body: the same key with a different body is `422 IDEMPOTENCY_KEY_REUSED`, never a silent replay of the wrong response. Successful responses are replayed verbatim. Keys expire after 24h. |
| **Concurrency** | Integer `version` on mutable resources. Mismatch → `409 CONFLICT_STALE_VERSION` carrying the current state. |
| **Wire naming** | `SCREAMING_SNAKE` for all enum-ish values, including decisions: `APPROVE`, `RETURN_FOR_CORRECTION`, `REJECT`. **Breaking change** — client and mock both change. |
| **Unknown enum values** | Parsed to an explicit `unknown` variant that callers must handle. Never a silent default. |
| **Correlation** | The client's existing correlation header is honoured, echoed in the error envelope, and stamped on every audit row. |
| **Timestamps** | UTC ISO-8601 on the wire, `timestamptz` in Postgres. |

---

## 6. Campaign lifecycle and contract

### Status machine — server is the only authority

```
DRAFT ──submit──► PENDING_APPROVAL ──approve──► APPROVED ──► ACTIVE ⇄ PAUSED ──► COMPLETED
  ▲                      │
  │                      ├──returnForCorrection──► RETURNED ──submit──► PENDING_APPROVAL
  └──────────────────────┴──reject──► CANCELLED  (terminal)
```

Submit transitions only from `DRAFT` or `RETURNED`, per the authoring PRD. Any illegal
transition is `409 CAMPAIGN_INVALID_TRANSITION` with the current status in `details`.
`ACTIVE`/`PAUSED`/`COMPLETED` are reachable in the machine but are driven by session
operations in sub-project 3, not by endpoints here.

Return preserves draft data ("return a correctable campaign without deleting draft data");
reject is terminal.

### Three fields the current client cannot send

| Requirement | Source | Contract change | Failure code |
|---|---|---|---|
| Warning acknowledgement before approve | approval PRD: "require explicit acknowledgement before Approve" | `decide` gains `acknowledgedWarnings` | `422 WARNINGS_UNACKNOWLEDGED` |
| Version on both mutating actions | "apply decisions idempotently with optimistic concurrency"; "prevent double submission and concurrent overwrite through version checks" | `submit` and `decide` gain `version` | `409 CONFLICT_STALE_VERSION` |
| Mandatory reason for return/reject | "mandatory configured reason for return/reject" | already sends `reason`; server enforces | `422 DECISION_REASON_REQUIRED` |
| An idempotency key on create/submit/decide | "submit idempotently"; "one Pending approval transition and audit event" on double-tap | call sites pass one — see below | `422 IDEMPOTENCY_KEY_REUSED` |

`decide()` currently sends only `{decision, reason}` and neither call sends a version, so
the app changes in this slice too.

The idempotency change is smaller than it looks: the transport is already built.
`CorrelationIdInterceptor` sets the `Idempotency-Key` header whenever one is supplied
through `RequestOptions.extra`, and `traceOptions(trace, {idempotencyKey})` is the supported
way to supply it — the header name already matches this contract. What is missing is that
`campaign_repository_impl.dart:22` calls `traceOptions(trace)` with no key. So the work is
minting and passing a per-user-action key at the mutation call sites, not building
plumbing. `retry_interceptor.dart` already refuses to retry an unsafe method without one,
which means passing keys also makes campaign mutations retryable for the first time.

### Segregation of duties is configured, not constant

The approval PRD says "under SoD policy". This slice implements `approver ≠ owner` as a
value read from `app_config`, **defaulting to enforced**, so sub-project 7 can version it
and put it behind approval without a rewrite. Hard-coding it would guarantee that rewrite.
The default is enforcement rather than permissiveness because a missing or unreadable
config row must not silently disable a governance control.

### `verifiedAttendance`

Derived from verified attendance records, which do not exist until sub-project 4. Returns
`0` here and is documented in the contract as **derived, never stored**, so no later code
writes to it.

---

## 7. Auth and enforcement

Login issues a short-lived access JWT carrying exactly the claims `scope_claims.dart`
already parses — `roles`, `permissions`, `organizationId`, `territoryIds` — plus a rotating
refresh token. The client's claim parser is therefore the contract; the server conforms to
it rather than inventing a second vocabulary.

Refresh rotation stores a hashed token per family. Presenting an already-used token revokes
the entire family, which is the standard mitigation for a stolen refresh token.

Enforcement order on every protected route:

| Layer | Rejects | Notes |
|---|---|---|
| Authenticate | `401` | missing, malformed or expired token |
| Authorise | `403 FORBIDDEN` | role lacks the capability |
| Scope | `404` | outside org/territory — see **D7** |

Passwords are argon2id. No MFA, no password-reset flow, no rate limiting in this slice
(§10).

---

## 8. Data model and migrations

```
organizations · territories
staff_users · staff_user_roles · staff_user_territories · refresh_tokens
campaigns · campaign_territories · campaign_sessions
campaign_submissions   ← immutable snapshot per submit; enables the changed-field diff
campaign_decisions     ← reviewer, decision, reason, acknowledged warnings, version, correlation id
idempotency_keys · audit_events · app_config
```

`campaign_submissions` exists in this slice even though the diff *endpoint* is sub-project
3: without a snapshot taken at submit time, a resubmission has nothing to diff against, and
the history cannot be reconstructed later.

`campaign_decisions` records exactly what the approval PRD requires: "reviewer, decision,
reason, warning acknowledgements, version, time and correlation ID".

### Concurrency is structural, not remembered

`campaigns.version` is bumped on every mutation, and the update is
`… WHERE id = ? AND version = ?`. **Zero affected rows is the conflict detection.** A code
path that forgets to check cannot silently overwrite, because the write itself does not
apply.

### Migrations are transactional — the P0.6 lesson applied

P0.6's worst defect was a migration that could brick the database permanently: drift runs
migration steps bare and bumps `user_version` only after `onUpgrade` returns, so a process
killed mid-step left a device durably on the old version with half the work committed, and
the retry threw out of `beforeOpen` on every subsequent launch. That is filed as **P0.R5**.

Postgres has transactional DDL, so the cure is structural here rather than an idempotency
idiom per step: the runner wraps **each migration and its version-row insert in one
transaction**. A kill applies the whole step or none of it. This only holds if the version
row is written inside the same transaction as the DDL — writing it after is the same bug
in a different database.

Migrations are numbered and forward-only. No down-migrations: a failed deploy rolls forward.

---

## 9. Testing and acceptance

**Acceptance criterion, falsifiable:** the CI `e2e` job runs the real service instead of
`tool/mock_server`, and all five matrix configs stay green. Not "the service has tests" —
the existing client, unchanged in behaviour, drives it through five real journeys.

Two things that criterion demands:

- **The service must be seedable as the mock is.** The mock supports
  `MOCK_CAMPAIGNS=rows|empty|error` and an E2E seeder; empty-state and error-state flows
  depend on commanding those. Hence **D-H**, gated out of production builds.
- **At least one flow must authenticate for real.** E2E currently swaps in
  `FakeAuthService`, which replaces the transport while keeping the real `SessionManager`.
  Since we now own auth (**D3**), shipping an identity provider that no end-to-end test has
  logged into would repeat P0.6's central mistake: a component with no consumer exercising
  it has no evidence behind it.

| Layer | Covers |
|---|---|
| Unit | status machine (every legal **and** illegal transition), submit validation, SoD, argon2id, refresh rotation and reuse detection, idempotency replay |
| Integration | repositories and migrations against a **real Postgres** service container — never a mock DB |
| Contract | shared-package DTO round-trips; parity assertions run against both mock and real service while both exist |
| E2E | the five Maestro configs against the real service |

**Cut-over rule:** `tool/mock_server` is retained until parity tests pass and the e2e
matrix is green against the real service, then deleted. It is not removed optimistically —
it is the harness the last two epics depended on.

**OpenAPI is deferred, not forgotten.** The shared Dart package is the source of truth,
both consumers are Dart, and there is no external consumer today (sub-project 8 consumes
*BMD's* API, not ours). Generating a specification nobody reads is exactly the kind of
professional-looking artifact worth resisting until someone needs it.

---

## 10. Non-goals

Sub-projects 2–8. Carpenter master and BMD reconciliation (decided in **D1**, built in 2
and 8). Attendance, media, evidence. Analytics and the real `verifiedAttendance`
computation. The changed-field **diff endpoint** (snapshots are stored here so it becomes
possible). Notifications on decision commit — the approval PRD requires them, and
`campaign_decisions` captures everything needed to add them without re-modelling. Rate
limiting, MFA, password reset. Cloud deployment: a `Dockerfile` and local `docker-compose`,
no hosting.

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| **This slice replaces the harness two epics relied on.** If the real service is less reliable than the mock, the e2e signal degrades before it improves. | Parity tests first; cut over only on green; keep the mock until then (§9). |
| The wire-naming change (**§5**) breaks the client and the mock simultaneously. | It lands in one commit across the shared package, server, client and mock — the reason for **D4**. |
| **D1** creates identity-integrity debt that only surfaces in reporting, where it is hardest to notice. | Duplicate suppression is a named required deliverable of sub-project 8, not a hardening task. |
| Owning auth (**D3**) means staff offboarding is now our correctness problem. | Access administration is scoped into sub-project 7 rather than left implicit. |
| Postgres is a new operational dependency for a team that has shipped only a Flutter app. | `docker-compose` for local parity; migrations transactional and forward-only; no ORM to hide behaviour. |

---

## 12. Follow-ups this spec does not close

- **P0.R5** — `from2To3`'s non-idempotent client migration, blocking before the first pilot
  device. Unrelated to the service, still open, and the source of §8's transactional rule.
- **P0.R6** — degradation observability end to end on the client.
- **`/consent/notices`** is referenced by `NoticeRepository` and implemented nowhere. It
  belongs to sub-project 4 with the consent-record contract. Recorded here because it is a
  latent 404 that only P0.5's deliberately-unwired seam is hiding.
- Browser rendering of the Flutter web app is still unverified at runtime; the service does
  not change that.
