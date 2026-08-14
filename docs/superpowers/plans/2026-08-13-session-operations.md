# Session Operations (sub-project 3a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Back the campaign-detail Sessions tab with real `campaign_service` endpoints — read a campaign's sessions and drive each through start/pause/close — replacing the `tool/mock_server` those controls hit today, and modernise `SessionStatus` to the ratified contract shape (SCREAMING_SNAKE, `tryParseWire`, no silent default).

**Architecture:** A pure session status machine (`session_machine.dart`, no IO) defines the legal transitions and the readiness rule; a `SessionRepo` enforces each transition with a single atomic conditional `UPDATE … WHERE status = ANY(@allowedFrom) RETURNING …` (compare-and-swap on status — no `version` column), disambiguating a zero-row result into 404 / idempotent-200 / 409 / 422; `sessionRouter` maps the repo's result type onto the error envelope and mounts into the existing shelf `Cascade`. The client's `SessionStatus` moves to `campaign_contracts`; the mock is updated to the same wire and pinned by the parity test.

**Tech Stack:** Dart 3.12, `shelf`/`shelf_router`, `postgres` 3.5.12 (hand-written SQL, no ORM), `campaign_contracts` path package; Flutter/Riverpod/Dio client; Maestro e2e on a GitHub emulator.

**Spec:** `docs/superpowers/specs/2026-08-13-session-operations-design.md`. Decisions are cited as **3a.D1**–**3a.D7**.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **SDK floor is exactly `sdk: ">=3.12.0 <4.0.0"`** in every `pubspec.yaml`. `dart_style` picks formatting from the language version; a lower floor makes `dart format --set-exit-if-changed` environment-dependent.
- **`shelf`/`shelf_router` only. No ORM. No code generation** in `server/` or `packages/campaign_contracts`.
- **Wire naming is `SCREAMING_SNAKE` for every enum-ish value.** `SessionStatus` wire values are `UPCOMING / ACTIVE / PAUSED / CAPTURE_CLOSED / COMPLETED`. Field names stay camelCase.
- **Unknown enum values never resolve to a default.** `tryParseWire` returns `null`; callers choose a visible fallback. The client's session fallback for an unknown status is `captureClosed` (action-disabling), never `upcoming` (3a.D1).
- **Out-of-scope resources return `404`, never `403`** (**D7**). A session whose campaign is in another organization is indistinguishable from a missing one.
- **`postgres` trap:** inside `Db.tx`, every statement goes through the `TxSession` passed to the callback, never `_db.execute` (that throws `PgException('… while inside a runTx call')`).
- **`ResultRow.toColumnMap()` returns `Map<String, dynamic>`** — read every column through the `row(r)` helper in `server/lib/src/db/pool.dart`, which casts once.
- **Timestamps:** UTC ISO-8601 on the wire (`.toUtc().toIso8601String()`), `timestamptz` in Postgres.
- **The claim vocabulary is fixed by the client.** No `session_*` permission exists; session writes reuse `campaign_create` (3a.D5). Do not invent a permission name.
- **Every server task runs its tests against** `DATABASE_URL=postgres://campaign:campaign@localhost:5432/campaign` (a native Postgres 16+; `cd server && docker compose up -d db` is one way). CI uses `postgres:16`.
- **Activity counts are `0` in 3a** (3a.D6). Do not add `session_id` to `registrations`.

---

## File Structure

```
packages/campaign_contracts/
  lib/src/session_status.dart          NEW  SessionStatus enum + wireValue + tryParseWire
  lib/src/error_codes.dart             MOD  + sessionInvalidTransition, sessionNotReady
  lib/campaign_contracts.dart          MOD  export session_status.dart
  test/session_status_test.dart        NEW
  test/error_codes_test.dart           MOD  (if present) new codes round-trip

server/
  lib/src/db/migrations/embedded.dart  MOD  + '006_session_status'
  lib/src/campaign/session_machine.dart NEW SessionAction, allowedFrom, targetOf, isReady
  lib/src/campaign/session_repo.dart    NEW SessionView, SessionRepo, SessionApplyResult
  lib/src/campaign/session_routes.dart  NEW sessionRouter
  lib/src/app.dart                      MOD mount the session leg into the Cascade
  lib/src/infra/error_envelope.dart     MOD map the two codes to 409 / 422
  lib/src/seed/seed_routes.dart         MOD seed one session for seed-camp-1
  test/support/seed_fixtures.dart       MOD seedSession helper for integration tests
  test/campaign/session_machine_test.dart NEW
  test/campaign/session_routes_test.dart  NEW
  test/db/migrator_test.dart            MOD assert 006 reconciles PLANNED → UPCOMING

lib/ (Flutter app)
  domain/session/campaign_session.dart          MOD re-export SessionStatus from contracts
  data/session/session_repository_impl.dart      MOD tryParseWire + unknown policy
  features/campaign_detail/presentation/campaign_detail_screen.dart MOD stable ids on session controls
  test/data/session/session_repository_impl_test.dart NEW
  test/features/campaign_detail/presentation/session_card_test.dart NEW

tool/mock_server/bin/server.dart       MOD SCREAMING_SNAKE session status + action map + counts 0
server/test/contract/parity_test.dart  MOD pin session shape/vocabulary parity

.maestro/flows/session_ops.yaml        NEW
.maestro/config.yaml                   MOD add the flow to the inventory
.github/workflows/ci.yml               MOD add the sessionOps emulator matrix config
```

---

### Task 1: Contract — `SessionStatus` and the two error codes

**Files:**
- Create: `packages/campaign_contracts/lib/src/session_status.dart`
- Create: `packages/campaign_contracts/test/session_status_test.dart`
- Modify: `packages/campaign_contracts/lib/campaign_contracts.dart`
- Modify: `packages/campaign_contracts/lib/src/error_codes.dart`

**Interfaces:**
- Produces: `enum SessionStatus { upcoming, active, paused, captureClosed, completed }` with `String get wireValue` (`UPCOMING/ACTIVE/PAUSED/CAPTURE_CLOSED/COMPLETED`) and `static SessionStatus? tryParseWire(String)`; `ApiErrorCode.sessionInvalidTransition` (`SESSION_INVALID_TRANSITION`) and `ApiErrorCode.sessionNotReady` (`SESSION_NOT_READY`).
- Consumes: nothing.

- [ ] **Step 1: Write the failing status test**

`packages/campaign_contracts/test/session_status_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every status has a distinct SCREAMING_SNAKE wire value', () {
    final wires = SessionStatus.values.map((s) => s.wireValue).toList();
    expect(wires.toSet().length, SessionStatus.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip', () {
    for (final s in SessionStatus.values) {
      expect(SessionStatus.tryParseWire(s.wireValue), s);
    }
  });

  test('the specific wire spellings the contract fixes', () {
    expect(SessionStatus.captureClosed.wireValue, 'CAPTURE_CLOSED');
    expect(SessionStatus.upcoming.wireValue, 'UPCOMING');
  });

  // The whole reason this enum moved: the client used
  // `firstWhere(orElse: () => upcoming)` on the camelCase Dart name, so an
  // unknown status silently became a startable session. Parsing must be null
  // on anything unrecognised, and case-sensitive.
  test('an unknown wire value is null, never a default', () {
    expect(SessionStatus.tryParseWire('NOT_A_STATUS'), isNull);
    expect(SessionStatus.tryParseWire(''), isNull);
    expect(SessionStatus.tryParseWire('active'), isNull, reason: 'case matters');
    expect(SessionStatus.tryParseWire('captureClosed'), isNull,
        reason: 'the old camelCase name is not the wire value');
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd packages/campaign_contracts && dart pub get && dart test test/session_status_test.dart`
Expected: compile failure — `SessionStatus` is not defined.

- [ ] **Step 3: Implement the enum**

`packages/campaign_contracts/lib/src/session_status.dart`:

```dart
/// A campaign session's operational lifecycle. The wire value is the contract;
/// the Dart name is an implementation detail on either side.
///
/// Moved out of the app's `lib/domain/session/campaign_session.dart` for
/// sub-project 3a so the server and client cannot disagree — the same move
/// `CampaignStatus` and `ImportStatus` already made. `CAPTURE_CLOSED` is the
/// operational terminal a user reaches; `COMPLETED` is set only when the
/// session's campaign completes (sub-project 3a.D3), not by any client action.
enum SessionStatus {
  upcoming,
  active,
  paused,
  captureClosed,
  completed;

  String get wireValue => switch (this) {
    upcoming => 'UPCOMING',
    active => 'ACTIVE',
    paused => 'PAUSED',
    captureClosed => 'CAPTURE_CLOSED',
    completed => 'COMPLETED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static SessionStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
```

- [ ] **Step 4: Add the two error codes**

In `packages/campaign_contracts/lib/src/error_codes.dart`, add the two members to the `enum ApiErrorCode` (after `importFileInvalid`), renaming the trailing `;` accordingly:

```dart
  // bulk import (sub-project 2b)
  importFileInvalid,
  // session operations (sub-project 3a)
  sessionInvalidTransition,
  sessionNotReady;
```

And add their arms to the `wireValue` switch (before the closing `};`):

```dart
    importFileInvalid => 'IMPORT_FILE_INVALID',
    sessionInvalidTransition => 'SESSION_INVALID_TRANSITION',
    sessionNotReady => 'SESSION_NOT_READY',
```

- [ ] **Step 5: Export the new file**

In `packages/campaign_contracts/lib/campaign_contracts.dart`, add to the export list (keep it alphabetical with the others):

```dart
export 'src/session_status.dart';
```

- [ ] **Step 6: Extend the error-codes round-trip test (if the file exists)**

If `packages/campaign_contracts/test/error_codes_test.dart` iterates `ApiErrorCode.values` for round-trip and SCREAMING_SNAKE, it already covers the new codes — run it. If it hard-codes a list, add the two new codes to that list.

- [ ] **Step 7: Run the contract tests — must pass**

Run: `cd packages/campaign_contracts && dart test`
Expected: all pass, including the new `session_status_test.dart`.

- [ ] **Step 8: Format, analyze, commit**

```bash
cd packages/campaign_contracts && dart format --set-exit-if-changed . && dart analyze
cd ../.. && git add packages/campaign_contracts
git commit -m "feat(contracts): SessionStatus wire vocabulary + session error codes

SessionStatus joins CampaignStatus/ImportStatus in campaign_contracts with
SCREAMING_SNAKE wire values and tryParseWire (null on unknown, never a
default). Adds SESSION_INVALID_TRANSITION (409) and SESSION_NOT_READY (422)
for the session-operation endpoints."
```

---

### Task 2: Migration `006_session_status` — reconcile the status vocabulary

**Files:**
- Modify: `server/lib/src/db/migrations/embedded.dart`
- Modify: `server/test/db/migrator_test.dart`

**Interfaces:**
- Consumes: the `Migrator` and `embeddedMigrations` map (Task 3 of the foundation plan).
- Produces: `campaign_sessions.status` default is `'UPCOMING'` and no row is left `'PLANNED'`.

**Context:** `campaign_sessions` shipped with `status TEXT NOT NULL DEFAULT 'PLANNED'`, and the campaign wizard's session insert (`campaign_repo.dart` `_replaceSessions`) sets no status, so it relies on that default. 3a's vocabulary has no `PLANNED`; the initial state is `UPCOMING`.

- [ ] **Step 1: Write the failing migrator test**

Add to `server/test/db/migrator_test.dart` (inside `main`, alongside the existing tests):

```dart
  test('006 reconciles the session status vocabulary to UPCOMING', () async {
    await Migrator(db).applyPending();

    // The column default is now UPCOMING, so a wizard insert (which sets no
    // status) starts a session in the 3a vocabulary, not the retired PLANNED.
    final def = await db.execute(
      "SELECT column_default FROM information_schema.columns "
      "WHERE table_name = 'campaign_sessions' AND column_name = 'status'",
    );
    expect(
      row(def.single)['column_default'],
      contains('UPCOMING'),
      reason: 'the default must be UPCOMING after 006',
    );

    // No legacy PLANNED rows survive (there are none in a fresh db, but the
    // UPDATE must be present and correct for existing deployments).
    final planned = await db.execute(
      "SELECT count(*) AS n FROM campaign_sessions WHERE status = 'PLANNED'",
    );
    expect(row(planned.single)['n'], 0);
  });
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/db/migrator_test.dart -n 'reconciles the session status'`
Expected: FAIL — the default is still `PLANNED`.

- [ ] **Step 3: Add the migration**

In `server/lib/src/db/migrations/embedded.dart`, add the entry to the `embeddedMigrations` map (after `005_imports`, so it applies last):

```dart
  '006_session_status': _sessionStatus,
```

and add the constant at the bottom of the file:

```dart
const String _sessionStatus = r'''
-- 3a reconciles the session vocabulary: the foundation shipped
-- campaign_sessions.status DEFAULT 'PLANNED', but the ratified SessionStatus
-- contract (campaign_contracts) has no PLANNED — a freshly created session is
-- UPCOMING. The wizard insert sets no status and leans on this default.
ALTER TABLE campaign_sessions ALTER COLUMN status SET DEFAULT 'UPCOMING';
UPDATE campaign_sessions SET status = 'UPCOMING' WHERE status = 'PLANNED';
''';
```

- [ ] **Step 4: Run the migrator tests — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/db/migrator_test.dart`
Expected: all pass, including the new reconciliation test and the existing table-inventory/idempotency/rollback tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/db/migrations/embedded.dart server/test/db/migrator_test.dart
git commit -m "feat(server): migration 006 reconciles campaign_sessions status to UPCOMING

The foundation shipped the table with DEFAULT 'PLANNED'; the ratified
SessionStatus contract has no PLANNED. 006 sets the default to UPCOMING and
migrates any existing PLANNED row. The wizard insert keeps relying on the
default, so no campaign_repo change is needed."
```

---

### Task 3: Session status machine (pure, no IO)

**Files:**
- Create: `server/lib/src/campaign/session_machine.dart`
- Create: `server/test/campaign/session_machine_test.dart`

**Interfaces:**
- Consumes: `SessionStatus`, `CampaignStatus` from `campaign_contracts` (Task 1).
- Produces:
  - `enum SessionAction { start, pause, close }`
  - `Set<SessionStatus> allowedFrom(SessionAction action)`
  - `SessionStatus targetOf(SessionAction action)`
  - `bool isReady({required CampaignStatus campaignStatus, required String? venue, required DateTime? startAt})`

**Why its own file:** the two rules hardest to get right — the legal transitions and the readiness predicate — are unit-testable with no database, exactly as `status_machine.dart` is for campaigns.

- [ ] **Step 1: Write the failing machine test**

`server/test/campaign/session_machine_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/campaign/session_machine.dart';
import 'package:test/test.dart';

void main() {
  group('transitions', () {
    test('start goes UPCOMING/PAUSED -> ACTIVE', () {
      expect(allowedFrom(SessionAction.start),
          {SessionStatus.upcoming, SessionStatus.paused});
      expect(targetOf(SessionAction.start), SessionStatus.active);
    });

    test('pause goes ACTIVE -> PAUSED', () {
      expect(allowedFrom(SessionAction.pause), {SessionStatus.active});
      expect(targetOf(SessionAction.pause), SessionStatus.paused);
    });

    test('close goes ACTIVE/PAUSED -> CAPTURE_CLOSED', () {
      expect(allowedFrom(SessionAction.close),
          {SessionStatus.active, SessionStatus.paused});
      expect(targetOf(SessionAction.close), SessionStatus.captureClosed);
    });

    test('CAPTURE_CLOSED and COMPLETED are terminal for every action', () {
      for (final action in SessionAction.values) {
        expect(allowedFrom(action), isNot(contains(SessionStatus.captureClosed)));
        expect(allowedFrom(action), isNot(contains(SessionStatus.completed)));
      }
    });
  });

  group('readiness', () {
    final future = DateTime.utc(2026, 9, 1, 9);

    test('ready when campaign approved/active AND venue AND start time', () {
      for (final s in [CampaignStatus.approved, CampaignStatus.active]) {
        expect(
          isReady(campaignStatus: s, venue: 'Hall A', startAt: future),
          isTrue,
        );
      }
    });

    test('not ready without a venue', () {
      expect(isReady(campaignStatus: CampaignStatus.approved, venue: '', startAt: future), isFalse);
      expect(isReady(campaignStatus: CampaignStatus.approved, venue: null, startAt: future), isFalse);
    });

    test('not ready without a start time', () {
      expect(isReady(campaignStatus: CampaignStatus.approved, venue: 'Hall A', startAt: null), isFalse);
    });

    test('not ready when the campaign is not approved/active', () {
      for (final s in [
        CampaignStatus.draft,
        CampaignStatus.pendingApproval,
        CampaignStatus.returned,
        CampaignStatus.paused,
        CampaignStatus.completed,
        CampaignStatus.cancelled,
      ]) {
        expect(isReady(campaignStatus: s, venue: 'Hall A', startAt: future), isFalse,
            reason: s.name);
      }
    });
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd server && dart test test/campaign/session_machine_test.dart`
Expected: FAIL — `session_machine.dart` does not exist.

