# Sub-project 5c — Verification queue: prioritised, filterable, self-claimable

**Status:** design, ready for planning.

5c makes the CRM verification *queue* real. 5a/5b built the decision round-trip
(approve/reject/return/escalate, supervisor override) but left the queue a
band-then-age list with no filters, no assignment, and no client screen. 5c
adds escalated-aware prioritisation, queue filters (all/mine/unassigned/
escalated), a version-free atomic **self-claim / release**, and the C-01
verification-queue screen — with mock parity and an e2e flow.

Deferred to a later slice (5d): supervisor **assign-to-another-verifier** (needs
a verifier roster + a `verification_assign` permission), **configurable SLA
thresholds / cross-band aging / risk scoring**, queue **pagination**, and
`nid_reveal`. Named here only to be excluded.

---

## 1. Context and current state

- `GET /verification/queue` (`verification_repo.dart` `queue`) is org-scoped +
  `status='CRM_REVIEW'`, ordered by band severity (`NO_REFERENCE<LOW<MEDIUM<
  HIGH`) then `captured_at`. It takes **no filter params** and requires
  `verification_decide`.
- `attendance.assignee_id` (migration 008, nullable FK → `staff_users`) exists
  but is **never written** — always null. `escalated_at`/`escalated_by`
  (migration 009) are written on an `ESCALATED` decision but the queue **never
  reads or surfaces them**.
- **No claim/assign endpoint exists.**
- The client already sends `?assignee=<id>` (`verification_repository_impl.dart`
  `queue`) which the **server silently ignores** — a live contract gap.
- The queue **screen is a placeholder** (`/verification`, C-01, "not yet
  implemented"). Only the single-case screen (`/verification/cases/:id`,
  `CrmCaseScreen`) is real. `VerificationQueueItem` exists as data-layer
  plumbing with no consuming UI.
- RBAC: `crm_verifier` = `verification_decide` + `sensitive_media_view`;
  `crm_supervisor` additionally holds `verification_override` (+ `nid_reveal`,
  `export`). No assignment-specific permission exists.

---

## 2. Decisions

### 5c.D1 — Escalated-aware prioritisation

The queue `ORDER BY` becomes:

```sql
ORDER BY (escalated_at IS NOT NULL) DESC,          -- escalated cases first
         CASE machine_band WHEN 'NO_REFERENCE' THEN 0 WHEN 'LOW' THEN 1
                           WHEN 'MEDIUM' THEN 2 ELSE 3 END,   -- risk band
         captured_at                                -- oldest-first within a tier
```

Escalated cases (still `CRM_REVIEW`; the 5b marker) sort first, then by risk
band, then oldest-captured within a band.

**Starvation tradeoff (acknowledged, deferred).** Strict priority ordering can
starve low-risk, non-escalated cases when higher-priority work keeps arriving.
The `captured_at` tiebreaker ages cases *within* a band, which is the first cut.
Cross-band aging and SLA-deadline promotion — the richer "SLA/risk" model — are
deferred to 5d. This is a deliberate YAGNI choice for a human-driven queue where
a supervisor can also use the filters; it is documented, not overlooked.

### 5c.D2 — Queue filters via a `QueueFilter` wire enum

`GET /verification/queue?filter=all|mine|unassigned|escalated` (default `all`).
A new `QueueFilter` enum lives in `campaign_contracts` with SCREAMING_SNAKE
`wireValue` (`ALL`/`MINE`/`UNASSIGNED`/`ESCALATED`) and `tryParseWire`
(null on unknown, never a default). Each filter keeps the org +
`status='CRM_REVIEW'` scope and the D1 ordering, adding one predicate:

| filter | predicate | RBAC |
|---|---|---|
| `all` | (none) | `verification_decide` |
| `mine` | `assignee_id = @callerUserId` | `verification_decide` |
| `unassigned` | `assignee_id IS NULL` | `verification_decide` |
| `escalated` | `escalated_at IS NOT NULL` | **`verification_override`** (supervisor) |

`mine` uses the caller's id **from the auth context**, never a client-supplied
id — a verifier cannot enumerate another's queue. `filter=escalated` from a
caller lacking `verification_override` → **403 `FORBIDDEN`**. An unrecognised
`filter` value → **400 `BAD_REQUEST`**. This replaces the ignored `?assignee=`
param, closing the contract gap.

### 5c.D3 — The queue item wire gains `escalatedAt`

