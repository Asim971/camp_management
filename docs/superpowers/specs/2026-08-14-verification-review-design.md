# CRM Verification Review Round-Trip (sub-project 5a) — Design

**Scope:** the first slice of **sub-project 5 — Verification** (foundation spec §2). 5a
delivers the *CRM review round-trip*: a captured attendance gets a machine verdict and
enters a prioritised review queue; a CRM verifier reads the case (with evidence, logged on
view) and decides **approve or reject** under HTTP optimistic locking. It moves the `crm`
CI config off `tool/mock_server`. Return-for-recapture, escalation, supervisor override, and
sophisticated SLA prioritisation are slice **5b** — named here only to be excluded.

**Goal:** stand up `GET /verification/queue`, `GET /verification/cases/<id>`, and
`POST /verification/cases/<id>/decision` on the real `campaign_service`, plus a deterministic
machine-check adapter that runs inside 4a's attendance confirm, so the client's `crm_case`
flow (`crm_case_decision` + `crm_case_conflict`) runs green against the real service.

**Depends on:** sub-project 1 (auth/RBAC, org scope, error envelope, audit), 2a (carpenters —
the reference-photo source), and **4a** (the `attendance` record in `MATCH_PROCESSING`, the
`media_objects` evidence blob, and the HMAC signed-URL helper — reused here for signed READ
URLs).

**Inherited constraints:** D2 (no ORM / no codegen), D7 (out-of-scope → 404), SCREAMING_SNAKE
wire values, "unknown enum values never default", and the fixed claim vocabulary
(`verification_decide`, `sensitive_media_view` exist; `crm_verifier` holds both).

---

## 1. Context — the contract the client already speaks

The `crm_case` client feature (`data/verification`, `domain/verification`,
`features/crm_case`) already calls:

- `GET /verification/queue` → `{items: [VerificationQueueItem]}` — a compact, SLA/risk-sorted
  list: `attendanceId, carpenterName, campaignName, age (Duration), band (MatchBand),
  referenceSource, assigneeId?`.
- `GET /verification/cases/<id>` → `VerificationCase`: `attendanceId, version (optimistic-lock
  token), status (AttendanceStatus), carpenterName, carpenterIdMasked, campaignName,
  sessionName, capturedAt, capturedImageUrl (short-lived signed URL), machine (MachineResult),
  referenceImageUrl?`.
- `POST /verification/cases/<id>/decision` — body `{outcome (VerificationOutcome), reason,
  supervisorOverride}` with header `If-Match: <expectedVersion>`; the response is ignored.

`MachineResult` = `{band (MatchBand: high/medium/low/noReference), referenceSource, reasons[]}`
— advisory only (the human sees the band + reasons, never a raw score). `VerificationOutcome`
= `{approved, rejected, returnForRecapture, escalated}`.

The `attendance` table (4a) has **no `version` column**, carpenters carry a nullable
`thumbnail_url` (the reference-photo source), and the client's `mapDioError` currently maps
`409 → conflict`. These three facts shape the decisions below.

---

## 2. Decisions

### 5a.D1 — Move the verification wire enums to `campaign_contracts`

The client consumes these on the wire, so — as 3a did for `SessionStatus` — they move to the
shared package with SCREAMING_SNAKE `wireValue` + `tryParseWire` (null on unknown, never a
default):

- `AttendanceStatus` → `NOT_CAPTURED, PENDING_SYNC, MATCH_PROCESSING, CRM_REVIEW, APPROVED,
  REJECTED, RETURNED` (the deferred 4a move — 5a is its first wire consumer).
- `MatchBand` → `HIGH, MEDIUM, LOW, NO_REFERENCE`.
- `ReferenceSource` → its existing members in SCREAMING_SNAKE.
- `VerificationOutcome` → `APPROVED, REJECTED, RETURN_FOR_RECAPTURE, ESCALATED`.

