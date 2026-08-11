# Sub-project 2a — Identity & Registrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the campaign service the authority for carpenter identity, campaign registrations and profile requests, and cut the Registration Workspace (W-06) over to it — with four slice-1 hardening items landed first.

**Architecture:** New `server/lib/src/participant/` module (repo + routes) behind the existing correlation → envelope → authenticate → authorise → idempotency chain; migration `004_identity` adds `carpenters`/`registrations`/`profile_requests`; `RegistrationStatus` moves into `packages/campaign_contracts`. A profile request creates a **provisional carpenter** in the same transaction and returns it, so the client can auto-add it to the basket (spec 2a.D1).

**Tech Stack:** Dart 3.12, `shelf` 1.4.2, `shelf_router` 1.1.4, `postgres` 3.5.12, Postgres 16 in CI (native PG 18 locally is fine), Flutter client with Dio/Riverpod/Drift, Maestro for e2e.

**Spec:** `docs/superpowers/specs/2026-08-11-identity-registrations-design.md`. Decisions cited as **2a.D1**–**2a.D5**, deliverables **2a-A**–**2a-I**.

## Global Constraints

Every task's requirements implicitly include this section.

- **SDK floor is exactly `sdk: ">=3.12.0 <4.0.0"`** in every touched `pubspec.yaml`. Already true everywhere; do not lower it.
- **`shelf`/`shelf_router` only — no ORM, no codegen** in `server/` or `packages/campaign_contracts` (foundation spec D2). The client's freezed/drift codegen is allowed in the app only.
- **Wire naming is `SCREAMING_SNAKE` for every enum-ish value.** New vocabulary this slice: `INVITED`, `REGISTERED`, `PENDING_PROFILE_SYNC`, `INELIGIBLE`, `WAITLISTED`, `CANCELLED`, `UNKNOWN_CARPENTER`, `LOCAL_ONLY`.
- **Unknown enum values never resolve to a default silently.** `tryParseWire` returns `null`; any fallback must be chosen explicitly and visibly at the call site.
- **Out-of-scope resources return `404`, never `403`** (foundation spec D7). Scope by `organization_id` inside the SQL, not as an after-the-fact check.
- **Raw `phone` and `nid` never leave the server** — not in response bodies, not in error `details`, not in audit payloads (spec 2a.D2). The wire carries only `displayId` (`CARP-••<last4>`) and `phoneSuffix` (last 4 digits).
- **`postgres` traps** (all cost real time in slice 1): inside `Db.tx` use the `TxSession`, never `Db.execute`; multi-statement SQL needs `queryMode: QueryMode.simple`; `ResultRow.toColumnMap()` needs the `row()` helper from `server/lib/src/db/pool.dart`; a `List<String>` named parameter binds as a Postgres array — correct for `= ANY(@ids)`, wrong for `jsonb`.
- **Every migration wraps its DDL *and* its version-row insert in one transaction** — already structural in `Migrator`; do not bypass it.
- **The claim vocabulary is fixed by the client** (`lib/core/auth/scope_claims.dart`). Roles: `campaign_creator`, `marketing_approver`, `crm_verifier`, `crm_supervisor`, `field_user`, `admin`, `reporting_viewer`. This slice's write permission is `campaign_create` — already in the vocabulary; invent nothing.
- **Timestamps:** UTC ISO-8601 on the wire, `timestamptz` in Postgres.
- **Tests run against** `DATABASE_URL=postgres://campaign:campaign@localhost:5432/campaign` (native PG 18 locally per the slice-1 environment note; CI stays on `postgres:16`).
- **Baselines that must not regress:** server suite 135 passing, contracts package 8 passing, app `flutter test` 414 passing / 29 skipped, `flutter analyze --fatal-infos` clean, `dart format --set-exit-if-changed` clean repo-wide (CI's gate formats the whole repo).
- **`tool/mock_server` changes only where the wire contract changes** (Task 8), and `crm`/`field` e2e configs stay on `USE_MOCK` — they belong to sub-projects 4–5.

---

## File Structure

```
packages/campaign_contracts/
  lib/src/registration_status.dart       NEW  RegistrationStatus + wireValue + tryParseWire
  lib/src/error_codes.dart               MOD  + unknownCarpenter
  lib/campaign_contracts.dart            MOD  barrel export
  test/registration_status_test.dart     NEW

server/
  lib/src/infra/idempotency.dart         MOD  reservation TTL + reaper
  lib/src/infra/request_log.dart         NEW  structured request logging
  lib/src/infra/json_fields.dart         NEW  readJsonBody/_field helpers extracted from campaign_routes
  lib/src/infra/error_envelope.dart      MOD  + unknownCarpenter -> 422
  lib/src/db/migrator.dart               MOD  advisory lock + in-tx recheck
  lib/src/db/migrations/embedded.dart    MOD  + 003_role_check, 004_identity
  lib/src/campaign/campaign_routes.dart  MOD  use json_fields helpers
  lib/src/participant/participant_repo.dart    NEW  SQL + masking + CarpenterView
  lib/src/participant/participant_routes.dart  NEW  4 endpoints
  lib/src/app.dart                       MOD  participant leg in the Cascade
  lib/src/seed/seed_routes.dart          MOD  carpenter fixtures + truncate list
  test/support/seed_fixtures.dart        MOD  + seedCarpenter/seedRegistration
  test/infra/idempotency_reaper_test.dart NEW
  test/infra/request_log_test.dart        NEW
  test/db/migrator_lock_test.dart         NEW
  test/db/migrator_test.dart              MOD  table inventory + role CHECK
  test/infra/error_envelope_test.dart     MOD  status-table line
  test/participant/participant_repo_test.dart   NEW
  test/participant/participant_routes_test.dart NEW
  test/app_test.dart                      MOD  /carpenters 401 gate
  test/contract/parity_test.dart          MOD  carpenter/registration parity

tool/mock_server/bin/server.dart          MOD  ratified registration shapes

lib/ (Flutter app)
  domain/common/status.dart               MOD  RegistrationStatus becomes re-export
  domain/registration/registration_repository.dart  MOD  requestNewProfile returns carpenter
  data/registration/registration_repository_impl.dart MOD  UUID key, 201 parse, explicit attendance mapping
  features/registration/application/registration_controller.dart MOD  basket auto-add + D1 comment
  features/registration/presentation/registration_workspace_screen.dart MOD  pre-D1 sheet copy
  core/dev/e2e_seeder.dart                MOD  4-digit phoneSuffix
test/data/registration/registration_repository_impl_test.dart NEW

.maestro/flows/registration_workspace.yaml NEW
.maestro/config.yaml                       MOD
.github/workflows/ci.yml                   MOD  registration matrix entry
```

**Why these boundaries.** `participant_repo.dart` holds every SQL statement and the masking rules so the PII guarantee (2a.D2) has one place to be tested; `participant_routes.dart` holds only HTTP concerns. `json_fields.dart` is extracted because Task 6 would otherwise copy five private helpers verbatim out of `campaign_routes.dart`. The three hardening tasks come first so every later integration test runs against the hardened middleware.

---

# Phase 1 — Hardening opener (2a-A)

### Task 1: Idempotency reservation TTL + opportunistic reaper

**Files:**
- Modify: `server/lib/src/infra/idempotency.dart`
- Create: `server/test/infra/idempotency_reaper_test.dart`

**Interfaces:**
- Consumes: `Db`, `row` (`server/lib/src/db/pool.dart`), `authOf` (`server/lib/src/auth/middleware.dart`), `ApiException`/`ApiErrorCode` — all existing.
- Produces: no signature changes. `idempotency({required Db db})` behaves identically except: a reservation (`response_status IS NULL`) older than 5 minutes is reclaimable, and each claim first sweeps up to 100 expired rows.

**Background.** The claim SQL already reclaims *expired* keys (`WHERE idempotency_keys.expires_at <= now()`), but a reservation left by a crashed process (kill -9, not an exception — exceptions already delete) holds the key at 409 for the full 24h TTL. Slice 1's final review filed this as SHOULD-FIX-SOON.

- [ ] **Step 1: Write the failing tests**

`server/test/infra/idempotency_reaper_test.dart`:

```dart
import 'dart:convert';

import 'package:campaign_service/src/auth/middleware.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:campaign_service/src/infra/idempotency.dart';
// The middleware hashes the body with DartSha256; a seeded reservation whose
// request_hash does not match would fail as KEY_REUSED (422) before the
// in-flight/stale logic this file tests is ever reached.
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late Handler handler;
  late String token;
  var handlerCalls = 0;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // org-1 / user-1 / campaign_creator
    final tokens = TokenService(db: db, config: config);
    token = (await tokens.issueFor('user-1')).accessToken;
    handlerCalls = 0;
    handler = const Pipeline()
        .addMiddleware(correlation())
        .addMiddleware(errorEnvelope())
        .addMiddleware(authenticate(db: db, tokens: tokens))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          handlerCalls++;
          return Response.ok(
            '{"ok":true}',
            headers: {'content-type': 'application/json'},
          );
        });
  });
  tearDown(() async => db.close());

  const body = '{"x":1}';
  String bodyHash() =>
      base64.encode(const DartSha256().hashSync(utf8.encode(body)).bytes);

  Future<Response> post(String key) => handler(
    Request(
      'POST',
      Uri.parse('http://localhost/anything'),
      body: body,
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
        'Idempotency-Key': key,
      },
    ),
  );

  /// A reservation as a crashed owner leaves it: claimed, no response, and
  /// [age] old. request_hash matches [body] so the KEY_REUSED guard passes.
  Future<void> seedReservation(String key, {required Duration age}) =>
      db.execute(
        'INSERT INTO idempotency_keys '
        '(user_id, key, request_hash, expires_at, created_at) '
        'VALUES (@user, @key, @hash, @expires, @created)',
        params: {
          'user': 'user-1',
          'key': key,
          'hash': bodyHash(),
          'expires': DateTime.now().toUtc().add(const Duration(hours: 24)),
          'created': DateTime.now().toUtc().subtract(age),
        },
      );

  test('a fresh reservation still answers 409 IN_FLIGHT', () async {
    await seedReservation('k-fresh', age: const Duration(seconds: 10));
    final res = await post('k-fresh');
    expect(res.statusCode, 409);
    final decoded =
        jsonDecode(await res.readAsString()) as Map<String, Object?>;
    expect(
      (decoded['error']! as Map)['code'],
      'IDEMPOTENCY_KEY_IN_FLIGHT',
      reason: 'the 5-minute reclaim window must not swallow live requests',
    );
    expect(handlerCalls, 0);
  });

  test('a stale reservation (crashed owner) is reclaimed and the handler '
      'runs', () async {
    await seedReservation('k-stale', age: const Duration(minutes: 6));
    final res = await post('k-stale');
    expect(res.statusCode, 200);
    expect(handlerCalls, 1, reason: 'the retry must win the key back');
  });

  test('an expired fulfilled row is swept by a later claim on a DIFFERENT '
      'key', () async {
    await db.execute(
      'INSERT INTO idempotency_keys '
      '(user_id, key, request_hash, response_status, response_body, '
      ' expires_at) '
      "VALUES ('user-1', 'k-old', 'h', 200, '{}', @expires)",
      params: {
        'expires': DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      },
    );
    await post('k-new'); // any claim sweeps
    final leftovers = await db.execute(
      "SELECT key FROM idempotency_keys WHERE key = 'k-old'",
    );
    expect(leftovers, isEmpty, reason: 'the reaper deletes expired rows');
  });

  test('an unexpired fulfilled row survives the sweep and still replays',
      () async {
    final first = await post('k-live');
    expect(first.statusCode, 200);
    await post('k-other'); // triggers a sweep
    final replay = await post('k-live');
    expect(replay.statusCode, 200);
    expect(handlerCalls, 2, reason: 'k-live must replay, not re-run');
  });
}
```

- [ ] **Step 2: Run and confirm the stale/reaper tests fail**

```bash
cd server && dart test test/infra/idempotency_reaper_test.dart
```

Expected: "fresh reservation" and "unexpired fulfilled" PASS already (current behaviour); "stale reservation" FAILS with a 409, and "expired fulfilled row" FAILS with the row still present. If the stale test passes before any change, it is vacuous — stop and check the seeded `created_at` actually predates the window.

- [ ] **Step 3: Implement reclaim + reaper**

In `server/lib/src/infra/idempotency.dart`:

Add below `_ttl`:

```dart
/// How long a reservation (a claimed key whose handler has not yet fulfilled
/// it) blocks retries with 409 before it is presumed dead and reclaimable.
/// Longer than any handler's runtime, far shorter than a user's patience —
/// a crashed owner previously held the key for the full 24h [_ttl].
const Duration _reservationTtl = Duration(minutes: 5);

/// Upper bound on rows the opportunistic reaper deletes per claim, so no
/// single request pays for unbounded cleanup after a long quiet period.
const int _reapLimit = 100;
```

In the claim SQL inside the `for` loop, extend the `DO UPDATE ... WHERE` and reset `created_at` (without the reset, a reclaimed reservation would *itself* look stale immediately and a third request could steal it mid-handler):

```dart
        final claim = await db.execute(
          'INSERT INTO idempotency_keys '
          '(user_id, key, request_hash, expires_at) '
          'VALUES (@user, @key, @hash, @expires) '
          'ON CONFLICT (user_id, key) DO UPDATE SET '
          '  request_hash = EXCLUDED.request_hash, '
          '  response_status = NULL, '
          '  response_body = NULL, '
          '  created_at = now(), '
          '  expires_at = EXCLUDED.expires_at '
          'WHERE idempotency_keys.expires_at <= now() '
          '   OR (idempotency_keys.response_status IS NULL '
          "       AND idempotency_keys.created_at <= now() - interval '5 minutes') "
          'RETURNING key',
```

Immediately before the `for (var attempt ...)` loop, add the sweep:

```dart
      // Opportunistic reaper: every claim first clears a bounded batch of
      // expired rows. Postgres has no DELETE ... LIMIT, hence the ctid
      // subquery. Bounded so a request never pays for unbounded cleanup;
      // eventually-complete because every subsequent claim sweeps again.
      try {
        await db.execute(
          'DELETE FROM idempotency_keys WHERE ctid IN ('
          '  SELECT ctid FROM idempotency_keys '
          '  WHERE expires_at <= now() '
          '  ORDER BY expires_at LIMIT $_reapLimit '
          '  FOR UPDATE SKIP LOCKED)',
        );
      } on Object {
        // Housekeeping must never fail the request it piggybacks on.
      }
```

> **Two corrections found by Task 1's review (2026-08-11), already reflected in the code
> block above — apply them from the start if re-running this plan.**
>
> **1. The original snippet's unguarded, unordered sweep was a deadlock-and-500 vector.**
> Two concurrent backends seq-scanning for expired ctids lock overlapping row sets in
> divergent orders (`synchronize_seqscans`), and the loser's deadlock error aborted the
> user's POST — best-effort cleanup failing the retry-safety endpoint. The guard swallows
> sweep failures; `ORDER BY expires_at ... FOR UPDATE SKIP LOCKED` makes concurrent
> sweeps take disjoint, deterministic victim sets.
>
> **2. The sweep silently emptied the expired-reclaim branch's only test.** The
> pre-existing reclaim test seeded ONE expired row, which the sweep now deletes before
> the claim runs — the test stayed green while pinning nothing. The fix seeds 100 decoy
> rows with strictly older `expires_at` (the sweep's new ORDER BY makes the victim set
> deterministic), so the key under test provably survives to reach the `DO UPDATE`
> reclaim. Verified non-vacuous by breaking the reclaim WHERE clause and watching the
> test fail.

- [ ] **Step 4: Run the new suite and the existing idempotency suite**

```bash
cd server && dart test test/infra/idempotency_reaper_test.dart test/infra/idempotency_test.dart
```

Expected: all pass. The pre-existing suite pins the in-flight/reuse/replay semantics this change must not alter.

- [ ] **Step 5: Prove the stale-reclaim test is not vacuous**

Temporarily change `interval '5 minutes'` to `interval '999 days'` and re-run: the stale-reservation test must FAIL (back to 409). Revert; it passes again.

- [ ] **Step 6: Format, analyze, full server suite, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server && git commit -m "fix(server): idempotency reservations expire after 5 minutes; expired rows reaped

A crashed owner (process kill, not exception -- exceptions already delete
their reservation) held a key at 409 IN_FLIGHT for the full 24h TTL. The
claim's DO UPDATE now also fires for reservations older than 5 minutes,
resetting created_at so a reclaimed reservation cannot itself be stolen
mid-handler. Every claim first sweeps up to 100 expired rows (ctid subquery
-- Postgres has no DELETE..LIMIT), closing the unbounded-growth finding."
```

---

### Task 2: Advisory-locked migrator + migration `003_role_check`

**Files:**
- Modify: `server/lib/src/db/migrator.dart`
- Modify: `server/lib/src/db/migrations/embedded.dart`
- Create: `server/test/db/migrator_lock_test.dart`
- Modify: `server/test/db/migrator_test.dart` (role-CHECK test; table inventory unchanged)

**Interfaces:**
- Consumes: `Db.tx`, `row`, `embeddedMigrations` — existing.
- Produces: `Migrator.applyPending()` unchanged in signature; now safe for two instances booting concurrently (loser waits, then skips — no error, no duplicate). `embeddedMigrations` gains key `'003_role_check'`.

- [ ] **Step 1: Write the failing concurrency test**

`server/test/db/migrator_lock_test.dart`:

```dart
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:test/test.dart';

import '../support/test_db.dart';

void main() {
  test('two migrators on separate connections apply every migration exactly '
      'once between them', () async {
    final a = await freshDb();
    // A second REAL connection: pg_advisory_xact_lock serialises across
    // connections, so both migrators sharing one Db would test nothing.
    final b = await Db.open(testDatabaseUrl);

    try {
      final results = await Future.wait([
        Migrator(a).applyPending(),
        Migrator(b).applyPending(),
      ]);

      final total = results[0].length + results[1].length;
      final rows = await a.execute('SELECT id FROM schema_migrations');
      expect(
        total,
        rows.length,
        reason:
            'every applied id was applied by exactly one migrator: the loser '
            'must skip (in-tx recheck), not fail on a duplicate insert and '
            'not double-apply',
      );
      expect(
        {...results[0], ...results[1]}.length,
        total,
        reason: 'no id may appear in both applied lists',
      );
    } finally {
      await a.close();
      await b.close();
    }
  });
}
```

- [ ] **Step 2: Run it and confirm the failure mode**

```bash
cd server && dart test test/db/migrator_lock_test.dart
```

Expected: FAIL — without the lock the race usually surfaces as one migrator throwing (duplicate key on `schema_migrations`, or DDL collision). Run it up to 3 times if it passes by luck; if it never fails, verify both connections really are distinct (`Db.open` twice).

- [ ] **Step 3: Implement lock + in-tx recheck**

In `server/lib/src/db/migrator.dart`, add above the class:

```dart
/// Session-arbitrary advisory-lock key for "the migration runner". Any
/// constant works as long as every instance uses the same one; 0x6d696772 is
/// ASCII 'migr'.
const int _migrationLockKey = 0x6d696772;
```

Replace the body of the `for (final id in pending)` loop:

```dart
    for (final id in pending) {
      var appliedThisId = false;
      await _db.tx((tx) async {
        // Serialises concurrent migrators (two instances booting together).
        // Transaction-scoped: released automatically at commit/rollback, so
        // a crashed migrator cannot leave the lock held.
        await tx.execute('SELECT pg_advisory_xact_lock($_migrationLockKey)');

        // The pending list was computed before we held the lock; another
        // instance may have applied this id while we waited. Recheck inside
        // the lock, where the answer cannot change under us.
        final already = await tx.execute(
          Sql.named('SELECT 1 FROM schema_migrations WHERE id = @id'),
          parameters: {'id': id},
        );
        if (already.isNotEmpty) return;

        // Every statement here goes through `tx`, never `_db` — see Db.tx.
        //
        // Simple query protocol: a migration is a multi-statement DDL script,
        // and the extended (prepared-statement) protocol postgres uses by
        // default rejects a Parse containing more than one command with
        // "cannot insert multiple commands into a prepared statement".
        await tx.execute(_migrations[id]!, queryMode: QueryMode.simple);
        final seam = onBeforeVersionInsert;
        if (seam != null) {
          await seam(id);
        }
        await tx.execute(
          Sql.named('INSERT INTO schema_migrations (id) VALUES (@id)'),
          parameters: {'id': id},
        );
        appliedThisId = true;
      });
      if (appliedThisId) applied.add(id);
    }
```

> **Correction found by Task 2's execution (2026-08-11, TDD, deterministic 5/5): the
> Step 3 snippet alone does NOT close the race.** The bootstrap
> `CREATE TABLE IF NOT EXISTS schema_migrations` at the top of `applyPending` runs
> outside any lock, and Postgres's existence-check-then-create is not atomic under
> concurrent DDL — two cold-boot migrators fail with SQLSTATE 23505 on `pg_type` before
> the per-migration lock is ever reached. Wrap that bootstrap statement in its own
> lock-guarded transaction using the same `_migrationLockKey`. The loser-skips guarantee
> still holds across the bootstrap/loop lock gap because the in-tx recheck (not the lock
> alone) is what makes the loser skip.

- [ ] **Step 4: Add migration `003_role_check`**

In `server/lib/src/db/migrations/embedded.dart`, add to the map and define:

```dart
const Map<String, String> embeddedMigrations = {
  '001_foundation': _foundation,
  '002_idempotency_reserve': _idempotencyReserve, // (existing key: keep the real name used in this file)
  '003_role_check': _roleCheck,
};

/// An unknown role reaching the login response breaks sign-in at the
/// client's claims trust boundary (scope_claims.dart rejects unrecognised
/// names). The list below IS that vocabulary — change either only with the
/// other (slice-1 final review, deferred M10).
const String _roleCheck = r'''
ALTER TABLE staff_user_roles
  ADD CONSTRAINT staff_user_roles_role_check
  CHECK (role IN ('campaign_creator', 'marketing_approver', 'crm_verifier',
                  'crm_supervisor', 'field_user', 'admin',
                  'reporting_viewer'));
''';
```

(Open the file first: keep migration `002`'s existing map key exactly as it is — only *add* `003_role_check`.)

- [ ] **Step 5: Add the CHECK test to `migrator_test.dart`**

Append inside `main()`:

```dart
  test('003_role_check rejects a role outside the client vocabulary',
      () async {
    await Migrator(db).applyPending();
    await db.execute(
      "INSERT INTO organizations (id, name) VALUES ('o1', 'Org')",
    );
    await db.execute(
      'INSERT INTO staff_users '
      '(id, username, display_name, password_hash, organization_id) '
      "VALUES ('u1', 'u1', 'U', 'x', 'o1')",
    );
    await expectLater(
      db.execute(
        "INSERT INTO staff_user_roles (user_id, role) VALUES ('u1', 'not_a_role')",
      ),
      // 23514 = check_violation. Assert the cause, not just "some exception"
      // (slice-1 Task 3 lesson: a loose matcher accepted the wrong error).
      throwsA(
        isA<ServerException>().having((e) => e.code, 'sqlstate', '23514'),
      ),
    );
    // The whole valid vocabulary still inserts.
    await db.execute(
      "INSERT INTO staff_user_roles (user_id, role) VALUES ('u1', 'admin')",
    );
  });
```

Add `import 'package:postgres/postgres.dart' show ServerException;` to the test file's imports if not present.

- [ ] **Step 6: Run the db suites**

```bash
cd server && dart test test/db/
```

Expected: all pass, including the existing seam/rollback tests (the lock + recheck must not disturb them) and the new lock + CHECK tests.

- [ ] **Step 7: Format, analyze, full suite, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server && git commit -m "feat(server): advisory-locked migrator; CHECK constraint on staff role names

pg_advisory_xact_lock serialises concurrent applyPending runs (two instances
booting together previously raced; the loser failed loudly on a duplicate
version-row insert). The pending list is rechecked inside the lock because it
was computed before the lock was held. Transaction-scoped lock: a crashed
migrator cannot leave it held.

003_role_check pins staff_user_roles.role to the client's fixed claim
vocabulary -- an unknown role previously reached the login response verbatim
and broke sign-in at the client's trust boundary (deferred finding M10)."
```

---

### Task 3: Structured request logging with trace id

> **LANDED EARLY on PR #6 (2026-08-11)** as the diagnostic for the failing
> real-auth e2e configs — the backend log was empty at exactly the moment it
> was needed. Implemented as specified below (`request_log.dart`, its two
> tests, the `buildApp` composition). Executors: verify it is present and its
> tests pass, do not re-implement.

**Files:**
- Create: `server/lib/src/infra/request_log.dart`
- Create: `server/test/infra/request_log_test.dart`
- Modify: `server/lib/src/app.dart` (compose it)

**Interfaces:**
- Consumes: `correlationOf(Request)` from `server/lib/src/infra/correlation.dart`.
- Produces: `Middleware requestLog({StringSink? sink})` — one JSON line per request: `{"method","path","status","durationMs","traceId"}`. Composed in `buildApp` between `correlation()` and `errorEnvelope()`.

- [ ] **Step 1: Write the failing test**

`server/test/infra/request_log_test.dart`:

```dart
import 'dart:convert';

import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:campaign_service/src/infra/request_log.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  Handler build(StringBuffer sink, Handler inner) => const Pipeline()
      .addMiddleware(correlation())
      .addMiddleware(requestLog(sink: sink))
      .addMiddleware(errorEnvelope())
      .addHandler(inner);

  test('logs one JSON line whose traceId matches the response header',
      () async {
    final sink = StringBuffer();
    final handler = build(sink, (req) async => Response.ok('ok'));

    final res = await handler(
      Request('GET', Uri.parse('http://localhost/campaigns?page=2')),
    );

    final lines = sink.toString().trim().split('\n');
    expect(lines, hasLength(1));
    final line = jsonDecode(lines.single) as Map<String, Object?>;
    expect(line['method'], 'GET');
    expect(line['path'], '/campaigns', reason: 'path only — query params can '
        'carry user data and do not belong in every log line');
    expect(line['status'], 200);
    expect(line['durationMs'], isA<int>());
    expect(
      line['traceId'],
      res.headers['x-correlation-id'],
      reason: 'the log line is only useful if the id in it is the id the '
          'client saw',
    );
  });

  test('a thrown error is logged with the enveloped status, not skipped',
      () async {
    final sink = StringBuffer();
    final handler = build(sink, (req) async => throw StateError('boom'));

    await handler(Request('GET', Uri.parse('http://localhost/x')));

    final line =
        jsonDecode(sink.toString().trim()) as Map<String, Object?>;
    expect(line['status'], 500,
        reason: 'requestLog sits OUTSIDE errorEnvelope, so it sees the '
            'envelope-produced 500, and a throwing handler still logs');
  });
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd server && dart test test/infra/request_log_test.dart
```

Expected: FAIL — `request_log.dart` does not exist.

- [ ] **Step 3: Implement**

`server/lib/src/infra/request_log.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'correlation.dart';

/// One structured JSON line per request: method, path, status, duration and
/// the correlation id — the operator's bridge from a client-reported trace id
/// to the server log (closes slice 1's D-B partial).
///
/// Compose INSIDE [correlation] (so [correlationOf] resolves) and OUTSIDE
/// [errorEnvelope] (so the logged status is the one the client actually
/// received, including envelope-produced 500s for thrown errors).
///
/// Deliberately logs the path WITHOUT its query string: query parameters can
/// carry user-entered search text, which does not belong in every log line.
Middleware requestLog({StringSink? sink}) {
  final out = sink ?? stdout;
  return (Handler inner) {
    return (Request request) async {
      final watch = Stopwatch()..start();
      final response = await inner(request);
      out.writeln(
        jsonEncode({
          'method': request.method,
          'path': '/${request.url.path}',
          'status': response.statusCode,
          'durationMs': watch.elapsedMilliseconds,
          'traceId': correlationOf(request),
        }),
      );
      return response;
    };
  };
}
```

(If `correlationOf` cannot resolve before the handler runs — check `correlation.dart`: it stores the id in the request context on the way in — read it *after* `inner` completes as shown; the id was attached by `correlation()` before `requestLog` ever saw the request.)

- [ ] **Step 4: Compose in `buildApp`**

In `server/lib/src/app.dart`, add the import and change the final pipeline:

```dart
  return const Pipeline()
      .addMiddleware(correlation())
      .addMiddleware(requestLog())
      .addMiddleware(errorEnvelope())
      .addHandler(cascade.handler);
```

- [ ] **Step 5: Run, format, analyze, full suite, commit**

```bash
cd server && dart test test/infra/request_log_test.dart && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server && git commit -m "feat(server): structured request logging with trace id

One JSON line per request (method, path minus query string, status,
durationMs, traceId), composed between correlation and errorEnvelope so a
thrown handler still logs the 500 the client actually saw. Closes slice 1's
D-B structured-logging partial."
```

---

# Phase 2 — Contract and server feature work

### Task 4: `RegistrationStatus` wire vocabulary + `UNKNOWN_CARPENTER`

**Files:**
- Create: `packages/campaign_contracts/lib/src/registration_status.dart`
- Create: `packages/campaign_contracts/test/registration_status_test.dart`
- Modify: `packages/campaign_contracts/lib/src/error_codes.dart`
- Modify: `packages/campaign_contracts/lib/campaign_contracts.dart`
- Modify: `server/lib/src/infra/error_envelope.dart` (status arm)
- Modify: `server/test/infra/error_envelope_test.dart` (status-table line)
- Modify: `lib/domain/common/status.dart` (app shim)

**Interfaces:**
- Produces: `enum RegistrationStatus { invited, registered, pendingProfileSync, ineligible, waitlisted, cancelled }` with `String get wireValue` and `static RegistrationStatus? tryParseWire(String)`; `ApiErrorCode.unknownCarpenter` with wire value `UNKNOWN_CARPENTER` and HTTP status **422**.
- Consumes: nothing new.

- [ ] **Step 1: Write the failing test**

`packages/campaign_contracts/test/registration_status_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every registration status has a distinct SCREAMING_SNAKE wire value',
      () {
    final wires = RegistrationStatus.values.map((s) => s.wireValue).toList();
    expect(wires.toSet().length, RegistrationStatus.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip', () {
    for (final s in RegistrationStatus.values) {
      expect(RegistrationStatus.tryParseWire(s.wireValue), s);
    }
  });

  test('an unknown wire value is null, never a default', () {
    expect(RegistrationStatus.tryParseWire('NOT_A_STATUS'), isNull);
    expect(RegistrationStatus.tryParseWire(''), isNull);
    expect(RegistrationStatus.tryParseWire('registered'), isNull,
        reason: 'case matters');
  });

  test('the exact vocabulary the server emits', () {
    expect(RegistrationStatus.pendingProfileSync.wireValue,
        'PENDING_PROFILE_SYNC');
    expect(RegistrationStatus.registered.wireValue, 'REGISTERED');
  });

  test('UNKNOWN_CARPENTER is in the error vocabulary', () {
    expect(ApiErrorCode.unknownCarpenter.wireValue, 'UNKNOWN_CARPENTER');
    expect(ApiErrorCode.tryParseWire('UNKNOWN_CARPENTER'),
        ApiErrorCode.unknownCarpenter);
  });
}
```

- [ ] **Step 2: Run and confirm compile failure**

```bash
cd packages/campaign_contracts && dart test
```

Expected: FAIL — `RegistrationStatus` undefined.

- [ ] **Step 3: Implement the enum**

`packages/campaign_contracts/lib/src/registration_status.dart`:

```dart
/// Controlled registration-status vocabulary — moved out of the app's
/// `lib/domain/common/status.dart` now that sub-project 2a defines its
/// server contract (the foundation spec's D5 rule: enums move only when
/// their wire contract lands, never before).
///
/// `pendingProfileSync` changed meaning with D1: it now means "this
/// registration's carpenter exists only as a locally captured provisional
/// profile, not yet ratified into the master" — no longer "awaiting an
/// authoritative Sales Eco identity".
enum RegistrationStatus {
  invited,
  registered,
  pendingProfileSync,
  ineligible,
  waitlisted,
  cancelled;

  String get wireValue => switch (this) {
    invited => 'INVITED',
    registered => 'REGISTERED',
    pendingProfileSync => 'PENDING_PROFILE_SYNC',
    ineligible => 'INELIGIBLE',
    waitlisted => 'WAITLISTED',
    cancelled => 'CANCELLED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static RegistrationStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
```

In `packages/campaign_contracts/lib/src/error_codes.dart`, add to the enum (after `segregationOfDutiesViolation`, new comment group):

```dart
  // participants (sub-project 2a)
  unknownCarpenter;
```

and to the `wireValue` switch:

```dart
    unknownCarpenter => 'UNKNOWN_CARPENTER',
```

In `packages/campaign_contracts/lib/campaign_contracts.dart`, add:

```dart
export 'src/registration_status.dart';
```

- [ ] **Step 4: Contracts tests pass**

```bash
cd packages/campaign_contracts && dart test
```

Expected: 13 passing (8 existing + 5 new).

- [ ] **Step 5: Server envelope arm + status-table test**

`server/lib/src/infra/error_envelope.dart` — the `status` switch is exhaustive, so the server will not compile until this arm exists. Add:

```dart
    ApiErrorCode.unknownCarpenter => 422,
```

In `server/test/infra/error_envelope_test.dart`, find the status-table test (the hand-enumerated code→status list from slice-1 finding M5) and add the pair `ApiErrorCode.unknownCarpenter: 422` to its table.

```bash
cd server && dart pub get && dart test test/infra/error_envelope_test.dart
```

Expected: pass.

- [ ] **Step 6: App shim**

In `lib/domain/common/status.dart`: delete the entire `enum RegistrationStatus { ... }` declaration and extend the existing re-export:

```dart
export 'package:campaign_contracts/campaign_contracts.dart'
    show CampaignStatus, RegistrationStatus;
```

Update the file's doc comment where it says the remaining enums "have NO wire value yet": `RegistrationStatus` has now moved; `AttendanceStatus`, `ImportStatus` and `IntegrityFlag` remain (import belongs to 2b, attendance to sub-project 4).

- [ ] **Step 7: Verify the app is unmoved**

```bash
flutter pub get
flutter analyze --fatal-infos
flutter test
```

Expected: analyze clean, **414 passing / 29 skipped** — identical counts. The consumers (`status_chip.dart`, `status_labels.dart`, `gallery_screen.dart`) all import via `domain/common/status.dart`, so the shim keeps every switch exhaustive over the same enum.

- [ ] **Step 8: Format and commit**

```bash
dart format --set-exit-if-changed lib packages server
git add packages/campaign_contracts server/lib/src/infra/error_envelope.dart server/test/infra/error_envelope_test.dart lib/domain/common/status.dart
git commit -m "feat(contracts): RegistrationStatus wire vocabulary + UNKNOWN_CARPENTER

RegistrationStatus moves into campaign_contracts now that sub-project 2a
defines its server contract -- the same D5 rule that moved CampaignStatus in
slice 1 and deliberately left this enum behind. The app file keeps its shim
shape: consumers are untouched.

UNKNOWN_CARPENTER (422) is the registration write's answer for carpenter ids
that are unknown or cross-org -- 422 not 404 because the campaign itself was
found; 404 stays reserved for out-of-scope resources (D7)."
```

---

### Task 5: Migration `004_identity` + `ParticipantRepo`

**Files:**
- Modify: `server/lib/src/db/migrations/embedded.dart`
- Create: `server/lib/src/participant/participant_repo.dart`
- Modify: `server/test/support/seed_fixtures.dart` (add `seedCarpenter`, `seedRegistration`)
- Modify: `server/test/db/migrator_test.dart` (table inventory)
- Create: `server/test/participant/participant_repo_test.dart`

**Interfaces:**
- Consumes: `Db`, `row`, `Db.tx`; `AuditWriter.writeTx` (`server/lib/src/infra/audit.dart`); `ApiException`/`ApiErrorCode`.
- Produces (Task 6 builds routes on exactly these):
  - `class CarpenterView { final String id; final String name; final String displayCode; final String phone; final String? territoryName; final String? dealerContext; final String? thumbnailUrl; final bool eligible; final String syncStatus; Map<String, Object?> toWireJson(); }`
  - `class ParticipantRepo { ParticipantRepo(Db db); Future<List<CarpenterView>> search({required String organizationId, required String q}); Future<List<CarpenterView>?> rosterForSession(String sessionId, {required String organizationId}); Future<({int registered, int alreadyRegistered})?> register({required String campaignId, required String organizationId, required List<String> carpenterIds, required String registeredBy, String? correlationId}); Future<({String requestId, CarpenterView carpenter})?> createProfileRequest({required String campaignId, required String organizationId, required String name, required String phone, required String requestedBy, String? correlationId}); }`
  - `null` returns mean "campaign/session not visible in this organization" → the route answers 404 (D7). `register` throws `ApiException(ApiErrorCode.unknownCarpenter)` for unknown/cross-org carpenter ids.
  - Test fixtures: `seedCarpenter(Db, {required String id, String name, String phone, String displayCode, String organizationId, String? territoryId, String source, String syncStatus, bool eligible})` and `seedRegistration(Db, {required String campaignId, required String carpenterId, String status, String registeredBy})`.

- [ ] **Step 1: Add migration `004_identity`**

In `server/lib/src/db/migrations/embedded.dart`, add `'004_identity': _identity,` to the map and:

```dart
const String _identity = r'''
CREATE TABLE carpenters (
  id               TEXT PRIMARY KEY,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  full_name        TEXT NOT NULL,
  -- Raw phone and nullable nid never leave the server unmasked (spec 2a.D2);
  -- they exist as sub-project 8's reconciliation join keys (D1).
  phone            TEXT NOT NULL,
  nid              TEXT,
  territory_id     TEXT REFERENCES territories(id),
  dealer_context   TEXT,
  thumbnail_url    TEXT,
  eligible         BOOLEAN NOT NULL DEFAULT TRUE,
  display_code     TEXT NOT NULL UNIQUE,
  source           TEXT NOT NULL,
  sync_status      TEXT NOT NULL DEFAULT 'LOCAL_ONLY',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX carpenters_org_name_idx
  ON carpenters(organization_id, lower(full_name));
CREATE INDEX carpenters_phone_idx ON carpenters(phone);
CREATE INDEX carpenters_nid_idx ON carpenters(nid);
-- Deliberately NO unique constraint on phone/nid: D1 matching is
-- confidence-scored with human adjudication (sub-project 8), and the schema
-- must tolerate what the matcher is designed to resolve (spec 2a.D3).

CREATE SEQUENCE carpenter_display_serial START 10000;

CREATE TABLE registrations (
  campaign_id    TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  carpenter_id   TEXT NOT NULL REFERENCES carpenters(id),
  status         TEXT NOT NULL,
  registered_by  TEXT NOT NULL REFERENCES staff_users(id),
  registered_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, carpenter_id)
);
CREATE INDEX registrations_carpenter_idx ON registrations(carpenter_id);

CREATE TABLE profile_requests (
  id            TEXT PRIMARY KEY,
  campaign_id   TEXT NOT NULL REFERENCES campaigns(id),
  carpenter_id  TEXT NOT NULL REFERENCES carpenters(id),
  requested_by  TEXT NOT NULL REFERENCES staff_users(id),
  name          TEXT NOT NULL,
  phone         TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'PENDING',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX profile_requests_campaign_idx ON profile_requests(campaign_id);
''';
```

Update `migrator_test.dart`'s table-inventory `containsAll` list with `'carpenters', 'registrations', 'profile_requests'`.

- [ ] **Step 2: Add the seed fixtures**

Append to `server/test/support/seed_fixtures.dart`:

```dart
/// Inserts one carpenter. Defaults line up with [seedOrganizationWithUser]
/// (`org-1`/`terr-1`), so an uncustomised test's token can see the row.
Future<void> seedCarpenter(
  Db db, {
  required String id,
  String name = 'Md. Karim',
  String phone = '+8801700004821',
  String displayCode = 'CARP-00004821',
  String organizationId = 'org-1',
  String? territoryId = 'terr-1',
  String? nid,
  String? dealerContext,
  String source = 'SEED',
  String syncStatus = 'LOCAL_ONLY',
  bool eligible = true,
}) => db.execute(
  'INSERT INTO carpenters '
  '(id, organization_id, full_name, phone, nid, territory_id, '
  ' dealer_context, display_code, source, sync_status, eligible) '
  'VALUES (@id, @org, @name, @phone, @nid, @territory, @dealer, @code, '
  '        @source, @sync, @eligible)',
  params: {
    'id': id,
    'org': organizationId,
    'name': name,
    'phone': phone,
    'nid': nid,
    'territory': territoryId,
    'dealer': dealerContext,
    'code': displayCode,
    'source': source,
    'sync': syncStatus,
    'eligible': eligible,
  },
);

/// Inserts one registration row directly, bypassing the route.
Future<void> seedRegistration(
  Db db, {
  required String campaignId,
  required String carpenterId,
  String status = 'REGISTERED',
  String registeredBy = 'user-1',
}) => db.execute(
  'INSERT INTO registrations '
  '(campaign_id, carpenter_id, status, registered_by) '
  'VALUES (@campaign, @carpenter, @status, @by)',
  params: {
    'campaign': campaignId,
    'carpenter': carpenterId,
    'status': status,
    'by': registeredBy,
  },
);
```

- [ ] **Step 3: Write the failing repo tests**

`server/test/participant/participant_repo_test.dart`:

```dart
import 'dart:convert';

import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:campaign_service/src/participant/participant_repo.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late ParticipantRepo repo;

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // org-1/terr-1/user-1
    // A second org whose rows must never leak into org-1's results.
    await seedOrganizationWithUser(
      db,
      orgId: 'org-2',
      territoryId: 'terr-2',
      userId: 'user-9',
      username: 'other',
    );
    repo = ParticipantRepo(db);
  });
  tearDown(() async => db.close());

  group('search', () {
    setUp(() async {
      await seedCarpenter(db, id: 'c-1'); // Md. Karim, ...4821
      await seedCarpenter(
        db,
        id: 'c-2',
        name: 'Karim Uddin',
        phone: '+8801700007734',
        displayCode: 'CARP-00007734',
      );
      await seedCarpenter(
        db,
        id: 'c-foreign',
        name: 'Md. Karim',
        organizationId: 'org-2',
        territoryId: 'terr-2',
        phone: '+8801700009999',
        displayCode: 'CARP-00009999',
      );
    });

    test('matches name case-insensitively, org-scoped', () async {
      final hits = await repo.search(organizationId: 'org-1', q: 'karim');
      expect(hits.map((c) => c.id).toSet(), {'c-1', 'c-2'},
          reason: 'c-foreign has the same name and must not appear');
    });

    test('matches a phone suffix', () async {
      final hits = await repo.search(organizationId: 'org-1', q: '4821');
      expect(hits.map((c) => c.id), ['c-1']);
    });

    test('matches a display code fragment', () async {
      final hits = await repo.search(organizationId: 'org-1', q: '7734');
      expect(hits.map((c) => c.id), contains('c-2'));
    });

    test('the wire shape masks and never carries the raw phone', () async {
      final hits = await repo.search(organizationId: 'org-1', q: 'karim');
      for (final c in hits) {
        final json = c.toWireJson();
        expect(json['displayId'], matches(RegExp(r'^CARP-••\d{4}$')));
        expect(json['phoneSuffix'], matches(RegExp(r'^\d{4}$')));
        expect(json['territory'], 'Territory');
        expect(json['syncStatus'], 'LOCAL_ONLY');
        expect(json.containsKey('attendanceState'), isFalse,
            reason: 'sub-project 4 owns that vocabulary (spec 2a.D4)');
        expect(jsonEncode(json), isNot(contains('+880')),
            reason: 'raw phone must never appear anywhere in the wire JSON');
      }
    });
  });

  group('register', () {
    setUp(() async {
      await seedCampaign(db, id: 'camp-1', territoryIds: const ['terr-1']);
      await seedCarpenter(db, id: 'c-1');
      await seedCarpenter(
        db,
        id: 'c-prov',
        name: 'Provisional Person',
        phone: '+8801700001111',
        displayCode: 'CARP-00001111',
        source: 'PROFILE_REQUEST',
        syncStatus: 'PENDING_PROFILE_SYNC',
      );
    });

    test('registers, counts already-registered on repeat, and derives '
        'PENDING_PROFILE_SYNC from the carpenter', () async {
      final first = await repo.register(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        carpenterIds: ['c-1', 'c-prov'],
        registeredBy: 'user-1',
      );
      expect((registered: 2, alreadyRegistered: 0), first);

      final again = await repo.register(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        carpenterIds: ['c-1', 'c-prov'],
        registeredBy: 'user-1',
      );
      expect((registered: 0, alreadyRegistered: 2), again);

      final statuses = await db.execute(
        'SELECT carpenter_id, status FROM registrations ORDER BY carpenter_id',
      );
      final byId = {
        for (final r in statuses.map(row))
          r['carpenter_id']! as String: r['status']! as String,
      };
      expect(byId['c-1'], 'REGISTERED');
      expect(byId['c-prov'], 'PENDING_PROFILE_SYNC');
    });

    test('a cross-org carpenter id is UNKNOWN_CARPENTER, and its details '
        'name the offending ids without any PII', () async {
      await seedCarpenter(
        db,
        id: 'c-foreign',
        organizationId: 'org-2',
        territoryId: 'terr-2',
        phone: '+8801700009999',
        displayCode: 'CARP-00009999',
      );
      await expectLater(
        repo.register(
          campaignId: 'camp-1',
          organizationId: 'org-1',
          carpenterIds: ['c-1', 'c-foreign'],
          registeredBy: 'user-1',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code.wireValue, 'code', 'UNKNOWN_CARPENTER')
              .having(
                (e) => e.details?['carpenterIds'],
                'offending ids',
                ['c-foreign'],
              ),
        ),
      );
      final rows = await db.execute('SELECT 1 FROM registrations');
      expect(rows, isEmpty,
          reason: 'a partially-valid batch must register NOTHING');
    });

    test('a cross-org campaign is null (route answers 404, D7)', () async {
      await seedCampaign(
        db,
        id: 'camp-foreign',
        organizationId: 'org-2',
        ownerId: 'user-9',
      );
      final result = await repo.register(
        campaignId: 'camp-foreign',
        organizationId: 'org-1',
        carpenterIds: ['c-1'],
        registeredBy: 'user-1',
      );
      expect(result, isNull);
    });

    test('writes an audit row with the correlation id', () async {
      await repo.register(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        carpenterIds: ['c-1'],
        registeredBy: 'user-1',
        correlationId: 'trace-123',
      );
      final audit = await db.execute(
        "SELECT correlation_id, payload FROM audit_events "
        "WHERE action = 'registration.create'",
      );
      expect(row(audit.single)['correlation_id'], 'trace-123');
    });
  });

  group('createProfileRequest', () {
    setUp(() async {
      await seedCampaign(db, id: 'camp-1');
    });

    test('creates a provisional carpenter and the request in one shot',
        () async {
      final result = await repo.createProfileRequest(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        name: 'New Person',
        phone: '+8801711112222',
        requestedBy: 'user-1',
        correlationId: 'trace-9',
      );
      expect(result, isNotNull);
      final carpenter = result!.carpenter;
      expect(carpenter.syncStatus, 'PENDING_PROFILE_SYNC');
      expect(carpenter.toWireJson()['displayId'],
          matches(RegExp(r'^CARP-••\d{4}$')));

      final stored = await db.execute(
        'SELECT source, sync_status FROM carpenters WHERE id = @id',
        params: {'id': carpenter.id},
      );
      expect(row(stored.single)['source'], 'PROFILE_REQUEST');

      final request = await db.execute(
        'SELECT status FROM profile_requests WHERE id = @id',
        params: {'id': result.requestId},
      );
      expect(row(request.single)['status'], 'PENDING');
    });

    test('the provisional carpenter is immediately searchable and '
        'registrable', () async {
      final created = await repo.createProfileRequest(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        name: 'Same Visit',
        phone: '+8801733334444',
        requestedBy: 'user-1',
      );
      final hits = await repo.search(organizationId: 'org-1', q: 'Same Vi');
      expect(hits.map((c) => c.id), contains(created!.carpenter.id));

      final reg = await repo.register(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        carpenterIds: [created.carpenter.id],
        registeredBy: 'user-1',
      );
      expect(reg, (registered: 1, alreadyRegistered: 0));
    });

    test('a cross-org campaign is null', () async {
      final result = await repo.createProfileRequest(
        campaignId: 'nope',
        organizationId: 'org-1',
        name: 'X Y',
        phone: '+8801700000000',
        requestedBy: 'user-1',
      );
      expect(result, isNull);
    });
  });

  group('rosterForSession', () {
    test('returns the campaign roster for an in-org session, null for an '
        'unknown one', () async {
      await seedCampaign(db, id: 'camp-1');
      await seedCampaignSession(db, id: 'sess-1', campaignId: 'camp-1');
      await seedCarpenter(db, id: 'c-1');
      await seedRegistration(db, campaignId: 'camp-1', carpenterId: 'c-1');

      final roster =
          await repo.rosterForSession('sess-1', organizationId: 'org-1');
      expect(roster, isNotNull);
      expect(roster!.map((c) => c.id), ['c-1']);

      expect(
        await repo.rosterForSession('sess-1', organizationId: 'org-2'),
        isNull,
        reason: 'out-of-scope session must be indistinguishable from absent',
      );
      expect(
        await repo.rosterForSession('missing', organizationId: 'org-1'),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 4: Run to confirm failure**

```bash
cd server && dart test test/participant/participant_repo_test.dart
```

Expected: FAIL — `participant_repo.dart` does not exist.

- [ ] **Step 5: Implement the repo**

`server/lib/src/participant/participant_repo.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:uuid/uuid.dart';

import '../db/pool.dart';
import '../infra/audit.dart';
import '../infra/error_envelope.dart';

const Uuid _uuid = Uuid();

/// A carpenter as the API presents it. Holds the RAW `phone` and full
/// `displayCode` so the masking lives in exactly one place ([toWireJson]);
/// nothing outside this class may serialise a carpenter.
class CarpenterView {
  const CarpenterView({
    required this.id,
    required this.name,
    required this.displayCode,
    required this.phone,
    required this.territoryName,
    required this.dealerContext,
    required this.thumbnailUrl,
    required this.eligible,
    required this.syncStatus,
  });

  final String id;
  final String name;
  final String displayCode;
  final String phone;
  final String? territoryName;
  final String? dealerContext;
  final String? thumbnailUrl;
  final bool eligible;
  final String syncStatus;

  /// Exactly the shape `RegistrationRepositoryImpl._fromJson` parses, plus
  /// the additive `syncStatus` (spec 2a.D5). `attendanceState` is ABSENT on
  /// purpose: its vocabulary belongs to sub-project 4 (spec 2a.D4). Raw
  /// phone/NID never appear here (spec 2a.D2).
  Map<String, Object?> toWireJson() => {
    'id': id,
    'name': name,
    'displayId': 'CARP-••${_last4(displayCode)}',
    'phoneSuffix': _last4(phone),
    'territory': territoryName ?? '',
    'dealerContext': dealerContext,
    'thumbnailUrl': thumbnailUrl,
    'eligible': eligible,
    'syncStatus': syncStatus,
  };

  static String _last4(String s) =>
      s.length <= 4 ? s : s.substring(s.length - 4);
}

/// SQL for carpenters, registrations and profile requests. Every query is
/// scoped by `organization_id` inside the SQL itself (D7): a foreign row is
/// never selected, so `null` returns are the ONLY missing-vs-foreign signal
/// and the routes turn them into ordinary 404s.
class ParticipantRepo {
  ParticipantRepo(this._db) : _audit = AuditWriter(_db);

  final Db _db;
  final AuditWriter _audit;

  static const String _carpenterColumns =
      'c.id, c.full_name, c.phone, c.display_code, c.dealer_context, '
      'c.thumbnail_url, c.eligible, c.sync_status, t.name AS territory_name';

  CarpenterView _view(Map<String, Object?> r) => CarpenterView(
    id: r['id']! as String,
    name: r['full_name']! as String,
    displayCode: r['display_code']! as String,
    phone: r['phone']! as String,
    territoryName: r['territory_name'] as String?,
    dealerContext: r['dealer_context'] as String?,
    thumbnailUrl: r['thumbnail_url'] as String?,
    eligible: r['eligible']! as bool,
    syncStatus: r['sync_status']! as String,
  );

  /// Org-scoped master search over name (case-insensitive contains),
  /// display code (contains) and phone (suffix). Bounded at 50 rows: the
  /// workspace renders a short list and pagination is a spec non-goal until
  /// a real dataset demands it.
  Future<List<CarpenterView>> search({
    required String organizationId,
    required String q,
  }) async {
    final res = await _db.execute(
      'SELECT $_carpenterColumns FROM carpenters c '
      'LEFT JOIN territories t ON t.id = c.territory_id '
      'WHERE c.organization_id = @org AND ('
      "  c.full_name ILIKE '%' || @q || '%' "
      "  OR c.display_code ILIKE '%' || @q || '%' "
      "  OR c.phone LIKE '%' || @q"
      ') '
      'ORDER BY lower(c.full_name), c.id LIMIT 50',
      params: {'org': organizationId, 'q': q},
    );
    return res.map(row).map(_view).toList();
  }

  /// The registered carpenters of [sessionId]'s CAMPAIGN — registration is
  /// campaign-level; the client warms a per-session offline cache from it.
  /// `null` when the session (or its campaign) is not visible in
  /// [organizationId].
  Future<List<CarpenterView>?> rosterForSession(
    String sessionId, {
    required String organizationId,
  }) async {
    final scoped = await _db.execute(
      'SELECT s.campaign_id FROM campaign_sessions s '
      'JOIN campaigns cg ON cg.id = s.campaign_id '
      'WHERE s.id = @session AND cg.organization_id = @org',
      params: {'session': sessionId, 'org': organizationId},
    );
    if (scoped.isEmpty) return null;
    final campaignId = row(scoped.single)['campaign_id']! as String;

    final res = await _db.execute(
      'SELECT $_carpenterColumns FROM registrations r '
      'JOIN carpenters c ON c.id = r.carpenter_id '
      'LEFT JOIN territories t ON t.id = c.territory_id '
      'WHERE r.campaign_id = @campaign '
      'ORDER BY lower(c.full_name), c.id',
      params: {'campaign': campaignId},
    );
    return res.map(row).map(_view).toList();
  }

  /// Registers [carpenterIds] into [campaignId]. Returns `null` when the
  /// campaign is not visible in [organizationId] (route → 404). Throws
  /// [ApiException] `UNKNOWN_CARPENTER` naming ids that are unknown or
  /// cross-org — ids only, never names or phones (spec 2a.D2). All-or-
  /// nothing: a partially valid batch registers nothing.
  Future<({int registered, int alreadyRegistered})?> register({
    required String campaignId,
    required String organizationId,
    required List<String> carpenterIds,
    required String registeredBy,
    String? correlationId,
  }) async {
    final campaign = await _db.execute(
      'SELECT 1 FROM campaigns WHERE id = @id AND organization_id = @org',
      params: {'id': campaignId, 'org': organizationId},
    );
    if (campaign.isEmpty) return null;

    // List<String> binds as a Postgres text[] — exactly what ANY() wants
    // (the jsonb trap from slice-1 Task 9 is the OTHER direction).
    final known = await _db.execute(
      'SELECT id FROM carpenters '
      'WHERE organization_id = @org AND id = ANY(@ids)',
      params: {'org': organizationId, 'ids': carpenterIds},
    );
    final knownIds = known.map((r) => row(r)['id']! as String).toSet();
    final unknown =
        carpenterIds.where((id) => !knownIds.contains(id)).toList();
    if (unknown.isNotEmpty) {
      throw ApiException(
        ApiErrorCode.unknownCarpenter,
        message: 'One or more carpenter ids are unknown.',
        details: {'carpenterIds': unknown},
      );
    }

    late int inserted;
    await _db.tx((tx) async {
      final result = await tx.execute(
        Sql.named(
          'INSERT INTO registrations '
          '(campaign_id, carpenter_id, status, registered_by) '
          'SELECT @campaign, c.id, '
          "  CASE WHEN c.sync_status = 'PENDING_PROFILE_SYNC' "
          "       THEN '${RegistrationStatus.pendingProfileSync.wireValue}' "
          "       ELSE '${RegistrationStatus.registered.wireValue}' END, "
          '  @by '
          'FROM carpenters c WHERE c.id = ANY(@ids) '
          'ON CONFLICT (campaign_id, carpenter_id) DO NOTHING',
        ),
        parameters: {
          'campaign': campaignId,
          'ids': carpenterIds,
          'by': registeredBy,
        },
      );
      inserted = result.affectedRows;
      await _audit.writeTx(
        tx,
        action: 'registration.create',
        resourceType: 'campaign',
        resourceId: campaignId,
        actorId: registeredBy,
        correlationId: correlationId,
        payload: {
          'carpenterCount': carpenterIds.length,
          'registered': inserted,
        },
      );
    });
    return (
      registered: inserted,
      alreadyRegistered: carpenterIds.length - inserted,
    );
  }

  /// Creates the provisional carpenter AND the profile request in one
  /// transaction (spec 2a.D1), returning both so the route can hand the
  /// carpenter straight back for the client's basket. `null` when the
  /// campaign is not visible (route → 404).
  Future<({String requestId, CarpenterView carpenter})?> createProfileRequest({
    required String campaignId,
    required String organizationId,
    required String name,
    required String phone,
    required String requestedBy,
    String? correlationId,
  }) async {
    final campaign = await _db.execute(
      'SELECT 1 FROM campaigns WHERE id = @id AND organization_id = @org',
      params: {'id': campaignId, 'org': organizationId},
    );
    if (campaign.isEmpty) return null;

    final carpenterId = _uuid.v4();
    final requestId = _uuid.v4();
    late CarpenterView view;
    await _db.tx((tx) async {
      final inserted = await tx.execute(
        Sql.named(
          'INSERT INTO carpenters '
          '(id, organization_id, full_name, phone, source, sync_status, '
          ' display_code) '
          "VALUES (@id, @org, @name, @phone, 'PROFILE_REQUEST', "
          "        'PENDING_PROFILE_SYNC', "
          "        'CARP-' || lpad(nextval('carpenter_display_serial')::text, 8, '0')) "
          'RETURNING id, full_name, phone, display_code, dealer_context, '
          '          thumbnail_url, eligible, sync_status, '
          '          NULL::text AS territory_name',
        ),
        parameters: {
          'id': carpenterId,
          'org': organizationId,
          'name': name,
          'phone': phone,
        },
      );
      view = _view(row(inserted.single));
      await tx.execute(
        Sql.named(
          'INSERT INTO profile_requests '
          '(id, campaign_id, carpenter_id, requested_by, name, phone) '
          'VALUES (@id, @campaign, @carpenter, @by, @name, @phone)',
        ),
        parameters: {
          'id': requestId,
          'campaign': campaignId,
          'carpenter': carpenterId,
          'by': requestedBy,
          'name': name,
          'phone': phone,
        },
      );
      await _audit.writeTx(
        tx,
        action: 'profile_request.create',
        resourceType: 'campaign',
        resourceId: campaignId,
        actorId: requestedBy,
        correlationId: correlationId,
        // The carpenter id, never the name/phone (spec 2a.D2).
        payload: {'carpenterId': carpenterId, 'requestId': requestId},
      );
    });
    return (requestId: requestId, carpenter: view);
  }
}
```

- [ ] **Step 6: Run the repo tests — must pass**

```bash
cd server && dart test test/participant/participant_repo_test.dart test/db/migrator_test.dart
```

Expected: all pass, including the updated table inventory.

- [ ] **Step 7: Format, analyze, full suite, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server && git commit -m "feat(server): identity schema and ParticipantRepo

Migration 004_identity: carpenters (raw phone/nid stored as sub-project 8's
reconciliation join keys, indexed, deliberately NOT unique -- matching is
confidence + adjudication per D1), registrations (PK campaign+carpenter, so
re-registering is structurally a no-op), profile_requests.

ParticipantRepo owns every SQL statement and CarpenterView owns the masking
(CARP-••<last4>, 4-digit phone suffix) so the never-send-raw-PII rule (2a.D2)
has exactly one place to hold. A profile request creates its provisional
carpenter in the same transaction and returns it (2a.D1): same-visit
registration is a repo-level guarantee, not a UI convention."
```

---

### Task 6: Participant routes + composition

**Files:**
- Create: `server/lib/src/infra/json_fields.dart` (extracted helpers)
- Modify: `server/lib/src/campaign/campaign_routes.dart` (use them)
- Create: `server/lib/src/participant/participant_routes.dart`
- Modify: `server/lib/src/app.dart`
- Modify: `server/test/app_test.dart`
- Create: `server/test/participant/participant_routes_test.dart`

**Interfaces:**
- Consumes: `ParticipantRepo`/`CarpenterView` (Task 5), `idempotency` (Task 1), `requirePermission`/`authOf`/`authenticate`, `correlationOf`, `ApiException`.
- Produces:
  - `Router participantRouter({required Db db, required ParticipantRepo repo})` serving `GET /carpenters`, `GET /sessions/<id>/registrations`, `POST /campaigns/<id>/registrations`, `POST /campaigns/<id>/profile-requests`.
  - `server/lib/src/infra/json_fields.dart` exporting `Future<Map<String, Object?>> readJsonBody(Request)`, `Never badField(String field, String problem)`, `String? stringField(Map<String, Object?> body, String field, {String? reportAs})`, `List<String> stringListField(Map<String, Object?> body, String field)` — moved verbatim (minus the leading underscores) from `campaign_routes.dart`, plus the other `_*Field` helpers that file already has (`intField`, `boolField`, `listField`, `dateTimeField`), all renamed public.
  - `buildApp` gains a participant Cascade leg; the authenticate path predicate becomes the shared `_authenticateUnder(roots, ...)`.

- [ ] **Step 1: Extract the JSON field helpers**

Create `server/lib/src/infra/json_fields.dart` by MOVING (not copying) `_readJsonBody`, `_badField`, `_stringField`, `_intField`, `_boolField`, `_listField`, `_stringListField`, `_dateTimeField` out of `server/lib/src/campaign/campaign_routes.dart`, renamed without underscores, keeping every doc comment. Update `campaign_routes.dart` to import and use them (`_readJsonBody(...)` → `readJsonBody(...)` etc.). No behaviour change.

```bash
cd server && dart analyze --fatal-infos && dart test test/campaign/
```

Expected: analyze clean, campaign suites green — they are the extraction's safety net.

- [ ] **Step 2: Write the failing route tests**

`server/test/participant/participant_routes_test.dart`:

```dart
import 'dart:convert';

import 'package:campaign_service/src/app.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

/// Drives the REAL buildApp tree (the slice-1 app_test lesson: a
/// hand-assembled pipeline is exactly how the routing bug went untested).
void main() {
  late Db db;
  late Handler handler;
  late String creatorToken; // campaign_create
  late String viewerToken; // no write permission
  var seq = 0;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // user-1, campaign_creator
    await seedOrganizationWithUser(
      db,
      userId: 'user-2',
      username: 'viewer',
      roles: const ['reporting_viewer'],
    );
    final tokens = TokenService(db: db, config: config);
    creatorToken = (await tokens.issueFor('user-1')).accessToken;
    viewerToken = (await tokens.issueFor('user-2')).accessToken;
    handler = buildApp(db: db, config: config);

    await seedCampaign(db, id: 'camp-1');
    await seedCarpenter(db, id: 'c-1'); // Md. Karim …4821
  });
  tearDown(() async => db.close());

  String nextKey() => 'key-${seq++}';

  Future<Response> get(String path, {String? bearer}) => handler(
    Request(
      'GET',
      Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'authorization': 'Bearer $bearer'},
    ),
  );

  Future<Response> post(
    String path,
    Map<String, Object?> body, {
    required String bearer,
    String? key,
  }) => handler(
    Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      headers: {
        'authorization': 'Bearer $bearer',
        'content-type': 'application/json',
        if (key != null) 'Idempotency-Key': key,
      },
    ),
  );

  Future<Map<String, Object?>> decode(Response res) async =>
      jsonDecode(await res.readAsString()) as Map<String, Object?>;

  group('GET /carpenters', () {
    test('401 without a token, through the real tree', () async {
      expect((await get('/carpenters?q=ka')).statusCode, 401);
    });

    test('400 below the 2-character minimum', () async {
      final res = await get('/carpenters?q=k', bearer: creatorToken);
      expect(res.statusCode, 400);
    });

    test('returns masked items', () async {
      final res = await get('/carpenters?q=karim', bearer: creatorToken);
      expect(res.statusCode, 200);
      final items = (await decode(res))['items']! as List;
      final first = items.first as Map<String, Object?>;
      expect(first['displayId'], 'CARP-••4821');
      expect(first['phoneSuffix'], '4821');
      expect(first['syncStatus'], 'LOCAL_ONLY');
    });
  });

  group('POST /campaigns/<id>/registrations', () {
    test('registers and answers the counts', () async {
      final res = await post(
        '/campaigns/camp-1/registrations',
        {'carpenterIds': ['c-1']},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 200);
      expect(await decode(res), {'registered': 1, 'alreadyRegistered': 0});
    });

    test('403 without campaign_create', () async {
      final res = await post(
        '/campaigns/camp-1/registrations',
        {'carpenterIds': ['c-1']},
        bearer: viewerToken,
        key: nextKey(),
      );
      expect(res.statusCode, 403);
    });

    test('404 for a cross-org campaign (D7), 422 UNKNOWN_CARPENTER for a '
        'bad id', () async {
      expect(
        (await post(
          '/campaigns/not-mine/registrations',
          {'carpenterIds': ['c-1']},
          bearer: creatorToken,
          key: nextKey(),
        )).statusCode,
        404,
      );
      final res = await post(
        '/campaigns/camp-1/registrations',
        {'carpenterIds': ['ghost']},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 422);
      expect(
        ((await decode(res))['error']! as Map)['code'],
        'UNKNOWN_CARPENTER',
      );
    });

    test('empty carpenterIds is a 400, not a silent no-op', () async {
      final res = await post(
        '/campaigns/camp-1/registrations',
        {'carpenterIds': <String>[]},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 400);
    });

    test('replays through the idempotency middleware', () async {
      final key = nextKey();
      final first = await post(
        '/campaigns/camp-1/registrations',
        {'carpenterIds': ['c-1']},
        bearer: creatorToken,
        key: key,
      );
      final replay = await post(
        '/campaigns/camp-1/registrations',
        {'carpenterIds': ['c-1']},
        bearer: creatorToken,
        key: key,
      );
      expect(await replay.readAsString(), await first.readAsString(),
          reason: 'same key + same body = verbatim replay, so the counts '
              'must say registered:1 both times, NOT alreadyRegistered:1');
      final rows = await db.execute('SELECT 1 FROM registrations');
      expect(rows, hasLength(1));
    });

    test('a missing Idempotency-Key is a 400', () async {
      final res = await post(
        '/campaigns/camp-1/registrations',
        {'carpenterIds': ['c-1']},
        bearer: creatorToken,
      );
      expect(res.statusCode, 400);
      expect(
        ((await decode(res))['error']! as Map)['code'],
        'IDEMPOTENCY_KEY_REQUIRED',
      );
    });
  });

  group('POST /campaigns/<id>/profile-requests', () {
    test('201 with the provisional carpenter, which is then registrable',
        () async {
      final res = await post(
        '/campaigns/camp-1/profile-requests',
        {'name': 'New Person', 'phone': '+880 1711-112222'},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 201);
      final body = await decode(res);
      expect(body['requestId'], isA<String>());
      final carpenter = body['carpenter']! as Map<String, Object?>;
      expect(carpenter['syncStatus'], 'PENDING_PROFILE_SYNC');
      expect(carpenter['phoneSuffix'], '2222');
      expect(carpenter.containsKey('phone'), isFalse,
          reason: 'no raw-phone key on the wire (spec 2a.D2)');
      expect(jsonEncode(body), isNot(contains('+880')),
          reason: 'nothing in the body may carry the full number');

      final reg = await post(
        '/campaigns/camp-1/registrations',
        {'carpenterIds': [carpenter['id']]},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(await decode(reg), {'registered': 1, 'alreadyRegistered': 0});
    });

    test('400 for a malformed phone, naming the field', () async {
      final res = await post(
        '/campaigns/camp-1/profile-requests',
        {'name': 'X', 'phone': 'call me maybe'},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 400);
      final error = (await decode(res))['error']! as Map;
      expect((error['details']! as Map)['field'], 'phone');
    });

    test('400 for a missing name', () async {
      final res = await post(
        '/campaigns/camp-1/profile-requests',
        {'phone': '+8801711112222'},
        bearer: creatorToken,
        key: nextKey(),
      );
      expect(res.statusCode, 400);
    });
  });

  group('GET /sessions/<id>/registrations', () {
    test('roster for an in-org session; 404 out of scope', () async {
      await seedCampaignSession(db, id: 'sess-1', campaignId: 'camp-1');
      await seedRegistration(db, campaignId: 'camp-1', carpenterId: 'c-1');

      final res =
          await get('/sessions/sess-1/registrations', bearer: creatorToken);
      expect(res.statusCode, 200);
      final items = (await decode(res))['items']! as List;
      expect((items.single as Map)['id'], 'c-1');

      expect(
        (await get('/sessions/ghost/registrations', bearer: creatorToken))
            .statusCode,
        404,
      );
    });
  });
}
```

- [ ] **Step 3: Run to confirm failure**

```bash
cd server && dart test test/participant/participant_routes_test.dart
```

Expected: FAIL — `participantRouter` does not exist (404s from the Cascade).

- [ ] **Step 4: Implement the routes**

`server/lib/src/participant/participant_routes.dart`:

```dart
import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/correlation.dart';
import '../infra/error_envelope.dart';
import '../infra/idempotency.dart';
import '../infra/json_fields.dart';
import 'participant_repo.dart';

/// Accepts `+`, digits, spaces and dashes; 8–15 digits after normalisation
/// (E.164 ceiling). Anything else is a badRequest naming the field — the
/// same "no silent coercion" contract as json_fields.dart.
String _requirePhone(Map<String, Object?> body) {
  final raw = stringField(body, 'phone');
  final normalized = raw?.replaceAll(RegExp(r'[ -]'), '');
  if (normalized == null ||
      !RegExp(r'^\+?\d{8,15}$').hasMatch(normalized)) {
    badField('phone', 'must be 8-15 digits, optionally with +, spaces or '
        'dashes');
  }
  return normalized;
}

String _requireNonEmptyString(Map<String, Object?> body, String field) {
  final value = stringField(body, field);
  if (value == null || value.trim().isEmpty) {
    badField(field, 'is required and must be non-empty');
  }
  return value.trim();
}

/// `/carpenters`, `/sessions/<id>/registrations` and the two write routes
/// under `/campaigns/<id>/`. Reads are authenticate-only (same posture and
/// same product-confirmation caveat as campaign reads — no read permission
/// exists in the client's claim vocabulary); writes require
/// `campaign_create`, matching the client's own route guard.
Router participantRouter({required Db db, required ParticipantRepo repo}) {
  final router = Router();

  router.get('/carpenters', (Request request) async {
    final auth = authOf(request);
    final q = request.url.queryParameters['q'] ?? '';
    if (q.trim().length < 2) {
      // The client UI already enforces this; the server re-enforces it so a
      // one-character probe cannot enumerate the whole org master.
      throw ApiException(
        ApiErrorCode.badRequest,
        message: '"q" must be at least 2 characters.',
        details: {'field': 'q'},
      );
    }
    final items = await repo.search(
      organizationId: auth.organizationId,
      q: q.trim(),
    );
    return _jsonResponse({
      'items': [for (final c in items) c.toWireJson()],
    });
  });

  router.get('/sessions/<id>/registrations', (
    Request request,
    String id,
  ) async {
    final auth = authOf(request);
    final roster = await repo.rosterForSession(
      id,
      organizationId: auth.organizationId,
    );
    if (roster == null) throw ApiException(ApiErrorCode.notFound);
    return _jsonResponse({
      'items': [for (final c in roster) c.toWireJson()],
    });
  });

  router.post(
    '/campaigns/<id>/registrations',
    const Pipeline()
        .addMiddleware(requirePermission('campaign_create'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final campaignId = request.params['id']!;
          final body = await readJsonBody(request);
          final ids = stringListField(body, 'carpenterIds');
          if (ids.isEmpty) {
            badField('carpenterIds', 'must be a non-empty array');
          }
          final result = await repo.register(
            campaignId: campaignId,
            organizationId: auth.organizationId,
            carpenterIds: ids,
            registeredBy: auth.userId,
            correlationId: correlationOf(request),
          );
          if (result == null) throw ApiException(ApiErrorCode.notFound);
          return _jsonResponse({
            'registered': result.registered,
            'alreadyRegistered': result.alreadyRegistered,
          });
        }),
  );

  router.post(
    '/campaigns/<id>/profile-requests',
    const Pipeline()
        .addMiddleware(requirePermission('campaign_create'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final campaignId = request.params['id']!;
          final body = await readJsonBody(request);
          final name = _requireNonEmptyString(body, 'name');
          final phone = _requirePhone(body);
          final result = await repo.createProfileRequest(
            campaignId: campaignId,
            organizationId: auth.organizationId,
            name: name,
            phone: phone,
            requestedBy: auth.userId,
            correlationId: correlationOf(request),
          );
          if (result == null) throw ApiException(ApiErrorCode.notFound);
          return Response(
            201,
            body: jsonEncode({
              'requestId': result.requestId,
              'carpenter': result.carpenter.toWireJson(),
            }),
            headers: {'content-type': 'application/json'},
          );
        }),
  );

  return router;
}

Response _jsonResponse(Map<String, Object?> body) => Response.ok(
  jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
```

- [ ] **Step 5: Compose in `buildApp`**

In `server/lib/src/app.dart`:

1. Generalise the predicate middleware — rename `_authenticateOnlyUnderCampaigns` to `_authenticateUnder` taking the path roots, keeping its entire doc comment (adjusting the first paragraph):

```dart
Middleware _authenticateUnder(
  Set<String> roots, {
  required Db db,
  required TokenService tokens,
}) {
  final authenticated = authenticate(db: db, tokens: tokens);
  return (Handler inner) {
    final gated = authenticated(inner);
    return (Request request) {
      final path = request.url.path;
      final matches = roots.any(
        (root) => path == root || path.startsWith('$root/'),
      );
      return matches ? gated(request) : inner(request);
    };
  };
}
```

2. The campaign leg keeps `{'campaigns'}`. Add the participant leg after it (before the seed leg):

```dart
  final participantHandler = const Pipeline()
      .addMiddleware(
        // 'campaigns' is here too: /campaigns/<id>/registrations and
        // /campaigns/<id>/profile-requests reach this leg via Cascade
        // fall-through from campaignRouter (which does not know them). For a
        // request that already passed the campaign leg's authenticate this
        // runs authenticate twice -- one extra indexed query, accepted for
        // keeping both legs independently fail-closed.
        _authenticateUnder(
          const {'carpenters', 'sessions', 'campaigns'},
          db: db,
          tokens: tokens,
        ),
      )
      .addHandler(
        participantRouter(db: db, repo: ParticipantRepo(db)).call,
      );

  var cascade = Cascade()
      .add(publicRouter.call)
      .add(authHandler)
      .add(campaignHandler)
      .add(participantHandler);
```

3. Add imports for `participant/participant_repo.dart` and `participant/participant_routes.dart`.

4. In `server/test/app_test.dart`, add:

```dart
  test('an unauthenticated GET /carpenters is 401 through the real tree',
      () async {
    final handler = buildApp(db: db, config: _config());
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/carpenters?q=ka')),
    );
    expect(res.statusCode, 401);
  });
```

(The existing "unmatched path is 404" test keeps guarding the other direction.)

- [ ] **Step 6: Run the route tests — must pass**

```bash
cd server && dart test test/participant/ test/app_test.dart test/campaign/ test/seed/
```

Expected: all green — participant, the composition tests, and the untouched campaign/seed suites.

- [ ] **Step 7: Format, analyze, full suite, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server && git commit -m "feat(server): participant routes -- search, roster, register, profile requests

GET /carpenters (2-char minimum re-enforced server-side), GET
/sessions/<id>/registrations, POST /campaigns/<id>/registrations and
/profile-requests, composed as a new Cascade leg behind the generalised
_authenticateUnder predicate. Writes require campaign_create and run through
idempotency; the registration replay test pins that a replayed 'registered:1'
body is returned verbatim rather than re-counted as alreadyRegistered.

json_fields.dart is the campaign router's field helpers extracted verbatim;
campaign_routes.dart now imports them (its suites are the extraction's net)."
```

---

### Task 7: Seed fixtures for carpenters

**Files:**
- Modify: `server/lib/src/seed/seed_routes.dart`

**Interfaces:**
- Consumes: existing seed machinery (`_seedBaseline`, `_truncateEverything`, fixture id constants).
- Produces: `POST /__test__/reset` also seeds two carpenters with **fixed, documented values** (below) that Task 10's Maestro flow and Task 8's parity tests hard-code. Exported constants `seedCarpenterKarimId = 'CARP_E2E'`, `seedCarpenterUddinId = 'CARP_E2E_2'`.

- [ ] **Step 1: Extend the truncate list**

In `_allSeedableTables`, add at the TOP of the list (before `campaign_decisions`):

```dart
  'profile_requests',
  'registrations',
  'carpenters',
```

(The single `TRUNCATE ... CASCADE` statement makes order cosmetic; the list exists to be complete, so keep it complete.)

- [ ] **Step 2: Add the carpenter fixture**

Add near the other fixture constants:

```dart
// Mirror tool/mock_server's carpenters (same ids and names) so
// carpenter-facing flows keep working whichever backend is behind
// API_BASE_URL. displayId on the wire: CARP-••4821 / CARP-••7734;
// phoneSuffix: 4821 / 7734 (4 digits — Task 8 aligns the mock's data).
const String seedCarpenterKarimId = 'CARP_E2E';
const String seedCarpenterUddinId = 'CARP_E2E_2';
```

And the seeding function, called from the `/reset` handler after `_seedCampaignFixture`:

```dart
Future<void> _seedCarpenterFixture(Db db) async {
  const carpenters = [
    (
      id: seedCarpenterKarimId,
      name: 'Md. Karim',
      phone: '+8801700004821',
      code: 'CARP-00004821',
      territory: seedTerritoryNorthId,
      dealer: 'Rahman Traders',
    ),
    (
      id: seedCarpenterUddinId,
      name: 'Karim Uddin',
      phone: '+8801700007734',
      code: 'CARP-00007734',
      territory: seedTerritorySouthId,
      dealer: null,
    ),
  ];
  for (final c in carpenters) {
    await db.execute(
      'INSERT INTO carpenters '
      '(id, organization_id, full_name, phone, territory_id, '
      " dealer_context, display_code, source, sync_status) "
      "VALUES (@id, @org, @name, @phone, @territory, @dealer, @code, "
      "        'SEED', 'LOCAL_ONLY')",
      params: {
        'id': c.id,
        'org': seedOrganizationId,
        'name': c.name,
        'phone': c.phone,
        'territory': c.territory,
        'dealer': c.dealer,
        'code': c.code,
      },
    );
  }
}
```

In the `/__test__/reset` handler add `await _seedCarpenterFixture(db);` after `_seedCampaignFixture(...)`.

- [ ] **Step 3: Pin it with a test**

Append to `server/test/seed/seed_gate_test.dart` (inside the seeding-enabled group; mirror its existing request helper):

```dart
  test('reset seeds the two carpenter fixtures', () async {
    // (use the file's existing enabled-config handler + reset call pattern)
    final res = await db.execute(
      'SELECT id, display_code FROM carpenters ORDER BY id',
    );
    final byId = {
      for (final r in res.map(row)) r['id']! as String: r['display_code'],
    };
    expect(byId, {
      'CARP_E2E': 'CARP-00004821',
      'CARP_E2E_2': 'CARP-00007734',
    });
  });
```

Open `seed_gate_test.dart` first and reuse its existing setup (it already builds a seeding-enabled `buildApp` and POSTs `/__test__/reset`); the snippet above shows only the new assertions.

- [ ] **Step 4: Run, format, analyze, commit**

```bash
cd server && dart test test/seed/ && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server && git commit -m "feat(server): seed carpenter fixtures for e2e

reset now leaves CARP_E2E (Md. Karim, ••4821, north) and CARP_E2E_2
(Karim Uddin, ••7734, south) behind -- same ids and names as the mock's
seeds, values fixed and documented so Maestro flows hard-code rather than
discover them. Truncate list extended with the 004_identity tables."
```

---

### Task 8: Mock server contract update + parity tests

**Files:**
- Modify: `tool/mock_server/bin/server.dart`
- Modify: `server/test/contract/parity_test.dart`

**Interfaces:**
- Consumes: the ratified wire shapes (Tasks 5–6), mock's `_Store`/`_json`/`_body` helpers.
- Produces: mock emits the ratified registration contract; `ParityTarget` gains `postJson`.

- [ ] **Step 1: Update the mock's carpenter seeds and routes**

In `tool/mock_server/bin/server.dart`:

1. In the `carpenters` seed list: change `'phoneSuffix': '821'` → `'4821'` and `'734'` → `'7734'` (the ratified mask is the last **4** digits), and add `'syncStatus': 'LOCAL_ONLY'` to both. Keep `attendanceState` — the still-mocked `crm`/`field` configs need it, and the shared contract makes it optional (spec 2a.D4).

2. Replace the registration write routes:

```dart
  r.post('/campaigns/<id>/registrations', (Request req, String id) async {
    final b = await _body(req);
    final ids = (b['carpenterIds'] as List?)?.cast<String>() ?? const [];
    if (ids.isEmpty) {
      return _json({
        'error': {'code': 'BAD_REQUEST', 'message': 'carpenterIds required'},
      }, status: 400);
    }
    return _json({'registered': ids.length, 'alreadyRegistered': 0});
  });

  r.post('/campaigns/<id>/profile-requests', (Request req, String id) async {
    final b = await _body(req);
    // A zero-padded 4-digit serial so displayId/phoneSuffix satisfy the
    // parity regexes ^CARP-••\d{4}$ and ^\d{4}$ exactly like the real
    // server's masks do.
    final serial = store.nextId().toString().padLeft(4, '0');
    final carpenter = {
      'id': 'CARP_REQ_$serial',
      'name': b['name'] ?? '',
      'displayId': 'CARP-••$serial',
      'phoneSuffix': serial,
      'territory': '',
      'dealerContext': null,
      'thumbnailUrl': null,
      'eligible': true,
      'syncStatus': 'PENDING_PROFILE_SYNC',
    };
    store.carpenters.add(carpenter);
    return _json({
      'requestId': 'REQ-$serial',
      'carpenter': carpenter,
    }, status: 201);
  });
```

The mock's `_Store` already has a `_seq` counter (it starts at 100 for campaign ids); add a public increment if absent:

```dart
  int nextId() => ++_seq;
```

- [ ] **Step 2: Extend the parity harness with POST**

In `server/test/contract/parity_test.dart`, extend `ParityTarget`:

```dart
class ParityTarget {
  ParityTarget(this.name, this.getJson, this.postJson);

  final String name;
  final Future<Map<String, Object?>> Function(String pathAndQuery) getJson;
  final Future<({int status, Map<String, Object?> body})> Function(
    String pathAndQuery,
    Map<String, Object?> body,
  ) postJson;
}
```

In `buildTargets`, build the real `postJson` through the existing in-process `handler` (adding `Idempotency-Key: parity-${_keySeq++}` and `content-type: application/json` headers, `_keySeq` a file-level counter) and the mock `postJson` via `HttpClient` POST — mirror the existing `_httpGet` helper with a `_httpPost` that writes the JSON body and returns status + decoded body. Update the two existing `ParityTarget(...)` constructions to pass their `postJson`.

Also have `buildTargets` seed the real side's carpenters when a new named parameter `seedCarpenters: true` is passed: call `seedCarpenter(db, id: 'CARP_E2E')` and `seedCarpenter(db, id: 'CARP_E2E_2', name: 'Karim Uddin', phone: '+8801700007734', displayCode: 'CARP-00007734')` (from `../support/seed_fixtures.dart`).

- [ ] **Step 3: Add the parity tests**

Append inside the existing `for (final targetName in ['real', 'mock'])` loop (or a new loop of the same shape):

```dart
    test('$targetName: carpenter search items satisfy the masked shape',
        () async {
      final targets =
          await buildTargets(campaignCount: 0, seedCarpenters: true);
      final target = targetName == 'real' ? targets.real : targets.mock;

      final body = await target.getJson('/carpenters?q=karim');
      final items = (body['items']! as List).cast<Map<String, Object?>>();
      expect(items, isNotEmpty);
      for (final c in items) {
        expect(c['displayId'], matches(RegExp(r'^CARP-••\d{4}$')));
        expect(c['phoneSuffix'], matches(RegExp(r'^\d{4}$')));
        expect(c['eligible'], isA<bool>());
        expect(
          c['syncStatus'],
          anyOf('LOCAL_ONLY', 'PENDING_PROFILE_SYNC'),
        );
        // attendanceState is OPTIONAL in the shared contract (2a.D4): the
        // real service omits it, the mock still emits it for the configs
        // that remain mocked. If present it must at least be a string.
        if (c.containsKey('attendanceState')) {
          expect(c['attendanceState'], isA<String>());
        }
      }
    });

    test('$targetName: registration answers the counts shape', () async {
      final targets =
          await buildTargets(campaignCount: 1, seedCarpenters: true);
      final target = targetName == 'real' ? targets.real : targets.mock;
      // seed-0 is buildTargets' first campaign on the real side; the mock
      // ignores the id entirely.
      final res = await target.postJson(
        '/campaigns/seed-0/registrations',
        {'carpenterIds': ['CARP_E2E']},
      );
      expect(res.status, 200);
      expect(res.body['registered'], isA<int>());
      expect(res.body['alreadyRegistered'], isA<int>());
    });

    test('$targetName: profile request answers 201 with a provisional '
        'carpenter', () async {
      final targets =
          await buildTargets(campaignCount: 1, seedCarpenters: false);
      final target = targetName == 'real' ? targets.real : targets.mock;
      final res = await target.postJson(
        '/campaigns/seed-0/profile-requests',
        {'name': 'Parity Person', 'phone': '+8801755556666'},
      );
      expect(res.status, 201);
      expect(res.body['requestId'], isA<String>());
      final carpenter = res.body['carpenter']! as Map<String, Object?>;
      expect(carpenter['syncStatus'], 'PENDING_PROFILE_SYNC');
      expect(carpenter['displayId'], matches(RegExp(r'^CARP-••\d{4}$')));
      expect(carpenter.containsKey('phone'), isFalse);
    });
```

- [ ] **Step 4: Run the parity suite**

```bash
cd tool/mock_server && dart pub get
cd ../../server && dart test test/contract/parity_test.dart
```

Expected: all pass on both targets. A failure here IS the deliverable working — it means mock and real disagree; fix the disagreeing side, never the assertion.

- [ ] **Step 5: Check `.maestro` and the app for the old 3-digit suffixes**

```bash
grep -rn "'821'\|'734'" .maestro lib tool/mock_server | grep -v 4821 | grep -v 7734
```

For each hit that refers to a carpenter phone suffix, update to the 4-digit value. Known hit: `lib/core/dev/e2e_seeder.dart` lines ~19 and ~30 (`'phoneSuffix': '821'` → `'4821'`, `'734'` → `'7734'`). `searchCached` matches with `endsWith`, so a Maestro flow typing `821` still matches `4821` — but the seeder data should carry the ratified shape regardless.

- [ ] **Step 6: Format, analyze, run BOTH packages' checks, commit**

```bash
cd tool/mock_server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd ../../server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
cd .. && flutter test test/  # e2e_seeder is app code; make sure nothing pinned the old suffix
git add tool/mock_server server lib/core/dev/e2e_seeder.dart
git commit -m "feat(mock): ratify the registration contract; parity tests pin it

The mock's registration routes now answer the ratified shapes: registrations
-> {registered, alreadyRegistered}; profile-requests -> 201 {requestId,
carpenter} with a PENDING_PROFILE_SYNC provisional. Carpenter seeds gain
syncStatus and the 4-digit phone suffix the mask rule defines (was 3).
attendanceState stays in the mock only -- the parity test pins it as
OPTIONAL in the shared contract (2a.D4), present for the still-mocked
crm/field configs, absent from the real service."
```

---

# Phase 3 — Client cut-over and e2e

### Task 9: Client cut-over

**Files:**
- Modify: `lib/domain/registration/registration_repository.dart`
- Modify: `lib/data/registration/registration_repository_impl.dart`
- Modify: `lib/features/registration/application/registration_controller.dart`
- Modify: `lib/features/registration/presentation/registration_workspace_screen.dart`
- Create: `test/data/registration/registration_repository_impl_test.dart`

**Interfaces:**
- Consumes: `campaign_contracts` (`RegistrationStatus` — not directly used here, but the shim from Task 4 must already be merged), server contract from Task 6.
- Produces:
  - `RegistrationRepository.requestNewProfile` returns `Future<Result<RegisteredCarpenter>>` (was `Result<void>`).
  - `RegistrationRepositoryImpl.register` sends a **UUID v4** `Idempotency-Key` per call.
  - `RegistrationController.requestNewProfile` adds the returned carpenter to the basket.

- [ ] **Step 1: Write the failing repository tests**

`test/data/registration/registration_repository_impl_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:acsl_campaign/data/registration/registration_repository_impl.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every request and answers a canned response — the transport-level
/// twin of slice-1 Task 10's key-string tests.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._respond);
  final ResponseBody Function(RequestOptions options) _respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Object? body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

const _carpenterJson = {
  'id': 'CARP_NEW',
  'name': 'New Person',
  'displayId': 'CARP-••0042',
  'phoneSuffix': '0042',
  'territory': '',
  'dealerContext': null,
  'thumbnailUrl': null,
  'eligible': true,
  'syncStatus': 'PENDING_PROFILE_SYNC',
};

void main() {
  late _RecordingAdapter adapter;
  late RegistrationRepositoryImpl repo;
  late AppDatabase db;

  RegistrationRepositoryImpl build(
    ResponseBody Function(RequestOptions) respond,
  ) {
    adapter = _RecordingAdapter(respond);
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    return RegistrationRepositoryImpl(dio, db);
  }

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('register sends a UUID v4 idempotency key, fresh per call', () async {
    repo = build((_) => _jsonBody({'registered': 1, 'alreadyRegistered': 0}));

    await repo.register('camp-1', ['c-1']);
    await repo.register('camp-1', ['c-1']);

    final keys = [
      for (final r in adapter.requests) r.headers['Idempotency-Key'] as String,
    ];
    expect(keys[0], matches(uuidV4),
        reason: 'the old comma-joined carpenter-id key collides across '
            'users and leaks ids into header logs');
    expect(keys[1], matches(uuidV4));
    expect(keys[0], isNot(keys[1]),
        reason: 'a new submit is a new operation, not a replay');
  });

  test('requestNewProfile parses the 201 and returns the provisional '
      'carpenter', () async {
    repo = build(
      (_) => _jsonBody(
        {'requestId': 'REQ-1', 'carpenter': _carpenterJson},
        status: 201,
      ),
    );

    final result = await repo.requestNewProfile('camp-1', 'New', '+88017');
    final carpenter = result.fold((c) => c, (f) => fail('expected Ok: $f'));
    expect(carpenter.id, 'CARP_NEW');
    expect(carpenter.displayId, 'CARP-••0042');
  });

  test('an absent attendanceState maps to notCaptured explicitly', () async {
    repo = build(
      (_) => _jsonBody({
        'items': [_carpenterJson], // no attendanceState key at all
      }),
    );
    final result = await repo.searchMaster('new');
    final items = result.fold((v) => v, (f) => fail('expected Ok: $f'));
    expect(items.single.attendanceState.name, 'notCaptured');
  });
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
flutter test test/data/registration/registration_repository_impl_test.dart
```

Expected: FAIL — the key is the comma-joined list and `requestNewProfile` returns `Result<void>` (compile error on the fold), which is the right reason.

- [ ] **Step 3: Change the domain contract**

`lib/domain/registration/registration_repository.dart` — change the signature and its doc:

```dart
  /// Submits a new-profile request and returns the provisional carpenter the
  /// server created for it (spec 2a.D1) so the caller can put the person
  /// straight into the registration basket — request → basket → register in
  /// one visit.
  Future<Result<RegisteredCarpenter>> requestNewProfile(
    String campaignId,
    String name,
    String phone,
  );
```

- [ ] **Step 4: Update the data implementation**

In `lib/data/registration/registration_repository_impl.dart`:

1. Add `import 'package:uuid/uuid.dart';` and a file-level `const Uuid _uuid = Uuid();`.

2. `register`: replace the key line:

```dart
        options: _options({'Idempotency-Key': _uuid.v4()}, trace),
```

(A per-call UUID: `RetryInterceptor` re-sends the same request object with the same header, so genuine retries still replay; a *new* call is a new operation. The old comma-joined id list collided across users on the `(user, key)` PK and leaked carpenter ids into any header-logging middleware.)

3. `requestNewProfile`: parse the 201:

```dart
  @override
  Future<Result<RegisteredCarpenter>> requestNewProfile(
    String campaignId,
    String name,
    String phone,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns/$campaignId/profile-requests',
        data: {'name': name, 'phone': phone},
        options: _options({'Idempotency-Key': _uuid.v4()}, null),
      );
      return Ok(_fromJson(res.data!['carpenter'] as Map<String, dynamic>));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
```

4. Make the attendance mapping explicit — replace `_attendance` with:

```dart
  /// `attendanceState` is OPTIONAL on the wire: the real service omits it
  /// until sub-project 4 defines the vocabulary; the mock still sends it.
  /// Absent → notCaptured is the deliberate, visible fallback for a
  /// display-only field (the shared-contract rule allows a fallback that is
  /// CHOSEN, not silently inherited from firstWhere's orElse). An
  /// unrecognised non-null value also lands on notCaptured — for this field
  /// that under-claims (shows "not captured" instead of a state we don't
  /// know), which is the safe direction.
  AttendanceStatus _attendanceFromWire(String? wire) {
    if (wire == null) return AttendanceStatus.notCaptured;
    for (final s in AttendanceStatus.values) {
      if (s.name == wire) return s;
    }
    return AttendanceStatus.notCaptured;
  }
```

and update `_fromJson` to call `_attendanceFromWire(j['attendanceState'] as String?)`.

- [ ] **Step 5: Controller — basket auto-add and the D1 comment**

In `lib/features/registration/application/registration_controller.dart`:

1. Replace the class doc comment (it still encodes the pre-D1 world):

```dart
/// Registration Workspace (W-06). Resolves participants against the
/// campaign service's carpenter master and builds a registration basket.
///
/// Since D1 (foundation spec, 2026-08-10) the master is OURS: a missing
/// profile becomes a profile request that immediately creates a local
/// provisional carpenter (spec 2a.D1) — returned by the server and added
/// straight to the basket below, so request → basket → register completes
/// in one visit. Ratification/merge against BMD Sales is sub-project 8's
/// adjudication queue, not something this workspace waits for.
```

2. Replace `requestNewProfile`:

```dart
  Future<void> requestNewProfile(String name, String phone) async {
    final res = await ref
        .read(registrationRepositoryProvider)
        .requestNewProfile(arg, name, phone);
    state = res.fold(
      (carpenter) => state.copyWith(
        basket: {...state.basket, carpenter.id: carpenter},
        message: 'Profile request submitted — pending sync',
      ),
      (f) => state.copyWith(message: f.message ?? 'Request failed'),
    );
  }
```

- [ ] **Step 6: Screen — fix the pre-D1 sheet copy and add the e2e semantics id**

In `lib/features/registration/presentation/registration_workspace_screen.dart`:

1. Every Maestro-driven control needs a semantics id — the repo's flows drive
   controls by `id:`, never by text (see `carpenter_search_confirm.yaml`:
   `search_field`, `search_result`, `confirm_continue`), and none of W-06's
   controls have one yet. Add `Semantics(identifier: ...)` wrappers, the same
   pattern as `dev_launcher_screen.dart:48`, to: the search field
   (`registration_search`), the request-profile button
   (`registration_request_profile`), the side-sheet name/phone fields and
   submit (`profile_name`, `profile_phone`, `profile_submit`), the register
   button (`registration_submit`), and — per result row — the add button:

```dart
                            : Semantics(
                                identifier: 'registration_add_${person.id}',
                                child: IconButton(
                                  icon: Icon(
                                    inBasket
                                        ? Icons.check
                                        : Icons.add_circle_outline,
                                  ),
                                  onPressed: inBasket
                                      ? null
                                      : () => c.addToBasket(person),
                                ),
                              ),
```

2. In `_showRequestProfileSheet`: title `'Request new Sales Eco profile'` → `'Request new carpenter profile'`, and the explanatory `Text` → 

```dart
        const Text(
          'Creates a local profile pending ratification and adds the '
          'participant to your basket as "Pending profile sync".',
        ),
```

- [ ] **Step 7: Run everything app-side**

```bash
flutter analyze --fatal-infos
flutter test
```

Expected: analyze clean; **417+ passing / 29 skipped** (414 baseline + the 3 new repository tests; more if you added others). Any pre-existing test that pinned the old snackbar/sheet copy or the old `requestNewProfile` signature: update it to the new contract — the contract change is the point of the task, but list every such edit in the commit message.

- [ ] **Step 8: Format and commit**

```bash
dart format --set-exit-if-changed lib test
git add lib test
git commit -m "feat(client): registration workspace speaks the ratified contract

Idempotency-Key for register is a per-call UUID v4 -- the comma-joined
carpenter-id list collided across users on the server's (user, key) PK and
leaked ids into header logs. requestNewProfile now parses the 201 and
returns the provisional carpenter, which the controller adds straight to
the basket (spec 2a.D1: request -> basket -> register in one visit).
attendanceState parsing is an explicit absent->notCaptured mapping instead
of firstWhere orElse. Sheet copy and controller doc stop describing the
pre-D1 'no local record' world."
```

---

### Task 10: Maestro flow + CI matrix entry

**Files:**
- Create: `.maestro/flows/registration_workspace.yaml`
- Modify: `.maestro/config.yaml`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: seed fixtures (Task 7: campaign `seed-camp-1` "ACSL Pilot Carpenter Drive" APPROVED; carpenter `Md. Karim`), the real-auth login prelude pattern from `.maestro/flows/real_auth_campaign_journey.yaml`, seed credentials `campaign_creator` / `Test1234!`.
- Produces: e2e config `registration` in the CI matrix, running against the real service.

- [ ] **Step 1: Study the two files this must imitate**

Open `.maestro/flows/real_auth_campaign_journey.yaml` (the real-auth login prelude and its `launchApp`/`runFlow` idioms) and `.maestro/config.yaml` (flow registry). Copy idioms exactly — env var names, `clearState` usage, any `subflows/` includes. Do not invent Maestro syntax.

- [ ] **Step 2: Write the flow**

`.maestro/flows/registration_workspace.yaml` — the journey, using whatever login prelude idiom step 1 found (shown here as a `runFlow` sketch to be replaced with the real prelude):

```yaml
# W-06 registration workspace against the REAL campaign service (2a-I).
# Fixtures: POST /__test__/reset leaves campaign seed-camp-1 ("ACSL Pilot
# Carpenter Drive", APPROVED) and carpenters "Md. Karim" (••4821) /
# "Karim Uddin" (••7734) — see server/lib/src/seed/seed_routes.dart.
appId: ${APP_ID}
---
# 1) Real login as campaign_creator (copy the prelude from
#    real_auth_campaign_journey.yaml verbatim, changing only the username).
# 2) Open the seeded APPROVED campaign and its workspace:
- tapOn: "ACSL Pilot Carpenter Drive"
- tapOn: "Add registrations"
- assertVisible: "Search carpenter master"
# 3) Master search + basket (all ids are the Semantics identifiers Task 9
#    adds; CARP_E2E is the seeded fixture id):
- tapOn:
    id: "registration_search"
- inputText: "Karim"
- assertVisible: "Md. Karim"
- assertVisible: ".*CARP-••4821.*"
- tapOn:
    id: "registration_add_CARP_E2E"
- assertVisible: "Registration basket (1)"
# 4) Register:
- tapOn:
    id: "registration_submit"
- assertVisible: "Registered 1 participant(s)"
# 5) Same-visit profile request lands in the basket:
- tapOn:
    id: "registration_search"
- inputText: "Nobody Matches This"
- assertVisible: "No matching carpenter in the master."
- tapOn:
    id: "registration_request_profile"
- tapOn:
    id: "profile_name"
- inputText: "Flow Person"
- tapOn:
    id: "profile_phone"
- inputText: "+8801799990001"
- hideKeyboard
- tapOn:
    id: "profile_submit"
- assertVisible: "Registration basket (1)"
- assertVisible: "Flow Person"
```

The literals above come from `registration_workspace_screen.dart` / `campaign_detail_screen.dart` and the Task 7 fixtures; the two commented locators (login prelude, add-button) MUST be resolved against the real files, then the flow verified locally (step 4) before it is committed.

- [ ] **Step 3: Register the flow and the CI matrix entry**

Add the flow path to `.maestro/config.yaml`'s flow list (imitate the existing entries).

In `.github/workflows/ci.yml`, add to the e2e matrix (next to the existing `realAuth` entry, imitating its exact shape):

```yaml
          - key: registration
            useMock: 0
            defines: '--dart-define=E2E_REAL_AUTH=true'
            flows: .maestro/flows/registration_workspace.yaml
```

- [ ] **Step 4: Verify locally end-to-end**

```bash
# Postgres up (native or docker), then:
cd server
ENABLE_TEST_SEEDING=true DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' \
  JWT_SECRET='a-secret-at-least-32-characters-long!!' dart run bin/server.dart &
cd ..
# Android emulator running, then (mirroring the CI job's steps):
sh tool/scripts/run_maestro_flows.sh .maestro/flows/registration_workspace.yaml
```

Expected: flow green locally. Fix locators until it is — a flow that has never passed locally is not committable. Note the slice-1 environment lesson: CI's api-34 viewport is shorter than the local AVD; prefer `assertVisible` over coordinate taps, and scroll before asserting content low on the page.

- [ ] **Step 5: Commit, push, watch CI**

```bash
git add .maestro .github/workflows/ci.yml
git commit -m "feat(e2e): registration workspace flow against the real service

Real-auth login as campaign_creator, master search, basket, register, and
the same-visit profile-request -> basket path -- the acceptance proof for
sub-project 2a (deliverable 2a-I). New CI matrix config 'registration'
(useMock: 0) alongside the existing staged configs."
git push
gh run watch
```

Expected: the full matrix green — the new `registration` config AND the existing 4-of-6 staged configs (the slice's acceptance criterion includes not regressing them).

---

## Self-Review (performed while writing)

- **Spec coverage:** 2a-A → Tasks 1–3; 2a-B → Tasks 2 (003) and 5 (004); 2a-C/D/E/F → Tasks 5–6; 2a-G → Task 4; 2a-H → Tasks 8–9; 2a-I → Task 10. Decisions: 2a.D1 (Task 5 tx + Task 9 basket), 2a.D2 (masking in `CarpenterView` + PII assertions in Tasks 5/6/8), 2a.D3 (schema comment, Task 5), 2a.D4 (absent field + parity optionality, Tasks 5/8/9), 2a.D5 (`syncStatus` additive, Tasks 5/8).
- **Type consistency:** `ParticipantRepo` signatures in Task 5's Interfaces block match Task 6's call sites verbatim; `ParityTarget.postJson` record shape `({int status, Map<String, Object?> body})` used consistently; `requestNewProfile` returns `Result<RegisteredCarpenter>` in domain, data and controller.
- **Known judgement calls recorded for reviewers:** the UUID key is generated in the *repository* per call (spec §9 said "controller"; the semantics — fresh per submit, stable across transport retries — are identical and the surface is smaller); the double-authenticate on the participant leg's `campaigns/*` fall-through is accepted and documented in `app.dart`.
