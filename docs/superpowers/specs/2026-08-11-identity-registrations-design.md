# Sub-project 2a — Carpenter identity, registrations, profile requests

**Date:** 2026-08-11 · **Scope:** first half of sub-project 2 of 8 (see the foundation
spec `2026-08-10-campaign-service-foundation-design.md` §2). Sub-project 2 was split into
**2a (this spec)** and **2b (async bulk import)** during brainstorming on 2026-08-11:
each half is roughly the reviewable size slice 1's eleven tasks proved manageable, 2b
builds on 2a's carpenter master, and each merges on its own green gate.

**Depends on:** sub-project 1 (merged via PR #6). Inherits its API conventions (§5),
middleware chain, error envelope, idempotency machinery, migration discipline and the
staged e2e cut-over state (4 of 6 configs on the real service; `crm`/`field` on
`USE_MOCK`).

---

## 1. Why this exists

The Flutter app already ships a Registration Workspace (W-06), a field carpenter search
(M-02) and the repositories behind them — all speaking HTTP to `tool/mock_server` routes
whose shapes were never ratified (the mock's own header comment marks campaign routes as
contract-checked and leaves these unmarked). This slice makes the server the authority
for carpenter identity and campaign registration, ratifies those wire shapes, and cuts
the registration workspace over to the real service.

It is also where **D1** (the foundation spec's deliberate override: *we own carpenter
master data locally and reconcile with BMD Sales later*) first becomes schema. The
carpenter table this slice creates must carry the hooks sub-project 8's reconciliation
engine needs (`source`, `sync_status`, indexed `phone`/`nid`), because retrofitting
identity provenance after rows exist is exactly the identity-integrity debt D1's risk
entry warns about.

### One client defect class this slice closes again

`RegistrationRepositoryImpl` sends `Idempotency-Key: carpenterIds.join(',')` — two users
registering the same pair of carpenters collide on the key, and carpenter ids leak into
any log that records headers. It also parses `attendanceState` with
`orElse: () => AttendanceStatus.notCaptured` — the same silent-default-on-unknown defect
slice 1 removed from `campaign_dto.dart`. Both are fixed in the cut-over task.

---

## 2. Scope

**In:**

- Four hardening ride-alongs from slice 1's final review, landed as the opening task:
  idempotency reservation TTL + reaper, `pg_advisory_xact_lock` around
  `Migrator.applyPending`, structured request logging with the correlation/trace id, and
  a CHECK constraint on `staff_user_roles.role`.
- Carpenter local master: table, org-scoped search (`GET /carpenters?q=`),
  server-computed masking (`displayId`, `phoneSuffix`).
- Session roster: `GET /sessions/{id}/registrations`.
- Registration writes: `POST /campaigns/{id}/registrations`.
- Profile requests: `POST /campaigns/{id}/profile-requests`, creating a **provisional
  carpenter** returned in the response.
- `RegistrationStatus` moves into `packages/campaign_contracts` with wire values, behind
  the same re-export shim pattern as `CampaignStatus`.
- New `ApiErrorCode.unknownCarpenter`.
- Client cut-over of the registration workspace: UUID idempotency key, explicit
  `attendanceState` handling, basket auto-add of the returned provisional carpenter,
  stale pre-D1 doc comment rewritten.
- Mock server updated only where the contract changes, pinned by parity tests.
- New Maestro flow `registration_workspace.yaml`, green against the real service in CI.

**Out (→ 2b):** everything bulk-import — job tables, the async lifecycle (202 + poll +
worker), `ImportStatus`/`ImportRowOutcome` wire vocabulary, client polling UI, W-07 flow.
2b was decided during brainstorming to build the **full async lifecycle** (not
synchronous-with-headroom); that decision binds 2b, not this slice.

**Out (→ later sub-projects):** reconciliation engine, adjudication queue and duplicate
suppression (8); NID reveal and audit-on-view (5); attendance state vocabulary (4);
profile-request adjudication UI (7/8).

---

## 3. Decisions

### 2a.D1 — A profile request creates a provisional carpenter immediately

The field workflow must not block on adjudication: the person is standing in front of
the user. `POST /campaigns/{id}/profile-requests` inserts a carpenter row
(`source = 'PROFILE_REQUEST'`, `sync_status = 'PENDING_PROFILE_SYNC'`) and a
`profile_requests` row in one transaction, and returns **201 with the provisional
carpenter in the standard wire shape** plus the request id. The client auto-adds it to
the registration basket, so request → basket → register completes in one visit.

This redefines `Pending profile sync` per D1 consequence 4: it now means *"exists only
as a locally captured provisional profile, not yet ratified into the master"* — no
longer "awaiting an authoritative Sales Eco identity". Ratification (promote or merge)
is sub-project 8's adjudication queue; `source` and `sync_status` are its hooks.

The controller doc comment in `registration_controller.dart` still encodes the pre-D1
world ("Never creates a local shadow master — missing profiles go through a Sales Eco
request"). It is rewritten in the cut-over task so nobody "fixes" the feature backwards.

### 2a.D2 — Raw phone and NID never cross the wire in this slice

The server stores real `phone` and nullable `nid` (the reconciliation matcher's join
keys). The wire carries only server-computed masks: `displayId` (`CARP-••4821`, last
four of `display_code`) and `phoneSuffix` (last four digits). The `nid_reveal`
permission exists in the fixed claim vocabulary but its endpoint belongs to sub-project
5 with audit-on-view. Nothing in this slice may echo raw identifiers, including in error
messages and audit payloads.

### 2a.D3 — No uniqueness constraint on phone or NID

D1 says matching is confidence-scored with a human adjudication queue (sub-project 8).
A hard `UNIQUE` on `phone` or `nid` would make the schema reject what the matcher is
designed to resolve, and real-world carpenters share phones. Indexes only. Duplicate
suppression for counting stays a named sub-project 8 deliverable, not a constraint here.

### 2a.D4 — `attendanceState` is absent from the real server's payload

Its vocabulary belongs to sub-project 4 and is not invented early (the same rule that
kept four enums out of `campaign_contracts` in slice 1). The client already treats an
absent field as `notCaptured`; the cut-over task makes that mapping explicit (absent →
`notCaptured` deliberately; unknown non-null values no longer silently default). The
mock keeps emitting it for the `crm`/`field` configs that still run against the mock;
parity tests assert the field is *optional* in the shared contract.

### 2a.D5 — The carpenter wire shape gains an additive `syncStatus` field

`LOCAL_ONLY | PENDING_PROFILE_SYNC` (later `LINKED`, sub-project 8). The client's
`_fromJson` ignores unknown keys, so this is non-breaking; it is the hook for a
"pending" badge and the adjudication UI. The client does not parse it in this slice.

---

## 4. Deliverables

| id | Deliverable |
|---|---|
| 2a-A | Hardening opener: reaper, advisory lock, request logging, role CHECK |
| 2a-B | Migrations `003_role_check` and `004_identity`: role CHECK, `carpenters`, `registrations`, `profile_requests` |
| 2a-C | `GET /carpenters?q=` org-scoped search with masking |
| 2a-D | `GET /sessions/{id}/registrations` roster |
| 2a-E | `POST /campaigns/{id}/registrations` idempotent batch register |
| 2a-F | `POST /campaigns/{id}/profile-requests` → provisional carpenter |
| 2a-G | `RegistrationStatus` wire vocabulary in `campaign_contracts` + shim |
| 2a-H | Client cut-over (key, mapping, basket auto-add, comment) + mock parity |
| 2a-I | `registration_workspace.yaml` Maestro flow green against the real service in CI |

---

## 5. Wire contract

Paths are exactly what the client already calls. All endpoints inherit slice 1's
conventions: Bearer auth, error envelope with stable `code`, correlation id echo,
out-of-scope resources 404 (D7), UTC ISO-8601 timestamps.

| Method + path | Auth | Behaviour |
|---|---|---|
| `GET /carpenters?q=` | any authenticated | Org-scoped search over `full_name` (case-insensitive contains), `display_code` (contains) and `phone` (suffix match). Server enforces the 2-character minimum the client UI already applies (400 below it). Returns `{"items": [Carpenter]}` including provisional carpenters. |
| `GET /sessions/{id}/registrations` | any authenticated | Roster of the **session's campaign** (registration is campaign-level; the client caches per session). 404 if the session's campaign is out of org scope. Returns `{"items": [Carpenter]}`. |
| `POST /campaigns/{id}/registrations` | `campaign_create` | Body `{"carpenterIds": ["..."]}`. 404 out-of-scope campaign; 422 `UNKNOWN_CARPENTER` listing ids that are unknown or cross-org; otherwise upserts all rows in one transaction and returns 200 `{"registered": n, "alreadyRegistered": m}`. Idempotent via the standard middleware. |
| `POST /campaigns/{id}/profile-requests` | `campaign_create` | Body `{"name": "...", "phone": "..."}` — both required and non-empty; phone must match `^\+?\d{8,15}$` after stripping spaces and dashes (400 otherwise). 201 `{"requestId": "...", "carpenter": Carpenter}`. Idempotent via the standard middleware. |

**Carpenter wire shape** (ratifies what the client parses today, minus
`attendanceState`, plus `syncStatus`):

```json
{
  "id": "…", "name": "…", "displayId": "CARP-••4821", "phoneSuffix": "4821",
  "territory": "…", "dealerContext": null, "thumbnailUrl": null,
  "eligible": true, "syncStatus": "LOCAL_ONLY"
}
```

`territory` is the territory **name** (what the client renders), resolved by join;
empty string when the carpenter has no territory.

**Contract package changes** (`packages/campaign_contracts`):

- `RegistrationStatus` moves in with `wireValue`/`tryParseWire`: `INVITED`,
  `REGISTERED`, `PENDING_PROFILE_SYNC`, `INELIGIBLE`, `WAITLISTED`, `CANCELLED`.
  `lib/domain/common/status.dart` re-exports it, same shim pattern as `CampaignStatus`.
  Unknown wire values parse to `null`, never a default.
- `ApiErrorCode` gains `unknownCarpenter` → `UNKNOWN_CARPENTER` (HTTP 422).

---

## 6. Data model — migrations `003_role_check` and `004_identity`

Transactional, forward-only, embedded as Dart consts, like 001/002. The hardening
opener ships `003_role_check` (the CHECK constraint below) so it lands before any
feature work; the identity schema is `004_identity` and applies after it in lexical
order.

```sql
CREATE TABLE carpenters (
  id               TEXT PRIMARY KEY,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  full_name        TEXT NOT NULL,
  phone            TEXT NOT NULL,         -- raw; never leaves the server unmasked (2a.D2)
  nid              TEXT,                  -- raw, nullable; same rule
  territory_id     TEXT REFERENCES territories(id),
  dealer_context   TEXT,
  thumbnail_url    TEXT,
  eligible         BOOLEAN NOT NULL DEFAULT TRUE,
  display_code     TEXT NOT NULL UNIQUE,  -- CARP-<8-digit zero-padded serial>
  source           TEXT NOT NULL,         -- 'SEED' | 'PROFILE_REQUEST' (| 'IMPORT' 2b | 'BMD' 8)
  sync_status      TEXT NOT NULL DEFAULT 'LOCAL_ONLY',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX carpenters_org_name_idx  ON carpenters(organization_id, lower(full_name));
CREATE INDEX carpenters_phone_idx     ON carpenters(phone);   -- reconciliation join key (D1)
CREATE INDEX carpenters_nid_idx       ON carpenters(nid);     -- reconciliation join key (D1)
-- Deliberately NO unique constraint on phone/nid (2a.D3).

CREATE SEQUENCE carpenter_display_serial;  -- feeds display_code

CREATE TABLE registrations (
  campaign_id    TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  carpenter_id   TEXT NOT NULL REFERENCES carpenters(id),
  status         TEXT NOT NULL,           -- RegistrationStatus wire values
  registered_by  TEXT NOT NULL REFERENCES staff_users(id),
  registered_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, carpenter_id) -- re-registering is structurally a no-op
);
CREATE INDEX registrations_carpenter_idx ON registrations(carpenter_id);

CREATE TABLE profile_requests (
  id            TEXT PRIMARY KEY,
  campaign_id   TEXT NOT NULL REFERENCES campaigns(id),
  carpenter_id  TEXT NOT NULL REFERENCES carpenters(id),  -- the provisional row it created
  requested_by  TEXT NOT NULL REFERENCES staff_users(id),
  name          TEXT NOT NULL,
  phone         TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'PENDING',  -- adjudication lives in sub-project 8
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX profile_requests_campaign_idx ON profile_requests(campaign_id);
```

`003_role_check` is `ALTER TABLE staff_user_roles ADD CONSTRAINT staff_user_roles_role_check
CHECK (role IN (…))`, listing exactly the seven roles in the client's fixed claim
vocabulary (`campaign_creator`, `marketing_approver`, `crm_verifier`, `crm_supervisor`,
`field_user`, `admin`, `reporting_viewer`).

**Write semantics.** `POST registrations`: load the campaign (404 by D7), validate every
carpenter id exists in-org (422 `UNKNOWN_CARPENTER` with the offending ids in
`details`), then in one transaction `INSERT … ON CONFLICT (campaign_id, carpenter_id) DO
NOTHING`, with `status = 'PENDING_PROFILE_SYNC'` when the carpenter's `sync_status` is
`PENDING_PROFILE_SYNC` and `'REGISTERED'` otherwise. Already-present rows are counted as
`alreadyRegistered`, not errors. Both write endpoints write `audit_events` rows carrying
the correlation id (all writes, per slice 1's Task 9 fix).

---

## 7. Enforcement

The slice-1 middleware chain is reused unchanged: correlation → error envelope →
authenticate → authorise → scope → idempotency → handler.

- Reads (`/carpenters`, roster) are gated by **authenticate only** — the same posture,
  and the same documented product-confirmation caveat, as campaign reads (no
  read-permission exists in the client's fixed claim vocabulary).
- Writes require **`campaign_create`**, matching the client's own route guard on
  `/campaigns/:id/register`.
- Org scope applies to every query (carpenters are org-owned rows). Territory scope
  remains unenforced-but-documented, consistent with slice 1's partial D-E; enforcing it
  is a named follow-up, not silently absorbed here.

---

## 8. Hardening opener (2a-A)

Lands as the plan's first task, before any feature work, each item with a
falsification-style test in the sdd tradition:

1. **Idempotency reservation TTL + reaper.** A crashed owner currently holds a key at
   409 for the full 24h TTL. Add a reservation TTL of **5 minutes** (a reservation with
   `response_status IS NULL` older than that is reclaimable by the next request — longer
   than any handler runtime, shorter than a user's patience) and an opportunistic reaper:
   each claim attempt first deletes rows with `expires_at < now()` (bounded, e.g.
   `LIMIT 100`, so no request pays for unbounded cleanup). Test: expired reservation
   reclaimed by a new request; fulfilled row survives until its 24h TTL; expired
   fulfilled rows disappear after a subsequent claim.
2. **`pg_advisory_xact_lock` around `applyPending`.** Two instances booting together
   currently race (loser fails loudly). Test: two concurrent `applyPending` calls on
   separate connections — one applies, one waits and applies nothing, zero duplicate
   rows.
3. **Structured request logging with trace id.** One log line per request: method, path,
   status, duration, correlation id. Closes slice 1's D-B partial. Test: the logged
   correlation id equals the `X-Correlation-Id` response header.
4. **CHECK on `staff_user_roles.role`.** An unknown role currently reaches the client's
   claims trust boundary verbatim and breaks sign-in. Test: inserting an unlisted role
   fails with a constraint violation.

---

## 9. Client cut-over (2a-H)

`RegistrationRepositoryImpl` keeps its offline-first shape (Drift-cached roster,
cache-only field search). Changes:

- `Idempotency-Key` for `register` becomes a per-submit UUID (v4), generated in the
  controller alongside the existing `TraceId.generate()`.
- `requestNewProfile` returns `Result<RegisteredCarpenter>` (parsed from the 201 body);
  `RegistrationController.requestNewProfile` auto-adds it to the basket. Snackbar copy
  unchanged.
- `_attendance` mapping made explicit: absent → `notCaptured` (deliberate), unknown
  non-null → no silent default (mapper decides visibly; slice 1's rule).
- `RegistrationStatus` imports resolve via the `campaign_contracts` re-export shim.
- The pre-D1 doc comment in `registration_controller.dart` is rewritten to describe the
  local-master reality and cite D1.

**Mock server:** updated only where the contract changed — honor `Idempotency-Key`
storage-free (echo semantics are fine; parity tests pin only the shared contract),
return the 201 profile-request shape, emit `syncStatus`, keep `attendanceState` for the
still-mocked configs. Parity tests (extending slice 1's suite) pin: search response
shape, mask formats, registration 200 body, profile-request 201 body, 422
`UNKNOWN_CARPENTER`, optionality of `attendanceState`.

**e2e:** new `.maestro/flows/registration_workspace.yaml` — real-auth login as a
`campaign_creator`, open a seeded campaign's registration workspace, master-search a
seeded carpenter, add to basket, request a new profile (auto-added), register, re-open
and assert the roster. Runs against the real service in CI alongside the existing 4-of-6
staged configs. Seed routes gain the carpenter/registration fixtures this flow needs
(gated behind `ENABLE_TEST_SEEDING` exactly as today).

---

## 10. Testing and acceptance

- Server: unit + integration suites green locally and on `postgres:16` in CI (the
  version-skew direction slice 1 documented). New suites mirror `lib/src/participant/`
  (or the plan's chosen directory) and the hardening items.
- Contracts: `RegistrationStatus` round-trip/unknown-value tests, `UNKNOWN_CARPENTER`
  wire test, in the package's own suite.
- Parity: mock and real branches agree on every pinned contract point above.
- App: `flutter analyze --fatal-infos` clean; test count does not regress from the
  slice-1 baseline (411 passing / 29 skipped); new repository-level tests for
  `RegistrationRepositoryImpl` (there are currently none) cover the UUID key, the 201
  parse, and the explicit attendance mapping.
- e2e: `registration_workspace.yaml` green against the real service in CI; the existing
  staged matrix stays green.

---

## 11. Non-goals

Bulk import in any form (2b). Reconciliation, merging, duplicate suppression,
adjudication (8). NID reveal (5). Attendance capture and its vocabulary (4).
Profile-request approval/rejection endpoints — `profile_requests.status` has exactly one
writable value (`PENDING`) in this slice. Registration cancellation/waitlisting UI — the
vocabulary ships so the server can express those states, but no endpoint transitions to
them yet. Pagination on `/carpenters` search — the client renders a short list; add it
when a real dataset demands it, not speculatively.

---

## 12. Risks

| Risk | Mitigation |
|---|---|
| Provisional carpenters pollute the master before adjudication exists (8 is far away). | `source`/`sync_status` make them queryable and reversible; search shows them (deliberate — the field needs them); nothing counts them for reporting yet (analytics is 6, behind 8's dedup). |
| The registration workspace is the first *new* e2e flow authored against the real service — flakiness here erodes trust in the staged-matrix pattern. | The flow reuses the proven real-auth prelude from slice 1's `locale` staging; seed fixtures are deterministic; the flow lands with the endpoints, not after. |
| Masking bugs leak PII (raw phone/NID) into responses, errors, or audit payloads. | 2a.D2 is a named decision with tests asserting raw values absent from every surface, including 422 details and audit rows. |
| The mock and real server drift on the registration contract while `crm`/`field` still run mocked. | Same defence as slice 1: parity tests pin every contract point both sides share. |

---

## 13. Follow-ups this spec does not close

- Territory-scope enforcement (slice 1's partial D-E) — still documented-only.
- Profile-request adjudication (promote/merge/reject) — sub-project 8, consuming
  `source`/`sync_status`/`profile_requests` as designed here.
- `syncStatus` badge in the client UI — the wire field ships; the UI use is deliberate
  future work.
- Registration lifecycle transitions (waitlist, cancel, ineligible) — vocabulary ships
  now, endpoints when a PRD flow needs them.
- Remaining slice-1 review follow-ups not selected as ride-alongs: shared wire DTOs +
  field-set parity, `audienceTypes`/session-venue store-or-drop, `CampaignQuery.page=1`,
  `/auth/*` errors through `ApiException`, CORS, Dockerfile build verification.
