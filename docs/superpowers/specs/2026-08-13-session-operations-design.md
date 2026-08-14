# Session Operations (sub-project 3a) — Design

**Scope:** the first slice of **sub-project 3 — Campaign lifecycle depth** (foundation
spec §2). 3a delivers *session operations* only: reading a campaign's sessions and
driving each session through its operational lifecycle (start / pause / close-capture).
The other two deliverables of sub-project 3 — the changed-field diff endpoint and
correction history — are a separate later slice (3b) and are named here only to be
excluded.

**Goal:** back the campaign-detail **Sessions tab** — which already renders Start /
Pause / Close-capture controls and per-session cards — with real `campaign_service`
endpoints, replacing the `tool/mock_server` those controls hit today, and modernise the
session status vocabulary to the ratified contract shape (SCREAMING_SNAKE, no
silent-default parsing) the way sub-project 2a did for `CampaignStatus`.

**Depends on:** sub-project 1 (foundation: campaigns, `campaign_sessions` table, auth/RBAC,
org scope, error envelope, audit) and 2a (registrations, `campaign_contracts` conventions).
Nothing here depends on attendance (4) or verification (5).

**Related decisions inherited from the foundation:** D2 (no ORM / no codegen), D7
(out-of-scope resources return 404, never 403), the SCREAMING_SNAKE wire rule, the
"unknown enum values never resolve to a default" rule, and the fixed claim vocabulary
(no `session_*` permission exists).

---

## 1. Context — what exists, and the gap

The `campaign_sessions` table shipped in the foundation (`001_foundation`): `id`,
`campaign_id`, `venue`, `capacity`, `start_at`, `end_at`, `status` (default `'PLANNED'`).
The campaign wizard writes sessions with a delete-and-reinsert on create/update
(`campaign_repo.dart` `_replaceSessions`) — and that INSERT does **not** set `status`, so
every wizard-created session is `'PLANNED'`.

There is **no read endpoint and no operation endpoint** for sessions. The real service
exposes only `GET /sessions/<id>/registrations` (a 2a roster). `GET /campaigns/<id>/sessions`
returns 404 today (confirmed in the W-07 e2e backend log), so the campaign-detail
controller folds that error to an empty list, and the Sessions tab's Start/Pause/Close
controls only work against the mock.

The **client already speaks a session contract** (`lib/data/session/session_repository_impl.dart`):

- `GET /campaigns/<id>/sessions` → `{ "items": [ SessionView, … ] }`
- `POST /sessions/<id>/start | pause | close` → a single `SessionView`
- `CampaignSession` fields: `id, campaignId, venue, status, startAt, endAt, capacity,
  registeredCount, pendingSyncCount, reviewCount, approvedCount, readinessOk`.

Two things about that client contract are **wrong by the foundation's own rules** and are
corrected here:

1. `_fromJson` matches `SessionStatus.values.firstWhere((s) => s.name == j['status'])` —
   it expects the **camelCase Dart enum name** on the wire (`"active"`, `"captureClosed"`),
   not the mandated SCREAMING_SNAKE.
2. That `firstWhere` uses `orElse: () => SessionStatus.upcoming` — the exact silent-default
   anti-pattern the foundation forbids ("unknown enum values never resolve to a default"),
   the same one 2a removed from `campaign_dto.dart`.

