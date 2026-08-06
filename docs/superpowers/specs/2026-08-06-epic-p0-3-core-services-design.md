# Design — Epic P0.3: Core Services

**Status:** Approved (design); implementation plan pending
**Date:** 2026-08-06
**Epic:** [`TASK_BREAKDOWN.md`](../../../TASK_BREAKDOWN.md) → Phase P0 → Epic P0.3 (T-0.3.1 … T-0.3.6)
**Basis:** [`ARCHITECTURE_Flutter.md`](../../../ARCHITECTURE_Flutter.md) §6, §12 (audit, correlation ID) · [UI/UX Guideline v1.0](../../../ACSL_Carpenter_Campaign_Management_UI_UX_Design_Guideline_v1_0.md) §2.1 (correction-first errors), §9, §12

---

## 1. Verified state of the epic

The epic table in `TASK_BREAKDOWN.md` marks P0.3 as scaffolded. Two of six tasks are genuinely complete; two are partial and two are unstarted.

| Task | Verified state | Evidence |
|---|---|---|
| T-0.3.1 `Result`/`Failure` | **Done.** Sealed `Result<T>` with `Ok`/`Err` and `fold`, plus a 10-value `FailureKind` taxonomy. | `lib/core/result/result.dart` |
| T-0.3.2 Dio + interceptors | **Partial.** `buildDio` and `AuthInterceptor` (bearer + 401 refresh seam) exist, and `mapDioError` maps status/transport to `FailureKind`. **Missing: correlation-ID interceptor and retry interceptor** — an explicit in-file TODO. Refresh throws `UnimplementedError` pending T-0.4.1. | `lib/core/network/dio_client.dart:23`, `lib/app/di/providers.dart:68` |
| T-0.3.3 Drift DB | **Partial.** All three v1 tables (`SyncTasks`, `AttendanceDrafts`, `CachedReferences`) exist and are in use. **Missing: `MigrationStrategy`, schema dumps, migration test.** `schemaVersion => 1` with no migration hook of any kind. | `lib/core/storage/app_database.dart:59-60`; no `drift_schemas/` |
| T-0.3.4 Secure storage wrapper | **Not done.** A raw `FlutterSecureStorage` is exposed directly as a provider, and a 20-line `loadOrCreateEvidenceKey` with real failure semantics sits in the composition root. There is no wrapper and no interface to test against. | `lib/app/di/providers.dart:92-131` |
| T-0.3.5 Breakpoints + adaptive scaffold | **Done.** Landed with P0.2. | `lib/core/responsive/breakpoints.dart`, `adaptive_scaffold.dart` |
| T-0.3.6 Client audit emitter | **Not done.** `AuditEvent` and an `AuditSink` interface exist; `AuditSink` has **zero implementations and zero call sites**, and nothing in the repo generates a correlation ID. | `lib/core/audit/audit.dart`; grep for `AuditSink` |

Four defects and loose ends surfaced while verifying, all in files this epic touches:

- **`AuditEvent.correlationId` is a required field with no producer.** `Failure.correlationId` reads one off a response header, so the only correlation ID that can exist today is server-minted, and no client code puts one on a request. Correlation-ID is the spine joining T-0.3.2 and T-0.3.6; neither is complete without it.
- **`mapDioError` loses the correlation ID on transport errors.** It reads only `error.response?.headers`, so a `connectionError` or timeout yields a `Failure` with a null correlation ID — the exact case a user most needs to quote to support.
- **The 401 retry issues its request through a bare `Dio()`.** `auth_interceptor.dart:43` constructs a fresh client with no `baseUrl` and no interceptors to replay `err.requestOptions`. Every repository in `lib/data/` calls relative paths (`/campaigns`, `/verification/queue`), so a successful token refresh would be followed by a request to an unresolvable URL. Latent only because `refreshToken` currently throws before reaching it.
- **`retry: ^3.1.2` is declared in `pubspec.yaml` and imported nowhere** — the same dead-dependency pattern as `workmanager`. `lib/core/sync/backoff.dart` already provides a pure, clock-free, unit-tested `BackoffPolicy` that covers the need better.

## 2. Decisions taken

