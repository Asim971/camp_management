# Verification Queue (5c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the CRM verification queue real — escalated-aware prioritisation, all/mine/unassigned/escalated filters, a version-free atomic self-claim/release, and the C-01 queue screen — with mock parity and an e2e flow.

**Architecture:** Extends the 5a/5b verification slice. The queue SELECT gains an escalated-first ordering and a `filter`-driven WHERE; two new `POST …/claim` / `…/release` routes do an atomic conditional UPDATE on `assignee_id` without touching the decision `version`. A `QueueFilter` wire enum joins `campaign_contracts`. The Flutter `/verification` placeholder becomes a real list screen with permission-gated filter tabs.

**Tech Stack:** Dart 3.12 `shelf`/`shelf_router`/`postgres` server (hand-written SQL, no ORM/codegen); `campaign_contracts` shared package; Flutter/Riverpod/Dio/GoRouter client; `tool/mock_server`; Maestro e2e on the GitHub emulator matrix. Postgres 16+ on `localhost:5432`.

**Spec:** `docs/superpowers/specs/2026-08-14-verification-queue-design.md` (decisions 5c.D1–D7).

## Global Constraints

Every task's requirements implicitly include this section.

- **SDK floor is exactly `sdk: ">=3.12.0 <4.0.0"`** in every `pubspec.yaml`. No code generation and no ORM anywhere in `server/` or `packages/campaign_contracts`.
- **Wire naming is `SCREAMING_SNAKE` for every enum value.** `QueueFilter`: `ALL`/`MINE`/`UNASSIGNED`/`ESCALATED`.
- **Unknown enum values never resolve to a default** — `tryParseWire` returns `null`; a client fallback must be explicit and `debugPrint`-visible.
- **Out-of-scope resources return `404`, never `403`** (foundation D7). Every query — the queue SELECT and both claim/release UPDATEs — filters `organization_id = @org`.
- **Queue ordering (D1):** `ORDER BY (escalated_at IS NOT NULL) DESC, CASE machine_band WHEN 'NO_REFERENCE' THEN 0 WHEN 'LOW' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END, captured_at`.
- **Filters (D2):** `?filter=all|mine|unassigned|escalated` (default `all`); `mine` → `assignee_id = @callerUserId` (id from AUTH, never the client); `unassigned` → `assignee_id IS NULL`; `escalated` → `escalated_at IS NOT NULL` **and requires `verification_override`** (403 otherwise); unknown filter → **400**.
- **Claim/release (D4):** atomic conditional UPDATE, org-scoped, audited (`verification.claimed`/`verification.released`), **never bump `version`**. Claim: `SET assignee_id=@me WHERE ... status='CRM_REVIEW' AND (assignee_id IS NULL OR assignee_id=@me)`; 0 rows → exists → **409 `CONFLICT_STALE_VERSION`**, gone/cross-org → **404**. Release: `SET assignee_id=NULL WHERE ... assignee_id=@me`; 0 rows → exists → 409, gone → 404.
- **The queue item wire (D3)** carries `attendanceId, carpenterName, campaignName, ageSeconds, band, referenceSource, assigneeId, escalatedAt` (escalatedAt = UTC ISO-8601 or null).
- **No new `ApiErrorCode` members and no new endpoints beyond claim/release.** `badRequest`(400)/`forbidden`(403)/`notFound`(404)/`conflictStaleVersion`(409) already exist and map in `error_envelope.dart`.
- **`ENABLE_TEST_SEEDING` must never be committed enabled** (CI-only); seed routes stay gated.
- **Postgres runs natively on `localhost:5432`** (`postgres://campaign:campaign@localhost:5432/campaign`). Windows `dart test` no-args crashes (frontend_server); run specific files/dirs, prefer PowerShell `$env:DATABASE_URL='...'; dart test test/<dir>` for DB-backed suites.
- **Maestro `inputText` MUST be ASCII-only** — a non-ASCII glyph (e.g. an em-dash) enters via a Unicode path that corrupts the CI swiftshader render surface (`Failed to find ColorBuffer`), after which `scrollUntilVisible` fails. **Keep each emulator to ≤2 flows** — a 3rd Decision/list flow on one emulator boot degrades its graphics (this is why the crm matrix is split into `crm`/`crm2`).

---

## File Structure

```
packages/campaign_contracts/
  lib/src/queue_filter.dart               NEW — QueueFilter + wireValue + tryParseWire
  lib/campaign_contracts.dart             export it
  test/queue_filter_test.dart             NEW

server/lib/src/db/migrations/embedded.dart    migration 010 (filter indexes)
server/lib/src/verification/verification_repo.dart    queue(filter,callerUserId) ordering+filters+escalatedAt; claim/release
server/lib/src/verification/verification_routes.dart  ?filter parse+403/400; POST claim/release routes

lib/domain/verification/verification_case.dart          VerificationQueueItem gains escalatedAt
lib/domain/verification/verification_repository.dart     queue({QueueFilter}); add claim/release
lib/data/verification/verification_repository_impl.dart  send ?filter; parse escalatedAt; claim/release
lib/features/verification_queue/                         NEW — C-01 queue screen (notifier + screen)
lib/app/router/app_router.dart                           /verification -> the real screen
lib/features/dev/presentation/dev_launcher_screen.dart   add dev_open_verification_queue

tool/mock_server/bin/server.dart          /verification/queue?filter= + claim/release + escalatedAt
server/test/contract/parity_test.dart     pin filter subsets + claim 409 + escalated-403
server/lib/src/seed/seed_routes.dart      queue fixtures (if needed for e2e)
.maestro/flows/crm_queue_claim.yaml       NEW — claim -> Mine -> release
.github/workflows/ci.yml                  new crm3 matrix entry (the queue flow alone)
```