`registeredCount / pendingSyncCount / reviewCount / approvedCount` are *attendance-activity*
counts. Their real per-session source is attendance (sub-project 4, which is per-session)
and verification (sub-project 5). 2a's `registrations` are **campaign-scoped** (`PRIMARY KEY
(campaign_id, carpenter_id)`, no `session_id`), so there is no honest per-session count to
compute in 3a.

---

## 2. Decisions

### 3a.D1 — `SessionStatus` moves to `campaign_contracts`, SCREAMING_SNAKE, no default

A new `packages/campaign_contracts/lib/src/session_status.dart`:

```
enum SessionStatus { upcoming, active, paused, captureClosed, completed }
```

with `String get wireValue` mapping to `UPCOMING / ACTIVE / PAUSED / CAPTURE_CLOSED /
COMPLETED` and `static SessionStatus? tryParseWire(String)` returning `null` on anything
unrecognised. This is the identical move 2a made for `CampaignStatus` and 2b for
`ImportStatus`: the wire value is the contract, the Dart name is an implementation detail,
and an unknown value is surfaced explicitly rather than silently downgraded.

`lib/domain/session/campaign_session.dart` re-exports `SessionStatus` from the contracts
package (a shim, so the ~handful of importers are untouched) and keeps the `CampaignSession`
freezed model and its `overCapacity` getter.

**Client unknown-status policy.** `SessionRepositoryImpl._fromJson` parses via
`tryParseWire`. An unrecognised wire status is **not** silently mapped to `upcoming`
(which would enable the Start button on a session in an unknown state). Instead the row is
kept but rendered **non-operational**: it maps to `captureClosed` — the most conservative,
action-disabling state — and a `debugPrint` names the raw wire value, exactly the visible-
fallback discipline `ImportStatus` parsing uses. A session is never dropped from the list
for an unknown status (unlike a dry-run row, a session is the operational unit itself).

### 3a.D2 — Session status machine, driven by three client actions

Legal transitions (pure, no IO — a `session_machine.dart` sibling of `status_machine.dart`):

| Action | From | To | Preconditions |
|---|---|---|---|
| `start` | `UPCOMING`, `PAUSED` | `ACTIVE` | readiness (3a.D4) holds |
| `pause` | `ACTIVE` | `PAUSED` | — |
| `close` | `ACTIVE`, `PAUSED` | `CAPTURE_CLOSED` | — |

`CAPTURE_CLOSED` is the operational terminal a user can reach: capture for that session is
done. `COMPLETED` is **not** reachable by any client action (3a.D3). "Resume" in the client
is simply `start` from `PAUSED`, so it needs no distinct verb.

### 3a.D3 — `COMPLETED` is campaign-derived and dormant in 3a

A session flips to `COMPLETED` only when its campaign completes. There is no campaign
activation/completion endpoint yet (the foundation's `status_machine` notes ACTIVE/PAUSED/
COMPLETED are "reachable in the lifecycle but driven" by machinery not built), so the
cascade has no trigger in 3a. We ship the rule as a repo helper —
`completeSessionsForCampaign(campaignId)` flipping every non-terminal session to
`COMPLETED` — ready for the campaign-activation slice to call, and `COMPLETED` is a valid
member of the vocabulary and the machine. It is exercised by a direct unit test on the
helper, not by an endpoint, in 3a.

### 3a.D4 — Readiness = approved/active campaign + venue + start time

`readinessOk` is server-computed and true iff **all** of:

- the session's campaign status is `APPROVED` or `ACTIVE`, and
- the session has a non-empty `venue`, and
- the session has a non-null `start_at`.

The client disables Start when `readinessOk` is false (and shows a "Readiness" warning
chip), so this boolean *is* the UI precondition for starting. The `start` endpoint
**independently** re-checks the same rule server-side (defense in depth): a start request
whose readiness fails is rejected with `SESSION_NOT_READY`, never trusted from the client.

Capacity- and timing-window refinements are deliberately deferred to attendance (4).

### 3a.D5 — `campaign_create` gates writes; reads are any org member

The claim vocabulary has no `session_*` permission and is fixed by the client (inventing
one breaks sign-in). Session write operations (`start`/`pause`/`close`) reuse
**`campaign_create`** — the campaign owner operating their own campaign's sessions,
consistent with "Add registrations" and "Bulk import" on the same campaign-detail screen.
`GET /campaigns/<id>/sessions` requires only authentication and is org-scoped: a campaign
outside the caller's organization returns **404** (D7), never 403.

Field capture (sub-project 4) may later broaden write access to `attendance_capture`; that
is a named consideration for 4, not a 3a change.

### 3a.D6 — Activity counts are `0` in 3a

`registeredCount / pendingSyncCount / reviewCount / approvedCount` are returned as `0`. They
are honestly zero — no attendance has been captured — and sub-project 4 (attendance,
per-session) fills them with real data. 3a does **not** add `session_id` to `registrations`
(2a made registrations campaign-scoped on purpose; conflating registration intent with
session-occurrence attendance is 4's model to define) and does **not** attribute
campaign-level registration counts to sessions (wrong for any multi-session campaign).

### 3a.D7 — Transitions are enforced by an atomic conditional UPDATE, not read-then-write

Each operation is a single compare-and-swap:

```
UPDATE campaign_sessions
   SET status = @to
 WHERE id = @id
   AND campaign_id IN (SELECT id FROM campaigns WHERE organization_id = @org)
   AND status = ANY(@allowedFrom)