| # | Decision | Rejected alternatives |
|---|---|---|
| D1 | **Close all four remaining gaps in one epic, with the two 🔒 server-contract touchpoints behind narrow seams** (`AuditTransport`, the existing `AuthInterceptor.refreshToken`). The epic closes; only wire formats stay contract-pending. | Unblocked-only (migrations + secure store + correlation ID) — leaves P0.3 open and T-0.3.6 unstarted for an unbounded period. Folding in T-0.4.1 auth lifecycle — pulls in Epic P0.4 and needs an auth contract that does not exist. |
| D2 | **The audit buffer is a new Drift table in schema v2.** Events survive process death, and the table forces a real v1→v2 migration with a data-survival test, closing T-0.3.3 with evidence rather than an empty hook. | In-memory ring buffer (contradicts "server is authoritative store" for compliance events, and leaves T-0.3.3 with nothing to test). |
| D3 | **A dedicated `AuditFlusher` reusing `BackoffPolicy` but not `SyncEngine`.** Audit and evidence have opposite failure semantics: `SyncEngineImpl` discards after `maxRetries: 8` and surfaces a user-visible failure, which for a compliance record would be silent data loss. Share the policy object, not the queue. | Audit rows inside `sync_task` (one retry budget and one give-up rule for both; batch-of-events fits the one-key-per-task shape badly; drops the v1→v2 migration). Extracting a generic `Outbox<T>` now (best long-term factoring, but reworks the repo's highest-risk tested component — T-2.1.1–2.1.5 — to serve a just-specified second consumer; D2's table sits behind the same `BackoffPolicy`, so the door stays open). |
| D4 | **Two-tier audit API: durable-async `emit`, ack-gated `revealAudited`.** Sensitive media is CRM-web-only and already needs a server round-trip for its signed URL, so there is no offline case to break by blocking on an ack. | Local durability as the gate everywhere (a device lost before flush leaves no server record that a face photo was viewed — weaker than `audit.dart:4`'s stated MUST). Deferring the sensitive-view path to T-3.1.6 (the decision reappears later and the stated MUST stays unbacked). |
| D5 | **`revealAudited` takes the reveal as a callback rather than returning `Result<void>`.** A `Result` the caller must check before revealing fails **open** the first time someone forgets to check it, which is the normal failure mode for a compliance control. Passing the callback in makes showing the value without a successful ack structurally impossible. | `Future<Result<void>> emitAndAwaitAck` matching house style at every other boundary — cheaper to read, fails open. |
| D6 | **Correlation IDs are per-action and passed explicitly**, with the interceptor minting one only when none was supplied. Threading touches the six repository methods that pair with an existing `AuditAction` (§4.1); every other call keeps the interceptor's per-request ID. | Ambient `Zone` values (no call-site plumbing, but Zone values leak or vanish across isolates, timers and Riverpod rebuilds, producing silently wrong traces — the worst failure mode for an audit trail). Per-request only (trivial, but the audit row and the API call it describes get different IDs, so §302's end-to-end trace is not delivered). |
| D7 | **Retry gates non-idempotent methods on an explicit idempotency key**, not on HTTP method semantics alone. | Retrying all of `PUT`/`DELETE` as spec-idempotent — this server's semantics are unconfirmed, and a retried bare `POST /campaigns` on a timeout creates two campaigns, which is precisely when you cannot tell whether the first landed. |
| D8 | **`429` maps to the existing `FailureKind.server`; the taxonomy gains no value.** Retry swallows transient rate-limiting, so a `429` reaches the user only after exhaustion, where "the service is busy, try again" is honest. | Adding `FailureKind.rateLimited` — safe (no exhaustive switch exists) but churns a taxonomy every feature reads for no user-visible gain. |

## 3. Deliverables

1. `lib/core/trace/trace_id.dart` — `TraceId` + `traceOptions()` — the shared leaf D6 needs
2. `lib/core/network/correlation_interceptor.dart` — `CorrelationIdInterceptor`; `mapDioError` gains the `extra` fallback — closes half of T-0.3.2
3. `lib/core/network/retry_interceptor.dart` — `RetryInterceptor` over `BackoffPolicy`; `retry` removed from `pubspec.yaml` — closes T-0.3.2 at D1's scope
4. `lib/core/storage/app_database.dart` — `AuditEvents` table, `schemaVersion => 2`, `MigrationStrategy`; `drift_schemas/` committed — closes T-0.3.3
5. `lib/core/storage/secure_store.dart` + `evidence_key_store.dart` — `SecureStore`, `FlutterSecureStore`, `SecureStoreKeys`, `EvidenceKeyStore` — closes T-0.3.4
6. `lib/core/audit/audit_emitter.dart` + `audit_transport.dart`; `audit.dart` gains `revealAudited` — closes T-0.3.6
7. `AuthInterceptor` 401-retry fix (replay through the configured client, not a bare `Dio()`)
8. `POST /audit/events` in `tool/mock_server/bin/server.dart`
9. `lib/app/di/providers.dart` — wiring, minus the two things moving out