Tests live beside their subjects.

---

### Task 1: `QueueFilter` contract enum

**Files:**
- Create: `packages/campaign_contracts/lib/src/queue_filter.dart`
- Modify: `packages/campaign_contracts/lib/campaign_contracts.dart`
- Create: `packages/campaign_contracts/test/queue_filter_test.dart`

**Interfaces:**
- Produces: `enum QueueFilter { all, mine, unassigned, escalated }` with `String get wireValue` (SCREAMING_SNAKE) and `static QueueFilter? tryParseWire(String)`.

**Context:** mirror the existing `match_band.dart` shape. No `ApiErrorCode` change → no server build-break to fold in.

- [ ] **Step 1: Write the failing test**

`packages/campaign_contracts/test/queue_filter_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('QueueFilter wire values are SCREAMING_SNAKE and round-trip', () {
    final wires = QueueFilter.values.map((f) => f.wireValue).toList();
    expect(wires.toSet().length, QueueFilter.values.length);
    for (final f in QueueFilter.values) {
      expect(f.wireValue, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: f.name);
      expect(QueueFilter.tryParseWire(f.wireValue), f);
    }
  });

  test('specific wire values', () {
    expect(QueueFilter.all.wireValue, 'ALL');
    expect(QueueFilter.mine.wireValue, 'MINE');
    expect(QueueFilter.unassigned.wireValue, 'UNASSIGNED');
    expect(QueueFilter.escalated.wireValue, 'ESCALATED');
  });

  test('an unknown wire value is null, never a default', () {
    expect(QueueFilter.tryParseWire('NOPE'), isNull);
    expect(QueueFilter.tryParseWire(''), isNull);
    expect(QueueFilter.tryParseWire('all'), isNull, reason: 'case matters');
  });
}
```

- [ ] **Step 2: Run — confirm failure**

Run: `cd packages/campaign_contracts && dart pub get && dart test test/queue_filter_test.dart`
Expected: compile failure — `QueueFilter` not exported.

- [ ] **Step 3: Implement**

`packages/campaign_contracts/lib/src/queue_filter.dart`:

```dart
/// How the verification queue is filtered (sub-project 5c). The wire value is
/// the contract; `mine` resolves to the caller's id server-side (never a
/// client-supplied id).
enum QueueFilter {
  all,
  mine,
  unassigned,
  escalated;

  String get wireValue => switch (this) {
    all => 'ALL',
    mine => 'MINE',
    unassigned => 'UNASSIGNED',
    escalated => 'ESCALATED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static QueueFilter? tryParseWire(String wire) {
    for (final f in values) {
      if (f.wireValue == wire) return f;
    }
    return null;
  }
}
```

Add to `campaign_contracts.dart`, alphabetically among the `export 'src/…'` lines:
```dart
export 'src/queue_filter.dart';
```

- [ ] **Step 4: Run — must pass**

Run: `cd packages/campaign_contracts && dart test`
Expected: all pass.

- [ ] **Step 5: Format, commit**

```bash
cd packages/campaign_contracts && dart format --set-exit-if-changed .
cd ../.. && git add packages/campaign_contracts
git commit -m "feat(contracts): QueueFilter wire enum for the verification queue"
```

---

### Task 2: Migration `010_queue_indexes`

**Files:**
- Modify: `server/lib/src/db/migrations/embedded.dart`
- Modify: `server/test/db/migrator_test.dart`

**Interfaces:**
- Produces: indexes `attendance_assignee_idx` and `attendance_escalated_idx`.

**Context:** `'009_escalation'` is currently the last key in `embeddedMigrations`. `migrator_test.dart` has a `row(...)` helper + `db` fixture.

- [ ] **Step 1: Write the failing migrator test**

Add to `server/test/db/migrator_test.dart`:

```dart
  test('010 adds the queue filter indexes', () async {
    await Migrator(db).applyPending();
    final idx = await db.execute(
      "SELECT indexname FROM pg_indexes WHERE tablename = 'attendance'",
    );
    final names = idx.map((r) => row(r)['indexname']! as String).toSet();
    expect(names, containsAll(<String>[
      'attendance_assignee_idx', 'attendance_escalated_idx',
    ]));
  });
```

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/db/migrator_test.dart -n '010 adds'`
Expected: FAIL.

- [ ] **Step 3: Add the migration**

In `embedded.dart`, add `'010_queue_indexes': _queueIndexes,` after `'009_escalation': _escalation,`, and:

```dart
const String _queueIndexes = r'''
CREATE INDEX attendance_assignee_idx
  ON attendance(organization_id, status, assignee_id);
CREATE INDEX attendance_escalated_idx
  ON attendance(organization_id, status)
  WHERE escalated_at IS NOT NULL;
''';
```

- [ ] **Step 4: Run migrator tests — must pass**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/db/migrator_test.dart`
Expected: all pass, incl. `010 adds…`.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/db/migrations/embedded.dart server/test/db/migrator_test.dart
git commit -m "feat(server): migration 010 — verification queue filter indexes"
```

---

### Task 3: Server — queue prioritisation, filters, and `escalatedAt`

**Files:**
- Modify: `server/lib/src/verification/verification_repo.dart`
- Modify: `server/lib/src/verification/verification_routes.dart`
- Modify: `server/test/verification/verification_routes_test.dart`

**Interfaces:**
- Consumes: `QueueFilter` (Task 1); `AuthContext.can(String)` and `.userId` (auth/middleware.dart); migration 010 (Task 2).
- Produces: `VerificationRepo.queue({required String organizationId, required QueueFilter filter, required String callerUserId})` — escalated-first ordering, filter-driven WHERE, `escalatedAt` in the wire.

**Context — current `queue`:** `queue({required String organizationId})` (verification_repo.dart ~55) selects `a.id, a.machine_band, a.machine_reference_src, a.assignee_id, a.captured_at, cr.full_name, c.name`, WHERE `organization_id=@org AND status='CRM_REVIEW'`, ORDER BY band CASE then captured_at, and `_queueItemWire` emits `attendanceId, carpenterName, campaignName, ageSeconds, band, referenceSource, assigneeId`. The route (`verification_routes.dart` ~22-31) requires `verification_decide` and calls `repo.queue(organizationId: auth.organizationId)` with no params. The test file has helpers `seedCrmReviewAttendance(db, {..., machineBand, capturedAt, status, version})` (which also seeds a `media_objects` row), `get(path, {bearer})`, and mints `crm_verifier` + `crm_supervisor` tokens in `setUp`.

- [ ] **Step 1: Write the failing tests**

Add to `verification_routes_test.dart`. Seed several `CRM_REVIEW` attendances whose ages/bands/escalation OPPOSE the priority tiers, plus assign some and escalate some (set `assignee_id`/`escalated_at` directly via `db.execute` after seeding, or extend the helper). Cover:

```dart
// Ordering: escalated first, then band, then oldest — data opposes each tier.
test('queue orders escalated-first, then band, then age', () async {
  // seed: A = MEDIUM, captured 30m ago, NOT escalated
  //       B = HIGH,   captured 1m ago,  escalated  (escalated_at set)
  //       C = NO_REFERENCE, captured 5m ago, NOT escalated
  final items = await queueItems(verifierToken); // filter=all
  expect(items.map((i) => i['attendanceId']),
      ['B', 'C', 'A'],
      reason: 'B escalated first; then C (worst band); then A (oldest non-esc)');
});

test('the queue item wire carries escalatedAt', () async {
  final items = await queueItems(verifierToken);
  final b = items.firstWhere((i) => i['attendanceId'] == 'B');
  expect(b['escalatedAt'], isNotNull);
  final a = items.firstWhere((i) => i['attendanceId'] == 'A');
  expect(a['escalatedAt'], isNull);
});

// filter=mine uses the CALLER's id (server-side), not a client value.
test('filter=mine returns only the callers assigned cases', () async {
  // assign A to verifierUserId, B to a different user
  final mine = await queueItems(verifierToken, filter: 'MINE');
  expect(mine.map((i) => i['attendanceId']), contains('A'));
  expect(mine.map((i) => i['attendanceId']), isNot(contains('B')));
});

test('filter=unassigned returns only null-assignee cases', () async {
  final un = await queueItems(verifierToken, filter: 'UNASSIGNED');
  expect(un.every((i) => i['assigneeId'] == null), isTrue);
});

// filter=escalated is supervisor-only.
test('filter=escalated requires verification_override', () async {
  final asVerifier = await getQueue(verifierToken, filter: 'ESCALATED');
  expect(asVerifier.statusCode, 403);
  final asSupervisor = await queueItems(supervisorToken, filter: 'ESCALATED');
  expect(asSupervisor.every((i) => i['escalatedAt'] != null), isTrue);
});

test('an unknown filter is 400', () async {
  final res = await getQueue(verifierToken, filter: 'WAT');
  expect(res.statusCode, 400);
  expect(errorCode(res), 'BAD_REQUEST');
});
```

Where `getQueue(bearer, {filter})` does `get('/verification/queue${filter==null?'':'?filter=$filter'}', bearer: bearer)` and `queueItems(...)` unwraps `jsonDecode(...)['items'] as List`. Use the existing `get`/token helpers and inline SQL to set `assignee_id`/`escalated_at` on seeded rows. Keep every existing verification test green.

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart`
Expected: the new cases FAIL (no filter support; no escalatedAt).

- [ ] **Step 3: Update the repo `queue`**

In `verification_repo.dart`, change the signature and body:

```dart
Future<List<Map<String, Object?>>> queue({
  required String organizationId,
  required QueueFilter filter,
  required String callerUserId,
}) async {
  final filterClause = switch (filter) {
    QueueFilter.all => '',
    QueueFilter.mine => 'AND a.assignee_id = @caller ',
    QueueFilter.unassigned => 'AND a.assignee_id IS NULL ',
    QueueFilter.escalated => 'AND a.escalated_at IS NOT NULL ',
  };
  final res = await _db.execute(
    'SELECT a.id, a.machine_band, a.machine_reference_src, a.assignee_id, '
    '       a.captured_at, a.escalated_at, cr.full_name AS carpenter_name, '
    '       c.name AS campaign_name '
    'FROM attendance a '
    'JOIN campaigns c ON c.id = a.campaign_id '
    'JOIN carpenters cr ON cr.id = a.carpenter_id '
    "WHERE a.organization_id = @org AND a.status = 'CRM_REVIEW' "
    '$filterClause'
    'ORDER BY (a.escalated_at IS NOT NULL) DESC, '
    '         CASE a.machine_band '
    "           WHEN 'NO_REFERENCE' THEN 0 WHEN 'LOW' THEN 1 "
    "           WHEN 'MEDIUM' THEN 2 ELSE 3 END, "
    '         a.captured_at',
    params: {'org': organizationId, 'caller': callerUserId},
  );
  final now = DateTime.now().toUtc();
  return [for (final r in res) _queueItemWire(row(r), now)];
}
```