RETURNING …
```

The `status = ANY(@allowedFrom)` guard makes the legal-transition check and the write one
atomic operation: the first of two concurrent `start`s wins, the second matches zero rows
rather than racing a stale read. Sessions therefore need **no `version` column** — the
status CAS is the concurrency control (unlike campaigns, whose broader field edits use
optimistic `version`).

On **zero rows updated**, disambiguate with one existence-scoped read:

- session not found in the caller's org → **404 `NOT_FOUND`**;
- session exists and is **already in the action's target state** (e.g. `start` on an
  `ACTIVE` session) → **200** with the current `SessionView` — an idempotent, double-tap-safe
  no-op;
- session exists in some other, incompatible state (e.g. `start` on `CAPTURE_CLOSED`) →
  **409 `SESSION_INVALID_TRANSITION`**, message naming the current state;
- `start` specifically, when the state is startable but readiness fails →
  **422 `SESSION_NOT_READY`** (checked before the CAS so the message is precise).

Every successful operation writes an `audit_events` row (`session.started` /
`session.paused` / `session.capture_closed`) with actor, session id, campaign id and the
request correlation id.

---

## 3. The wire contract

New error codes in `campaign_contracts` `error_codes.dart`:

- `sessionInvalidTransition` → `SESSION_INVALID_TRANSITION` (HTTP 409)
- `sessionNotReady` → `SESSION_NOT_READY` (HTTP 422)

### Endpoints

| Method | Path | Auth | Success |
|---|---|---|---|
| GET | `/campaigns/<id>/sessions` | authenticated, org-scoped | `200 { "items": [SessionView] }` |
| POST | `/sessions/<id>/start` | `campaign_create` | `200 SessionView` |
| POST | `/sessions/<id>/pause` | `campaign_create` | `200 SessionView` |
| POST | `/sessions/<id>/close` | `campaign_create` | `200 SessionView` |

The action endpoints are addressed by session id (`/sessions/<id>/<action>`), matching the
client contract already shipped; the read is campaign-nested. `<id>` on the action routes is
still org-scoped through the campaign join in the UPDATE (a cross-org session id → 404).

### `SessionView` wire shape

```json
{
  "id": "…", "campaignId": "…", "venue": "…",
  "status": "UPCOMING",            // SessionStatus.wireValue
  "startAt": "2026-08-01T09:00:00.000Z",  // ISO-8601 UTC or null
  "endAt": null,                          // ISO-8601 UTC or null
  "capacity": 60,
  "registeredCount": 0, "pendingSyncCount": 0,
  "reviewCount": 0, "approvedCount": 0,   // all 0 in 3a (3a.D6)
  "readinessOk": true
}
```

Field names are camelCase (matching the client's `_fromJson` and the rest of the wire);
only enum *values* are SCREAMING_SNAKE. `venue` is non-null on the wire (the client types it
`String`); a null DB venue is emitted as `""` and makes `readinessOk` false.

---

## 4. Session status machine

`server/lib/src/campaign/session_machine.dart` — pure, no IO, unit-tested in isolation like
`status_machine.dart`:

- `Set<SessionStatus> allowedFrom(SessionAction action)` → the legal source states above.
- `SessionStatus targetOf(SessionAction action)` → `ACTIVE / PAUSED / CAPTURE_CLOSED`.
- `bool isReady({required CampaignStatus campaignStatus, required String? venue,
  required DateTime? startAt})` → the 3a.D4 rule.

The machine holds the vocabulary of `{start, pause, close}` and the readiness predicate; it
owns no SQL and no HTTP. The repo maps a zero-row CAS to the 404/200/409/422 outcomes of
3a.D7; the route maps those to the error envelope. Wire values live only in
`campaign_contracts`.

---

## 5. Server components

**Files**

- Create `packages/campaign_contracts/lib/src/session_status.dart` + barrel export; extend
  `error_codes.dart` with the two codes; tests.
- Create `server/lib/src/campaign/session_machine.dart` (+ test).
- Create `server/lib/src/campaign/session_repo.dart` — `SessionRepo`:
  - `Future<List<SessionView>> listForCampaign(String campaignId, {required String organizationId})`
    — org-scoped SELECT; activity counts hard-coded 0; `readinessOk` computed by joining the
    campaign's status.
  - `Future<SessionTransition> apply(SessionAction action, {required String sessionId,
    required String organizationId, required String actorId, String? correlationId})` —
    the atomic CAS + zero-row disambiguation + audit write, returning a small result type the
    route turns into 200 / 404 / 409 / 422.
  - `Future<void> completeSessionsForCampaign(String campaignId)` — the dormant 3a.D3 helper.
- Create `server/lib/src/campaign/session_routes.dart` — `Router sessionRouter({required Db db})`
  wiring the four endpoints, `requirePermission('campaign_create')` on the three writes.
- Modify `server/lib/src/app.dart` — add the session leg to the Cascade under the `campaigns`
  and `sessions` roots (authenticated), mirroring how the participant leg is mounted.
- Modify `server/lib/src/db/migrations/embedded.dart` — a new migration `006_session_status`:
  `ALTER TABLE campaign_sessions ALTER COLUMN status SET DEFAULT 'UPCOMING';` and
  `UPDATE campaign_sessions SET status = 'UPCOMING' WHERE status = 'PLANNED';` The wizard's
  reinsert keeps relying on the (new) default, so no `campaign_repo` write change is needed —
  but a test pins that a freshly created campaign's sessions read back `UPCOMING`.
- Modify `server/lib/src/seed/seed_routes.dart` — seed one session for `seed-camp-1`
  (`UPCOMING`, a venue, a `start_at`) so the e2e and the client have a session to operate.

**Audit.** `session.started/paused/capture_closed` rows via the existing `AuditWriter`,
inside the same transaction as the status write (an operation and its audit trail commit
together, as 2b's import commit does).

**Org scope.** Every read and every CAS scopes through `campaigns.organization_id`; a session
whose campaign is in another org is indistinguishable from a missing one (404).

---

## 6. Client and mock changes

**Client**

- `lib/domain/session/campaign_session.dart` — import `SessionStatus` from
  `campaign_contracts` (re-export shim); keep `CampaignSession` + `overCapacity`.
- `lib/data/session/session_repository_impl.dart` — `_fromJson` parses status with
  `SessionStatus.tryParseWire`, applying the 3a.D1 unknown-status policy (fallback to
  `captureClosed`, `debugPrint` the raw value) instead of `orElse: upcoming`.
- The campaign-detail `_SessionCard` already enables/disables Start/Pause/Resume/Close by
  status; verify it matches the machine (Start on `upcoming`|`paused`, Pause on `active`,
  Close on `active`; a `captureClosed`/`completed` card shows no operation). Small widget
  tests pin this and the disabled-Start-when-`!readinessOk` gate.

**Mock (`tool/mock_server`)** — update session status wire values to SCREAMING_SNAKE and the
action mapping (`start→ACTIVE`, `pause→PAUSED`, `close→CAPTURE_CLOSED`), seed a session with
`status: "UPCOMING"`. The contract parity test (established in 2b) pins that the mock and the
real service emit the same session shapes and status vocabulary.

---

## 6a. Validated dependencies and patterns

Confirmed by web research during design; fold these into the plan verbatim so the
implementer does not re-derive them.

- **Atomic state transition = conditional UPDATE … RETURNING.** `UPDATE … SET status=@to
  WHERE id=@id AND status = ANY(@allowedFrom) RETURNING …` is the recommended race-safe
  state-machine primitive in Postgres: the guard and the write are one atomic step, the first
  concurrent writer wins, and losers match zero rows rather than overwriting a stale read.
  Distinguishing "no row" (404) from "wrong state" (409) needs one follow-up existence read —
  there is no single-statement way to get both the transition result and the not-found reason.
- **Idempotency stance for action endpoints.** A repeated action that finds the resource
  *already in the target state* returns 200 with the current representation (double-tap /
  retry safe); an action from a genuinely incompatible state returns 409 with a message that
  names the current state ("Cannot start a session whose capture is closed"), not a bare
  "Conflict". This matches REST state-transition guidance and keeps the client's optimistic
  UI from surfacing spurious errors on a fast double tap.
- **No `version` column for sessions.** The status CAS subsumes optimistic locking for the
  only field these endpoints mutate; a `version` column would be dead weight here (campaigns
  keep theirs because they mutate many fields at once).

Sources: PostgreSQL `UPDATE … RETURNING` atomicity thread; the Interlock atomic-transition
pattern; REST idempotency/safety and 409-state-conflict guidance.

---

## 7. E2E and seeding

A new Maestro flow `.maestro/flows/session_ops.yaml` (tag `session_ops`), real service,
`useMock: '0'`, real-auth APK — the 2a/2b pattern:

1. Sign in for real as `campaign_creator` (holds `campaign_create`).
2. Open the seeded `ACSL Pilot Carpenter Drive` campaign → **Sessions** tab.
3. The seeded session renders (`UPCOMING`, readiness OK).
4. Tap **Start** → assert the card shows the active state (a stable, asserted headline/chip).
5. Tap **Pause** → assert paused.
6. Tap **Start** (resume) → assert active again.
7. Tap **Close capture** → assert capture-closed and that the operation controls are gone.

A new CI matrix config `sessionOps` (blocking emulator gate, `--dart-define=E2E_REAL_AUTH=true`,
`useMock '0'`) plus — optionally, following 2b — the non-blocking Maestro Cloud pilot tag.
`run_maestro_flows.sh`'s `POST /__test__/reset` reseeds the session before the flow, so one
run's Start/Close can't leak into the next.

The Sessions-tab controls need stable ids/asserted text; where the current `_SessionCard`
lacks them (the status chip text, the operation buttons), add id-driven Semantics — the same
hardening 2a's registration flow and 2b's import flow required for Maestro's merged-node
geometry.

---

## 8. Testing strategy

- **Contract unit tests** — `session_status` round-trip + SCREAMING_SNAKE + unknown→null;
  error-code round-trip.
- **`session_machine` unit tests** — every legal and illegal (action, from-state) pair; the
  readiness predicate across campaign status × venue × start_at.
- **`session_repo` / route integration tests** (real Postgres, the foundation harness):
  - `GET` lists a campaign's sessions org-scoped; a cross-org campaign → 404; counts are 0.
  - each action's happy path flips status and returns the updated view;
  - the atomic-CAS outcomes: idempotent 200 on already-in-target; 409 on incompatible state
    with a stateful message; 404 on unknown/cross-org id; 422 `SESSION_NOT_READY` when start's
    readiness fails; 403 without `campaign_create`; 401 unauthenticated.
  - an audit row is written per successful operation.
  - `completeSessionsForCampaign` flips non-terminal sessions to `COMPLETED` and leaves
    terminal ones untouched (the dormant-cascade unit test).
  - **falsification**: a concurrency test firing two `start`s at one `UPCOMING` session asserts
    exactly one transitions and the other is the idempotent 200 (or 409), never two writes.
- **Client** — `session_repository_impl` parses SCREAMING_SNAKE, applies the unknown-status
  fallback (not `upcoming`), and posts to `/sessions/<id>/<action>`; `_SessionCard` widget
  tests for the per-status control gating and the readiness-disabled Start.
- **Parity** — mock and real emit identical session shapes/vocabulary.
- **Whole-suite guard** — the Flutter baseline count moves only by the tests this slice adds.

---

## 9. Out of scope (named to be excluded)

- **Changed-field diff endpoint and correction history** — sub-project 3b.
- **Campaign activation/completion** (what would actually *drive* `COMPLETED`) — a later
  slice of sub-project 3; 3a ships the dormant cascade helper only.
- **Real per-session activity counts** — sub-project 4 (attendance); 3a returns 0.
- **`attendance_capture` write access to sessions** — a consideration for sub-project 4.
- **Session CRUD** (creating/editing sessions) — already owned by the campaign wizard
  (`campaign_repo._replaceSessions`); 3a only reads and transitions them.
- **Capacity enforcement / timing windows on start** — deferred to attendance (4).