## 4. Component contracts

### 4.1 `TraceId` and interceptor order (T-0.3.2)

`lib/core/trace/trace_id.dart` is a leaf that imports nothing from the app. Both `core/network` and `core/audit` depend on it, which keeps arrows one-way and stops `audit` importing `network` merely to name an ID.

```dart
final class TraceId {
  factory TraceId.generate();
  const TraceId.of(String value);
  final String value;
}

Options traceOptions(TraceId trace, {String? idempotencyKey});
```

Interceptor order becomes `[CorrelationIdInterceptor, AuthInterceptor, RetryInterceptor]`, and the order carries meaning in both directions. Correlation runs first on request so auth and retry both observe the ID. Retry sits last on the error path so `AuthInterceptor` gets first refusal on a 401 — reversed, retry would spend its budget re-sending a request with a stale token.

`CorrelationIdInterceptor` reads `options.extra['traceId']`, mints a fresh `TraceId` if absent, sets `X-Correlation-Id`, and writes the resolved value back into `extra`. `mapDioError` prefers the response header and falls back to `extra`, which is what fixes the null-ID-on-transport-error defect in §1.

**Trace lifecycle.** A user action mints one `TraceId` at the controller layer and passes it to both the repository call and the `AuditEvent`, so the audit row and every HTTP call it caused share an ID.

Exactly six repository methods gain an optional trailing `{TraceId? trace}` — the ones that pair one-to-one with an existing `AuditAction`:

| Method | `AuditAction` |
|---|---|
| `CampaignRepository.createDraft` | `campaignCreated` |
| `CampaignRepository.submitForApproval` | `campaignSubmitted` |
| `CampaignRepository.decide` | `campaignApproved` / `campaignReturned` / `campaignRejected` |
| `RegistrationRepository.register` | `participantRegistered` |
| `ImportRepository.commit` | `bulkImportCommitted` |
| `VerificationRepository.decide` | `verificationDecided` |

Other mutations — `updateDraft`, `requestNewProfile`, `uploadDryRun`, and session `start`/`close`/`pause` — are **not** threaded, because no `AuditAction` exists for them and an action-scoped ID with no audit row to join to buys nothing. They keep the interceptor's per-request ID, so they stay traceable in server logs, and gain a `trace` parameter when and if their audit action is defined. `attendanceCaptured` is emitted by the sync engine, not a repository, and is out of scope (§9).

**What this epic delivers for those six is the plumbing, not the emission.** The `trace` parameter and its propagation land here; the matching `emit` calls belong to the feature tasks that own the actions (T-1.4.2, T-1.6.3, T-3.1.4). So on merge, the parameter is threaded and unit-tested but five of the six paths have no audit row joining to their trace ID yet. The one path proven end-to-end within this epic is `evidenceKeyRotated`, which belongs to a core service rather than a feature. That is the normal shape for a core-services epic — `AuditSink` itself shipped as a consumer-less interface in P0 — but it is stated here so the gap is a known state rather than a surprise during the feature epics.

### 4.2 `RetryInterceptor` (T-0.3.2)

| Aspect | Rule |
|---|---|
| Retryable transport | `connectionError`, `connectionTimeout`, `receiveTimeout`, `sendTimeout` |
| Retryable status | `429`, `502`, `503`, `504` |
| Not retryable | `500`, `501`, and all other 4xx. A `500` may have committed a write and no contract says otherwise |
| Method gate | `GET`/`HEAD` retry freely. `POST`/`PUT`/`PATCH`/`DELETE` retry **only** with `extra['idempotencyKey']`, forwarded as an `Idempotency-Key` header (D7) |
| Delay | `Retry-After` when present; else `BackoffPolicy.delayFor(attempt, jitterSeed: jitterSeedFor(traceId))` |
| Policy | `BackoffPolicy(base: 300ms, maxDelay: 3s, maxRetries: 2, jitterFraction: 0.2)` — worst case under ~7s added latency |
| Testability | The delay is an injected `Future<void> Function(Duration)` seam; tests never sleep |

