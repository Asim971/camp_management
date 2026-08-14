# Attendance Capture Round-Trip (sub-project 4a) — Design

**Scope:** the first slice of **sub-project 4 — Attendance and evidence** (foundation spec
§2). 4a delivers the *online capture round-trip* only: the four server endpoints the field
capture flow already calls — consent notices, media presign, media upload, and idempotent
attendance confirm — so the **unchanged** client runs its capture against the real
`campaign_service` instead of `tool/mock_server`. Media hardening (real object storage,
encryption-at-rest, retention) is slice **4b**; attempt lineage / recapture is slice **4c**;
both are named here only to be excluded.

**Goal:** stand up `GET /consent/notices`, `POST /media/presign`, `PUT /media/upload/<id>`,
and `POST /attendance/<key>/confirm` on the real service, persisting an attendance record
(with its consent record and evidence blob) so `field_online_capture` — the presign → upload
→ confirm drain the offline sync engine already performs — goes green against the real
service. This is a **server-only** slice: the client already speaks every endpoint.

**Depends on:** sub-project 1 (auth/RBAC, org scope, error envelope, idempotency middleware,
audit), 2a (carpenters), and 3a (sessions — attendance attaches to a session). Nothing here
depends on verification (5).

**Inherited constraints (foundation):** D2 (no ORM / no codegen), D7 (out-of-scope → 404),
SCREAMING_SNAKE wire values, the fixed claim vocabulary (`attendance_capture` exists, held by
`field_user`), and the idempotency middleware (`Idempotency-Key`, already used by the campaign
decision and the import commit).

---

## 1. Context — the capture drain the client already performs

Capture is offline-first. `camera_capture` writes an encrypted evidence blob to a private
dir and a durable `attendance_drafts` row, then enqueues a `SyncTaskSpec` (type `attendance`,
`idempotencyKey` = a client UUID = the attendance id). The offline **sync engine** drains it
through `core/sync/sync_uploader.dart` `DioSyncUploader._uploadAttendance`, which performs,
all carrying `Idempotency-Key: <key>`:

1. `POST /media/presign` `{ "attendanceId": "<key>" }` → `{ "url": "<uploadUrl>" }`.
2. `PUT <uploadUrl>` — the encrypted bytes, `application/octet-stream`, via a **fresh
   `Dio()` with no interceptors and no bearer token** (this is the presigned-URL idea: the
   URL itself is the authorization).
3. `POST /attendance/<key>/confirm` — body is the capture payload; **the response is
   ignored** (`post<void>`). A `409` on this call is treated as success (idempotent replay).

The confirm payload (from `capture_controller.dart`):

```json
{
  "encryptedMediaPath": "<client-local path, server ignores>",
  "sessionId": "…", "carpenterId": "…",
  "capturedAt": "…ISO8601…", "capturedBy": "<userId>",
  "consentVersion": 1, "consentLanguage": "en",
  "consentShownAt": "…ISO8601…", "consentContentHash": "<hash of the notice shown>"
}
```

There is **no `campaignId`** (the server derives it from the session) and **no geolocation**
(not in the client payload). `GET /consent/notices` is `NoticeRepository.fetchLatest`, which
expects `{ "notices": [ ConsentNotice, … ] }`; it is a background refresh, off the capture
path (capture uses a bundled notice), and today 404s because nothing implements it.

The "Match processing" state the field flow asserts comes from the client's **local**
offline-queue task label (`offline_queue_screen.dart`), set after a successful drain — **not**
parsed from the confirm response. So 4a needs no wire `AttendanceStatus` and no client change.

---

## 2. Decisions

### 4a.D1 — A server-only slice; the client is unchanged, `AttendanceStatus` does not move

The client already calls all four endpoints and ignores the confirm response. 4a implements
them on the real service, updates the mock to match, seeds a consent notice, and moves the
capture flow's CI config off `USE_MOCK`. No app code changes. Unlike `SessionStatus` in 3a,
`AttendanceStatus` is **not** moved to `campaign_contracts`: nothing parses an attendance
status off the wire in 4a. It moves in sub-project 5, when verification reads and transitions
it. The server stores the status as the literal string `'MATCH_PROCESSING'`.