- [ ] **Step 3: Implement the machine**

`server/lib/src/campaign/session_machine.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';

/// The three operations the client drives. `start` doubles as "resume" (from
/// PAUSED); there is no distinct resume verb.
enum SessionAction { start, pause, close }

/// The states from which [action] is legal. CAPTURE_CLOSED and COMPLETED are
/// terminal: no action leaves them (COMPLETED is only ever reached by the
/// campaign-completion cascade, sub-project 3a.D3).
Set<SessionStatus> allowedFrom(SessionAction action) => switch (action) {
  SessionAction.start => {SessionStatus.upcoming, SessionStatus.paused},
  SessionAction.pause => {SessionStatus.active},
  SessionAction.close => {SessionStatus.active, SessionStatus.paused},
};

/// The state [action] moves a session to.
SessionStatus targetOf(SessionAction action) => switch (action) {
  SessionAction.start => SessionStatus.active,
  SessionAction.pause => SessionStatus.paused,
  SessionAction.close => SessionStatus.captureClosed,
};

/// Whether a session may be started right now (3a.D4). True iff the campaign is
/// APPROVED or ACTIVE, the session has a non-empty venue, and it has a start
/// time. The `start` endpoint re-checks this server-side rather than trusting
/// the client's `readinessOk`.
bool isReady({
  required CampaignStatus campaignStatus,
  required String? venue,
  required DateTime? startAt,
}) {
  final campaignOk = campaignStatus == CampaignStatus.approved ||
      campaignStatus == CampaignStatus.active;
  final venueOk = venue != null && venue.trim().isNotEmpty;
  return campaignOk && venueOk && startAt != null;
}
```

- [ ] **Step 4: Run the machine tests — must pass**

Run: `cd server && dart test test/campaign/session_machine_test.dart`
Expected: all pass.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/campaign/session_machine.dart server/test/campaign/session_machine_test.dart
git commit -m "feat(server): pure session status machine and readiness rule