The client's domain files re-export these from contracts (shims); the verification repo parses
every one via `tryParseWire`, with a visible non-default fallback (an unknown status/band is
surfaced, never silently read as e.g. `approved`).

### 5a.D2 — A deterministic machine-check adapter, run synchronously in the confirm

A pure `MachineCheck` interface with a deterministic **stub** implementation (real 1:1
face-match / PAD is ML that swaps in behind the interface later):

```
MachineResult check({required bool hasReference}) =>
  hasReference
    ? (band: MEDIUM, referenceSource: <the carpenter's>, reasons: ['Face comparison inconclusive — manual review'])
    : (band: NO_REFERENCE, referenceSource: NONE, reasons: ['No reference photo on file']);
```

It runs **inside 4a's `AttendanceRepo.confirm`**, in the same transaction, after the
attendance is persisted: it computes the `MachineResult` (from whether the carpenter has a
`thumbnail_url`), stores it on the attendance, and sets `status = 'CRM_REVIEW'` (replacing the
4a `MATCH_PROCESSING` literal). A real 4a capture therefore flows straight into the 5a queue —
one live pipeline. `MATCH_PROCESSING` remains a valid vocabulary member (a transient the real
async adapter will use) but is no longer a resting state for a stub that is instant.

The stub band is `MEDIUM`/`NO_REFERENCE` — always routing to `CRM_REVIEW` (5a is the human
review flow; auto-approve-on-`HIGH` is a later policy, not 5a). Nothing auto-approves.

### 5a.D3 — Optimistic locking via `If-Match` → **412 Precondition Failed**

The decision is a conditional request: `If-Match: <version>`. The server compares it to the
attendance's current `version`; on mismatch it returns **`412 PRECONDITION_FAILED`** — the
RFC-correct response to a failed `If-Match` (validated by research: `412` is for a failed
precondition header; `409` is for intrinsic state conflicts *without* one). On match it
transitions status, writes the decision, and bumps `version`. This refines the client, whose
`mapDioError` gains a `412 → FailureKind.conflict` arm so the `crm_case_conflict` flow still
surfaces a conflict message. (This differs deliberately from the campaign lifecycle's
body-version `409 CONFLICT_STALE_VERSION`: that endpoint takes the version in the body, not an
`If-Match` header, so its mechanism — and code — legitimately differ.)

### 5a.D4 — Case read is authenticated + audited-on-view; media read is a bearer-less signed URL