### 4a.D2 — Evidence bytes live in Postgres `BYTEA`; presign returns the server's own upload URL

A `media_objects` table holds the (already client-encrypted) bytes as `BYTEA`. Web research
confirms `BYTEA` is the appropriate choice for evidence-sized blobs (a few MB) in a
single-Postgres, "one backup restores everything" system; its costs (table bloat, backup
size, cache pressure) are exactly what push it to object storage **later** — that move, plus
server-side encryption-at-rest and retention/expiry, is **4b**. `presign` returns a URL
pointing at the service's own `PUT /media/upload/<id>`, built from the request `Host` so the
emulator (`10.0.2.2:8080`) and the Cloud tunnel both reach it.

### 4a.D3 — The upload URL is a short-lived HMAC-signed capability (not an unauthenticated PUT)

The client PUTs with a bearer-less `Dio()`, so `PUT /media/upload/<id>` cannot require a
token. An upload endpoint guarded only by an unguessable id is a documented
storage-exhaustion (DoS) / pollution vector (validated by research). So the *URL itself* is
the capability: `POST /media/presign` (authenticated, `attendance_capture`) returns
`…/media/upload/<id>?exp=<unixSeconds>&sig=<hmac>` where `sig = HMAC-SHA256(key, "<id>.<exp>")`
and `key` is derived from the server's existing secret (`ServerConfig.jwtSecret`, via a fixed
context string — **no new required env var**). The upload endpoint recomputes the HMAC,
constant-time-compares it, and checks `exp` is in the future; a bad or expired signature is
`403`. TTL is short (15 minutes) — presign and PUT are back-to-back in the drain. This is the
correct presigned-URL pattern done self-contained: the authorization to write bytes is minted
by an authenticated request and expires, without an external object store. Real object-store
signed URLs replace this in 4b; the client is agnostic (it PUTs to whatever URL it is given).

### 4a.D4 — Confirm derives scope from the session, requires the evidence, and is idempotent

`POST /attendance/<key>/confirm` (authenticated, `attendance_capture`):