Each queue item adds `escalatedAt` (UTC ISO-8601 string, or null) alongside the
existing `attendanceId, carpenterName, campaignName, ageSeconds, band,
referenceSource, assigneeId`. The client renders an "Escalated" badge when it is
non-null and compares `assigneeId` to its own session `userId` to show "Mine".

### 5c.D4 — Version-free atomic self-claim / release

Two new routes, both requiring `verification_decide`, org-scoped, audited, and
**not touching `attendance.version`**:

- **`POST /verification/cases/<id>/claim`** — an atomic conditional UPDATE:

  ```sql
  UPDATE attendance SET assignee_id = @me
   WHERE id = @id AND organization_id = @org AND status = 'CRM_REVIEW'
     AND (assignee_id IS NULL OR assignee_id = @me)
  RETURNING id;
  ```

  1 row → **200** (claiming your own is idempotent). 0 rows → re-check
  org-scoped existence + state: exists but `assignee_id` is another user →
  **409 `CONFLICT_STALE_VERSION`** (message: already being reviewed by someone
  else); exists but not `CRM_REVIEW` → **409**; missing/cross-org → **404**.
  Writes a `verification.claimed` audit event. The row lock on the specific id
  serialises concurrent claims — the standard race-free primitive for claiming a
  chosen row (as opposed to `FOR UPDATE SKIP LOCKED`, which is for
  pop-next-available worker queues, not this model).

- **`POST /verification/cases/<id>/release`** — `UPDATE attendance SET
  assignee_id = NULL WHERE id=@id AND organization_id=@org AND assignee_id=@me
  RETURNING id`. 1 row → **200**; 0 rows → re-check: assigned to another →
  **409**; missing/cross-org → **404**. Writes `verification.released`.

Claim/release deliberately do **not** bump `version`: a verifier who loaded a
case (version N), claims it, then decides with `If-Match: N` still succeeds —
assignment is orthogonal to the decision CAS.

> **Verb note.** POST on an action sub-path matches the existing `POST
> …/decision` and suits a distinct auditable event with 409 semantics; a
> PUT/DELETE-on-`…/assignment` sub-resource is the idempotent-REST alternative
> but is not the codebase's convention.

### 5c.D5 — Migration 010: filter indexes

Back the new filter predicates:

```sql
CREATE INDEX attendance_assignee_idx
  ON attendance(organization_id, status, assignee_id);
CREATE INDEX attendance_escalated_idx
  ON attendance(organization_id, status)
  WHERE escalated_at IS NOT NULL;
```

A composite index for `assignee`/`unassigned` filters and a partial index for
the escalated filter. The existing `attendance_status_idx` still backs the
default queue.

### 5c.D6 — Build the C-01 verification-queue screen

Replace the `/verification` placeholder with a real screen:

- A prioritised list of queue items — carpenter, campaign, band chip, age, an
  **Escalated** badge (when `escalatedAt` non-null), and an assignee indicator
  (Mine / Unassigned / someone else).
- **Filter tabs**: All · Mine · Unassigned · Escalated. The **Escalated tab is
  rendered only for a user holding `Permission.verificationOverride`** (the
  `PermissionGate` pattern 5b used for the override switch); a plain verifier
  sees three tabs.
- A **Claim / Release** control (Claim an unassigned case; Release your own). A
  409 surfaces as "already being reviewed by someone else — refresh."
- Tapping an item navigates to the existing `/verification/cases/:id` screen.
- The repo's `queue({String? assigneeId})` is refactored to
  `queue({QueueFilter filter})` sending `?filter=…`. `mapDioError` already maps
  409 → `FailureKind.conflict`.

### 5c.D7 — RBAC and org scope

Queue, claim, and release require `verification_decide`; the `escalated` filter
additionally requires `verification_override`. Every query — the queue SELECT
and both claim/release UPDATEs — stays org-scoped (foundation D7): an
out-of-scope attendance is 404/invisible. Every claim/release writes an audit
event.

---

## 3. Endpoints and error codes

| Endpoint | Method | Auth | Notes |
|---|---|---|---|
| `/verification/queue?filter=` | GET | `verification_decide` (+ `verification_override` for `filter=escalated`) | prioritised, filtered list; unknown filter → 400; escalated w/o override → 403 |
| `/verification/cases/<id>/claim` | POST | `verification_decide` | atomic self-claim; 200 / 409 / 404 |
| `/verification/cases/<id>/release` | POST | `verification_decide` | release own; 200 / 409 / 404 |