`GET /verification/cases/<id>` requires `verification_decide` **and** `sensitive_media_view`,
is org-scoped (D7 404 out-of-org), and **writes an audit-on-view row** (`verification.case_viewed`)
recording the verifier (actor), the attendance id (target), and the correlation id — the
compliance record of who viewed the sensitive evidence (research-validated fields). It mints
short-lived HMAC-signed READ URLs (4a's `signed_url` helper) for `capturedImageUrl` and, when
the carpenter has one, `referenceImageUrl`. A new **`GET /media/<id>?exp&sig`** (bearer-less,
signature-verified — the same capability model as 4a's upload, since the client's `<img>`
fetch carries no token) serves the `media_objects` bytes. Audit-on-view lives on the
authenticated case GET, not the bearer-less media GET, because only the former knows the actor.

### 5a.D5 — Decisions: approve/reject only; reason required for reject

`POST /verification/cases/<id>/decision` (`verification_decide`): `approved → APPROVED`,
`rejected → REJECTED`. A `rejected` decision with no `reason` is `422 DECISION_REASON_REQUIRED`.
`returnForRecapture`, `escalated`, and `supervisorOverride` are **5b**: 5a rejects them with
`422` (an explicit "not supported yet" rather than a silent half-transition). Each accepted
decision writes a `verification_decisions` row (verifier, outcome, reason, version-at-decision,
correlation) and an `audit_events` row, in one transaction with the status+version update.

### 5a.D6 — RBAC and org scope

`verification_decide` gates all three endpoints; `GET /verification/cases/<id>` additionally
requires `sensitive_media_view` (the evidence). Everything is org-scoped through the
attendance → campaign → organization join; a case outside the caller's org is `404`. The media
GET is authorized solely by its HMAC signature (bearer-less).

---

## 3. The wire contract

New error codes (`campaign_contracts` `error_codes.dart`):

- `preconditionFailed` → `PRECONDITION_FAILED` (HTTP **412**) — stale `If-Match`.
- `decisionReasonRequired` already exists (422) and is reused for a reason-less reject; if its
  current wording is campaign-specific, keep the code and let the message carry context.
- `verificationOutcomeUnsupported` → `VERIFICATION_OUTCOME_UNSUPPORTED` (HTTP **422**) — a
  `returnForRecapture`/`escalated` decision or a `supervisorOverride` in 5a.

### Endpoints

| Method | Path | Auth | Success |
|---|---|---|---|
| GET | `/verification/queue` | `verification_decide` | `200 { "items": [QueueItem] }` |
| GET | `/verification/cases/<id>` | `verification_decide` + `sensitive_media_view` | `200 VerificationCase` (+ audit-on-view) |
| POST | `/verification/cases/<id>/decision` | `verification_decide`, `If-Match` | `200 VerificationCase` (updated) |
| GET | `/media/<id>?exp&sig` | HMAC signature | `200` (image bytes) |

`VerificationCase`/`QueueItem` wire shapes match the client models verbatim (camelCase keys;
`status`/`band`/`referenceSource` as SCREAMING_SNAKE `wireValue`; `age` as an integer of
seconds — matching the client's `Duration` parse; image URLs are the signed `/media/<id>` URLs;
`carpenterIdMasked` never exposes the raw id, per 2a.D2).

---

## 4. Data model — migration `008_verification`

```
ALTER TABLE attendance ADD COLUMN version                INTEGER NOT NULL DEFAULT 1;
ALTER TABLE attendance ADD COLUMN assignee_id            TEXT REFERENCES staff_users(id);
ALTER TABLE attendance ADD COLUMN machine_band           TEXT;   -- MatchBand wire, null pre-check
ALTER TABLE attendance ADD COLUMN machine_reference_src  TEXT;   -- ReferenceSource wire
ALTER TABLE attendance ADD COLUMN machine_reasons        JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE TABLE verification_decisions (
  id                   TEXT PRIMARY KEY,
  attendance_id        TEXT        NOT NULL REFERENCES attendance(id) ON DELETE CASCADE,
  verifier_id          TEXT        NOT NULL REFERENCES staff_users(id),
  outcome              TEXT        NOT NULL,      -- VerificationOutcome wire (APPROVED/REJECTED in 5a)
  reason               TEXT,
  supervisor_override  BOOLEAN     NOT NULL DEFAULT FALSE,
  version_at_decision  INTEGER     NOT NULL,
  correlation_id       TEXT,
  decided_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX verification_decisions_attendance_idx ON verification_decisions(attendance_id);
CREATE INDEX attendance_status_idx ON attendance(organization_id, status);  -- queue reads
```

The machine result lives as columns on `attendance` (one result per attendance; no separate
table needed for a single advisory verdict). `attendance_status_idx` backs the queue's
`WHERE status = 'CRM_REVIEW'` scan.

---

## 5. Server components

- `packages/campaign_contracts/lib/src/` — `match_band.dart`, `reference_source.dart`,
  `verification_outcome.dart`, move `attendance_status.dart`; `error_codes.dart` +
  `preconditionFailed`, `verificationOutcomeUnsupported` (+ tests).
- `server/lib/src/infra/error_envelope.dart` — map `preconditionFailed` → 412,
  `verificationOutcomeUnsupported` → 422.
- `server/lib/src/verification/machine_check.dart` (new) — the `MachineCheck` interface + the
  deterministic stub (pure, unit-tested).
- `server/lib/src/attendance/attendance_repo.dart` (modify) — the confirm runs `MachineCheck`,
  stores the result, sets `CRM_REVIEW` (the machine-check step is the only 4a change).
- `server/lib/src/verification/verification_repo.dart` + `verification_routes.dart` (new) —
  queue (org-scoped, `CRM_REVIEW`, ordered by band severity then `captured_at`), case
  (org-scoped, mints signed media URLs, audit-on-view), decision (`If-Match` → 412, approve/
  reject transaction, `verificationOutcomeUnsupported` for the rest).
- `server/lib/src/media/media_routes.dart` (modify) — add the bearer-less signed
  `GET /media/<id>` read endpoint (reusing `verifyUploadSignature`/a read variant); its leg
  stays outside `authenticate` like `/media/upload`.
- `server/lib/src/media/signed_url.dart` (modify if needed) — a `signReadUrl`/reuse so the case
  endpoint mints `GET /media/<id>?exp&sig`.
- `server/lib/src/app.dart` — mount the verification leg (`verification` root, authenticated).
- `server/lib/src/db/migrations/embedded.dart` — `008_verification`.
- `server/lib/src/seed/seed_routes.dart` — seed `CASE_E2E` (a `CRM_REVIEW` attendance + media +
  a carpenter reference) and `CASE_CONFLICT` (already-decided / version-bumped so its decision
  412s).

Org scope, audit, and the confirm transaction all follow the established patterns
(`writeTx` inside the decision/confirm tx; `row(...)` for every read; `Sql.named` params).

---

## 6. Client, mock, and e2e

**Client** (a modernization slice, like 3a — not zero-change like 4a):
- `AttendanceStatus`/`MatchBand`/`ReferenceSource`/`VerificationOutcome` re-export from
  contracts; the verification repo parses via `tryParseWire` with visible fallbacks.
- `mapDioError` gains a `412 → FailureKind.conflict` arm (so the decision-conflict surfaces as
  a conflict, matching the `crm_case_conflict` flow's expectation).
- The `crm_case` UI already renders the case/queue/decision; verify its wire reads match and
  the `crm_submit`/`crm_outcome_*`/`crm_reason` ids the flows drive are intact.

**Mock** (`tool/mock_server`) — update `/verification/queue`, `/verification/cases/<id>`, and
the decision to the ratified SCREAMING_SNAKE wire and the `412` conflict; keep the `CASE_E2E`
and `CASE_CONFLICT` fixtures. Parity pins the three shapes + the `412`-on-stale-`If-Match`.

**Seed** — `CASE_E2E` (a real `CRM_REVIEW` attendance with a machine result, evidence blob, and
a carpenter that has a reference photo) and `CASE_CONFLICT` (same, but its stored `version` is
already ahead of what a fresh GET hands the client — so the decision 412s deterministically).

---

## 6a. Validated dependencies and patterns

Confirmed by web research during design; fold into the plan verbatim.

- **`If-Match` optimistic locking returns `412 Precondition Failed`, not `409`.** `412` is the
  RFC response to a failed conditional (`If-Match`) header; `409` is for intrinsic state
  conflicts without a precondition header. The client sends `If-Match`, so `412` is the correct
  pairing; the client maps `412 → conflict`. (The campaign lifecycle's body-version conflict
  legitimately stays `409` — a different mechanism.)
- **Audit-on-view of sensitive/biometric evidence records actor + target + action + timestamp
  + correlation**, and belongs on the authenticated case read (which knows the verifier), not
  the bearer-less media fetch. This is the compliance record of who viewed the evidence.
- **Short-lived HMAC-signed READ URLs for private media** reuse 4a's capability model: the
  `<img>` fetch carries no bearer, so the signed URL is the authorization; the read endpoint
  verifies the signature and serves the bytes.
- **The machine check is an adapter (ports/adapters):** a deterministic stub behind an
  interface, so a real ML matcher swaps in without touching the queue/case/decision code.

Sources: 409-vs-412 for optimistic concurrency (dev-toolbox, howhttpworks 412, rest-discuss
optimistic-locking thread); sensitive/biometric audit-logging fields (hoop.dev biometric audit
logging; polygraf AI audit trails).

---

## 7. E2E and seeding

The existing `crm` config's two flows, moved to the **real service**:
- `crm_case_decision.yaml` — open `CASE_E2E`, read the case + evidence + "Machine recommendation
  (advisory)", pick `crm_outcome_approved`, submit → the attendance is `APPROVED`.
- `crm_case_conflict.yaml` — open `CASE_CONFLICT`, approve with a reason, submit → the stale
  `If-Match` yields `412`, surfaced as a conflict.

Both sign in for real as `crm_verifier` (holds `verification_decide` + `sensitive_media_view`).
The `crm` matrix config flips to `useMock: '0'` (with `E2E_REAL_AUTH=true --dart-define=
ROLE=crm_verifier`); `run_maestro_flows.sh`'s `POST /__test__/reset` reseeds `CASE_E2E` +
`CASE_CONFLICT` before each flow. Where the case/decision controls or the machine-recommendation
text lack stable ids/assertable copy for Maestro, add id-driven `Semantics` — the 2a/2b/3a/4a
hardening.

---

## 8. Testing strategy

- **Contract** — round-trip + SCREAMING_SNAKE + unknown→null for the four moved enums; error
  codes incl. `PRECONDITION_FAILED` (412) and `VERIFICATION_OUTCOME_UNSUPPORTED` (422).
- **`machine_check` unit tests** — `hasReference` → `MEDIUM`/`NO_REFERENCE`; deterministic.
- **`attendance` confirm** — a confirm now lands the attendance in `CRM_REVIEW` with a machine
  result (extend the 4a confirm tests, keeping the idempotent-replay and evidence-required
  cases green).
- **Verification route integration** (real Postgres):
  - queue lists `CRM_REVIEW` cases org-scoped, band-then-age ordered; a cross-org campaign's
    attendance never appears; 403 without `verification_decide`.
  - case returns the shape with signed `/media/<id>` URLs; **an audit-on-view row is written**;
    403 without `sensitive_media_view`; 404 cross-org.
  - the signed media GET serves bytes for a valid signature, 403 for a bad/expired one.
  - decision: approve → `APPROVED` (+ decision row + version bump + audit); reject with reason →
    `REJECTED`; reject without reason → 422 `DECISION_REASON_REQUIRED`; a stale `If-Match` →
    **412** (the load-bearing optimistic-lock test) and no state change; `returnForRecapture`/
    `escalated`/`supervisorOverride` → 422 `VERIFICATION_OUTCOME_UNSUPPORTED`; 401/403.
  - **falsification** — two decisions racing on one case: the first bumps `version`, the second
    (stale `If-Match`) is 412, never a second transition.
- **Client** — verification repo parses SCREAMING_SNAKE + the unknown-fallback; `mapDioError`
  maps 412 → conflict; the crm_case widget tests stay green.
- **Parity** — mock and real agree on the three shapes + the 412 conflict.
- **Whole-suite guard** — the Flutter baseline moves only by this slice's tests.

---

## 9. Out of scope (named to be excluded)

- **`returnForRecapture` (the recapture loop) and `escalated`**, and their status side effects —
  sub-project 5b (recapture overlaps 4c's attempt lineage).
- **Supervisor override** (`verification_override`) — 5b.
- **Real SLA/risk queue prioritisation, assignment/claim workflow** — 5a orders by band+age; the
  richer model is 5b.
- **A real ML matcher / PAD** — 5a ships the deterministic stub behind the `MachineCheck`
  interface.
- **`nid_reveal`** (revealing the raw national id, audited) — a later CRM slice.
- **Media encryption-at-rest, retention, real object storage** — sub-project 4b (5a reuses 4a's
  Postgres-BYTEA + signed-URL model unchanged).