1. Loads the `session` **org-scoped** (join `campaigns.organization_id` = the actor's org);
   a session outside the org, or unknown, is `404` (D7). `campaign_id` comes from that session.
2. Requires the `carpenter` to exist in the org (`404` otherwise).
3. Requires the `media_objects` row for `<key>` to exist — i.e. the upload landed. If not,
   `422 ATTENDANCE_EVIDENCE_MISSING` (the client always uploads first, so this only fires on
   a malformed/out-of-order call).
4. Persists — in **one transaction** — the `attendance` row (id `<key>`, org, campaign,
   session, carpenter, `media_ref = <key>`, `status = 'MATCH_PROCESSING'`, `captured_by`,
   `captured_at`) and its `consent_records` row (notice version, language, content hash,
   shown-at), and writes an `audit_events` row (`attendance.captured`).
5. Returns `{ "status": "MATCH_PROCESSING", "id": "<key>" }`.

Idempotency is the **existing** `Idempotency-Key` middleware (the client sends the header):
a replay returns the stored `2xx` response, which the client treats as success. No new
matching, PAD, or 1:1 comparison happens in 4a — the record simply lands in
`MATCH_PROCESSING`; the actual verification pipeline is sub-project 5.

### 4a.D5 — RBAC

`attendance_capture` (held by `field_user`) gates `POST /media/presign` and
`POST /attendance/<key>/confirm`. `PUT /media/upload/<id>` is **signature-gated, not
bearer-gated** (4a.D3). `GET /consent/notices` is authenticate-only (any org member; it is a
background refresh, and the vocabulary has no consent-specific permission).

### 4a.D6 — No matching, PAD, geofence, or 1:1 in 4a

The confirm records evidence and consent and returns `MATCH_PROCESSING`. Face matching,
presentation-attack detection, geofence evaluation, integrity-flag derivation, and the
`MATCH_PROCESSING → CRM_REVIEW/APPROVED/REJECTED` transitions are verification concerns
(sub-project 5). 4a stores what the client sends and stops.

---

## 3. The wire contract

### New error codes (`campaign_contracts` `error_codes.dart`)

- `attendanceEvidenceMissing` → `ATTENDANCE_EVIDENCE_MISSING` (HTTP 422) — confirm references
  a media object that was never uploaded.

(An invalid/expired upload signature reuses `forbidden` → 403; an out-of-org session/carpenter
reuses `notFound` → 404. No `AttendanceStatus` codes — that vocabulary lands in sub-project 5.)

### Endpoints

| Method | Path | Auth | Success |
|---|---|---|---|
| GET | `/consent/notices` | authenticated | `200 { "notices": [ConsentNotice] }` |
| POST | `/media/presign` | `attendance_capture` | `200 { "url": "<signed upload url>" }` |
| PUT | `/media/upload/<id>` | HMAC signature (query) | `200` |
| POST | `/attendance/<key>/confirm` | `attendance_capture` + `Idempotency-Key` | `200 { "status":"MATCH_PROCESSING", "id":"<key>" }` |

`ConsentNotice` wire: `{ "version": <int>, "language": "en"|"bn", "title": "…", "body": "…",
"contentHash": "…" }` — matching `ConsentNotice.fromJson` (the client reads `version` and
`language`; extra fields are ignored, so `title`/`body`/`contentHash` are additive).

Field names are camelCase; only enum values (here just the stored `status` literal) are
SCREAMING_SNAKE.

---

## 4. Data model — migration `007_attendance`

```
consent_notices
  version           INT      NOT NULL
  language          TEXT     NOT NULL        -- 'en' | 'bn'
  title             TEXT     NOT NULL
  body              TEXT     NOT NULL
  content_hash      TEXT     NOT NULL
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
  PRIMARY KEY (version, language)

media_objects                                 -- no org column: written by an
  id                TEXT PRIMARY KEY           --   unauthenticated (signed) PUT with
  content_type      TEXT NOT NULL              --   no org context; org scope is
  bytes             BYTEA NOT NULL             --   enforced at confirm via the
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()  -- attendance that links it

attendance
  id                TEXT PRIMARY KEY           -- == idempotency key == media id
  organization_id   TEXT NOT NULL REFERENCES organizations(id)
  campaign_id       TEXT NOT NULL REFERENCES campaigns(id)
  session_id        TEXT NOT NULL REFERENCES campaign_sessions(id)
  carpenter_id      TEXT NOT NULL REFERENCES carpenters(id)
  media_ref         TEXT NOT NULL             -- media_objects.id (== id in 4a)
  status            TEXT NOT NULL              -- 'MATCH_PROCESSING' in 4a
  captured_by       TEXT NOT NULL REFERENCES staff_users(id)
  captured_at       TIMESTAMPTZ NOT NULL
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
  INDEX (organization_id, session_id)

consent_records
  id                TEXT PRIMARY KEY
  attendance_id     TEXT NOT NULL REFERENCES attendance(id) ON DELETE CASCADE
  notice_version    INT  NOT NULL
  language          TEXT NOT NULL
  content_hash      TEXT NOT NULL
  shown_at          TIMESTAMPTZ NOT NULL
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
```

`media_objects` deliberately has no `organization_id`: it is written by the bearer-less
signed PUT, which has no auth context. Orphaned blobs (uploaded, never confirmed) are inert —
4b adds retention cleanup. `attendance.media_ref` + the org-scoped `attendance` row are what
tie an evidence blob to an organization.

---

## 5. Server components

**Files**

- `packages/campaign_contracts/lib/src/error_codes.dart` — add `attendanceEvidenceMissing`
  (+ tests).
- `server/lib/src/infra/error_envelope.dart` — map `attendanceEvidenceMissing` → 422.
- `server/lib/src/media/signed_url.dart` (new) — `String signUploadUrl({required String host,
  required String id, required DateTime now})` and `bool verifyUploadSignature({required
  String id, required int exp, required String sig, required DateTime now})`, keyed off
  `ServerConfig.jwtSecret` via a fixed context string; pure, unit-tested (no IO).
- `server/lib/src/media/media_repo.dart` + `media_routes.dart` (new) — `POST /media/presign`
  (mint the signed URL), `PUT /media/upload/<id>` (verify signature; upsert the `media_objects`
  row from the raw body). Cap the accepted body size (a sane evidence ceiling, e.g. a few MB)
  → 413/422 on exceed.
- `server/lib/src/attendance/attendance_repo.dart` + `attendance_routes.dart` (new) —
  `POST /attendance/<key>/confirm` (the 4a.D4 transaction), behind `attendance_capture` and
  the idempotency middleware.
- `server/lib/src/consent/consent_routes.dart` (new) — `GET /consent/notices`.
- `server/lib/src/app.dart` — mount the new legs (`media`, `attendance`, `consent`) into the
  Cascade under their roots, authenticated where required; `/media/upload` and
  `/media/presign` and `/consent/notices` and `/attendance` roots added to the relevant
  `_authenticateUnder` sets (except `/media/upload`, which authenticates by signature inside
  the handler, so its leg must NOT be wrapped in `authenticate`).
- `server/lib/src/db/migrations/embedded.dart` — `007_attendance`.
- `server/lib/src/seed/seed_routes.dart` — seed a consent notice (version 1, `en` + `bn`)
  mirroring the client's bundled `assets/consent/notice_v1.json`.

**Config:** no new required env var — the upload-signing key derives from the existing
`JWT_SECRET`. `ServerConfig` gains a derived getter, not a new input.

**Org scope / audit:** the confirm scopes through `campaigns.organization_id`; a cross-org
session or carpenter is a 404. The `attendance.captured` audit row commits in the confirm
transaction.

---

## 6. Client, mock, and seed

**Client — no changes.** 4a is the "unchanged client against the real service" acceptance
(spec §9). `NoticeRepository.refreshInBackground` remains as-is (unwired); capture stays on
the bundled notice. The existing `AttendanceStatus` enum stays in `domain/common/status.dart`.

**Mock (`tool/mock_server`)** — already implements all four endpoints. Align its confirm
response to `{ "status": "MATCH_PROCESSING" }` (SCREAMING_SNAKE) and its presign to return a
plausibly-shaped URL; add `GET /consent/notices` if missing. Parity pins that the mock and the
real service agree on the four shapes (envelope keys + the `MATCH_PROCESSING` status literal).
The mock need not implement real HMAC signing (the client is agnostic); parity asserts body
shapes, not URL signatures.

**Seed** — a consent notice (as above). The 3a-seeded session on `seed-camp-1` and the
2a-seeded carpenter (`Md. Karim`) give the capture flow a real session + carpenter to attend.

---

## 6a. Validated dependencies and patterns

Confirmed by web research during design; fold into the plan verbatim.

- **Postgres `BYTEA` for evidence blobs is appropriate for this MVP.** It cleanly holds a few
  MB; its costs (DB bloat, backup size, buffer-cache pressure) are the reason to move to
  object storage later (4b), not a reason to avoid it now in a single-Postgres,
  one-backup-restores-everything service. Cap the accepted upload size server-side.
- **A presigned upload URL must be a signed, expiring capability — never an unauthenticated
  PUT guarded only by an unguessable id.** The URL-*generating* endpoint stays authenticated;
  the URL carries a short-lived HMAC the upload endpoint verifies. An unauthenticated upload
  endpoint is a documented storage-exhaustion (DoS) / pollution vector. HMAC-SHA256 over
  `id.exp` with a server-held key is the self-contained form (no object store required).
- **Idempotent submit is the existing `Idempotency-Key` middleware.** At-least-once mobile
  drain (the offline queue retries) requires the confirm to dedup by key and replay the stored
  response; a `409`/replayed-`2xx` both read as success on the client. No new mechanism.
- **Two-phase presign → PUT → confirm** is the standard direct-upload shape; its failure mode
  is an orphaned blob (uploaded, never confirmed), which 4a leaves inert and 4b reaps.

Sources: PostgreSQL BYTEA-vs-object-storage guidance (PostgreSQL wiki BinaryFilesInDB, Sling
Academy); presigned-URL security (AWS S3 presigned-URL docs; documenso #2492 missing-auth
finding; files.link presigned-URLs-explained).

---

## 7. E2E and seeding

A new Maestro flow proving the **real-service** capture round-trip: sign in for real as
`field_user` (the `attendance_capture` holder), reach a seeded session + carpenter, capture
(the E2E `FakeCaptureSource` supplies a deterministic image), acknowledge consent, submit, and
assert the offline queue reaches **"Match processing"** — which only happens after a real
`presign → PUT → confirm` against the service. A new **`capture`** CI matrix config runs it
against the real `campaign_service` (`useMock: '0'`, `--dart-define=E2E_REAL_AUTH=true
--dart-define=ROLE=field_user`, a blocking gate). The existing `field` config (which also runs
`field_capture_recapture`) stays on `USE_MOCK` until 4c fully migrates it; 4a moves only the
online round-trip. `run_maestro_flows.sh`'s `POST /__test__/reset` reseeds the notice + session
+ carpenter before the flow.

Where the capture UI's controls or the offline-queue status text lack stable ids/assertable
text for Maestro, add id-driven `Semantics` — the same hardening 2a/2b/3a required.

---

## 8. Testing strategy

- **Contract** — `error_codes` round-trip incl. `ATTENDANCE_EVIDENCE_MISSING`.
- **`signed_url` unit tests** — round-trip sign→verify; a tampered `id`/`exp`/`sig` fails; an
  expired `exp` fails; constant-time compare. **Falsification:** a verify that ignores the
  signature accepts a forged URL — assert it does not.
- **Server integration** (real Postgres, foundation harness):
  - `GET /consent/notices` returns the seeded notice(s); requires auth.
  - `POST /media/presign` returns a URL whose signature the upload endpoint accepts; requires
    `attendance_capture` (403 without); the minted URL's `exp` is in the future.
  - `PUT /media/upload/<id>` stores bytes for a valid signature; **rejects a bad/expired
    signature with 403** (the load-bearing security test); rejects an oversized body.
  - `POST /attendance/<key>/confirm`: happy path persists the attendance + consent rows +
    audit and returns `MATCH_PROCESSING`; a replay (same key) is idempotent (one attendance
    row, stored response returned); a cross-org session or carpenter → 404; a confirm with no
    prior upload → 422 `ATTENDANCE_EVIDENCE_MISSING`; 403 without `attendance_capture`; 401
    unauthenticated.
  - **End-to-end within the suite:** presign → upload → confirm in sequence yields a readable
    attendance row whose `media_ref` resolves to the stored bytes.
- **Parity** — mock and real agree on the four shapes and the `MATCH_PROCESSING` literal.
- **Client** — unchanged; the existing capture/sync tests must stay green (the whole-suite
  count moves only by any test infra 4a adds, which should be none on the client).

---

## 9. Out of scope (named to be excluded)

- **Real object storage, server-side encryption-at-rest, retention/expiry, orphan reaping** —
  sub-project 4b.
- **Attempt lineage / recapture** (`field_capture_recapture`) — sub-project 4c.
- **Face matching, PAD, 1:1 comparison, geofence evaluation, integrity-flag derivation, and
  the `MATCH_PROCESSING → CRM_REVIEW/APPROVED/REJECTED` transitions** — verification,
  sub-project 5. 4a leaves every record in `MATCH_PROCESSING`.
- **Moving `AttendanceStatus` to `campaign_contracts`** — sub-project 5 (first wire consumer).
- **Geolocation capture** — not in the client payload; not added here.
- **Migrating the whole `field` CI config off `USE_MOCK`** — only the online-capture flow moves
  in 4a; recapture keeps the mock until 4c.