No new `ApiErrorCode` members: `badRequest`(400), `forbidden`(403),
`notFound`(404), and `conflictStaleVersion`(409) all already exist and map in
`error_envelope.dart`. The claim/release 409 reuses `conflictStaleVersion`
(the client already maps 409 → conflict).

---

## 4. Files

**Contracts:**
- Create `packages/campaign_contracts/lib/src/queue_filter.dart` (`QueueFilter`
  + `wireValue` + `tryParseWire`); export from the barrel.

**Server:**
- Modify `verification_repo.dart` — the D1 ordering, the `filter`-driven WHERE,
  `escalatedAt` in the wire, and `claim`/`release` methods.
- Modify `verification_routes.dart` — the `filter` query param (parse via
  `QueueFilter.tryParseWire`, 400 on unknown; 403 on escalated without
  `verification_override`), and the `POST …/claim` / `POST …/release` routes.
- Modify `db/migrations/embedded.dart` — migration `010`.

**Client:**
- Modify `verification_repository_impl.dart` + `verification_repository.dart` —
  `queue({QueueFilter filter})`; add `claim`/`release`; parse `escalatedAt`.
- Create the C-01 queue screen under `lib/features/verification_queue/`
  (list + filter tabs + claim/release + navigation); wire it into
  `app_router.dart` in place of the placeholder.

**Mock + e2e:**
- Modify `tool/mock_server/bin/server.dart` — `/verification/queue?filter=` +
  claim/release handlers with the 409/404 rules.
- Modify `server/test/contract/parity_test.dart` — pin the filter + claim rules.
- Modify `seed_routes.dart` (if needed) + `.maestro/flows/` + `.github/workflows/
  ci.yml` — a claim → Mine → release e2e flow. **Maestro `inputText` stays
  ASCII-only** (a non-ASCII glyph corrupts the swiftshader render surface on CI).

---

## 5. Client behaviour

- The queue screen loads `filter=all` by default; switching tabs re-queries with
  the tab's filter. The Escalated tab appears only for `verification_override`
  holders.
- Each item shows band/age/escalated/assignee; a Claim button on an unassigned
  case, a Release button on one that is Mine. A 409 shows the "already being
  reviewed" message and refreshes the list.
- An unknown wire `band`/`referenceSource`/`status`/`filter` never crashes — the
  existing visible-fallback pattern applies; `escalatedAt` parses as a nullable
  timestamp.

---

## 6. Testing (falsification-first)

Server:
- Ordering: seed cases whose ages/bands **oppose** the priority tiers (an old
  HIGH non-escalated, a fresh escalated MEDIUM, etc.) and assert escalated-first
  then band then age — so a regression to a simpler ORDER BY fails.
- Filters: `mine`/`unassigned`/`escalated` each return exactly the right subset;
  `mine` uses the caller's id (a second user's cases never appear);
  `filter=escalated` without `verification_override` → **403**; unknown filter →
  **400**.
- Claim: unassigned → 200 + `assignee_id` set + `verification.claimed` audit;
  claim of another's case → **409** + `assignee_id` unchanged; claim of your own
  → idempotent 200; claim on a decided (non-CRM_REVIEW) case → 409; cross-org →
  404. **Claim does not bump `version`** — a decision with the pre-claim
  `If-Match` still succeeds (proves assignment is orthogonal to the CAS).
- Release: clears only your own; releasing another's → 409.

Client: the repo sends `?filter=…`; parses `escalatedAt`; claim/release call the
right endpoints; a 409 maps to conflict. Widget test for the queue screen: tabs,
the permission-gated Escalated tab, claim/release controls.

Mock parity: mock and real agree on the filter subsets, the claim 200/409, and
the escalated-403. E2E: a `crm_verifier` opens the queue, claims a seeded case,
sees it under **Mine**, releases it.

---

## 7. Out of scope (named to be excluded)

- **Supervisor assign-to-another-verifier** (a `verification_assign` permission +
  a seeded verifier roster + an assignee picker) → 5d.
- **Configurable SLA thresholds, cross-band aging / SLA-deadline promotion, risk
  scoring** beyond band + escalation + within-band age → 5d.
- **Queue pagination / infinite scroll** — 5c returns the full org `CRM_REVIEW`
  list ordered; pagination is 5d.
- **`nid_reveal`** (audited raw-NID reveal) → a later CRM slice.