In `_queueItemWire`, add the escalatedAt key:

```dart
'escalatedAt': (r['escalated_at'] as DateTime?)?.toUtc().toIso8601String(),
```

(`@caller` is always bound; it is only referenced by the `mine` clause.)

- [ ] **Step 4: Update the route**

In `verification_routes.dart`, the queue handler:

```dart
final auth = authOf(request);
final filterWire = request.url.queryParameters['filter'] ?? 'ALL';
final filter = QueueFilter.tryParseWire(filterWire);
if (filter == null) {
  throw ApiException(ApiErrorCode.badRequest,
      message: 'Unknown queue filter "$filterWire".');
}
if (filter == QueueFilter.escalated && !auth.can('verification_override')) {
  throw ApiException(ApiErrorCode.forbidden,
      message: 'The escalated queue requires the verification_override permission.');
}
final items = await repo.queue(
  organizationId: auth.organizationId,
  filter: filter,
  callerUserId: auth.userId,
);
return _json({'items': items});
```

Add `import 'package:campaign_contracts/campaign_contracts.dart';` if not present.

- [ ] **Step 5: Run the verification tests — must pass**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart`
Expected: all pass — ordering, each filter, mine-uses-caller, escalated-403, unknown-400, escalatedAt, plus every 5a/5b case.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/verification/verification_repo.dart server/lib/src/verification/verification_routes.dart server/test/verification/verification_routes_test.dart
git commit -m "feat(server): verification queue — escalated-first ordering, filters, escalatedAt

GET /verification/queue?filter=all|mine|unassigned|escalated. mine uses the
caller's id from auth; escalated requires verification_override (403 else);
unknown filter -> 400. Ordering is escalated-first, then band severity, then age.
The queue item wire carries escalatedAt."
```

---

### Task 4: Server — claim / release

**Files:**
- Modify: `server/lib/src/verification/verification_repo.dart`
- Modify: `server/lib/src/verification/verification_routes.dart`
- Modify: `server/test/verification/verification_routes_test.dart`

**Interfaces:**
- Consumes: `AuditWriter.writeTx` / `.write`; `authOf`; `correlationOf`.
- Produces: `VerificationRepo.claim(...)` / `release(...)` returning `enum ClaimCode { done, conflict, notFound }`; routes `POST /verification/cases/<id>/claim` and `POST /verification/cases/<id>/release`.

**Context:** `AuditWriter` has `write({action, resourceType, resourceId, actorId, correlationId, payload})`. `attendance.assignee_id` is a nullable TEXT FK. The claim UPDATE must NOT bump `version`. Model the atomic-CAS + 0-rows re-check on 5b's decide (`verification_repo.dart`).

- [ ] **Step 1: Write the failing tests**

Add to `verification_routes_test.dart` (seed a CRM_REVIEW attendance `id` version 1; mint verifier + supervisor tokens; a `claim(id, {bearer})` helper posting to `/verification/cases/$id/claim` with the bearer, and a `release(...)` similarly):

```dart
test('claiming an unassigned case assigns it to the caller + audits', () async {
  final res = await claim(id, bearer: verifierToken);
  expect(res.statusCode, 200);
  expect(await assigneeId(id), verifierUserId); // SELECT assignee_id
  final audit = await db.execute(
    "SELECT 1 FROM audit_events WHERE action='verification.claimed' AND resource_id=@id",
    params: {'id': id});
  expect(audit, isNotEmpty);
});

test('claiming a case held by another is 409, unchanged', () async {
  await db.execute('UPDATE attendance SET assignee_id=@u WHERE id=@id',
      params: {'u': 'someone-else', 'id': id});
  final res = await claim(id, bearer: verifierToken);
  expect(res.statusCode, 409);
  expect(await assigneeId(id), 'someone-else');
});

test('claiming your own case is idempotent 200', () async {
  await claim(id, bearer: verifierToken);
  final res = await claim(id, bearer: verifierToken);
  expect(res.statusCode, 200);
});

test('claiming a decided case is 409', () async {
  await db.execute("UPDATE attendance SET status='APPROVED' WHERE id=@id",
      params: {'id': id});
  expect((await claim(id, bearer: verifierToken)).statusCode, 409);
});

test('claiming a cross-org / missing case is 404', () async {
  expect((await claim('no-such-id', bearer: verifierToken)).statusCode, 404);
});

// The key invariant: claim does NOT bump version.
test('claim does not bump the decision version', () async {
  await claim(id, bearer: verifierToken);          // id still version 1
  final res = await decide(id, bearer: verifierToken, ifMatch: '1',
      body: {'outcome': 'APPROVED'});
  expect(res.statusCode, 200); // pre-claim If-Match still valid
});

test('release clears only your own; releasing anothers is 409', () async {
  await claim(id, bearer: verifierToken);
  expect((await release(id, bearer: verifierToken)).statusCode, 200);
  expect(await assigneeId(id), isNull);
  await db.execute('UPDATE attendance SET assignee_id=@u WHERE id=@id',
      params: {'u': 'other', 'id': id});
  expect((await release(id, bearer: verifierToken)).statusCode, 409);
});
```

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart`
Expected: the claim/release cases FAIL (routes don't exist).

- [ ] **Step 3: Implement the repo methods**

In `verification_repo.dart`:

```dart
enum ClaimCode { done, conflict, notFound }