The policy instance is deliberately **not** the sync engine's. Sync tolerates `maxRetries: 8` over up to five minutes because a field upload can wait; a foreground API call blocking the UI that long is a bug. Same class, different tuning.

The idempotency-key gate is the client half of the 🔒 *server idempotency* contract. `uuid` is already a dependency and `SyncTasks.id` is already a client-generated key, so the generation pattern exists.

**Not consolidated on purpose:** `sync_uploader.dart:85-93` resembles a copy of `mapDioError` but diverges deliberately — it maps `409` to `conflict` meaning *already confirmed, treat as success upstream*. Merging them would break that. The divergence is documented in both files so a later reader does not "clean it up".

### 4.3 Schema v2 and the migration (T-0.3.3)

```dart
class AuditEvents extends Table {
  IntColumn      get seq           => integer().autoIncrement()();
  TextColumn     get id            => text().unique()();
  TextColumn     get action        => text()();
  TextColumn     get entity        => text()();
  TextColumn     get entityId      => text()();
  TextColumn     get correlationId => text()();
  TextColumn     get actorId       => text()();
  TextColumn     get remarks       => text().nullable()();
  DateTimeColumn get occurredAt    => dateTime()();
  IntColumn      get attempts      => integer().withDefault(const Constant(0))();
  TextColumn     get lastError     => text().nullable()();
}
```

`seq` autoincrements as the primary key so flush order is genuinely FIFO: `id` is a UUID and `occurredAt` can tie at millisecond resolution, so neither gives stable ordering. `id` stays unique for server-side dedupe of a retried batch.

`actorId` is stored rather than inferred from the auth token at flush time. Field devices are shared, so an event captured offline by one user can flush after a different user has logged in; attributing it to whoever happens to be holding the phone would corrupt the trail. `occurredAt` is a client-clock value the server should treat as untrusted and pair with its own receipt time.

Rows are deleted on confirmed send. That is what lets the ack-gated path need no extra column: `revealAudited` writes the row, posts inline, deletes on success; a failed post leaves the row simply pending for the flusher to retry.

Migration: `schemaVersion => 2` with `stepByStep(from1To2: (m, schema) => m.createTable(schema.auditEvents))`. The existing three tables are untouched.

**Sequencing constraint for the implementation plan:** `dart run drift_dev schema dump` must capture v1 **before** the code is bumped to v2, or the v1 baseline requires a git checkout to recover. Then `drift_dev schema generate` emits the test helpers and `drift_schemas/` is committed.

### 4.4 `SecureStore` and `EvidenceKeyStore` (T-0.3.4)

```dart
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
```

`FlutterSecureStore` owns the `AndroidOptions(resetOnError: false)` decision currently living as a comment in the composition root — v10 defaults it to `true`, which silently deletes a value it cannot decrypt. `SecureStoreKeys` centralises key names and carries the never-rename warning: renaming abandons any key already on a device, and with it the ability to decrypt evidence encrypted under it. `InMemorySecureStore` lands in `test/support/`, replacing the `mocktail` mock of `FlutterSecureStorage` in `test/app/evidence_key_test.dart`.

**Platform constraint, stated because the platform quietly breaks the implied guarantee:** on web, `flutter_secure_storage_web` is `localStorage` with a wrapped key — **not** hardware-backed. `SecureStore` on web is obfuscation, not protection. Consequences: the evidence AES key stays mobile-only (capture already is), and the CRM web surface must persist nothing whose compromise matters beyond the session.

`EvidenceKeyStore` takes `SecureStore` and `AuditSink`, and emits `AuditAction.evidenceKeyRotated` on the unreadable-key path that today only `debugPrint`s — a case where every previously captured piece of evidence becomes undecryptable and currently leaves no durable trace. The enum has no consumers yet, so adding a value is safe.

Dependency direction: `EvidenceKeyStore` depends on the `AuditSink` *interface* in `audit.dart` (a pure leaf), while the Drift-backed implementation lives in `audit_emitter.dart`. Storage and audit stay acyclic.

### 4.5 `DurableAuditSink` and `AuditFlusher` (T-0.3.6)

```dart
Future<void> emit(AuditEvent event);        // returns on local commit
Future<Result<T>> revealAudited<T>(        // ack-gated (D4, D5)
  AuditEvent event,
  Future<T> Function() reveal,
);
```

