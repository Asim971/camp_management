# Sub-project 5b — Verification decision completion + supervisor authority

**Status:** design, ready for planning.

5b completes the CRM verification decision path that 5a opened. 5a shipped the
core round-trip (approve / reject, `If-Match` optimistic locking, audit-on-view,
signed evidence). 5b adds the rest of the decision vocabulary —
**return-for-recapture** and **escalation** — and **supervisor override**, the
authority for a `crm_supervisor` to correct an already-decided case. It also
folds in the small decision-path quality fixes recorded during 5a.

Richer SLA/risk **queue prioritisation, claim/assign workflow, and the
supervisor queue are slice 5c**; `nid_reveal` is a later CRM slice; a real
ML/PAD matcher stays behind 5a's `MachineCheck` interface; media hardening is
4b; the full **field re-capture loop is 4c** — named here only to be excluded.

---

## 1. Context and current state (what 5a left)

- `POST /verification/cases/<id>/decision` accepts `{outcome, reason,
  supervisorOverride}` + an `If-Match` header. Today only `APPROVED` and
  `REJECTED` succeed; `RETURN_FOR_RECAPTURE`, `ESCALATED`, and *any*
  `supervisorOverride: true` return **422 `VERIFICATION_OUTCOME_UNSUPPORTED`**.
  `REJECTED` with a blank reason → **422 `DECISION_REASON_REQUIRED`**. A stale
  `If-Match`, or a case whose `status <> 'CRM_REVIEW'` (already decided), →
  **412 `PRECONDITION_FAILED`**.