Legal transitions (start/pause/close) and the readiness predicate live IO-free
so they are unit-testable without a database, mirroring campaign status_machine.
CAPTURE_CLOSED and COMPLETED are terminal; start doubles as resume from PAUSED."
```

---

### Task 4: `SessionRepo` — list, atomic transition, and the dormant complete helper

**Files:**
- Create: `server/lib/src/campaign/session_repo.dart`
- Modify: `server/test/support/seed_fixtures.dart`
- Create: `server/test/campaign/session_repo_test.dart`

**Interfaces:**
- Consumes: `Db`, `row` (`db/pool.dart`); `AuditWriter` (`infra/audit.dart`); the session machine (Task 3); `SessionStatus`, `CampaignStatus` (Task 1); migration 006 (Task 2).
- Produces:
  - `class SessionView { final String id, campaignId, venue; final SessionStatus status; final DateTime? startAt, endAt; final int capacity; final bool readinessOk; Map<String, Object?> toWireJson(); }`
  - `enum SessionOutcome { applied, idempotentNoop, invalidTransition, notReady, notFound }`
  - `class SessionApplyResult { final SessionOutcome outcome; final SessionView? view; final SessionStatus? currentStatus; }`
  - `class SessionRepo { SessionRepo(Db db); Future<List<SessionView>?> listForCampaign(String campaignId, {required String organizationId}); Future<SessionApplyResult> apply(SessionAction action, {required String sessionId, required String organizationId, required String actorId, String? correlationId}); Future<void> completeSessionsForCampaign(String campaignId); }`
  - Test helper `seedSession(...)` in `seed_fixtures.dart` (signature in Step 1).

- [ ] **Step 1: Add the `seedSession` test helper**

In `server/test/support/seed_fixtures.dart`, add (it uses the same `Db` the other seed helpers take):

```dart
/// Inserts one campaign_sessions row for integration tests. `status` is a
/// SessionStatus wire value (e.g. 'UPCOMING'); `venue`/`startAt` default to a
/// ready-to-start shape so a test only overrides what it is exercising.
Future<String> seedSession(
  Db db, {
  required String campaignId,
  String id = 'sess-1',
  String status = 'UPCOMING',
  String? venue = 'BMD Training Center, Hall A',
  DateTime? startAt,
  int capacity = 60,
}) async {
  await db.execute(
    'INSERT INTO campaign_sessions '
    '(id, campaign_id, venue, capacity, start_at, status) '
    'VALUES (@id, @c, @v, @cap, @s, @st)',
    params: {
      'id': id,
      'c': campaignId,
      'v': venue,
      'cap': capacity,
      's': startAt ?? DateTime.utc(2026, 9, 1, 9),
      'st': status,
    },
  );
  return id;
}
```

(Import `Db` at the top if the file does not already: `import 'package:campaign_service/src/db/pool.dart';` — check first.)

- [ ] **Step 2: Write the failing repo tests**

`server/test/campaign/session_repo_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/campaign/session_machine.dart';
import 'package:campaign_service/src/campaign/session_repo.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late SessionRepo repo;
  const org = 'org-1';

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // org-1, user-1 campaign_creator
    await seedCampaign(db, id: 'camp-1'); // APPROVED by default in the helper
    repo = SessionRepo(db);
  });
  tearDown(() async => db.close());

  test('listForCampaign returns sessions with zero activity counts', () async {
    await seedSession(db, campaignId: 'camp-1', id: 's-1');
    final list = await repo.listForCampaign('camp-1', organizationId: org);
    expect(list, isNotNull);
    final v = list!.single;
    expect(v.status, SessionStatus.upcoming);
    expect(v.readinessOk, isTrue); // approved campaign + venue + start time
    final wire = v.toWireJson();
    expect(wire['registeredCount'], 0);
    expect(wire['approvedCount'], 0);
    expect(wire['status'], 'UPCOMING');
  });

  test('listForCampaign is null for a campaign outside the org (=> 404)',
      () async {
    final list = await repo.listForCampaign('camp-1',
        organizationId: 'someone-else');
    expect(list, isNull);
  });

  test('start flips UPCOMING -> ACTIVE and writes an audit row', () async {
    await seedSession(db, campaignId: 'camp-1', id: 's-1');
    final r = await repo.apply(SessionAction.start,
        sessionId: 's-1', organizationId: org, actorId: 'user-1');
    expect(r.outcome, SessionOutcome.applied);
    expect(r.view!.status, SessionStatus.active);

    final audit = await db.execute(
      "SELECT action FROM audit_events WHERE resource_id = 's-1'",
    );
    expect(audit.map((x) => row(x)['action']), contains('session.started'));
  });

  test('start again on an ACTIVE session is an idempotent no-op (200)',
      () async {
    await seedSession(db, campaignId: 'camp-1', id: 's-1', status: 'ACTIVE');
    final r = await repo.apply(SessionAction.start,
        sessionId: 's-1', organizationId: org, actorId: 'user-1');
    expect(r.outcome, SessionOutcome.idempotentNoop);
    expect(r.view!.status, SessionStatus.active);
  });

  test('start on a CAPTURE_CLOSED session is an invalid transition', () async {
    await seedSession(db,
        campaignId: 'camp-1', id: 's-1', status: 'CAPTURE_CLOSED');
    final r = await repo.apply(SessionAction.start,
        sessionId: 's-1', organizationId: org, actorId: 'user-1');
    expect(r.outcome, SessionOutcome.invalidTransition);
    expect(r.currentStatus, SessionStatus.captureClosed);
  });

  test('start on a startable session that is not ready => notReady', () async {
    // No venue => not ready, even though UPCOMING is a legal start state.
    await seedSession(db, campaignId: 'camp-1', id: 's-1', venue: null);
    final r = await repo.apply(SessionAction.start,
        sessionId: 's-1', organizationId: org, actorId: 'user-1');
    expect(r.outcome, SessionOutcome.notReady);
  });

  test('apply on an unknown / cross-org session => notFound', () async {
    final missing = await repo.apply(SessionAction.start,
        sessionId: 'nope', organizationId: org, actorId: 'user-1');
    expect(missing.outcome, SessionOutcome.notFound);
  });

  test('two concurrent starts: exactly one applies, the other is a no-op',
      () async {
    await seedSession(db, campaignId: 'camp-1', id: 's-1');
    final results = await Future.wait([
      repo.apply(SessionAction.start,
          sessionId: 's-1', organizationId: org, actorId: 'user-1'),
      repo.apply(SessionAction.start,
          sessionId: 's-1', organizationId: org, actorId: 'user-1'),
    ]);
    final outcomes = results.map((r) => r.outcome).toList();
    expect(outcomes.where((o) => o == SessionOutcome.applied).length, 1,
        reason: 'the status CAS must let exactly one writer win');
    // The loser is never a second write; it observes ACTIVE as a no-op.
    expect(
      outcomes.where((o) => o == SessionOutcome.idempotentNoop).length,
      1,
    );
  });

  test('completeSessionsForCampaign flips non-terminal sessions to COMPLETED',
      () async {
    await seedSession(db, campaignId: 'camp-1', id: 's-active', status: 'ACTIVE');
    await seedSession(db,
        campaignId: 'camp-1', id: 's-closed', status: 'CAPTURE_CLOSED');
    await repo.completeSessionsForCampaign('camp-1');
    final rows = await db.execute(
      "SELECT id, status FROM campaign_sessions WHERE campaign_id = 'camp-1'",
    );
    final byId = {for (final r in rows) row(r)['id']: row(r)['status']};
    expect(byId['s-active'], 'COMPLETED');
    expect(byId['s-closed'], 'CAPTURE_CLOSED',
        reason: 'already-terminal sessions are left untouched');
  });
}
```

> Check the exact `seedOrganizationWithUser` / `seedCampaign` signatures and the org id they use (the existing `server/test/campaign/*_test.dart` and `import_routes_test.dart` call these). Use the same `org` constant and the same default campaign status (APPROVED). If `seedCampaign` defaults to a non-approved status, pass `status: 'APPROVED'` (or the helper's equivalent) so readiness holds.

- [ ] **Step 3: Run it and confirm it fails**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/campaign/session_repo_test.dart`
Expected: FAIL — `session_repo.dart` does not exist.

- [ ] **Step 4: Implement the repo**

`server/lib/src/campaign/session_repo.dart`:

```dart
import 'package:postgres/postgres.dart';

import '../db/pool.dart';
import '../infra/audit.dart';
import 'package:campaign_contracts/campaign_contracts.dart';
import 'session_machine.dart';

/// A session as the API presents it. Activity counts are 0 in 3a (3a.D6): the
/// real per-session numbers are produced by attendance (sub-project 4).
class SessionView {
  const SessionView({
    required this.id,
    required this.campaignId,
    required this.venue,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.capacity,
    required this.readinessOk,
  });

  final String id;
  final String campaignId;
  final String venue; // '' when the DB venue is null; never null on the wire
  final SessionStatus status;
  final DateTime? startAt;
  final DateTime? endAt;
  final int capacity;
  final bool readinessOk;

  Map<String, Object?> toWireJson() => {
    'id': id,
    'campaignId': campaignId,
    'venue': venue,
    'status': status.wireValue,
    'startAt': startAt?.toUtc().toIso8601String(),
    'endAt': endAt?.toUtc().toIso8601String(),
    'capacity': capacity,
    'registeredCount': 0,
    'pendingSyncCount': 0,
    'reviewCount': 0,
    'approvedCount': 0,
    'readinessOk': readinessOk,
  };
}

enum SessionOutcome { applied, idempotentNoop, invalidTransition, notReady, notFound }

class SessionApplyResult {
  const SessionApplyResult(this.outcome, {this.view, this.currentStatus});
  final SessionOutcome outcome;
  final SessionView? view; // set for applied and idempotentNoop
  final SessionStatus? currentStatus; // set for invalidTransition (for message)
}

/// Owns all session SQL. Every read and write is org-scoped through the
/// campaigns join (D7: a cross-org session is indistinguishable from missing).
class SessionRepo {
  SessionRepo(this._db) : _audit = AuditWriter(_db);

  final Db _db;
  final AuditWriter _audit;

  static const _selectCols =
      's.id, s.campaign_id, s.venue, s.status, s.start_at, s.end_at, '
      's.capacity, c.status AS campaign_status';

  SessionView _view(Map<String, Object?> r) {
    final campaignStatus =
        CampaignStatus.tryParseWire(r['campaign_status']! as String) ??
            CampaignStatus.draft;
    final status = SessionStatus.tryParseWire(r['status']! as String) ??
        SessionStatus.captureClosed; // unknown => non-operational, never a default
    final venue = (r['venue'] as String?) ?? '';
    final startAt = r['start_at'] as DateTime?;
    return SessionView(
      id: r['id']! as String,
      campaignId: r['campaign_id']! as String,
      venue: venue,
      status: status,
      startAt: startAt,
      endAt: r['end_at'] as DateTime?,
      capacity: (r['capacity'] as int?) ?? 0,
      readinessOk: isReady(
        campaignStatus: campaignStatus,
        venue: venue,
        startAt: startAt,
      ),
    );
  }

  /// Sessions for a campaign, or null if the campaign is not in [organizationId]
  /// (the route turns null into 404). An in-org campaign with no sessions
  /// returns an empty list.
  Future<List<SessionView>?> listForCampaign(
    String campaignId, {
    required String organizationId,
  }) async {
    final campaign = await _db.execute(
      'SELECT 1 FROM campaigns WHERE id = @id AND organization_id = @org',
      params: {'id': campaignId, 'org': organizationId},
    );
    if (campaign.isEmpty) return null;

    final res = await _db.execute(
      'SELECT $_selectCols FROM campaign_sessions s '
      'JOIN campaigns c ON c.id = s.campaign_id '
      'WHERE s.campaign_id = @id AND c.organization_id = @org '
      'ORDER BY s.start_at NULLS LAST, s.id',
      params: {'id': campaignId, 'org': organizationId},
    );
    return [for (final r in res) _view(row(r))];
  }

  Future<Map<String, Object?>?> _load(
    String sessionId,
    String organizationId,
  ) async {
    final res = await _db.execute(
      'SELECT $_selectCols FROM campaign_sessions s '
      'JOIN campaigns c ON c.id = s.campaign_id '
      'WHERE s.id = @id AND c.organization_id = @org',
      params: {'id': sessionId, 'org': organizationId},
    );
    return res.isEmpty ? null : row(res.single);
  }

  /// Applies [action] to a session with a single atomic compare-and-swap on
  /// status (§6a / 3a.D7). The `status = ANY(@allowedFrom)` guard makes the
  /// legality check and the write one step: two concurrent starts cannot both
  /// win; the loser matches zero rows and is re-read as an idempotent no-op or
  /// an invalid transition.
  Future<SessionApplyResult> apply(
    SessionAction action, {
    required String sessionId,
    required String organizationId,
    required String actorId,
    String? correlationId,
  }) async {
    final loaded = await _load(sessionId, organizationId);
    if (loaded == null) {
      return const SessionApplyResult(SessionOutcome.notFound);
    }
    final current = SessionStatus.tryParseWire(loaded['status']! as String) ??
        SessionStatus.captureClosed;
    final target = targetOf(action);

    // Not a legal source state: already-there is an idempotent no-op, anything
    // else is a conflict — decided before touching the row.
    if (!allowedFrom(action).contains(current)) {
      if (current == target) {
        return SessionApplyResult(SessionOutcome.idempotentNoop, view: _view(loaded));
      }
      return SessionApplyResult(
        SessionOutcome.invalidTransition,
        currentStatus: current,
      );
    }

    // Legal source state: `start` additionally requires readiness.
    if (action == SessionAction.start && !_view(loaded).readinessOk) {
      return const SessionApplyResult(SessionOutcome.notReady);
    }

    final froms = allowedFrom(action).map((s) => s.wireValue).toList();
    final from0 = froms.first;
    final from1 = froms.length > 1 ? froms[1] : froms.first;

    // Atomic CAS + audit in one transaction, so an operation and its audit
    // trail commit together (the same posture as the import commit).
    final updated = await _db.tx((tx) async {
      final res = await tx.execute(
        Sql.named(
          'UPDATE campaign_sessions '
          'SET status = @to '
          'WHERE id = @id '
          '  AND status IN (@from0, @from1) '
          '  AND campaign_id IN '
          '      (SELECT id FROM campaigns WHERE organization_id = @org) '
          'RETURNING $_selectCols',
        ),
        parameters: {
          'to': target.wireValue,
          'id': sessionId,
          'from0': from0,
          'from1': from1,
          'org': organizationId,
        },
      );
      if (res.isEmpty) return null; // raced: someone else moved it first
      await _audit.write(
        action: _auditAction(action),
        resourceType: 'campaign_session',
        resourceId: sessionId,
        actorId: actorId,
        correlationId: correlationId,
        payload: {'to': target.wireValue},
      );
      return row(res.single);
    });

    if (updated != null) {
      return SessionApplyResult(SessionOutcome.applied, view: _view(updated));
    }

    // Lost the race: re-read to report the same no-op / conflict a slower
    // caller would have seen.
    final after = await _load(sessionId, organizationId);
    if (after == null) return const SessionApplyResult(SessionOutcome.notFound);
    final now = SessionStatus.tryParseWire(after['status']! as String) ??
        SessionStatus.captureClosed;
    if (now == target) {
      return SessionApplyResult(SessionOutcome.idempotentNoop, view: _view(after));
    }
    return SessionApplyResult(
      SessionOutcome.invalidTransition,
      currentStatus: now,
    );
  }

  String _auditAction(SessionAction action) => switch (action) {
    SessionAction.start => 'session.started',
    SessionAction.pause => 'session.paused',
    SessionAction.close => 'session.capture_closed',
  };

  /// Dormant in 3a (3a.D3): flips every non-terminal session of [campaignId] to
  /// COMPLETED. The campaign-activation slice that drives campaign completion
  /// will call this; there is no endpoint for it here.
  Future<void> completeSessionsForCampaign(String campaignId) async {
    await _db.execute(
      "UPDATE campaign_sessions SET status = 'COMPLETED' "
      "WHERE campaign_id = @id "
      "  AND status NOT IN ('CAPTURE_CLOSED', 'COMPLETED')",
      params: {'id': campaignId},
    );
  }
}
```

> Note on `AuditWriter` inside a transaction: it is constructed over `_db`. Check `server/lib/src/infra/audit.dart` — if `AuditWriter.write` executes on the `Db` (not the `tx`), calling it inside `_db.tx` will throw the runTx-reentrancy `PgException`. If so, follow the 2b import-commit pattern: perform the audit INSERT directly on `tx` inside the transaction (copy the INSERT SQL from `audit.dart`), rather than through the `AuditWriter`. The repo test's audit assertion will surface this immediately.

- [ ] **Step 5: Run the repo tests — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/campaign/session_repo_test.dart`
Expected: all pass, including the concurrency falsification and the dormant-complete test.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/campaign/session_repo.dart server/test/support/seed_fixtures.dart server/test/campaign/session_repo_test.dart
git commit -m "feat(server): SessionRepo — org-scoped list and atomic-CAS transitions

Each operation is one UPDATE ... WHERE status IN (allowedFrom) RETURNING, so
the legality check and the write are atomic and two concurrent starts cannot
both win; a zero-row result is re-read into an idempotent no-op or an invalid
transition. Activity counts are 0 (attendance fills them in sub-project 4).
completeSessionsForCampaign ships dormant for the campaign-completion cascade."
```

---

### Task 5: Session routes, envelope status mapping, and Cascade wiring

**Files:**
- Create: `server/lib/src/campaign/session_routes.dart`
- Modify: `server/lib/src/infra/error_envelope.dart`
- Modify: `server/lib/src/app.dart`
- Create: `server/test/campaign/session_routes_test.dart`

**Interfaces:**
- Consumes: `SessionRepo`, `SessionApplyResult`, `SessionOutcome` (Task 4); `authOf`, `requirePermission` (`auth/middleware.dart`); `ApiException`, `ApiErrorCode` (Task 1 + envelope); `correlationOf` (`infra/correlation.dart`).
- Produces: `Router sessionRouter({required Db db})` serving `GET /campaigns/<id>/sessions` and `POST /sessions/<id>/{start,pause,close}`; the `sessionInvalidTransition`→409 / `sessionNotReady`→422 status mapping.

- [ ] **Step 1: Map the two codes to HTTP status**

In `server/lib/src/infra/error_envelope.dart`, add to the `int get status => switch (code)` block (next to `campaignInvalidTransition => 409` and the 422 group):

```dart
    ApiErrorCode.sessionInvalidTransition => 409,
    ApiErrorCode.sessionNotReady => 422,
```

- [ ] **Step 2: Write the failing routes tests**

`server/test/campaign/session_routes_test.dart` (model the harness on `server/test/import_/import_routes_test.dart`: build the whole app with `buildApp`, mint tokens with `TokenService`, seed via the fixtures):

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

void main() {
  late Db db;
  late Handler handler;
  late String creatorToken; // campaign_create
  late String viewerToken; // reporting_viewer, no campaign_create

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // user-1 campaign_creator
    await seedOrganizationWithUser(db,
        userId: 'user-2', username: 'viewer', roles: const ['reporting_viewer']);
    final tokens = TokenService(db: db, config: config);
    creatorToken = (await tokens.issueFor('user-1')).accessToken;
    viewerToken = (await tokens.issueFor('user-2')).accessToken;
    handler = buildApp(db: db, config: config);
    await seedCampaign(db, id: 'camp-1'); // APPROVED
    await seedSession(db, campaignId: 'camp-1', id: 's-1');
  });
  tearDown(() async => db.close());

  Future<Response> get(String path, {String? bearer}) => handler(Request(
        'GET',
        Uri.parse('http://localhost$path'),
        headers: {if (bearer != null) 'authorization': 'Bearer $bearer'},
      ));

  Future<Response> post(String path, {String? bearer}) => handler(Request(
        'POST',
        Uri.parse('http://localhost$path'),
        headers: {if (bearer != null) 'authorization': 'Bearer $bearer'},
      ));

  Future<Map<String, Object?>> body(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  test('GET lists the campaign sessions with zero counts', () async {
    final res = await get('/campaigns/camp-1/sessions', bearer: creatorToken);
    expect(res.statusCode, 200);
    final items = (await body(res))['items']! as List;
    expect(items, hasLength(1));
    final s = items.single as Map<String, Object?>;
    expect(s['status'], 'UPCOMING');
    expect(s['registeredCount'], 0);
    expect(s['readinessOk'], true);
  });

  test('GET a campaign outside the org is 404, not 403', () async {
    await seedCampaign(db, id: 'other-org-camp', organizationId: 'org-2');
    final res = await get('/campaigns/other-org-camp/sessions', bearer: creatorToken);
    expect(res.statusCode, 404);
  });

  test('start -> pause -> close walks the lifecycle', () async {
    final started = await post('/sessions/s-1/start', bearer: creatorToken);
    expect(started.statusCode, 200);
    expect((await body(started))['status'], 'ACTIVE');

    final paused = await post('/sessions/s-1/pause', bearer: creatorToken);
    expect((await body(paused))['status'], 'PAUSED');

    final closed = await post('/sessions/s-1/close', bearer: creatorToken);
    expect((await body(closed))['status'], 'CAPTURE_CLOSED');
  });

  test('start twice is an idempotent 200 (double-tap safe)', () async {
    await post('/sessions/s-1/start', bearer: creatorToken);
    final again = await post('/sessions/s-1/start', bearer: creatorToken);
    expect(again.statusCode, 200);
    expect((await body(again))['status'], 'ACTIVE');
  });

  test('start on a closed session is 409 SESSION_INVALID_TRANSITION', () async {
    await post('/sessions/s-1/start', bearer: creatorToken);
    await post('/sessions/s-1/close', bearer: creatorToken);
    final res = await post('/sessions/s-1/start', bearer: creatorToken);
    expect(res.statusCode, 409);
    expect(((await body(res))['error']! as Map)['code'], 'SESSION_INVALID_TRANSITION');
  });

  test('start when not ready is 422 SESSION_NOT_READY', () async {
    await seedSession(db, campaignId: 'camp-1', id: 's-novenue', venue: null);
    final res = await post('/sessions/s-novenue/start', bearer: creatorToken);
    expect(res.statusCode, 422);
    expect(((await body(res))['error']! as Map)['code'], 'SESSION_NOT_READY');
  });

  test('an unknown session id is 404', () async {
    final res = await post('/sessions/nope/start', bearer: creatorToken);
    expect(res.statusCode, 404);
  });

  test('a viewer without campaign_create is 403', () async {
    final res = await post('/sessions/s-1/start', bearer: viewerToken);
    expect(res.statusCode, 403);
  });

  test('unauthenticated is 401', () async {
    final res = await post('/sessions/s-1/start');
    expect(res.statusCode, 401);
  });
}
```

> Confirm the `seedCampaign` signature accepts `organizationId` for the cross-org test; if not, seed a second org+campaign the way the existing route tests do it. Confirm `seedOrganizationWithUser` supports `roles:`; the import route tests already use a `reporting_viewer` viewer this way.

- [ ] **Step 3: Run it and confirm it fails**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/campaign/session_routes_test.dart`
Expected: FAIL — `sessionRouter` does not exist / the session leg is not mounted.

- [ ] **Step 4: Implement the router**

`server/lib/src/campaign/session_routes.dart`:

```dart
import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/correlation.dart';
import '../infra/error_envelope.dart';
import 'session_machine.dart';
import 'session_repo.dart';

/// `GET /campaigns/<id>/sessions` (any authenticated org member; org-scoped)
/// and `POST /sessions/<id>/{start,pause,close}` (campaign_create). All are
/// org-scoped inside the repo SQL — a cross-org session id is a 404 (D7).
Router sessionRouter({required Db db}) {
  final router = Router();
  final repo = SessionRepo(db);

  Response _json(Object? body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );

  router.get('/campaigns/<id>/sessions', (Request request, String id) async {
    final auth = authOf(request);
    final list = await repo.listForCampaign(id, organizationId: auth.organizationId);
    if (list == null) throw ApiException(ApiErrorCode.notFound);
    return _json({'items': [for (final s in list) s.toWireJson()]});
  });

  Handler _action(SessionAction action) => const Pipeline()
      .addMiddleware(requirePermission('campaign_create'))
      .addHandler((Request request) async {
        final auth = authOf(request);
        final sessionId = request.params['id']!;
        final result = await repo.apply(
          action,
          sessionId: sessionId,
          organizationId: auth.organizationId,
          actorId: auth.userId,
          correlationId: correlationOf(request),
        );
        switch (result.outcome) {
          case SessionOutcome.applied:
          case SessionOutcome.idempotentNoop:
            return _json(result.view!.toWireJson());
          case SessionOutcome.notFound:
            throw ApiException(ApiErrorCode.notFound);
          case SessionOutcome.notReady:
            throw ApiException(
              ApiErrorCode.sessionNotReady,
              message: 'Session is not ready to start: it needs an approved or '
                  'active campaign, a venue and a start time.',
            );
          case SessionOutcome.invalidTransition:
            throw ApiException(
              ApiErrorCode.sessionInvalidTransition,
              message: 'Cannot ${action.name} a session in state '
                  '${result.currentStatus!.wireValue}.',
            );
        }
      });

  router.post('/sessions/<id>/start', _action(SessionAction.start));
  router.post('/sessions/<id>/pause', _action(SessionAction.pause));
  router.post('/sessions/<id>/close', _action(SessionAction.close));

  return router;
}
```

- [ ] **Step 5: Mount the session leg in the Cascade**

In `server/lib/src/app.dart`:

1. Add the import: `import 'campaign/session_routes.dart';`
2. Build the leg (after the `importHandler` block, mirroring it). The `_authenticateUnder` roots must cover both a `campaigns`-prefixed path and a bare `sessions` path:

```dart
  final sessionHandler = const Pipeline()
      .addMiddleware(
        _authenticateUnder(
          const {'campaigns', 'sessions'},
          db: db,
          tokens: tokens,
        ),
      )
      .addHandler(sessionRouter(db: db).call);
```

3. Add it to the `Cascade` (after `.add(importHandler)`):

```dart
      .add(sessionHandler)
```

> Cascade ordering note: `sessionHandler` handles `GET /campaigns/<id>/sessions` and `POST /sessions/<id>/<action>`. The campaign leg's router does not define those, so it falls through (routeNotFound → next leg) to reach this one, exactly as the participant leg is reached for `/campaigns/<id>/registrations`. Place `sessionHandler` after the participant leg; the specific paths do not collide with campaign or participant routes.

- [ ] **Step 6: Run the routes tests — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/campaign/session_routes_test.dart`
Expected: all pass (200 list, 404 cross-org, lifecycle walk, idempotent 200, 409, 422, 404 unknown, 403 viewer, 401 unauth).

- [ ] **Step 7: Full server suite, format, analyze, commit**

```bash
cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test
dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/campaign/session_routes.dart server/lib/src/infra/error_envelope.dart server/lib/src/app.dart server/test/campaign/session_routes_test.dart
git commit -m "feat(server): session endpoints — GET list + start/pause/close

GET /campaigns/<id>/sessions (any org member, 404 out-of-org) and
POST /sessions/<id>/{start,pause,close} (campaign_create). The repo's result
type maps onto the envelope: applied/no-op -> 200, notFound -> 404,
SESSION_INVALID_TRANSITION -> 409, SESSION_NOT_READY -> 422. Mounted as a new
Cascade leg under the campaigns/sessions roots."
```

---

### Task 6: Client — `SessionStatus` from contracts, safe parsing, and driveable controls

**Files:**
- Modify: `lib/domain/session/campaign_session.dart`
- Modify: `lib/data/session/session_repository_impl.dart`
- Modify: `lib/features/campaign_detail/presentation/campaign_detail_screen.dart`
- Create: `test/data/session/session_repository_impl_test.dart`
- Create: `test/features/campaign_detail/presentation/session_card_test.dart`

**Interfaces:**
- Consumes: `SessionStatus` from `campaign_contracts` (Task 1); the `/campaigns/<id>/sessions` and `/sessions/<id>/<action>` wire shapes (Tasks 4–5).
- Produces: no new server-facing interface; the app now parses SCREAMING_SNAKE session status and exposes stable ids on the session controls for the e2e (Task 8).

- [ ] **Step 1: Write the failing client repo test**

`test/data/session/session_repository_impl_test.dart` (model on `test/data/import/import_repository_impl_test.dart` — a recording `HttpClientAdapter` + a bare Dio):

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:acsl_campaign/data/session/session_repository_impl.dart';
import 'package:acsl_campaign/domain/session/campaign_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this._respond);
  final ResponseBody Function(RequestOptions o) _respond;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async {
    requests.add(o);
    return _respond(o);
  }
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body) => ResponseBody.fromString(
      jsonEncode(body), 200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

void main() {
  SessionRepositoryImpl build(ResponseBody Function(RequestOptions) r) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = _Adapter(r);
    return SessionRepositoryImpl(dio);
  }

  test('parses SCREAMING_SNAKE status from the list endpoint', () async {
    final repo = build((_) => _json({
          'items': [
            {'id': 's1', 'campaignId': 'c1', 'venue': 'Hall', 'status': 'CAPTURE_CLOSED',
             'capacity': 10, 'readinessOk': false},
          ],
        }));
    final res = await repo.listForCampaign('c1');
    final list = res.fold((l) => l, (f) => fail('expected Ok: $f'));
    expect(list.single.status, SessionStatus.captureClosed);
  });

  test('an unknown status is non-operational (captureClosed), never upcoming',
      () async {
    final repo = build((_) => _json({'id': 's1', 'campaignId': 'c1',
        'venue': 'Hall', 'status': 'SOME_FUTURE_STATE', 'capacity': 0,
        'readinessOk': false}));
    final res = await repo.start('s1');
    final s = res.fold((s) => s, (f) => fail('expected Ok: $f'));
    expect(s.status, SessionStatus.captureClosed,
        reason: 'unknown must not become a startable upcoming session');
  });

  test('actions POST to /sessions/<id>/<action>', () async {
    late RequestOptions seen;
    final repo = build((o) { seen = o; return _json({'id': 's1', 'campaignId': 'c1',
        'venue': 'Hall', 'status': 'PAUSED', 'capacity': 0, 'readinessOk': true}); });
    await repo.pause('s1');
    expect(seen.path, '/sessions/s1/pause');
    expect(seen.method, 'POST');
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/data/session/session_repository_impl_test.dart`
Expected: FAIL — the unknown-status test gets `upcoming` (current `orElse`), and `SessionStatus` is still the local enum.

- [ ] **Step 3: Move `SessionStatus` to a re-export shim**

In `lib/domain/session/campaign_session.dart`, delete the local `enum SessionStatus { upcoming, active, captureClosed, paused, completed }` and re-export the contract enum instead. Add near the top (after the existing imports/`part`):

```dart
export 'package:campaign_contracts/campaign_contracts.dart' show SessionStatus;
```

Keep the `CampaignSession` freezed class and `overCapacity` exactly as they are. (The enum member set is unchanged — `upcoming, active, paused, captureClosed, completed` — so no other file needs editing; only the wire values and parse site change.)

- [ ] **Step 4: Parse with `tryParseWire` and the unknown policy**

In `lib/data/session/session_repository_impl.dart`, replace the `status:` line in `_fromJson`:

```dart
    // was: SessionStatus.values.firstWhere((s) => s.name == j['status'],
    //          orElse: () => SessionStatus.upcoming),
    status: _parseStatus(j['status'] as String?),
```

and add the helper (import `package:flutter/foundation.dart` for `debugPrint` if not present):

```dart
  /// An unrecognised wire status is surfaced as a visible, action-disabling
  /// fallback — never `upcoming`, which would enable Start on a session in an
  /// unknown state. Same policy as ImportStatus parsing.
  SessionStatus _parseStatus(String? wire) {
    final parsed = wire == null ? null : SessionStatus.tryParseWire(wire);
    if (parsed == null) {
      debugPrint('SessionRepositoryImpl: unrecognised session status "$wire"; '
          'treating it as captureClosed (non-operational).');
      return SessionStatus.captureClosed;
    }
    return parsed;
  }
```

- [ ] **Step 5: Run the client repo test — must pass**

Run: `flutter test test/data/session/session_repository_impl_test.dart`
Expected: all pass.

- [ ] **Step 6: Write the failing session-card widget test**

`test/features/campaign_detail/presentation/session_card_test.dart` — pump a `_SessionCard` (or the Sessions tab with a fake controller, following `test/widget/bulk_import_screen_test.dart`) for each status and assert the control gating and stable ids. The controls the e2e drives need `Semantics(identifier: …)` ids: `session_start`, `session_pause`, `session_close`, and the status chip text must be assertable.

```dart
// Assert, at minimum:
// - status UPCOMING + readinessOk: 'session_start' is present and enabled.
// - status UPCOMING + !readinessOk: 'session_start' is present but disabled.
// - status ACTIVE: 'session_pause' and 'session_close' present; no 'session_start'.
// - status CAPTURE_CLOSED: none of the three operation controls are present.
// Use find.bySemanticsIdentifier or a keyed finder consistent with how the
// registration/bulk-import widget tests locate id-driven controls.
```

- [ ] **Step 7: Add stable ids to the session controls**

In `lib/features/campaign_detail/presentation/campaign_detail_screen.dart` `_SessionCard`, give each operation button a stable identifier and confirm the gating matches the machine (Start on `upcoming`/`paused`, enabled only when `readinessOk`; Pause on `active`; Close on `active`/`paused`; nothing on `captureClosed`/`completed`). Wrap each with the same `Semantics(identifier: …)` idiom the registration/bulk-import controls use (the app's `BmdButton` takes an `identifier:` — reuse it):

```dart
// Start/Resume:
BmdButton(identifier: 'session_start', label: …, onPressed: session.readinessOk ? … : null)
// Pause:
BmdButton(identifier: 'session_pause', label: 'Pause', onPressed: …)
// Close capture:
BmdButton(identifier: 'session_close', label: 'Close capture', onPressed: …)
```

Also give the status chip a form the flow can assert (a stable text label per status, e.g. "Active" / "Paused" / "Capture closed").

- [ ] **Step 8: Run the widget test and the full Flutter suite**

Run: `flutter test test/features/campaign_detail/presentation/session_card_test.dart` then `flutter test`
Expected: the new tests pass; the whole suite passes with the count up only by the tests this task adds. Investigate any pre-existing test that referenced the old camelCase session status wire (there should be none — the app never emitted session status).

- [ ] **Step 9: Format, analyze, commit**

```bash
flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs
dart format --set-exit-if-changed lib test
flutter analyze --fatal-infos
git add lib/domain/session lib/data/session lib/features/campaign_detail test/data/session test/features/campaign_detail/presentation/session_card_test.dart
git commit -m "feat(client): session status from contracts + driveable controls

SessionStatus re-exports from campaign_contracts (SCREAMING_SNAKE wire).
_fromJson parses via tryParseWire; an unknown status is a non-operational
captureClosed, never a startable upcoming (the old orElse default). The
Sessions-tab controls carry stable ids (session_start/pause/close) and gate by
the status machine so Maestro can drive them."
```

---

### Task 7: Mock server parity — SCREAMING_SNAKE sessions

**Files:**
- Modify: `tool/mock_server/bin/server.dart`
- Modify: `server/test/contract/parity_test.dart`

**Interfaces:**
- Consumes: the ratified session wire (Tasks 1, 4, 5).
- Produces: a mock whose session shapes and status vocabulary match the real service, pinned by parity.

- [ ] **Step 1: Update the mock session fixture and action map**

In `tool/mock_server/bin/server.dart` `sessionsFor`, change the seeded session to the ratified shape: `status: 'UPCOMING'`, and set every activity count to `0` (3a.D6) to match the real service:

```dart
        'status': 'UPCOMING',
        'startAt': '2026-08-01T09:00:00.000Z',
        'endAt': '2026-08-01T13:00:00.000Z',
        'capacity': 60,
        'registeredCount': 0,
        'pendingSyncCount': 0,
        'reviewCount': 0,
        'approvedCount': 0,
        'readinessOk': true,
```

and in `sessionAction`, emit SCREAMING_SNAKE:

```dart
    s['status'] = switch (action) {
      'start' => 'ACTIVE',
      'close' => 'CAPTURE_CLOSED',
      'pause' => 'PAUSED',
      _ => s['status'],
    };
```

- [ ] **Step 2: Pin session parity**

In `server/test/contract/parity_test.dart`, add a case asserting the mock and the real service agree on the session wire: the set of status wire values is exactly the SCREAMING_SNAKE `SessionStatus.values.map((s) => s.wireValue)` set, and a `SessionView`'s JSON keys match. Follow the existing parity cases' structure (they already compare campaign/import shapes). If parity is asserted by launching the mock and hitting it, add `GET /campaigns/<id>/sessions` and one `POST /sessions/<id>/start` to the compared set; assert the `status` value round-trips through `SessionStatus.tryParseWire` (i.e. is non-null and SCREAMING_SNAKE).

- [ ] **Step 3: Run parity + the mock's own smoke, format, analyze, commit**

```bash
cd tool/mock_server && dart pub get && dart analyze && dart format --set-exit-if-changed .
cd ../.. && cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/contract/parity_test.dart
cd .. && git add tool/mock_server/bin/server.dart server/test/contract/parity_test.dart
git commit -m "chore(mock): session wire matches the real service (SCREAMING_SNAKE, 0 counts)

The mock now emits UPCOMING/ACTIVE/PAUSED/CAPTURE_CLOSED and zeroed activity
counts, and parity pins that its session shape and status vocabulary match the
real campaign_service."
```

---

### Task 8: E2E — seed a session, the Maestro flow, and the CI gate

**Files:**
- Modify: `server/lib/src/seed/seed_routes.dart`
- Create: `.maestro/flows/session_ops.yaml`
- Modify: `.maestro/config.yaml`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the real endpoints (Tasks 4–5), the driveable controls (Task 6), the seed reset (`/__test__/reset`).
- Produces: a green `e2e (sessionOps)` emulator gate proving the Sessions tab operates against the real service.

- [ ] **Step 1: Seed an operable session for `seed-camp-1`**

In `server/lib/src/seed/seed_routes.dart` `_seedCampaignFixture`, after inserting the campaign_territories row, insert one session for the APPROVED `seed-camp-1` only (so the e2e always has a ready, startable session; the other fixtures need none):

```dart
    if (fixture.id == 'seed-camp-1') {
      await db.execute(
        'INSERT INTO campaign_sessions '
        '(id, campaign_id, venue, capacity, start_at, status) '
        "VALUES (@id, @c, @v, 60, @s, 'UPCOMING')",
        params: {
          'id': 'seed-camp-1-session-1',
          'c': fixture.id,
          'v': 'BMD Training Center, Hall A',
          's': DateTime.utc(2026, 9, 1, 9),
        },
      );
    }
```

Add a server test (in `server/test/seed/…` if one exists, else extend an existing seed test) asserting `/__test__/reset` then `GET /campaigns/seed-camp-1/sessions` returns one `UPCOMING`, `readinessOk: true` session. If there is no seed-route test file, assert it inside `session_routes_test.dart` by calling the seed path — but prefer the seed test if the harness exists.

- [ ] **Step 2: Write the Maestro flow**

`.maestro/flows/session_ops.yaml` (model the login prelude and comments on `.maestro/flows/bulk_import.yaml`):

```yaml
# 3a session operations against the REAL campaign_service. POST /__test__/reset
# seeds campaign "ACSL Pilot Carpenter Drive" (APPROVED, owner campaign_creator)
# with one UPCOMING, ready session. Requires the realAuth APK
# (--dart-define=E2E_REAL_AUTH=true): RouteGuards redirect an unauthenticated
# session to /login, so this signs in for real as campaign_creator (who holds
# campaign_create -- the permission gating start/pause/close).
appId: ${APP_ID}
tags:
  - session_ops
  - critical
  - android
---
- clearState
- launchApp

- assertVisible:
    id: "login_username"
- tapOn:
    id: "login_username"
- inputText: "campaign_creator"
- tapOn:
    id: "login_password"
- inputText: "Test1234!"
- hideKeyboard
- tapOn:
    id: "login_submit"

- assertVisible:
    id: "dev_launcher"
- tapOn:
    id: "dev_open_campaigns"

- assertVisible: ".*ACSL Pilot Carpenter Drive.*"
- tapOn: ".*ACSL Pilot Carpenter Drive.*"

# Campaign detail: open the Sessions tab.
- tapOn: "Sessions"

# The seeded UPCOMING session's Start is enabled (readiness OK). Each action is
# a real POST /sessions/<id>/<action> to the campaign_service; assert the
# resulting status label after each (extendedWaitUntil: the action is an async
# round trip).
- tapOn:
    id: "session_start"
- extendedWaitUntil:
    visible: ".*Active.*"
    timeout: 15000
- tapOn:
    id: "session_pause"
- extendedWaitUntil:
    visible: ".*Paused.*"
    timeout: 15000
- tapOn:
    id: "session_start"
- extendedWaitUntil:
    visible: ".*Active.*"
    timeout: 15000
- tapOn:
    id: "session_close"
- extendedWaitUntil:
    visible: ".*Capture closed.*"
    timeout: 15000
```

> The exact status label strings (`Active` / `Paused` / `Capture closed`) must match what `_SessionCard`'s status chip renders (Task 6 Step 7). If the chip merges into a multi-line accessibility node, wrap the asserted text in `.*….*` as the 2a/2b flows do, and escape any parentheses.

- [ ] **Step 3: Add the flow to the workspace inventory**

In `.maestro/config.yaml`, add to the `flows:` list:

```yaml
  - flows/session_ops.yaml
```

- [ ] **Step 4: Add the CI matrix config**

In `.github/workflows/ci.yml`, add a matrix entry to the `e2e` job's `matrix.config` list (mirroring the `bulkImport` entry — real service, real auth, blocking):

```yaml
          # 3a: real-auth login, open the seeded APPROVED campaign's Sessions
          # tab, and drive start -> pause -> resume -> close against the real
          # campaign_service. Acceptance proof for sub-project 3a.
          - key: sessionOps
            defines: '--dart-define=E2E_REAL_AUTH=true'
            useMock: '0'
            flows: .maestro/flows/session_ops.yaml
```

- [ ] **Step 5: Local emulator reproduction (or targeted validation)**

If an emulator is available, build the sessionOps APK and run the flow the way CI does (`run_maestro_flows.sh`). Otherwise, validate the pieces the flow depends on without the emulator: bring up the server (`cd server && ENABLE_TEST_SEEDING=true JWT_SECRET=… docker compose up -d --build`), `curl -X POST localhost:8080/__test__/reset`, log in as `campaign_creator`, and confirm `GET /campaigns/seed-camp-1/sessions` returns one `UPCOMING` session and `POST /sessions/seed-camp-1-session-1/start` returns `ACTIVE`. Record what was validated.

- [ ] **Step 6: Commit**

```bash
git add server/lib/src/seed/seed_routes.dart .maestro/flows/session_ops.yaml .maestro/config.yaml .github/workflows/ci.yml
# include any seed test file you added
git commit -m "feat(e2e): session operations flow against the real service

Seeds one UPCOMING, ready session on seed-camp-1. A new session_ops Maestro
flow signs in for real as campaign_creator, opens the Sessions tab, and drives
start -> pause -> resume -> close against the real campaign_service, asserting
each status. Added as a blocking sessionOps emulator matrix config (useMock 0)."
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task:
- §2 3a.D1 (SessionStatus contract, no default) → Task 1 + Task 6 (client parse).
- §2 3a.D2 (status machine) → Task 3; §2 3a.D3 (dormant COMPLETED cascade) → Task 4 (`completeSessionsForCampaign` + test).
- §2 3a.D4 (readiness) → Task 3 (`isReady`) + Task 5 (422 gate).
- §2 3a.D5 (campaign_create writes; any-org-member reads; 404 out-of-org) → Task 5.
- §2 3a.D6 (counts 0) → Task 4 (`toWireJson`) + Task 7 (mock).
- §2 3a.D7 (atomic CAS; 404/200/409/422 disambiguation) → Task 4 (repo) + Task 5 (routes).
- §3 endpoints + SessionView shape → Tasks 4–5. §3 error codes → Task 1 + Task 5 (status mapping).
- §5 migration/seed/audit/org-scope → Tasks 2, 4, 5, 8. §6 client + mock → Tasks 6, 7. §7 e2e → Task 8. §8 testing → the tests in every task (machine unit, route integration incl. the concurrency falsification, client, parity, whole-suite guard).
- §9 out-of-scope items are not implemented (no diff/correction-history, no campaign activation endpoint, no session_id on registrations, no attendance_capture gate, no session CRUD).

**Placeholder scan:** no "TBD"/"handle edge cases"/"similar to Task N"/bare "write tests" — every code step carries real code; every test step carries real assertions.

**Type consistency:** `SessionStatus{upcoming,active,paused,captureClosed,completed}`, `SessionAction{start,pause,close}`, `allowedFrom`/`targetOf`/`isReady`, `SessionView`/`SessionOutcome`/`SessionApplyResult`, `SessionRepo.{listForCampaign,apply,completeSessionsForCampaign}`, and `sessionRouter({required Db db})` are used with identical names and signatures across Tasks 1→8. Wire values are SCREAMING_SNAKE everywhere; field names camelCase. Error codes `sessionInvalidTransition`→409 / `sessionNotReady`→422 are defined in Task 1 and mapped in Task 5.