**Flush triggers:** batch size (20 events), a 30s periodic timer, connectivity regained (reusing the existing `connectivityStreamProvider`), and app lifecycle pause/detach. A single in-flight guard stops concurrent flushes racing on the same head rows.

**Nothing is ever deleted unsent.** Unlike `SyncEngineImpl`, which discards after `maxRetries: 8` and surfaces a user-visible failure, the flusher has no discard path at all: a row leaves the table only on a confirmed send. Backoff plateaus at `maxDelay` and retries indefinitely. Rows are roughly 200 bytes, so a device offline for weeks costs single-digit megabytes. Above a 20,000-row high-water mark the flusher emits one degraded-state signal rather than dropping anything.

**A poison pill must not block the queue.** FIFO by `seq` means one permanently-rejected row — a malformed event drawing a `400` — would stall every later event forever. The read query is therefore `where attempts < 10 order by seq limit 20`.

These two rules are distinct, and the distinction matters: past ten attempts a row stops being *retried*, but it is never *deleted*. It stays in the table, excluded from the flush window, counted in the high-water-mark signal, and available for diagnostics — so one bad event degrades exactly one record instead of the whole trail, and the record itself is still recoverable. A "no discard" guarantee and an "unbounded retry" guarantee are not the same promise, and only the first is made here.

**The 🔒 seam.** `AuditTransport.send(List<AuditEvent>)`, with `DioAuditTransport` posting `POST /audit/events` as `{events: [...]}` — a placeholder shape flagged contract-pending, as the campaign endpoints already are. Rather than a throwing stub that would fail every dev-mode flush and grow the table, the mock server gains the endpoint so dev and E2E flush for real while the seam stays honest under production config.

**Startup.** The flusher is instantiated eagerly at app bootstrap. Copying `SyncEngine`'s lazy construction (it is created on a feature's first `ref.read` and drains off its connectivity stream) would mean audit only flushes once someone opens the offline-queue screen.

## 5. Error handling

Flush failures never surface to the user and never block a workflow — that is the buffer's entire purpose. If the local Drift write in `emit` fails, the user's action still proceeds; an audit outage must not block a campaign approval.

`revealAudited` is the sole exception and fails **closed**, including on a failed local write. Its `Err` carries the transport failure mapped through `mapDioError`, so the caller receives the real `FailureKind` (`network`, `timeout`, `server`, `unauthorized`) plus the correlation ID rather than an opaque marker — a `403` on the audit endpoint is a permissions problem and must not read the same as a dropped connection. A failed *local* write, which has no `DioException` behind it, yields `Failure(FailureKind.unknown)` with the trace ID attached.

The consuming screen renders one correction-first message per Guideline §2.1 — *"This access could not be recorded, so the photo cannot be shown"* — never a generic error, and never the raw kind. T-3.1.6 owns that screen; this epic ships the mechanism and the `Failure`.

## 6. Testing

All against in-memory Drift and scripted transports; no test sleeps.

| Unit | Assertions |
|---|---|
| `audit_emitter_test.dart` | FIFO order by `seq`; delete-on-success; buffer-on-failure with `attempts`/`lastError` recorded; poison-pill row skipped past threshold and never deleted; `revealAudited` does **not** invoke the callback when the ack fails, does when it succeeds, and writes the row *before* calling the transport; batch-size and connectivity triggers each fire one flush |
| `retry_interceptor_test.dart` | No retry on bare `POST`; retry on `POST` carrying an idempotency key; no retry on `500`; retry on `503`/`429`; `Retry-After` honoured over backoff; exhaustion returns the last error; `GET` retried without a key |
| `correlation_interceptor_test.dart` | Mints when `extra` is empty, preserves a supplied ID, sets `X-Correlation-Id`; `mapDioError` recovers the ID from `extra` on a `connectionError` |
| `storage/migration_test.dart` | Post-migration schema matches v2 **and** pre-existing `sync_task` / `attendance_draft` rows survive with contents intact |
| `secure_store_test.dart` | Round-trip and delete via `InMemorySecureStore`; `SecureStoreKeys` values are stable |
| `evidence_key_test.dart` (rewritten) | Generates on first run; reuses an existing key; the `PlatformException` path regenerates **and** emits `evidenceKeyRotated` |
| `auth_interceptor_test.dart` | After a successful refresh the replayed request resolves against the configured `baseUrl` (the §1 bare-`Dio()` defect) |

