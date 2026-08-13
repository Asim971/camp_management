# Sub-project 2b — Async bulk import (W-07)

**Date:** 2026-08-13 · **Scope:** second half of sub-project 2 of 8 (see the foundation
spec `2026-08-10-campaign-service-foundation-design.md` §2). Sub-project 2 was split into
**2a (carpenter identity + registrations, shipped — PR #7, merge `23efc4d`)** and **2b
(this spec, async bulk import)**. 2b builds directly on 2a's carpenter master: every
import row is classified and committed through 2a's `ParticipantRepo` matching and
registration paths.

**Depends on:** sub-projects 1 and 2a (both merged to `main`). Inherits their API
conventions, middleware chain, error envelope, idempotency machinery, migration
discipline, the carpenter master (`carpenters`/`registrations`/`profile_requests`), the
PII-masking chokepoint (`CarpenterView`), and the staged e2e cut-over state.

---

## 1. Why this exists

The Flutter app ships a Bulk Import screen (W-07) and the repository behind it — both
speaking HTTP to `tool/mock_server` routes that fabricate fixed results synchronously and
were never ratified. This slice makes the server the authority for bulk registration
import, ratifies those wire shapes as an **asynchronous job lifecycle**, and cuts the
client over to it.

It is the natural continuation of 2a: an import row resolves against the same carpenter
master 2a built. A matched row registers like a 2a basket entry; an unmatched row creates
a provisional carpenter through 2a's exact profile-request path, then registers.

### The client defect class this slice closes again

`ImportRepositoryImpl._fromJson`/`_rowFromJson` parse `status` and `outcome` with
`firstWhere(orElse: () => ImportStatus.dryRun)` / `orElse: () => ImportRowOutcome.error`
— the same silent-default-on-unknown defect removed from `campaign_dto` (slice 1) and
`RegistrationRepositoryImpl` (2a). Both are fixed in the cut-over.

---

## 2. Scope

**In:**

- Async dry-run engine: `POST /campaigns/{id}/imports/dry-run` (multipart CSV) validates
  the file, writes a durable `processing` job, returns **202 + jobId**; an in-process
  background task parses and classifies each row against the carpenter master; a
  stuck-job reaper fails jobs orphaned by a restart.
- Poll: `GET /imports/{jobId}` returns status, progress, and row outcomes.
- Commit: `POST /campaigns/{id}/imports/{jobId}/commit` registers the committable set
  (`valid` + `needsProfile`) in one idempotent transaction, each row reconciled to a
  registration.
- Migration `005_imports`: `import_jobs`, `import_job_rows`.
- Contracts: `ImportStatus` and `ImportRowOutcome` move into `campaign_contracts` with
  wire vocabularies (full enums ship; only the implemented transitions occur). New
  `ApiErrorCode.importFileInvalid` (422).
- Client cut-over: a `FileSource` seam (real `file_selector` + E2E fake injecting a
  bundled CSV), a polling controller, explicit enum parsing, the commit path namespaced
  under `/campaigns/{id}/`.
- Mock server updated to the ratified async shapes, pinned by parity tests.
- New Maestro flow `bulk_import.yaml` green against the real service in CI.

**Out (→ 2c, a named follow-up slice):** partial-completion commit
(`partiallyCompleted`), per-row retry of eligible failed rows, job cancel (`cancelled`),
per-row deselection in the commit UI, reconciliation *history* records, versioned
template download, masked result download / expiring source downloads, malware/AV
scanning. File *validation* (type, size, encoding, schema) covers the PRD's "unsafe
file" acceptance criterion pragmatically; AV scanning has no infrastructure in a
Dart pilot and is not stubbed as if it did.

**Out (→ later sub-projects):** the reconciliation/duplicate-suppression engine and
adjudication queue (8); attendance and its vocabulary (4).

**Implemented `ImportStatus` transitions:** `processing` → `readyToCommit` (dry-run
classified) → `completed` (committed); `failed` (dry-run or commit failed wholesale, or
a reaped orphan). **Shipped-but-unused this slice:** `dryRun`, `partiallyCompleted`,
`cancelled` (the wire vocabulary is complete so 2c needs no contract change).

---

## 3. Decisions

### 2b.D1 — In-process background task, not a claim-loop worker

The dry-run handler validates the file, writes the job (`processing`) and its rows in one
transaction, returns 202, and kicks an **unawaited** background task. The task opens its
**own `Db` connection** — the shared single connection cannot be held for a multi-row
classify without blocking request serving (the same reason `parity_test.dart` opens
separate connections). Pilot files are hundreds of rows; classification is seconds, so
"async" here is about the contract and durable lifecycle, not long-running work.

Rejected: a durable claim-loop worker (multi-replica-ready, more moving parts) — the
service is single-replica (slice 1 deferred `pg_advisory_xact_lock` to "before any
multi-replica deploy"); and synchronous-under-async-contract (contradicts 2a's
full-async-lifecycle decision — no real processing/progress states).

### 2b.D2 — A restart is survived by a reaper, not by claiming

An in-process task dies with its process. A job left in `processing` with `claimed_at`
older than a fixed TTL (5 minutes — longer than any pilot file's classify, shorter than a
user's patience) is flipped to `failed` by a bounded opportunistic sweep on each
dry-run/poll — the exact idempotency-reservation-TTL shape from 2a's Task 1. A failed
job is recoverable by re-uploading. Multi-replica job claiming is a named 2c/ops
follow-up.

### 2b.D3 — The raw file is not persisted; only its hash

`import_jobs.file_hash` is the SHA-256 of the uploaded bytes (replay detection, audit).
Rows are parsed into `import_job_rows` and that is the durable record. No file-download
surface exists (the PRD's masked/expiring downloads are 2c), so there is nothing to
persist the raw bytes for, and not persisting them is the safer default (2a.D2's spirit:
sensitive data does not linger).

### 2b.D4 — Row identity is the file line number

`row_id` is derived from the 1-based data-line number (`row-1`, `row-2`, …), stable and
deterministic (PRD "deterministic row identity"), so a re-upload of the same file
produces the same row ids and the idempotent commit produces zero duplicate
registrations.

### 2b.D5 — Commit registers `valid` + `needsProfile`, all-or-nothing

The committable set is exactly `valid` (matched an in-org master carpenter) plus
`needsProfile` (no match — commit creates a provisional carpenter via 2a's exact
`createProfileRequest` path, then registers). `duplicate`/`unauthorized`/`error` are never
committable. The whole commit is one transaction: any row failing rolls it all back — no
partial state this slice (`partiallyCompleted` and per-row retry are 2c). Idempotent by
the job-scoped key: a replayed commit registers each row at most once (PRD acceptance
criterion).

`WARNING` (valid-but-flagged, e.g. an ineligible master match) is shipped in the
vocabulary but **not produced** by this slice's classifier — the eligibility-caveat rule
lands with the richer commit UI in 2c. This keeps the committable set unambiguous
(`valid` + `needsProfile`) rather than introducing a third partly-committable state now.

Rejected: valid-only commit (a fresh-list import would commit nothing and be nearly
useless); the `needsProfile` path reuses 2a logic verbatim, so the added scope is small.

---

## 4. Deliverables

| id | Deliverable |
|---|---|
| 2b-A | Migration `005_imports`: `import_jobs`, `import_job_rows` |
| 2b-B | `ImportStatus`/`ImportRowOutcome` wire vocabulary in `campaign_contracts` + `IMPORT_FILE_INVALID`; app shims |
| 2b-C | CSV parse + validate + row classification (`ImportRepo`, reusing `ParticipantRepo`) |
| 2b-D | Async dry-run engine: 202 + durable job + in-process task + reaper |
| 2b-E | `GET /imports/{jobId}` poll |
| 2b-F | `POST /campaigns/{id}/imports/{jobId}/commit` idempotent committable-set registration |
| 2b-G | Client cut-over: `FileSource` seam, polling controller, explicit enum parsing, namespaced commit |
| 2b-H | Mock ratified async shapes + parity tests |
| 2b-I | `bulk_import.yaml` Maestro flow + bundled CSV + `bulkImport` CI config, green against the real service |

---

## 5. Wire contract

Paths inherit slice-1 conventions (Bearer auth, error envelope with stable `code`,
correlation id, out-of-scope 404 per D7, UTC ISO-8601).

| Method + path | Auth | Behaviour |
|---|---|---|
| `POST /campaigns/{id}/imports/dry-run` | `bulk_import` | multipart field `file`. 404 out-of-scope campaign. 400 `BAD_REQUEST` for a missing/empty file part. 422 `IMPORT_FILE_INVALID` for a present-but-bad file (wrong type, over the 2 MB cap, non-UTF-8, missing required header column) — no job created. Else **202** `{job}` with status `PROCESSING`, `totalRows`, rows present with `outcome` null. |
| `GET /imports/{jobId}` | `bulk_import` | Org-scoped (job's `organization_id` vs caller's). 404 out of scope. `{job}` with status, `processedRows`/`totalRows`, and rows (each with masked carpenter fields when linked). |
| `POST /campaigns/{id}/imports/{jobId}/commit` | `bulk_import` | Idempotent via the standard middleware (job-scoped key). 404 out-of-scope campaign/job. 409 if the job is not `READY_TO_COMMIT`. Registers the committable set in one transaction; 200 `{job}` status `COMPLETED`. |

`bulk_import` is already in the client's fixed claim vocabulary (held by
`campaign_creator`, `admin`) — invent nothing.

**Job wire shape:**

```json
{
  "id": "…", "campaignId": "…", "status": "PROCESSING",
  "totalRows": 5, "processedRows": 2,
  "rows": [
    {"rowId": "row-1", "name": "…", "outcome": "VALID",
     "message": null, "linkedCarpenterId": "…"}
  ]
}
```

`outcome` is null until a row is classified. Row wire fields carry masked identifiers
only when a carpenter is linked; the raw phone/nid from the CSV never appear on the wire
(2a.D2).

**Contract package changes** (`packages/campaign_contracts`):

- `ImportStatus` → `DRY_RUN`, `READY_TO_COMMIT`, `PROCESSING`, `COMPLETED`,
  `PARTIALLY_COMPLETED`, `FAILED`, `CANCELLED` (SCREAMING_SNAKE, distinct,
  round-tripping, unknown → null). Moves in behind the re-export shim; the app's
  `lib/domain/common/status.dart` re-exports it, same pattern as `RegistrationStatus`.
- `ImportRowOutcome` → `VALID`, `WARNING`, `DUPLICATE`, `NEEDS_PROFILE`, `UNAUTHORIZED`,
  `ERROR`. Moves from `lib/domain/import/import_job.dart` into the contracts package,
  re-exported. Unknown → null.
- `ApiErrorCode.importFileInvalid` → `IMPORT_FILE_INVALID` (HTTP 422).

**CSV schema** (2b defines it; neither the mock nor the client had one):

- A header row is required. Required columns: `name`, `phone`. Optional: `nid`,
  `territory`, `dealer_context`. Column order is free; matching is by header name
  (case-insensitive, trimmed).
- A missing required header column → `IMPORT_FILE_INVALID`, no job created.
- Each data line becomes one `import_job_rows` row with `row_id = "row-<1-based line>"`.

---

## 6. Data model — migration `005_imports`

Transactional, forward-only, embedded as a Dart const, applied after `004_identity` by
the advisory-locked runner (2a's Task 2).

```sql
CREATE TABLE import_jobs (
  id               TEXT PRIMARY KEY,
  campaign_id      TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  status           TEXT NOT NULL,              -- ImportStatus wire value
  filename         TEXT NOT NULL,
  file_hash        TEXT NOT NULL,              -- sha256 of the bytes (2b.D3)
  total_rows       INTEGER NOT NULL DEFAULT 0,
  processed_rows   INTEGER NOT NULL DEFAULT 0,
  config_version   TEXT,                       -- app_config version at classify (audit)
  uploaded_by      TEXT NOT NULL REFERENCES staff_users(id),
  claimed_at       TIMESTAMPTZ,                -- worker start; reaper input (2b.D2)
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX import_jobs_campaign_idx ON import_jobs(campaign_id);
CREATE INDEX import_jobs_status_claimed_idx ON import_jobs(status, claimed_at);

CREATE TABLE import_job_rows (
  job_id               TEXT NOT NULL REFERENCES import_jobs(id) ON DELETE CASCADE,
  row_id               TEXT NOT NULL,          -- "row-<1-based line>" (2b.D4)
  name                 TEXT NOT NULL,
  phone                TEXT NOT NULL,          -- raw; never leaves the server (2a.D2)
  nid                  TEXT,
  territory_hint       TEXT,
  dealer_context       TEXT,
  outcome              TEXT,                   -- ImportRowOutcome, NULL until classified
  message              TEXT,                   -- neutral, non-accusatory (PRD §2.1)
  linked_carpenter_id  TEXT REFERENCES carpenters(id),
  PRIMARY KEY (job_id, row_id)
);
```

**Engine (2b.D1/D2):**

1. **dry-run handler.** Read the multipart bytes; validate type (CSV), size (≤ 2 MB —
   hundreds of name/phone rows is a few KB, so the cap is generous headroom, not a real
   limit), encoding (UTF-8), and header (required columns present) — a failure is
   `IMPORT_FILE_INVALID` (422), no job. On success: parse each data line,
   `INSERT` the job (`PROCESSING`, `claimed_at = now()`, `total_rows = n`) and all rows
   (`outcome` null) in one transaction; return **202** `{job}`. Kick an unawaited
   background task (2b.D1). The reaper (bounded sweep) runs first: any `PROCESSING` job
   with `claimed_at <= now() - 5 min` → `FAILED`.
2. **background task.** Opens its own `Db` connection. For each row: classify against the
   carpenter master (org-scoped `ParticipantRepo` matching), write `outcome`/`message`/
   `linked_carpenter_id`, bump `processed_rows`. On completion flip to `READY_TO_COMMIT`;
   on an unexpected fault flip to `FAILED`. Audit event on terminal (`import.dry_run`,
   correlation id, job id, counts — no PII).
3. **poll.** Org-scoped read; 404 out of scope; returns the job + rows.
4. **commit handler.** Behind `requirePermission('bulk_import')` → `idempotency`. Load
   the job (404 if out of scope; 409 if not `READY_TO_COMMIT`). In one transaction:
   for each committable row (`valid`/`needsProfile` — see 2b.D5), resolve or create the
   carpenter (2a's `createProfileRequest` path for `needsProfile`), `INSERT` the
   registration `ON CONFLICT DO NOTHING`, set `linked_carpenter_id`. Flip the job to
   `COMPLETED`. Audit (`import.commit`, counts, correlation id). Return 200 `{job}`.

---

## 7. Enforcement

The slice-1 middleware chain is reused unchanged. All three endpoints require
`bulk_import`; there is no read-only import role, and the client already gates W-07 on
`bulkImport`. Org scope applies to every query (jobs are org-owned). Territory scope
remains documented-only, consistent with slice 1's partial D-E.

---

## 8. Client cut-over (2b-G)

- **`FileSource` seam** mirroring `CaptureSource`: `abstract interface class FileSource`
  with `RealFileSource` (the existing `file_selector` `openFile` for CSV) and
  `FakeFileSource` (returns a bundled asset CSV). `fileSourceProvider` returns the fake
  under `config.e2e`, the real impl otherwise — exactly `captureSourceProvider`. The
  bulk-import screen's inline `openFile()` moves behind this provider.
- **`ImportRepositoryImpl`:** the commit path becomes `/campaigns/{id}/imports/{jobId}/
  commit`; `_fromJson`/`_rowFromJson` parse `status`/`outcome` via the contracts'
  `tryParseWire` with explicit unknown handling (no `firstWhere orElse`). A new
  `poll(jobId)` calls `GET /imports/{jobId}`.
- **`ImportController`:** `uploadDryRun` keeps the 202 job, then polls `GET /imports/
  {jobId}` every ~1 second until a terminal state (`readyToCommit`/`failed`) or a ~30-second
  timeout (pilot files classify in seconds; the timeout surfaces a stuck job as an error
  rather than spinning forever); `ImportState` carries `processedRows`/`totalRows`
  progress. `commit` is unchanged in shape but hits the
  namespaced path and uses a per-call UUID idempotency key (the current `jobId`-as-key is
  fine for a job-scoped op, but a UUID matches 2a's fix and avoids leaking the id into
  header logs).
- **`ImportJob.committable`** updates from `count(valid)` to `count(valid) +
  count(needsProfile)` (+ `warning`), matching 2b.D5.
- **Mock server:** ratified async shapes — dry-run returns 202 + a job a subsequent poll
  reports `READY_TO_COMMIT`; commit → `COMPLETED`. Parity tests pin the job shape, both
  vocabularies, and mask formats on both backends.

---

## 9. Testing and acceptance

- Server: unit + integration suites green locally and on `postgres:16` in CI. New suites
  cover parse/validate, classification (each of the six outcomes against seeded master
  data), the async task (dry-run → poll → readyToCommit), the reaper (a stale
  `PROCESSING` job → `FAILED`), and commit (committable-set registration, idempotent
  replay = zero duplicates, 409 when not ready).
- Contracts: `ImportStatus`/`ImportRowOutcome` round-trip + unknown-value tests;
  `IMPORT_FILE_INVALID` wire/status test.
- Parity: mock and real agree on every pinned contract point.
- App: `flutter analyze --fatal-infos` clean; test count does not regress; new repository
  tests cover the poll loop, explicit enum parsing, and the namespaced commit; a widget
  test drives the polling UI through the processing → ready → committed lifecycle.
- e2e: a bundled `assets/e2e/bulk_import_sample.csv` (rows spanning `valid`, `duplicate`,
  `needsProfile`, `error`) drives `.maestro/flows/bulk_import.yaml`: real-auth login →
  open a seeded campaign's bulk import → `FakeFileSource` injects the CSV → upload →
  **poll to `readyToCommit`** → review outcome counts → commit → `completed`. New
  `bulkImport` CI matrix config against the real service; the existing staged matrix stays
  green. Seed fixtures gain a carpenter that makes one sample row a `duplicate` and one a
  master match. The flow is authored with the 2a-hardened idioms (semantics ids, `.*`
  wraps on merged nodes, `hideKeyboard` only after real input, no back-navigating stray
  hideKeyboard, and — being a poll flow — an explicit wait/assert for the terminal state
  rather than a fixed sleep).

---

## 10. Non-goals

Partial-completion commit, per-row retry, cancel, per-row commit deselection,
reconciliation history, template/result downloads, AV scanning (all 2c). Reconciliation/
dedup engine and adjudication (8). Attendance (4). Multi-replica job claiming (ops
follow-up, with slice 1's deferred advisory lock). Pagination of the row table (the
pilot renders a short list; virtualization when a real dataset demands it).

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| An in-process task orphaned by a restart leaves a job stuck in `PROCESSING`. | The reaper (2b.D2) fails it after 5 minutes; re-upload recovers. Named multi-replica follow-up. |
| The background task's connection contends with request serving. | It opens its own `Db` connection (2b.D1); the request-serving connection is never held by classify. |
| A large/malicious file exhausts memory or blocks. | Size cap + type/encoding validation reject before a job exists; AV scanning is an explicit 2c non-goal, not a false stub. |
| The CSV file-picker cannot be driven by Maestro. | The `FileSource` seam injects a bundled CSV under E2E (mirrors the fake camera); the async/poll/commit path — the real risk — gets true end-to-end proof. |
| Poll flakiness on CI's short viewport / timing. | The flow waits on the terminal-state assertion, not a fixed sleep; authored with 2a's hardened Maestro idioms. |
| Silent enum defaults reach the UI (the historical defect). | Explicit `tryParseWire` on both enums; unknown → visible, never a default. |

---

## 12. Follow-ups this spec does not close

- **2c:** partial-completion commit, per-row retry of eligible failed rows, cancel,
  per-row deselection, reconciliation history, template/result downloads.
- Multi-replica job claiming (advisory lock / claim timeout) — with slice 1's deferred
  `pg_advisory_xact_lock`.
- AV/malware scanning — needs infrastructure the pilot lacks.
- The 2a-carried follow-ups remain: territory-scope enforcement, `syncStatus` badge,
  registration lifecycle transitions, and the campaign-detail narrow-viewport overflow
  the 2a e2e surfaced.