Future<ClaimCode> claim({
  required String attendanceId,
  required String organizationId,
  required String userId,
  String? correlationId,
}) async {
  final res = await _db.execute(
    'UPDATE attendance SET assignee_id = @me '
    'WHERE id = @id AND organization_id = @org '
    "  AND status = 'CRM_REVIEW' "
    '  AND (assignee_id IS NULL OR assignee_id = @me) '
    'RETURNING id',
    params: {'me': userId, 'id': attendanceId, 'org': organizationId},
  );
  if (res.affectedRows == 0) {
    final exists = await _db.execute(
      'SELECT 1 FROM attendance WHERE id = @id AND organization_id = @org',
      params: {'id': attendanceId, 'org': organizationId});
    return exists.isEmpty ? ClaimCode.notFound : ClaimCode.conflict;
  }
  await _audit.write(
    action: 'verification.claimed', resourceType: 'attendance',
    resourceId: attendanceId, actorId: userId, correlationId: correlationId);
  return ClaimCode.done;
}

Future<ClaimCode> release({
  required String attendanceId,
  required String organizationId,
  required String userId,
  String? correlationId,
}) async {
  final res = await _db.execute(
    'UPDATE attendance SET assignee_id = NULL '
    'WHERE id = @id AND organization_id = @org AND assignee_id = @me '
    'RETURNING id',
    params: {'me': userId, 'id': attendanceId, 'org': organizationId},
  );
  if (res.affectedRows == 0) {
    final exists = await _db.execute(
      'SELECT 1 FROM attendance WHERE id = @id AND organization_id = @org',
      params: {'id': attendanceId, 'org': organizationId});
    return exists.isEmpty ? ClaimCode.notFound : ClaimCode.conflict;
  }
  await _audit.write(
    action: 'verification.released', resourceType: 'attendance',
    resourceId: attendanceId, actorId: userId, correlationId: correlationId);
  return ClaimCode.done;
}
```

(These use `_db.execute` directly — no transaction is needed: the single UPDATE is atomic, and the audit write is a best-effort follow-on consistent with how the queue/case reads audit. `affectedRows` is on the postgres `Result`.)

- [ ] **Step 4: Implement the routes**

In `verification_routes.dart`, add before `return router;`:

```dart
router.post('/verification/cases/<id>/claim',
  const Pipeline().addMiddleware(requirePermission('verification_decide')).addHandler(
    (Request request) async {
      final auth = authOf(request);
      final code = await repo.claim(
        attendanceId: request.params['id']!, organizationId: auth.organizationId,
        userId: auth.userId, correlationId: correlationOf(request));
      return _claimResponse(code);
    }));

router.post('/verification/cases/<id>/release',
  const Pipeline().addMiddleware(requirePermission('verification_decide')).addHandler(
    (Request request) async {
      final auth = authOf(request);
      final code = await repo.release(
        attendanceId: request.params['id']!, organizationId: auth.organizationId,
        userId: auth.userId, correlationId: correlationOf(request));
      return _claimResponse(code);
    }));
```

Add a helper in the file:

```dart
Response _claimResponse(ClaimCode code) => switch (code) {
  ClaimCode.done => _json({'status': 'ok'}),
  ClaimCode.conflict => throw ApiException(ApiErrorCode.conflictStaleVersion,
      message: 'This case is being reviewed by someone else; reload the queue.'),
  ClaimCode.notFound => throw ApiException(ApiErrorCode.notFound),
};
```

- [ ] **Step 5: Run the tests — must pass**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart`
Expected: all pass — claim/release incl. the no-version-bump invariant, plus every prior case.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/verification/verification_repo.dart server/lib/src/verification/verification_routes.dart server/test/verification/verification_routes_test.dart
git commit -m "feat(server): version-free atomic self-claim/release for verification cases

POST /verification/cases/<id>/claim assigns the case to the caller via an atomic
conditional UPDATE (assignee_id IS NULL OR = me); 409 if held by another, 404 if
gone. release clears only your own. Neither bumps version, so a decision with the
pre-claim If-Match still succeeds. Both audited."
```

---

### Task 5: Client — repo `queue(filter)`, claim/release, `escalatedAt`

**Files:**
- Modify: `lib/domain/verification/verification_case.dart`
- Modify: `lib/domain/verification/verification_repository.dart`
- Modify: `lib/data/verification/verification_repository_impl.dart`
- Modify: `test/data/verification/verification_repository_impl_test.dart`

**Interfaces:**
- Consumes: `QueueFilter` (Task 1); the queue wire `escalatedAt` (Task 3); claim/release endpoints (Task 4).
- Produces: `VerificationRepository.queue({required QueueFilter filter})`, `claim(String attendanceId)`, `release(String attendanceId)`; `VerificationQueueItem.escalatedAt` (`DateTime?`).

**Context:** `VerificationQueueItem` (verification_case.dart:30-40) is `@freezed` with `attendanceId, carpenterName, campaignName, age (Duration), band, referenceSource, assigneeId?`. The impl's `queue({String? assigneeId})` (verification_repository_impl.dart:29-45) sends `?assignee=` and maps items via `_queueItem`. The interface (`verification_repository.dart`) declares `queue({String? assigneeId})`. The `_RecordingAdapter` test harness records `requests`.

- [ ] **Step 1: Write the failing client tests**

Extend `test/data/verification/verification_repository_impl_test.dart`:

```dart
test('queue sends ?filter=MINE', () async {
  await repo.queue(filter: QueueFilter.mine);
  expect(lastRequest.uri.queryParameters['filter'], 'MINE');
});

test('queue parses escalatedAt (and null)', () async {
  // stub items: one with "escalatedAt":"2026-08-01T10:00:00.000Z", one null
  final result = await repo.queue(filter: QueueFilter.all);
  final items = result.asOk;
  expect(items.firstWhere((i) => i.attendanceId=='esc').escalatedAt, isNotNull);
  expect(items.firstWhere((i) => i.attendanceId=='plain').escalatedAt, isNull);
});