- The decision CAS guards `status = 'CRM_REVIEW'` (5a's re-decide guard), so a
  closed case cannot be re-decided by anyone.
- `verification_decisions` (migration 008) already carries `outcome`, `reason`,
  `supervisor_override`, `version_at_decision`, `verifier_id`, `correlation_id`,
  `decided_at`. `attendance` carries `version`, `assignee_id`, `machine_*`.
- RBAC (`server/lib/src/auth/tokens.dart`): `crm_verifier` holds
  `verification_decide` + `sensitive_media_view`; `crm_supervisor` additionally
  holds `verification_override` + `nid_reveal`. No route checks
  `verification_override` today — it is defined but unenforced.
- The client case screen (`lib/features/crm_case/`) already lists all four
  `VerificationOutcome` values, but the two extra ones 422 on the server. The
  decision request already carries a `supervisorOverride` flag (default false)
  with **no UI control that sets it true**. The client `loadCase` mapper
  **hard-codes `status: AttendanceStatus.crmReview`** — the server sends no
  `status` field.
- `AttendanceStatus` still lives in `lib/domain/common/status.dart` with **no
  `wireValue`** and no `tryParseWire` — 5a.D1 intended to move it but did not,
  because 5a never parsed status on the wire.

---

## 2. Decisions

### 5b.D1 — The full outcome set and its status side-effects

The decision endpoint accepts all four `VerificationOutcome` values. Their
effect on the attendance status machine:

| Outcome (wire) | Attendance status after | Reason required | Notes |
|---|---|---|---|
| `APPROVED` | `APPROVED` | no | 5a, unchanged |
| `REJECTED` | `REJECTED` | **yes** | 5a, unchanged |
| `RETURN_FOR_RECAPTURE` | `RETURNED` | **yes** | verification-side only; the field re-capture loop is 4c and will read `RETURNED` rows |
| `ESCALATED` | **`CRM_REVIEW` (unchanged)** + sets `escalated_at`, `escalated_by` | **yes** | still an open, undecided case; a supervisor picks it up. The rich supervisor queue is 5c |

`RETURN_FOR_RECAPTURE` produces the `RETURNED` status literal and records the
decision; **5b does not build the field re-capture flow** (that reads `RETURNED`
and opens a new capture attempt — sub-project 4c). `ESCALATED` does **not**
change the status (the case is still awaiting a decision); it stamps an
escalation marker so a supervisor can find and decide it. There is **no new
`ESCALATED` attendance status** — deliberately, so the status machine and the
client enum gain no member that has nowhere to be worked until 5c.

### 5b.D2 — Reason is required for reject, return, escalate, and any override

A non-blank `reason` is required when the outcome is `REJECTED`,
`RETURN_FOR_RECAPTURE`, or `ESCALATED`, **or** whenever `supervisorOverride`
is `true` (regardless of outcome). A missing/blank reason → **422
`DECISION_REASON_REQUIRED`**. `APPROVED` without override needs no reason
(unchanged from 5a). This is validated **before** the CAS, so an invalid
request never changes state.

### 5b.D3 — Supervisor override: re-decide a closed case, version-safe

`supervisorOverride: true` lets a `crm_supervisor` (who holds
`verification_override`) apply a decision **even to an already-decided case**
(`APPROVED` / `REJECTED` / `RETURNED`) — correcting a prior decision. The
override:

- **Drops** 5a's `status = 'CRM_REVIEW'` guard from the CAS, so a closed case is
  reachable.
- **Keeps** the `version = @ifMatch` predicate, so a concurrent edit still
  yields **412** (the supervisor must be acting on the version they fetched).
- Records `supervisor_override = true` on the `verification_decisions` row and
  writes the `verification.decided` audit event, as any decision does.
- Applies to any outcome uniformly (correcting to approve/reject/return); the
  override is purely "ignore the current status, honour the version".

A caller who sends `supervisorOverride: true` **without** the
`verification_override` permission → **403 `FORBIDDEN`** (not 422 — it is an
authorization failure, not a validation one). This is checked in the decision
route from the authenticated permission set. A plain approve/reject/return/
escalate (`supervisorOverride` absent or false) is unaffected and needs only
`verification_decide`, exactly as in 5a.

### 5b.D4 — The two-mode CAS

The decision compare-and-swap has two shapes selected by `supervisorOverride`:

```sql
-- normal decision (verification_decide): keeps the open-case guard
UPDATE attendance
   SET status = @newStatus, version = version + 1,
       escalated_at = @escAt, escalated_by = @escBy   -- only set when ESCALATED
 WHERE id = @id AND version = @ifMatch AND organization_id = @org
   AND status = 'CRM_REVIEW'
RETURNING version;

-- supervisor override (verification_override): drops the status guard,
-- keeps the version guard
UPDATE attendance
   SET status = @newStatus, version = version + 1,
       escalated_at = @escAt, escalated_by = @escBy   -- only set when ESCALATED
 WHERE id = @id AND version = @ifMatch AND organization_id = @org
RETURNING version;
```

The `SET` clause is identical in both shapes; only the `WHERE` differs (the
override drops `AND status = 'CRM_REVIEW'`). For `ESCALATED`, `@newStatus` is
`'CRM_REVIEW'` (unchanged) and `@escAt`/`@escBy` are set; for the other outcomes
`@newStatus` is `APPROVED`/`REJECTED`/`RETURNED` and the escalation params are
`NULL` (leaving any prior marker untouched — bind `escalated_at =
COALESCE(@escAt, escalated_at)` if a prior marker must survive a later
non-escalate decision; the implementer decides, but a re-decision of an escalated
case need not preserve the stamp). A supervisor override to `ESCALATED` is
permitted but unusual; it behaves uniformly (status stays `CRM_REVIEW`, marker
set). On **0 rows affected**, re-check org-scoped existence: row exists → **412
`PRECONDITION_FAILED`**; gone/cross-org → **404 `NOT_FOUND`** (5a's
disambiguation). The `UPDATE`, the `verification_decisions` INSERT, and the
audit write all run in **one `Db.tx`** via `tx.execute`/`writeTx`.

### 5b.D5 — The case wire emits `status`; `AttendanceStatus` moves to contracts

`loadCase` returns a `status` field carrying the attendance's real status as a
SCREAMING_SNAKE `AttendanceStatus` wire value. The client parses it via
`AttendanceStatus.tryParseWire` (unknown → null, surfaced as a visible fallback,
**never a silent default**) and stops hard-coding `crmReview`. This is required
because a supervisor can now open an already-decided case to override it — the
UI must know the true status.

To parse it safely, **`AttendanceStatus` moves to `campaign_contracts`** with a
`wireValue` (SCREAMING_SNAKE) + static `tryParseWire`, and
`lib/domain/common/status.dart` keeps it as a re-export shim — the same pattern
5a used for `MatchBand`/`ReferenceSource`/`VerificationOutcome`, and what 5a.D1
originally intended. Its members already map 1:1 to the wire:
`notCaptured→NOT_CAPTURED`, `pendingSync→PENDING_SYNC`,
`matchProcessing→MATCH_PROCESSING`, `crmReview→CRM_REVIEW`, `approved→APPROVED`,
`rejected→REJECTED`, `returned→RETURNED`. No member is added or removed.

### 5b.D6 — Malformed decision body → 400

`POST …/decision` currently does `jsonDecode(await request.readAsString())`
with no guard; a non-JSON or non-object body throws and is caught by the generic
envelope fallback as **500**. 5b guards it: a body that is not a JSON object →
**400 `BAD_REQUEST`** with a clear message, consistent with the malformed-body
handling 4a added to the confirm endpoint.

### 5b.D7 — Migration 009: the escalation marker

Add two nullable columns to `attendance`:

```sql
ALTER TABLE attendance ADD COLUMN escalated_at TIMESTAMPTZ;
ALTER TABLE attendance ADD COLUMN escalated_by TEXT REFERENCES staff_users(id);
```

That is the entire schema change. `escalated_by` references the verifier who
escalated. 5c's supervisor queue will filter on `escalated_at IS NOT NULL`; 5b
only stamps the marker on an `ESCALATED` decision. No new status literal, no
`verification_decisions` change (its `outcome` already carries `ESCALATED`).

### 5b.D8 — RBAC and org scope (unchanged from 5a, extended for override)

Queue and decision require `verification_decide`; the case additionally requires
`sensitive_media_view`; `supervisorOverride: true` additionally requires
`verification_override`. Every query — including both CAS shapes — stays
org-scoped: an out-of-scope attendance is 404/invisible (D7 of the foundation).
Every case read is audited-on-view (5a.D4, unchanged). Every decision writes an
audit event.

---

## 3. Endpoints and error codes

No new endpoints. The one changed endpoint:

`POST /verification/cases/<id>/decision` — body `{outcome, reason?,
supervisorOverride?}`, header `If-Match: <int>`.

| Condition | Status | Error code |
|---|---|---|
| `If-Match` missing / non-int | 400 | `BAD_REQUEST` |
| Body not a JSON object | 400 | `BAD_REQUEST` (D6) |
| Unknown `outcome` wire | 422 | `VERIFICATION_OUTCOME_UNSUPPORTED` |
| `supervisorOverride:true` without `verification_override` | 403 | `FORBIDDEN` (D3) |
| Reason blank when required | 422 | `DECISION_REASON_REQUIRED` (D2) |
| Attendance out of org / missing | 404 | `NOT_FOUND` |
| Stale version (or closed case, non-override) | 412 | `PRECONDITION_FAILED` |
| Success | 200 | — (returns `{status: <newStatus>}`) |

`GET /verification/cases/<id>` — unchanged except the response body gains a
`status` field (D5).

No new `ApiErrorCode` members are needed:
`badRequest`/`forbidden`/`notFound`/`preconditionFailed`/`decisionReasonRequired`/
`verificationOutcomeUnsupported` all already exist and map to the right HTTP
status in `error_envelope.dart`. `VerificationOutcome` already has all four
members from 5a.

---

## 4. Files

**Contracts:**
- Create `packages/campaign_contracts/lib/src/attendance_status.dart`
  (`AttendanceStatus` + `wireValue` + `tryParseWire`); export from the barrel.
- Modify `lib/domain/common/status.dart` — `AttendanceStatus` becomes a
  re-export shim (other enums unchanged).

**Server:**
- Modify `server/lib/src/db/migrations/embedded.dart` — migration `009`.
- Modify `server/lib/src/verification/verification_repo.dart` — the two-mode
  CAS, the full outcome→status map, the escalation stamp, reason rules, `status`
  in the case wire.
- Modify `server/lib/src/verification/verification_routes.dart` — malformed-body
  guard (400), the `verification_override` check → 403.

**Client:**
- Modify `lib/data/verification/verification_repository_impl.dart` — parse case
  `status` via `tryParseWire`; send the full outcome set + override.
- Modify `lib/features/crm_case/` — reason fields for return/escalate; a
  supervisor-override control gated on `verification_override`; render the real
  status.

**Mock + e2e:**
- Modify `tool/mock_server/bin/server.dart` — decision handler honours the four
  outcomes + override with the 403/422/412 rules.
- Modify `server/test/contract/parity_test.dart` — pin the new rules.
- Modify `server/lib/src/seed/seed_routes.dart` + `.maestro/flows/` +
  `.github/workflows/ci.yml` — fixtures and flows for a return-for-recapture and
  a supervisor override.

---

## 5. Client behaviour

- The case screen lists all four outcomes (already true); selecting
  `RETURN_FOR_RECAPTURE`/`ESCALATED` now requires and sends a reason and
  succeeds. Reason mandatory for reject/return/escalate.
- A **supervisor-override control** appears only when the signed-in user holds
  `verification_override`; it is meaningful when the case is already decided
  (the client now knows the status from the wire). Turning it on requires a
  justification and sends `supervisorOverride: true`.
- The `loadCase` mapper parses `status` via `AttendanceStatus.tryParseWire`
  (unknown → visible fallback, never a silent default) instead of hard-coding
  `crmReview`.
- 403 already maps to `FailureKind.forbidden`; an override-without-permission
  surfaces as a forbidden error. 412 → conflict (5a) unchanged.

---

## 6. Testing (falsification-first, like 5a)

Server:
- `RETURN_FOR_RECAPTURE` → attendance `RETURNED`, decision row written, reason
  required (blank → 422).
- `ESCALATED` → status stays `CRM_REVIEW`, `escalated_at`/`escalated_by` set,
  reason required (blank → 422).
- Supervisor override: a `crm_supervisor` re-decides an already-decided
  (`APPROVED`) case → 200 and the status/decision change; a `crm_verifier`
  sending `supervisorOverride:true` → **403**; an override with a **stale
  `If-Match`** → **412** (proves override stays version-safe); override with a
  blank reason → **422**.
- Malformed decision body → **400** (D6).
- `GET case` returns `status`; the client repo test parses it and an unknown
  status value falls back visibly (no crash).
- **Folded-in 5a deferred gaps:** a multi-band queue-ordering test (seed
  ≥2 `CRM_REVIEW` cases with different `machine_band`, assert the
  `NO_REFERENCE < LOW < MEDIUM < HIGH` severity order); the signed media GET
  asserts the response `content-type` matches the stored `content_type`.

Mock parity: the mock decision handler + parity test agree with the real service
on the four outcomes, the 403 override gate, the reason 422s, and the 412s.

E2E (real service): a `crm_verifier` return-for-recapture flow, and a
`crm_supervisor` override flow, with seeded fixtures; the `crm` matrix stays on
the real service (5a cut-over).

---

## 7. Out of scope (named to be excluded)

- **SLA/risk queue prioritisation, claim/assign workflow, the rich supervisor
  queue** for escalated cases → **sub-project 5c**.
- **`nid_reveal`** (audited raw-NID reveal) → a later CRM slice.
- **Real ML / PAD matcher** → stays behind 5a's `MachineCheck` interface.
- **Media encryption-at-rest, retention, real object storage** → sub-project 4b.
- **The field re-capture loop** (reacting to `RETURNED`, opening a new capture
  attempt, attempt lineage) → sub-project 4c. 5b delivers only the
  verification-side `RETURNED` transition.