The data-survival assertion in the migration test is the one that protects users: a migration that silently drops a queued attendance capture loses field evidence that cannot be recaptured.

Existing coverage that must stay green: `test/core/sync_engine_test.dart`, `test/core/backoff_test.dart` (the retry interceptor reuses `BackoffPolicy` unchanged), and the full 33-test suite.

## 7. Sequence

Each step ends with analyze clean and tests green.

1. `drift_dev schema dump` of **v1** — must precede any schema change (§4.3)
2. `lib/core/trace/trace_id.dart` + `CorrelationIdInterceptor` + the `mapDioError` fallback + tests
3. `RetryInterceptor` + tests; remove `retry` from `pubspec.yaml`; fix the `AuthInterceptor` 401 replay + test
4. `SecureStore` / `SecureStoreKeys` / `InMemorySecureStore` + tests
5. `AuditEvents` table, `schemaVersion => 2`, `MigrationStrategy`, `schema generate`, `drift_schemas/` committed + migration test
6. `DurableAuditSink` + `AuditFlusher` + `AuditTransport` + tests; `POST /audit/events` in the mock server
7. `EvidenceKeyStore` (needs both step 4 and `AuditSink`) + rewritten `evidence_key_test.dart`
8. `providers.dart` wiring + eager flusher bootstrap; thread `TraceId` through the six repository methods in §4.1 and their controllers

Step 1 leads because the v1 baseline is unrecoverable after step 5 without a git checkout. Steps 2–4 are independent of the schema work and could run in parallel with it.

**Verification gates for the epic** (matching CI's `gate` job): `dart format --set-exit-if-changed` clean, `flutter analyze --fatal-infos` exits 0, `flutter test` green, `flutter build web` and `flutter build apk --flavor dev` succeed.

## 8. Risks

| Risk | Mitigation |
|---|---|
| **The audit wire format is 🔒 unconfirmed**, so `POST /audit/events` and its payload shape will change. | Contained to `DioAuditTransport`; the table, flusher, poison-pill rule and `revealAudited` contract are all transport-agnostic. The mock server endpoint keeps dev and E2E honest meanwhile. |
| **Threading `TraceId` touches six repository signatures** across campaign, registration, import and verification, and their controllers. | Optional trailing named parameter, so no call site breaks; the interceptor mints an ID for any call that omits it. Migrate one repository at a time with its tests. |
| **`stepByStep` migrations need generated schema versions**; getting the dump order wrong loses the v1 baseline. | Step 1 of the sequence, before any schema edit, called out explicitly in §4.3. |
| **The v1→v2 migration runs on real field devices** holding un-uploaded attendance evidence. | The migration only adds a table, and the migration test asserts existing rows survive with contents intact. |
| **Web/wasm Drift must carry the new table too**, since CRM sensitive-view audit runs on web. | `driftDatabase` already opens wasm on web and `stepByStep` is platform-independent; the emitter tests run on the Dart VM, and `flutter build web` stays a gate. |
| **An eagerly-started flusher adds work to app boot.** | It is a timer registration and one Drift count query; the first flush is triggered by the 30s timer or a connectivity event, not synchronously at boot. |

## 9. Out of scope

- **Auth token lifecycle (T-0.4.1).** `AuthInterceptor.refreshToken` stays a throwing seam; this epic only fixes how a *successful* refresh replays its request. Epic P0.4 owns login/refresh/logout.
- **A generic `Outbox<T>` shared by `sync_task` and `audit_event`** — revisit only when a third durable-queue consumer appears (D3).
- **The sensitive-media reveal UI** — T-3.1.6 owns the screen, the signed-URL flow and the blur-until-open behaviour; this epic ships `revealAudited` and its `Failure`.
- **Audit event *emission* from feature actions.** The 12 existing `AuditAction` values are wired by their owning features (T-1.4.2 approve/return/reject, T-1.6.3 import commit, T-3.1.4 verification decision). This epic emits only `evidenceKeyRotated`, which belongs to a core service.
- **Background audit flush via `workmanager`** — T-2.1.3 remains unimplemented for evidence too; audit flushes only while the app is alive.
- **`FailureKind` taxonomy changes**, including a dedicated rate-limit kind (D8).
- **Consolidating `sync_uploader.dart`'s error mapping with `mapDioError`** — the divergence is intentional (§4.2).