test('claim POSTs to the claim endpoint', () async {
  await repo.claim('att-1');
  expect(lastRequest.method, 'POST');
  expect(lastRequest.uri.path, '/verification/cases/att-1/claim');
});

test('a 409 on claim maps to conflict', () async {
  // stub a 409 for the claim path
  final result = await repo.claim('att-1');
  expect(result.asErr.kind, FailureKind.conflict);
});
```
(Match the file's existing recording-adapter helpers and `asOk`/`asErr` accessors.)

- [ ] **Step 2: Run — confirm failure**

Run: `flutter test test/data/verification/verification_repository_impl_test.dart`
Expected: FAIL (queue takes `assigneeId`; no claim/release; no escalatedAt).

- [ ] **Step 3: Update the model + interface**

In `verification_case.dart`, add to `VerificationQueueItem`:
```dart
    DateTime? escalatedAt, // set when the case was escalated (5b); null otherwise
```
In `verification_repository.dart`, change the interface:
```dart
Future<Result<List<VerificationQueueItem>>> queue({required QueueFilter filter});
Future<Result<void>> claim(String attendanceId);
Future<Result<void>> release(String attendanceId);
```
Add `import 'package:campaign_contracts/campaign_contracts.dart';`.

- [ ] **Step 4: Update the impl**

In `verification_repository_impl.dart`:
- `queue`: change to `queue({required QueueFilter filter})`, send `queryParameters: {'filter': filter.wireValue}`.
- `_queueItem`: add `escalatedAt: j['escalatedAt'] == null ? null : DateTime.parse(j['escalatedAt'] as String),`.
- Add:
```dart
@override
Future<Result<void>> claim(String attendanceId) async {
  try {
    await _dio.post<void>('/verification/cases/$attendanceId/claim');
    return const Ok(null);
  } catch (e) { return Err(mapDioError(e)); } // 409 -> conflict
}
@override
Future<Result<void>> release(String attendanceId) async {
  try {
    await _dio.post<void>('/verification/cases/$attendanceId/release');
    return const Ok(null);
  } catch (e) { return Err(mapDioError(e)); }
}
```

- [ ] **Step 5: Run codegen + tests**

Run: `flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs`, then `flutter test test/data/verification/verification_repository_impl_test.dart`, then the full `flutter test`.
Expected: new tests pass; full suite green. If any existing caller/mock of `queue({assigneeId:})` breaks, update it to `queue(filter:)` (the queue screen is a placeholder, so consumers are test-only).

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format --set-exit-if-changed lib test && flutter analyze --fatal-infos
git add lib/domain/verification lib/data/verification test/data/verification
git commit -m "feat(client): queue(filter) + claim/release + escalatedAt

VerificationRepository.queue takes a QueueFilter (sends ?filter=WIRE); the queue
item carries escalatedAt; claim/release POST to the new endpoints and map 409 to
conflict."
```

---

### Task 6: Client — the C-01 verification-queue screen

**Files:**
- Create: `lib/features/verification_queue/application/verification_queue_notifier.dart`
- Create: `lib/features/verification_queue/presentation/verification_queue_screen.dart`
- Modify: `lib/app/router/app_router.dart`
- Modify: `lib/features/dev/presentation/dev_launcher_screen.dart`
- Create: `test/widget/verification_queue_screen_test.dart`

**Interfaces:**
- Consumes: `VerificationRepository.queue({filter})` / `claim` / `release` (Task 5); `QueueFilter`; `verificationRepositoryProvider` (app/di/providers.dart); `Permission.verificationOverride` + the `PermissionGate`/session-scope pattern (lib/core/auth/); `authStateProvider`.
- Produces: the `/verification` screen (screen id `C-01`).

**Context:** model the Riverpod list on `lib/features/campaign_list/` (a `campaign_list_notifier.dart` + `campaign_list_screen.dart`). Permission gating: `switch (ref.watch(authStateProvider)) { AuthSignedIn(:final session) => session.scope.can(Permission.verificationOverride), _ => false }` (see `lib/core/auth/permission_gate.dart`). Navigation to a case: `context.go('/verification/cases/$attendanceId')` (GoRouter). The current `/verification` route builds `PlaceholderScreen`.

- [ ] **Step 1: Write the failing widget test**

`test/widget/verification_queue_screen_test.dart` — pump the screen with an overridden `verificationRepositoryProvider` (a fake returning a fixed list incl. one escalated + one unassigned item) and an `authStateProvider` override. Assert (match the repo's existing widget-test setup patterns):
- the list renders an item per queue entry (a `Semantics(identifier: 'queue_item_<id>')` or the carpenter text);
- tabs `queue_tab_all`, `queue_tab_mine`, `queue_tab_unassigned` are present;
- `queue_tab_escalated` is present when the session holds `verification_override` and ABSENT otherwise (two pump variants);
- an unassigned item shows a `queue_claim` control; tapping it calls the repo's `claim`.

Write concrete assertions with real `find.bySemanticsLabel`/identifier finders and a fake repo capturing `claim` calls.

- [ ] **Step 2: Run — confirm failure**

Run: `flutter test test/widget/verification_queue_screen_test.dart`
Expected: FAIL — the screen/notifier don't exist.

- [ ] **Step 3: Implement the notifier**

`verification_queue_notifier.dart` — an `AutoDisposeFamilyAsyncNotifier<List<VerificationQueueItem>, QueueFilter>` whose `build(filter)` calls `ref.read(verificationRepositoryProvider).queue(filter: filter)` and folds the Result (throw on Err so the AsyncValue carries the error). Expose `claim(String id)` / `release(String id)` that call the repo and `ref.invalidateSelf()` on success; surface a conflict distinctly (return a small enum like the crm case controller's `DecisionResult`) so the screen can show the "being reviewed" message. Provider: `final verificationQueueProvider = AsyncNotifierProvider.autoDispose.family<...>(VerificationQueueNotifier.new);`.

- [ ] **Step 4: Implement the screen**

`verification_queue_screen.dart` — a `ConsumerStatefulWidget` holding the current `QueueFilter`. A `TabBar`/segmented control with tabs All/Mine/Unassigned and, gated on `verification_override`, Escalated (each `Semantics(identifier: 'queue_tab_<name>')`). The body watches `verificationQueueProvider(currentFilter)` and renders `AsyncValue` (loading/error/data). Each item is a tile (`Semantics(identifier: 'queue_item_<attendanceId>')`) showing carpenter, campaign, a band chip, age, an "Escalated" badge when `escalatedAt != null`, and a Mine/Unassigned indicator (compare `assigneeId` to `session.userId`). A `queue_claim` button on unassigned items and `queue_release` on your own call the notifier; a conflict shows a SnackBar "This case is being reviewed by someone else" and refreshes. Tapping the tile `context.go('/verification/cases/${item.attendanceId}')`.

- [ ] **Step 5: Wire the route + dev launcher**

In `app_router.dart`, replace the `/verification` `PlaceholderScreen` builder with `const VerificationQueueScreen()` (import it), keeping the nested `cases/:id` route. In `dev_launcher_screen.dart`, add an entry `(id: 'dev_open_verification_queue', label: 'Verification queue', route: '/verification')` alongside the other dev buttons.

- [ ] **Step 6: Run codegen + tests**

Run: `flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs`, then `flutter test test/widget/verification_queue_screen_test.dart`, then the full `flutter test`.
Expected: new tests pass; full suite green (count up only by this task's tests). The `/verification` route no longer renders the placeholder.

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format --set-exit-if-changed lib test && flutter analyze --fatal-infos
git add lib/features/verification_queue lib/app/router/app_router.dart lib/features/dev/presentation/dev_launcher_screen.dart test/widget/verification_queue_screen_test.dart
git commit -m "feat(client): build the C-01 verification queue screen

A prioritised list with All/Mine/Unassigned tabs (+ an Escalated tab gated on
verification_override), an Escalated badge, per-item Claim/Release, and tap-to-case.
Replaces the /verification placeholder; adds a dev-launcher button."
```

---

### Task 7: Mock parity

**Files:**
- Modify: `tool/mock_server/bin/server.dart`
- Modify: `server/test/contract/parity_test.dart`

**Context:** the mock's `/verification/queue` (server.dart ~234) returns a static `store.verificationQueue` (one item, no filtering). There is no claim/release handler. To support filters, give the mock a small mutable assignee map and a richer fixture (an escalated item, an unassigned item, one assigned to a known id), honour `?filter=`, add `escalatedAt` to items, and add claim/release handlers with the 409/404 rules. The mock does NOT model RBAC, so `filter=escalated`'s 403 stays a real-service assertion (note it in a comment, as prior parity tasks did).

- [ ] **Step 1: Align the mock**

In `tool/mock_server/bin/server.dart`:
- `/verification/queue`: read `req.url.queryParameters['filter'] ?? 'ALL'`; on `MINE`/`UNASSIGNED`/`ESCALATED` filter the fixture list (by a mutable `assignee`/`escalatedAt` on each item); unknown filter → `_json({'error':{'code':'BAD_REQUEST',...}}, status: 400)`. Ensure each item includes `escalatedAt` (ISO string or null) and `assigneeId`.
- Add `POST /verification/cases/<id>/claim`: if the case is another's → 409 `{'error':{'code':'CONFLICT_STALE_VERSION',...}}`; else set its assignee to a fixed mock user id and return `{'status':'ok'}`. `POST .../release`: clear assignee if it's the mock user's, else 409. Match the mock's existing error-envelope shape.

- [ ] **Step 2: Pin parity**

In `server/test/contract/parity_test.dart`, add a case asserting mock and real agree on: `filter=unassigned` returns only null-assignee items; a claim on an unassigned case returns 200 and a second claim by a different principal returns 409; the queue item shape carries `escalatedAt` (parses as null or an ISO timestamp on both). Seed the real side as the verification tests do (a `crm_verifier` token + `CRM_REVIEW` attendances). Note `filter=escalated`'s 403 is real-only. Do not weaken existing parity cases.

- [ ] **Step 3: Run parity, format, analyze, commit**

```bash
cd tool/mock_server && dart pub get && dart analyze && dart format --set-exit-if-changed .
cd ../../server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/contract/parity_test.dart
cd .. && git add tool/mock_server/bin/server.dart server/test/contract/parity_test.dart
git commit -m "chore(mock): verification queue filters + claim/release parity"
```

---

### Task 8: E2E — claim → Mine → release against the real service

**Files:**
- Modify: `server/lib/src/seed/seed_routes.dart` (only if the queue needs an extra seeded case)
- Create: `.maestro/flows/crm_queue_claim.yaml`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the real queue/claim/release endpoints (Tasks 3–4), the C-01 screen + `dev_open_verification_queue` button (Task 6), the seeded `CASE_E2E` (CRM_REVIEW, unassigned) fixture.

**Context:** 5a/5b seed `CASE_E2E` (CRM_REVIEW, v1, unassigned) and reset per flow. The crm e2e matrix is split into `crm` (decision+conflict) and `crm2` (recapture+override) — **2 flows per emulator** because a 3rd degrades the emulator's graphics. So this queue flow needs its OWN matrix entry `crm3` (a single flow), NOT appended to `crm`/`crm2`. The dev launcher's `dev_open_verification_queue` (Task 6) opens `/verification`.

- [ ] **Step 1: Confirm the seed suffices**

`CASE_E2E` (CRM_REVIEW, unassigned) is enough for a claim→Mine→release flow. Confirm `_seedVerificationFixture` leaves `CASE_E2E` unassigned after reset (assignee_id null). If a second CRM_REVIEW case would make the "All vs Mine" distinction clearer for the flow, add one; otherwise no seed change. Note the decision in your report.

- [ ] **Step 2: Write the queue flow**

Create `.maestro/flows/crm_queue_claim.yaml`, modelled on `crm_case_decision.yaml`'s real-auth login prelude: sign in as `crm_verifier`/`Test1234!` → `dev_launcher` → `dev_open_verification_queue` (opens `/verification`) → assert the queue list shows `CASE_E2E` (e.g. `.*Md. Karim.*` or a `queue_item_CASE_E2E` id) → tap `queue_claim` on it → switch to the `queue_tab_mine` tab → assert `CASE_E2E` appears there → tap `queue_release` → assert it leaves Mine. Use `scrollUntilVisible` for below-the-fold controls. **No `inputText` needed** (claim/release are button taps) — but if any text is entered, keep it ASCII-only. Tags: `crm`, `critical`, `android`, `pr-smoke`. `appId: ${APP_ID}`.

- [ ] **Step 3: Add a `crm3` CI matrix entry**

In `.github/workflows/ci.yml`, add a new matrix entry after `crm2`:
```yaml
          - key: crm3
            defines: '--dart-define=E2E_REAL_AUTH=true --dart-define=ROLE=crm_verifier'
            useMock: '0'
            flows: >-
              .maestro/flows/crm_queue_claim.yaml
```
(A dedicated entry keeps this flow on its own fresh emulator — the ≤2-flows-per-emulator rule; a single flow is safest.)

- [ ] **Step 4: Local validation (no emulator)**

Bring up the real server (Postgres native; JWT secret ≥32 chars; `ENABLE_TEST_SEEDING=true` LOCALLY ONLY — never commit it enabled), `POST /__test__/reset`, log in as `crm_verifier`, and curl: `GET /verification/queue?filter=all` (CASE_E2E present, assigneeId null, escalatedAt null); `POST /verification/cases/CASE_E2E/claim` → 200; `GET /verification/queue?filter=mine` (CASE_E2E present); `POST /verification/cases/CASE_E2E/release` → 200; `GET ?filter=mine` (CASE_E2E absent). Record the transcript in your report. (If a live server is impractical on Windows, drive these as a server test and note it.)

- [ ] **Step 5: Commit**

```bash
git add server/lib/src/seed/seed_routes.dart .maestro/flows/crm_queue_claim.yaml .github/workflows/ci.yml
git commit -m "feat(e2e): crm queue claim -> Mine -> release against the real service

A crm_verifier opens the C-01 queue, claims CASE_E2E, sees it under Mine, and
releases it. Runs in its own crm3 matrix entry (one flow per emulator)."
```

---

## Self-Review

**1. Spec coverage.** Every 5c decision maps to a task:
- 5c.D1 (escalated-first ordering) → Task 3.
- 5c.D2 (QueueFilter + filter predicates + escalated-403 + unknown-400) → Task 1 (enum) + Task 3 (route/repo).
- 5c.D3 (escalatedAt in the wire) → Task 3 (server) + Task 5 (client parse).
- 5c.D4 (version-free atomic claim/release) → Task 4.
- 5c.D5 (migration 010 indexes) → Task 2.
- 5c.D6 (C-01 screen) → Task 6 (+ Task 5 repo plumbing).
- 5c.D7 (RBAC + org scope) → Tasks 3–4 (route gates; org scope in every query).
- Mock parity → Task 7; e2e → Task 8.
- Out of scope (assign-to-another, configurable SLA/aging/risk, pagination, nid_reveal) → not implemented, named in the spec.

**2. Placeholder scan.** Each code step carries concrete SQL/Dart; tests carry real assertions. Test helper names (`queueItems`, `getQueue`, `claim`, `release`, `assigneeId`, `errorCode`, `lastRequest`, `asOk`/`asErr`) match the existing 5a/5b test files' equivalents — the implementer reuses those files' helpers rather than inventing new harnesses; noted at first use. The widget-test finders are described concretely (semantics identifiers `queue_item_<id>`, `queue_tab_<name>`, `queue_claim`, `queue_release`).

**3. Type consistency.** `QueueFilter.wireValue`/`tryParseWire` (Task 1) are sent by the client (Task 5) and parsed by the server route (Task 3). `VerificationQueueItem.escalatedAt` (`DateTime?`, Task 5) is emitted as `escalatedAt` ISO/null by the server (Task 3) and honoured by the mock (Task 7). `ClaimCode {done,conflict,notFound}` (Task 4) maps to 200/409/404. `queue({required QueueFilter filter})` is the single queue signature across interface (Task 5), impl (Task 5), and notifier (Task 6). The claim/release routes (`POST /verification/cases/<id>/claim|release`, Task 4) are the exact paths the client posts to (Task 5) and the e2e/mock drive (Tasks 7–8).
