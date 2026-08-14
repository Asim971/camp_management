# Verification Decision Completion (5b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the CRM verification decision path — add return-for-recapture, escalation, and supervisor override to the `POST /verification/cases/<id>/decision` endpoint, with the client, mock, and e2e caught up.

**Architecture:** Extends the 5a verification slice. The decision endpoint gains the full `VerificationOutcome` vocabulary with a status-machine side-effect each, a two-mode optimistic-locking CAS (normal keeps 5a's `status='CRM_REVIEW'` guard; supervisor override drops it but stays version-safe), and RBAC on `verification_override`. `AttendanceStatus` joins the shared contracts package so the client parses the case status instead of hard-coding it.

**Tech Stack:** Dart 3.12 `shelf`/`shelf_router`/`postgres` server (hand-written SQL, no ORM/codegen); `campaign_contracts` shared package; Flutter/Riverpod/Dio client; `tool/mock_server`; Maestro e2e on the GitHub emulator matrix. Postgres 16+ on `localhost:5432`.

**Spec:** `docs/superpowers/specs/2026-08-14-verification-decision-completion-design.md` (decisions cited 5b.D1–D8).

## Global Constraints

Every task's requirements implicitly include this section.

- **SDK floor is exactly `sdk: ">=3.12.0 <4.0.0"`** in every `pubspec.yaml`. No code generation and no ORM anywhere in `server/` or `packages/campaign_contracts`.
- **Wire naming is `SCREAMING_SNAKE` for every enum value.** `AttendanceStatus` wire values: `NOT_CAPTURED`, `PENDING_SYNC`, `MATCH_PROCESSING`, `CRM_REVIEW`, `APPROVED`, `REJECTED`, `RETURNED`.
- **Unknown enum values never resolve to a default.** `tryParseWire` returns `null`; a client fallback must be explicit and `debugPrint`-visible.
- **Out-of-scope resources return `404`, never `403`** (foundation D7). Every verification query — including both CAS shapes — filters `organization_id = @org`.
- **Decision endpoint status codes:** `If-Match` missing/non-int → **400**; body not a JSON object → **400**; unknown `outcome` wire → **422 `VERIFICATION_OUTCOME_UNSUPPORTED`**; `supervisorOverride:true` without `verification_override` → **403 `FORBIDDEN`**; blank reason when required → **422 `DECISION_REASON_REQUIRED`**; stale version (or closed case for a non-override) → **412 `PRECONDITION_FAILED`**; missing/cross-org attendance → **404 `NOT_FOUND`**.
- **Reason is required** when the outcome is `REJECTED`, `RETURN_FOR_RECAPTURE`, or `ESCALATED`, **or** whenever `supervisorOverride` is `true`. `APPROVED` without override needs none.
- **The two-mode CAS:** a normal decision keeps `AND status = 'CRM_REVIEW'`; a supervisor override drops that clause but keeps `AND version = @ifMatch`. Both keep `AND organization_id = @org`. Zero affected rows → re-check existence → 412 (exists) / 404 (gone).
- **Outcome → attendance status:** `APPROVED→APPROVED`, `REJECTED→REJECTED`, `RETURN_FOR_RECAPTURE→RETURNED`, `ESCALATED→CRM_REVIEW` (unchanged) + stamp `escalated_at`/`escalated_by`.
- **The `verification_decisions.outcome` column stores the `VerificationOutcome` wire value** (`APPROVED`/`REJECTED`/`RETURN_FOR_RECAPTURE`/`ESCALATED`), NOT the resulting status. `VerificationDecisionResult.finalStatus` carries the attendance status.
- **`ENABLE_TEST_SEEDING` must never be committed enabled** anywhere (CI-only); seed routes stay gated behind it.
- **Postgres runs natively on `localhost:5432`** (`postgres://campaign:campaign@localhost:5432/campaign`). On Windows, `dart test` with no args crashes (frontend_server, branch-independent); run specific files/dirs, and prefer PowerShell `$env:DATABASE_URL='...'; dart test test/<dir>` for DB-backed suites.
- **Every decision writes a `verification.decided` audit event; every case view writes `verification.case_viewed`** — both unchanged from 5a.
- **No new `ApiErrorCode` members and no new endpoints.** All error codes used already exist and are mapped in `server/lib/src/infra/error_envelope.dart`; `VerificationOutcome` already has all four members.

---

## File Structure

```
packages/campaign_contracts/
  lib/src/attendance_status.dart        NEW — AttendanceStatus + wireValue + tryParseWire
  lib/campaign_contracts.dart           export the new file
  test/attendance_status_test.dart      NEW

lib/domain/common/status.dart           AttendanceStatus becomes a re-export shim

server/lib/src/db/migrations/embedded.dart   migration 009 (escalated_at/escalated_by)
server/lib/src/verification/verification_repo.dart    full outcomes, two-mode CAS, escalation, status in wire
server/lib/src/verification/verification_routes.dart  override→403 gate, malformed body→400
server/lib/src/seed/seed_routes.dart          crm_supervisor user (if absent)

lib/data/verification/verification_repository_impl.dart   parse case status
lib/features/crm_case/presentation/crm_case_screen.dart   reason-when-required + override control
lib/features/crm_case/application/crm_case_controller.dart  pass override through (already present)

tool/mock_server/bin/server.dart          decision handler: four outcomes + reason-422
server/test/contract/parity_test.dart     pin the new rules
.maestro/flows/crm_case_recapture.yaml    NEW — return-for-recapture (crm_verifier)
.maestro/flows/crm_case_override.yaml      NEW — supervisor override (crm_supervisor)
.github/workflows/ci.yml                   add the two flows to the crm matrix
```

Tests live beside their subjects (`server/test/verification/…`, `server/test/db/…`, `test/data/verification/…`, `server/test/media/…`).

---

### Task 1: Move `AttendanceStatus` to `campaign_contracts`

**Files:**
- Create: `packages/campaign_contracts/lib/src/attendance_status.dart`
- Modify: `packages/campaign_contracts/lib/campaign_contracts.dart`
- Modify: `lib/domain/common/status.dart`
- Create: `packages/campaign_contracts/test/attendance_status_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum AttendanceStatus { notCaptured, pendingSync, matchProcessing, crmReview, approved, rejected, returned }` with `String get wireValue` (SCREAMING_SNAKE) and `static AttendanceStatus? tryParseWire(String)`.

**Context:** `RegistrationStatus` and `ImportStatus` already made this exact move; `lib/domain/common/status.dart` already re-exports them via `show`. `AttendanceStatus` has **no** `wireValue` today and 13 importers reach it through `status.dart`. This is a mechanical move — no `ApiErrorCode` change, so no server build-break to fold in (unlike 5a Task 1).

- [ ] **Step 1: Write the failing enum test**

`packages/campaign_contracts/test/attendance_status_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('AttendanceStatus wire values are SCREAMING_SNAKE and round-trip', () {
    final wires = AttendanceStatus.values.map((s) => s.wireValue).toList();
    expect(wires.toSet().length, AttendanceStatus.values.length);
    for (final s in AttendanceStatus.values) {
      expect(s.wireValue, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: s.name);
      expect(AttendanceStatus.tryParseWire(s.wireValue), s);
    }
  });

  test('specific wire values are exactly as the server emits', () {
    expect(AttendanceStatus.crmReview.wireValue, 'CRM_REVIEW');
    expect(AttendanceStatus.returned.wireValue, 'RETURNED');
    expect(AttendanceStatus.matchProcessing.wireValue, 'MATCH_PROCESSING');
    expect(AttendanceStatus.notCaptured.wireValue, 'NOT_CAPTURED');
  });

  test('an unknown wire value is null, never a default', () {
    expect(AttendanceStatus.tryParseWire('NOT_A_STATUS'), isNull);
    expect(AttendanceStatus.tryParseWire(''), isNull);
    expect(AttendanceStatus.tryParseWire('crmReview'), isNull,
        reason: 'case matters');
  });
}
```

- [ ] **Step 2: Run it and confirm failure**

Run: `cd packages/campaign_contracts && dart pub get && dart test test/attendance_status_test.dart`
Expected: compile failure — `AttendanceStatus` is not exported from `campaign_contracts`.

- [ ] **Step 3: Implement the enum**

`packages/campaign_contracts/lib/src/attendance_status.dart` (mirror `match_band.dart`'s shape):

```dart
/// Attendance lifecycle status. The wire value is the contract; the Dart name
/// is an implementation detail on either side. Moved out of the app's
/// `lib/domain/common/status.dart` so the server and client cannot disagree
/// about it (spec 5a.D1, delivered in 5b when the client first parses it).
enum AttendanceStatus {
  notCaptured,
  pendingSync,
  matchProcessing,
  crmReview,
  approved,
  rejected,
  returned;

  String get wireValue => switch (this) {
    notCaptured => 'NOT_CAPTURED',
    pendingSync => 'PENDING_SYNC',
    matchProcessing => 'MATCH_PROCESSING',
    crmReview => 'CRM_REVIEW',
    approved => 'APPROVED',
    rejected => 'REJECTED',
    returned => 'RETURNED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  static AttendanceStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
```

Add to `packages/campaign_contracts/lib/campaign_contracts.dart`, alphabetically among the existing `export 'src/…'` lines:

```dart
export 'src/attendance_status.dart';
```

- [ ] **Step 4: Run the contracts tests — must pass**

Run: `cd packages/campaign_contracts && dart test`
Expected: all pass, including the new `attendance_status_test.dart`.

- [ ] **Step 5: Turn the app's `AttendanceStatus` into a shim**

In `lib/domain/common/status.dart`: delete the local `enum AttendanceStatus { … }` block and add `AttendanceStatus` to the existing contracts re-export `show` list (which already lists `CampaignStatus, RegistrationStatus, ImportStatus`). Update the doc comment that says "[AttendanceStatus] and [IntegrityFlag] remain" — now only `IntegrityFlag` remains. Leave `IntegrityFlag`, `StatusTone`, and every other enum untouched.

- [ ] **Step 6: Regenerate and verify the app is unbroken**

Run (Flutter needs codegen; `verification_case.dart` is `@freezed` and references `AttendanceStatus`):
```
flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs
dart format --set-exit-if-changed lib packages
flutter analyze --fatal-infos
flutter test
```
Expected: analyze clean; the full suite passes with the SAME counts as before this task (a changed count means the shim altered behaviour — investigate, do not accept). Do not stage generated `*.freezed.dart`/`*.g.dart` (they are git-ignored).

- [ ] **Step 7: Commit**

```bash
cd packages/campaign_contracts && dart format --set-exit-if-changed .
cd ../.. && git add packages/campaign_contracts lib/domain/common/status.dart
git commit -m "feat(contracts): share AttendanceStatus so the client can parse case status

AttendanceStatus moves to campaign_contracts with a SCREAMING_SNAKE wireValue
and tryParseWire (unknown -> null), and lib/domain/common/status.dart keeps it
as a re-export shim — the same move RegistrationStatus/ImportStatus already made.
5b's case wire emits status, so the client must parse it rather than hard-code
crmReview."
```

---

### Task 2: Migration `009_escalation`

**Files:**
- Modify: `server/lib/src/db/migrations/embedded.dart`
- Modify: `server/test/db/migrator_test.dart`

**Interfaces:**
- Produces: `attendance.escalated_at` (TIMESTAMPTZ, nullable), `attendance.escalated_by` (TEXT, nullable, FK → `staff_users(id)`).

**Context:** `embeddedMigrations` (`embedded.dart:2`) is applied in lexical key order; `'008_verification'` (line 10) is currently last. `staff_users(id)` exists. `migrator_test.dart` has a `row(...)` helper and a `db` fixture.

- [ ] **Step 1: Write the failing migrator test**

Add to `server/test/db/migrator_test.dart`, inside the existing `main()` group:

```dart
  test('009 adds the escalation marker columns', () async {
    await Migrator(db).applyPending();
    final cols = await db.execute(
      "SELECT column_name FROM information_schema.columns "
      "WHERE table_name = 'attendance'",
    );
    final names = cols.map((r) => row(r)['column_name']! as String).toSet();
    expect(names, containsAll(<String>['escalated_at', 'escalated_by']));
  });
```

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/db/migrator_test.dart -n '009 adds'` (PowerShell)
Expected: FAIL.

- [ ] **Step 3: Add the migration**

In `embedded.dart`, add `'009_escalation': _escalation,` after `'008_verification': _verification,`, and define the const alongside the others:

```dart
const String _escalation = r'''
ALTER TABLE attendance ADD COLUMN escalated_at TIMESTAMPTZ;
ALTER TABLE attendance ADD COLUMN escalated_by TEXT REFERENCES staff_users(id);
''';
```

- [ ] **Step 4: Run the migrator tests — must pass**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/db/migrator_test.dart`
Expected: all pass, including `009 adds…`.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/db/migrations/embedded.dart server/test/db/migrator_test.dart
git commit -m "feat(server): migration 009 — attendance escalation marker columns"
```

---

### Task 3: Return-for-recapture and escalation outcomes

**Files:**
- Modify: `server/lib/src/verification/verification_repo.dart`
- Modify: `server/lib/src/verification/verification_routes.dart`
- Modify: `server/test/verification/verification_routes_test.dart`

**Interfaces:**
- Consumes: `AttendanceStatus` (Task 1) is NOT needed server-side (the server uses status string literals); migration 009 (Task 2).
- Produces: `VerificationRepo.decide` now accepts `RETURN_FOR_RECAPTURE` (→ status `RETURNED`) and `ESCALATED` (→ status stays `CRM_REVIEW`, stamps `escalated_at`/`escalated_by`), both requiring a reason. `VerificationDecisionResult.finalStatus` carries the resulting attendance status. `verification_decisions.outcome` stores the `VerificationOutcome` wire value. **Supervisor override is NOT in this task** (Task 4) — `supervisorOverride:true` continues to yield `unsupportedOutcome`/422 until Task 4 lands, so the branch is never in a state where override is ungated.

**Context — current `decide()` (verification_repo.dart:175-289):** validates existence, then `supported = approved || rejected`; `if (!supported || supervisorOverride) return unsupportedOutcome`; rejects-need-reason; single-mode CAS with `AND status = 'CRM_REVIEW'`; stores `outcome: newStatus` (the resulting status) on the decision row. This task widens the supported set to include recapture + escalate, fixes the decision-row `outcome` to store the *outcome* wire, and adds the escalation stamp — while LEAVING `supervisorOverride` rejected.

- [ ] **Step 1: Write the failing tests**

Add to `server/test/verification/verification_routes_test.dart` (model on the existing approve/reject cases; they seed a `CRM_REVIEW` attendance, mint a `crm_verifier` token, and POST with an `If-Match` header — reuse that harness/helpers). Add cases:

```dart
// RETURN_FOR_RECAPTURE -> attendance RETURNED, decision row records the outcome.
test('return-for-recapture moves the case to RETURNED', () async {
  // seed a CRM_REVIEW attendance at version 1 (existing helper), then:
  final res = await decideAs(verifierToken, id, ifMatch: 1, body: {
    'outcome': 'RETURN_FOR_RECAPTURE',
    'reason': 'Face not clearly visible; recapture in better light.',
  });
  expect(res.statusCode, 200);
  expect(jsonDecode(await res.readAsString())['status'], 'RETURNED');
  final row = await attendanceRow(db, id);
  expect(row['status'], 'RETURNED');
  expect(row['version'], 2);
  final decision = await latestDecision(db, id);
  expect(decision['outcome'], 'RETURN_FOR_RECAPTURE'); // the OUTCOME, not status
});

// RETURN_FOR_RECAPTURE without a reason -> 422.
test('return-for-recapture requires a reason', () async {
  final res = await decideAs(verifierToken, id, ifMatch: 1,
      body: {'outcome': 'RETURN_FOR_RECAPTURE', 'reason': '  '});
  expect(res.statusCode, 422);
  expect(errorCode(res), 'DECISION_REASON_REQUIRED');
  expect((await attendanceRow(db, id))['status'], 'CRM_REVIEW'); // unchanged
});

// ESCALATED -> status stays CRM_REVIEW, escalation marker set.
test('escalate keeps CRM_REVIEW and stamps the escalation marker', () async {
  final res = await decideAs(verifierToken, id, ifMatch: 1, body: {
    'outcome': 'ESCALATED',
    'reason': 'Ambiguous match; needs supervisor eyes.',
  });
  expect(res.statusCode, 200);
  final row = await attendanceRow(db, id);
  expect(row['status'], 'CRM_REVIEW');
  expect(row['version'], 2);
  expect(row['escalated_at'], isNotNull);
  expect(row['escalated_by'], verifierUserId);
  expect((await latestDecision(db, id))['outcome'], 'ESCALATED');
});

test('escalate requires a reason', () async {
  final res = await decideAs(verifierToken, id, ifMatch: 1,
      body: {'outcome': 'ESCALATED'});
  expect(res.statusCode, 422);
  expect(errorCode(res), 'DECISION_REASON_REQUIRED');
});
```

Where `decideAs`/`attendanceRow`/`latestDecision`/`errorCode` are small local helpers (or inline the existing test file's equivalents — match its style; do not invent a parallel harness). Keep the 5a approve/reject/stale-412/already-decided-412 cases green.

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart`
Expected: the four new cases FAIL (recapture/escalate currently 422 `VERIFICATION_OUTCOME_UNSUPPORTED`).

- [ ] **Step 3: Widen the outcome handling in `decide()`**

In `verification_repo.dart`, replace the `supported`/reason block and `newStatus` computation. After the existence check:

```dart
final outcome = VerificationOutcome.tryParseWire(outcomeWire);
if (outcome == null || supervisorOverride) {
  // Unknown wire, or override (override lands in Task 4). Both -> 422 here.
  return const VerificationDecisionResult(
    VerificationDecisionCode.unsupportedOutcome,
  );
}

const statusForOutcome = {
  VerificationOutcome.approved: 'APPROVED',
  VerificationOutcome.rejected: 'REJECTED',
  VerificationOutcome.returnForRecapture: 'RETURNED',
  VerificationOutcome.escalated: 'CRM_REVIEW', // stays open; marker set below
};
final newStatus = statusForOutcome[outcome]!;

final reasonRequired = outcome == VerificationOutcome.rejected ||
    outcome == VerificationOutcome.returnForRecapture ||
    outcome == VerificationOutcome.escalated;
if (reasonRequired && (reason == null || reason.trim().isEmpty)) {
  return const VerificationDecisionResult(
    VerificationDecisionCode.reasonRequired,
  );
}

final escalating = outcome == VerificationOutcome.escalated;
```

- [ ] **Step 4: Stamp escalation and store the outcome wire in the CAS block**

Extend the CAS `UPDATE` (still single-mode with the `status = 'CRM_REVIEW'` guard — override is Task 4) to set the escalation columns, and store the OUTCOME wire (not the status) on the decision row:

```dart
final casResult = await tx.execute(
  Sql.named(
    'UPDATE attendance SET status = @status, version = version + 1, '
    '  escalated_at = @escAt, escalated_by = @escBy '
    'WHERE id = @id AND version = @ifMatch AND organization_id = @org '
    "  AND status = 'CRM_REVIEW' "
    'RETURNING version',
  ),
  parameters: {
    'status': newStatus,
    'escAt': escalating ? DateTime.now().toUtc() : null,
    'escBy': escalating ? verifierId : null,
    'id': attendanceId,
    'ifMatch': ifMatchVersion,
    'org': organizationId,
  },
);
```

In the `verification_decisions` INSERT, change the `outcome` parameter from `newStatus` to `outcome.wireValue`; likewise the audit payload `{'outcome': outcome.wireValue, 'status': newStatus, 'reason': reason}`. Set `finalStatus: newStatus` on the `applied` result (unchanged).

> Note on escalation columns: this always writes `@escAt`/`@escBy` — for a non-escalate decision they are `null`, which clears any prior escalation marker on a case being closed. That is intentional and deterministic; a closed/returned case does not need a live escalation marker.

- [ ] **Step 5: Update the route's messages**

In `verification_routes.dart`, the `reasonRequired` arm message becomes `'A reason is required for this decision.'` and the `unsupportedOutcome` arm message becomes `'Unrecognised or unsupported outcome.'` (the outcome set is no longer just approve/reject). Do not change the error codes.

- [ ] **Step 6: Run the verification tests — must pass**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart`
Expected: all pass — the four new cases plus every 5a case (approve/reject, stale-412, already-decided-412, reason-422, RBAC).

- [ ] **Step 7: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/verification/verification_repo.dart server/lib/src/verification/verification_routes.dart server/test/verification/verification_routes_test.dart
git commit -m "feat(server): verification decisions gain return-for-recapture and escalate

RETURN_FOR_RECAPTURE -> attendance RETURNED; ESCALATED keeps the case in
CRM_REVIEW and stamps escalated_at/escalated_by so a supervisor can pick it up
(the rich supervisor queue is 5c). Both require a reason. The decision row now
stores the VerificationOutcome wire value, not the resulting status. Supervisor
override stays rejected until the next task, so override is never ungated."
```

---

### Task 4: Supervisor override (two-mode CAS + 403 gate + malformed body → 400)

**Files:**
- Modify: `server/lib/src/verification/verification_repo.dart`
- Modify: `server/lib/src/verification/verification_routes.dart`
- Modify: `server/test/verification/verification_routes_test.dart`

**Interfaces:**
- Consumes: Task 3's widened `decide()`; `AuthContext.can(String permission)` (auth/middleware.dart) — the route already has `authOf(request)`.
- Produces: `supervisorOverride:true` from a caller holding `verification_override` re-decides a case regardless of its current status (drops the `status='CRM_REVIEW'` CAS guard) but stays version-safe; a caller lacking the permission → 403; a malformed decision body → 400.

**Context:** `crm_supervisor` holds `verification_override` (`tokens.dart` `permissionsByRole`); `crm_verifier` does not. The route requires `verification_decide` (which `crm_supervisor` also holds). The permission check for override is conditional on the request field, so it lives in the handler, not a route-wide middleware. `CASE_CONFLICT`-style already-decided rows are how 5a tested closed cases (status `APPROVED`, a version ahead).

- [ ] **Step 1: Write the failing tests**

Add to `verification_routes_test.dart` (seed an ALREADY-DECIDED attendance — `status='APPROVED'`, `version=2` — as the 5a already-decided test does; mint BOTH a `crm_verifier` and a `crm_supervisor` token):

```dart
// A supervisor can re-decide a closed case; the override is recorded.
test('supervisor override re-decides a closed case', () async {
  // seed id2: status APPROVED, version 2
  final res = await decideAs(supervisorToken, id2, ifMatch: 2, body: {
    'outcome': 'REJECTED',
    'reason': 'Original approval was incorrect on review.',
    'supervisorOverride': true,
  });
  expect(res.statusCode, 200);
  final row = await attendanceRow(db, id2);
  expect(row['status'], 'REJECTED');
  expect(row['version'], 3);
  final decision = await latestDecision(db, id2);
  expect(decision['outcome'], 'REJECTED');
  expect(decision['supervisor_override'], isTrue);
});

// A plain verifier sending override -> 403 (not 422).
test('override without verification_override is 403', () async {
  final res = await decideAs(verifierToken, id2, ifMatch: 2, body: {
    'outcome': 'REJECTED', 'reason': 'x', 'supervisorOverride': true,
  });
  expect(res.statusCode, 403);
  expect(errorCode(res), 'FORBIDDEN');
  expect((await attendanceRow(db, id2))['status'], 'APPROVED'); // unchanged
});

// Override stays version-safe: a stale If-Match still 412s even for a supervisor.
test('supervisor override with a stale If-Match is 412', () async {
  final res = await decideAs(supervisorToken, id2, ifMatch: 1, body: {
    'outcome': 'REJECTED', 'reason': 'stale', 'supervisorOverride': true,
  });
  expect(res.statusCode, 412);
  expect((await attendanceRow(db, id2))['status'], 'APPROVED'); // unchanged
});

// Override requires a reason.
test('supervisor override requires a reason', () async {
  final res = await decideAs(supervisorToken, id2, ifMatch: 2, body: {
    'outcome': 'APPROVED', 'supervisorOverride': true,
  });
  expect(res.statusCode, 422);
  expect(errorCode(res), 'DECISION_REASON_REQUIRED');
});

// A non-JSON body -> 400, not 500.
test('a malformed decision body is 400', () async {
  final res = await rawDecide(verifierToken, id, ifMatch: 1, rawBody: 'not json');
  expect(res.statusCode, 400);
  expect(errorCode(res), 'BAD_REQUEST');
});
```

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart`
Expected: the new override/malformed cases FAIL (override → 422 today; malformed → 500 today).

- [ ] **Step 3: Add the two-mode CAS to `decide()`**

In `verification_repo.dart`: remove `supervisorOverride` from the `unsupportedOutcome` guard (Task 3 left it there); add `|| supervisorOverride` to `reasonRequired`; branch the CAS on `supervisorOverride`. Only the `WHERE` differs:

```dart
if (outcome == null) {
  return const VerificationDecisionResult(
    VerificationDecisionCode.unsupportedOutcome,
  );
}
// ... newStatus, statusForOutcome as in Task 3 ...
final reasonRequired = supervisorOverride ||
    outcome == VerificationOutcome.rejected ||
    outcome == VerificationOutcome.returnForRecapture ||
    outcome == VerificationOutcome.escalated;
// ... reason check ...

final whereOpenGuard = supervisorOverride ? '' : "  AND status = 'CRM_REVIEW' ";
final casResult = await tx.execute(
  Sql.named(
    'UPDATE attendance SET status = @status, version = version + 1, '
    '  escalated_at = @escAt, escalated_by = @escBy '
    'WHERE id = @id AND version = @ifMatch AND organization_id = @org '
    '$whereOpenGuard'
    'RETURNING version',
  ),
  parameters: { /* same as Task 3 */ },
);
```

The 0-rows re-check is unchanged (exists → `versionConflict`/412, gone → `notFound`/404). The decision-row INSERT already writes `supervisor_override = @override` from the `supervisorOverride` argument — no change needed there.

> The route enforces the `verification_override` permission (Step 4) BEFORE calling `decide()`, so the repo trusting the `supervisorOverride` flag here is safe: an unauthorized override never reaches this CAS.

- [ ] **Step 4: Add the 403 gate and the malformed-body guard in the route**

In `verification_routes.dart`, the decision handler:

```dart
final raw = await request.readAsString();
final Object? decoded;
try {
  decoded = jsonDecode(raw);
} on FormatException {
  throw ApiException(ApiErrorCode.badRequest,
      message: 'Request body must be a JSON object.');
}
if (decoded is! Map) {
  throw ApiException(ApiErrorCode.badRequest,
      message: 'Request body must be a JSON object.');
}
final body = decoded.cast<String, Object?>();
final supervisorOverride = (body['supervisorOverride'] as bool?) ?? false;
if (supervisorOverride && !auth.can('verification_override')) {
  throw ApiException(ApiErrorCode.forbidden,
      message: 'Supervisor override requires the verification_override permission.');
}
```

Then call `repo.decide(..., supervisorOverride: supervisorOverride, ...)`. Keep the `If-Match` 400 check ahead of body parsing (unchanged).

- [ ] **Step 5: Run the verification tests — must pass**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart`
Expected: all pass — override succeeds for a supervisor, 403 without the permission, 412 on a stale override, 422 without a reason, 400 on a malformed body, and every prior case (Task 3 + 5a) still green.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/verification/verification_repo.dart server/lib/src/verification/verification_routes.dart server/test/verification/verification_routes_test.dart
git commit -m "feat(server): supervisor override re-decides a closed case, version-safe

supervisorOverride:true from a crm_supervisor (verification_override) drops the
status='CRM_REVIEW' CAS guard so a decided case can be corrected, but keeps the
version guard so a stale If-Match still 412s. A caller lacking the permission ->
403. A malformed decision body -> 400 instead of the generic 500."
```

---

### Task 5: Case wire emits `status`; fold in the two deferred 5a test gaps

**Files:**
- Modify: `server/lib/src/verification/verification_repo.dart`
- Modify: `server/test/verification/verification_routes_test.dart`
- Modify: `server/test/media/media_routes_test.dart`

**Interfaces:**
- Produces: `GET /verification/cases/<id>` response gains a `status` field (the attendance's status wire literal, e.g. `CRM_REVIEW`/`APPROVED`). Consumed by the client in Task 6.

**Context:** `loadCase` (verification_repo.dart:98-154) does not select or emit `status`. The queue band-severity `ORDER BY` (repo `queue`) is untested for multi-band ordering; the signed media GET test (`media_routes_test.dart`) asserts bytes but not the `content-type` header. These two are the 5a-deferred gaps folded here.

- [ ] **Step 1: Write the failing tests**

In `verification_routes_test.dart`:

```dart
test('the case wire carries the attendance status', () async {
  // seed a CRM_REVIEW case (id) and an already-decided APPROVED case (id2)
  final open = await getCaseAs(verifierToken, id);
  expect(jsonDecode(await open.readAsString())['status'], 'CRM_REVIEW');
  final closed = await getCaseAs(supervisorToken, id2);
  expect(jsonDecode(await closed.readAsString())['status'], 'APPROVED');
});

test('the queue orders worst band first, then oldest', () async {
  // seed three CRM_REVIEW cases in one org with bands MEDIUM, NO_REFERENCE, LOW
  // (and, for two same-band rows, different captured_at) then:
  final items = await queueAs(verifierToken); // List of maps
  final bands = items.map((i) => i['band']).toList();
  expect(bands, ['NO_REFERENCE', 'LOW', 'MEDIUM'],
      reason: 'severity order: NO_REFERENCE < LOW < MEDIUM < HIGH');
});
```

In `media_routes_test.dart`, extend the existing signed-GET test (or add one) to assert the response content-type matches the stored value:

```dart
expect(ok.headers['content-type'], 'image/png',
    reason: 'the stored content_type must be served back, not defaulted');
```

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart test/media/media_routes_test.dart`
Expected: the `status`, queue-ordering, and content-type assertions FAIL (status absent; ordering possibly untested; content-type unasserted — the route already serves it correctly, so that assertion may pass immediately: if so, keep it as a regression pin and note it in the report).

- [ ] **Step 3: Emit `status` from `loadCase`**

In `verification_repo.dart` `loadCase`: add `a.status` to the SELECT column list, and add `'status': r['status'],` to the returned wire map (near `'version'`). No other change.

- [ ] **Step 4: Run the tests — must pass**

Run: `cd server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/verification/verification_routes_test.dart test/media/media_routes_test.dart`
Expected: all pass. If the media content-type assertion passed at Step 2 already (route was correct), it now stands as a regression pin.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/verification/verification_repo.dart server/test/verification/verification_routes_test.dart server/test/media/media_routes_test.dart
git commit -m "feat(server): case wire emits status; pin queue ordering + media content-type

loadCase returns the attendance status so the client stops hard-coding crmReview
(needed now that a supervisor can open a decided case). Folds in the two 5a
deferred test gaps: a multi-band queue-ordering assertion and a signed-media
content-type header assertion."
```

---

### Task 6: Client — parse case status, reason-when-required, supervisor-override control

**Files:**
- Modify: `lib/data/verification/verification_repository_impl.dart`
- Modify: `lib/features/crm_case/presentation/crm_case_screen.dart`
- Create: `test/data/verification/verification_repository_impl_test.dart` additions (extend the existing 5a test file)

**Interfaces:**
- Consumes: `AttendanceStatus.tryParseWire` (Task 1); the case wire `status` field (Task 5); `crm_case_controller.dart`'s `decide({outcome, reason, supervisorOverride})` (already accepts `supervisorOverride`, default false).
- Produces: no new server-facing interface.

**Context:** the `_case()` mapper (verification_repository_impl.dart:94-112) hard-codes `status: AttendanceStatus.crmReview`. The decision `_submit`/`_canSubmit` (crm_case_screen.dart:244-251) require a reason for ALL outcomes and never set `supervisorOverride`. Permission checks use `session.scope.can(Permission.verificationOverride)` — see `lib/core/auth/permission_gate.dart` and `Permission.verificationOverride` (`scope_claims.dart:36`). The Dio layer already maps 403 → `FailureKind.forbidden` and 412 → conflict (`dio_client.dart:70,73`) — no network change needed.

- [ ] **Step 1: Write the failing client tests**

Extend `test/data/verification/verification_repository_impl_test.dart` (recording `HttpClientAdapter` + bare Dio, as the 5a tests do):

```dart
test('getCase parses the wire status', () async {
  // stub a case response whose JSON includes "status": "APPROVED"
  final result = await repo.getCase('att-1');
  expect(result.asOk.status, AttendanceStatus.approved);
});

test('an unknown wire status falls back visibly, not crashing', () async {
  // stub "status": "WAT"
  final result = await repo.getCase('att-1');
  expect(result.asOk.status, AttendanceStatus.crmReview); // visible fallback
});

test('decide sends RETURN_FOR_RECAPTURE and the supervisorOverride flag', () async {
  await repo.decide(
    VerificationDecision(
      attendanceId: 'att-1', verifierId: 'u', outcome:
          VerificationOutcome.returnForRecapture, reason: 'r',
      supervisorOverride: true),
    expectedVersion: 2);
  expect(lastRequest.data['outcome'], 'RETURN_FOR_RECAPTURE');
  expect(lastRequest.data['supervisorOverride'], true);
});
```
(Match the existing file's stub/recording helpers and `asOk` accessor; do not invent a new harness.)

- [ ] **Step 2: Run — confirm failure**

Run: `flutter test test/data/verification/verification_repository_impl_test.dart`
Expected: the status-parse cases FAIL (mapper hard-codes `crmReview`).

- [ ] **Step 3: Parse the wire status**

In `verification_repository_impl.dart`, replace `status: AttendanceStatus.crmReview,` with `status: _status(j['status'] as String?),` and add the parser mirroring `_band`/`_refSource`:

```dart
AttendanceStatus _status(String? s) {
  final parsed = AttendanceStatus.tryParseWire(s ?? '');
  if (parsed == null) {
    debugPrint('VerificationRepositoryImpl: unrecognized status "$s"');
    return AttendanceStatus.crmReview; // visible fallback, never silent
  }
  return parsed;
}
```

- [ ] **Step 4: Reason-when-required and the supervisor-override control**

In `crm_case_screen.dart`'s `_DecisionPanelState`:
- Add `bool _override = false;`.
- Make the reason mandatory only when required: change `_canSubmit` so reason is required iff `_override || _outcome ∈ {rejected, returnForRecapture, escalated}`; approve without override may submit with an empty reason:

```dart
bool get _reasonRequired =>
    _override ||
    _outcome == VerificationOutcome.rejected ||
    _outcome == VerificationOutcome.returnForRecapture ||
    _outcome == VerificationOutcome.escalated;

bool get _canSubmit =>
    _outcome != null &&
    (!_reasonRequired || _reason.text.trim().isNotEmpty) &&
    !_submitting;
```
- Update the `BmdField.multiline` `required:` to `_reasonRequired` and its helper copy accordingly.
- Show a supervisor-override switch ONLY when the signed-in user holds `verification_override`. Read it from the session scope via the existing pattern (e.g. `ref.watch(authStateProvider)` → `AuthSignedIn(:final session) => session.scope.can(Permission.verificationOverride)`, else false); gate a `SwitchListTile`/`Semantics(identifier: 'crm_supervisor_override')` on it, binding `_override`. When on, render a short note that it re-opens a decided case.
- Pass it through: `.decide(outcome: _outcome!, reason: _reason.text.trim(), supervisorOverride: _override)`.

- [ ] **Step 5: Run the client tests + full suite**

Run: `flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs`, then `flutter test test/data/verification/verification_repository_impl_test.dart`, then `flutter test`.
Expected: new tests pass; full suite green (count up only by this task's new tests). Investigate any crm_case widget test that assumed reason-always-required or a fixed status.

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format --set-exit-if-changed lib test && flutter analyze --fatal-infos
git add lib/data/verification lib/features/crm_case test/data/verification
git commit -m "feat(client): parse case status; reason-when-required; supervisor override

The case status is parsed from the wire (unknown -> visible fallback) instead of
hard-coded. Reason is required only for reject/return/escalate or an override; a
plain approve needs none. A supervisor-override switch appears only for a user
holding verification_override and re-opens a decided case."
```

---

### Task 7: Mock parity

**Files:**
- Modify: `tool/mock_server/bin/server.dart`
- Modify: `server/test/contract/parity_test.dart`

**Context:** the mock decision handler (`tool/mock_server/bin/server.dart:242-263`) is version-aware (412 on stale `If-Match`) and echoes `{'status': outcome}`. It does not model the four-outcome→status mapping, the reason-422, or the case wire's `status` field. It does NOT enforce RBAC (no per-request permission model), so the override-403 stays a real-service-only assertion (as 5a documented its `sensitive_media_view` parity limitation).

- [ ] **Step 1: Align the mock decision handler**

In the mock's `/verification/cases/<id>/decision` handler, after the existing `If-Match` → 412 check: map the outcome to a status (`APPROVED→APPROVED`, `REJECTED→REJECTED`, `RETURN_FOR_RECAPTURE→RETURNED`, `ESCALATED→CRM_REVIEW`, unknown→422 `VERIFICATION_OUTCOME_UNSUPPORTED`); return 422 `DECISION_REASON_REQUIRED` when the outcome is reject/return/escalate (or `supervisorOverride` is true) and the `reason` is blank; otherwise return `{'status': mappedStatus}`. Also ensure the mock's `verificationCase(id, …)` fixture includes a `status` key (e.g. `'CRM_REVIEW'`, and `'APPROVED'` for the `CASE_CONFLICT` fixture) so it matches the real wire (Task 5).

- [ ] **Step 2: Pin parity**

In `server/test/contract/parity_test.dart`, add a case asserting mock and real agree on: a `RETURN_FOR_RECAPTURE` decision returns `{status: 'RETURNED'}` on both; a reject/return/escalate with a blank reason returns 422 `DECISION_REASON_REQUIRED` on both; and the case wire carries a `status` that parses via `AttendanceStatus.tryParseWire` non-null on both. Seed the real side as the verification route tests do (a `crm_verifier` token + a `CRM_REVIEW` attendance + media). Do not weaken existing parity cases. (The override-403 is real-service-only — note it in a comment, as 5a did for `sensitive_media_view`.)

- [ ] **Step 3: Run parity, format, analyze, commit**

```bash
cd tool/mock_server && dart pub get && dart analyze && dart format --set-exit-if-changed .
cd ../../server && $env:DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign'; dart test test/contract/parity_test.dart
cd .. && git add tool/mock_server/bin/server.dart server/test/contract/parity_test.dart
git commit -m "chore(mock): decision handler honours the full outcome set + reason-422

Mock maps RETURN_FOR_RECAPTURE->RETURNED and ESCALATED->CRM_REVIEW, 422s a blank
reason where one is required, and the case fixture carries a status field.
Parity pins these; the override-403 stays a real-service RBAC assertion."
```

---

### Task 8: E2E — recapture + supervisor override against the real service

**Files:**
- Modify: `server/lib/src/seed/seed_routes.dart` (only if a `crm_supervisor` login user is not already seeded)
- Create: `.maestro/flows/crm_case_recapture.yaml`
- Create: `.maestro/flows/crm_case_override.yaml`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the real endpoints (Tasks 3–5), the seeded `CASE_E2E` (CRM_REVIEW) and `CASE_CONFLICT` (APPROVED, version 2) fixtures, the `crm_verifier`/`crm_supervisor` seed users, the dev launcher's `dev_open_crm_case`/`dev_open_crm_case_conflict` buttons.

**Context:** 5a seeds `CASE_E2E` (CRM_REVIEW, v1) and `CASE_CONFLICT` (APPROVED, v2) and the crm flows sign in for real (login prelude) — see `.maestro/flows/crm_case_decision.yaml` and `crm_case_conflict.yaml`. `POST /__test__/reset` reseeds both every flow. The dev launcher exposes `dev_open_crm_case` (→ CASE_E2E) and `dev_open_crm_case_conflict` (→ CASE_CONFLICT). The recapture flow reuses CASE_E2E (fresh CRM_REVIEW each reset); the override flow reuses CASE_CONFLICT (APPROVED v2) logged in as `crm_supervisor`. Confirm the seed roles include `crm_supervisor` with password `Test1234!`; if only `crm_verifier` is seeded, add a `crm_supervisor` user in `seed_routes.dart` (same helper, role `crm_supervisor`).

- [ ] **Step 1: Ensure a `crm_supervisor` login user is seeded**

Check `server/lib/src/seed/seed_routes.dart`'s baseline seed (the role list that seeds one user per role). If `crm_supervisor` is absent, add it (username `crm_supervisor`, password `Test1234!`, role `crm_supervisor`) alongside `crm_verifier`. Extend the seed test (or add one) asserting `POST /__test__/reset` then a login as `crm_supervisor` succeeds and the token carries `verification_override`. If it is already seeded, skip the code change and note it in the report.

- [ ] **Step 2: Recapture flow**

Create `.maestro/flows/crm_case_recapture.yaml`, modelled on `crm_case_decision.yaml`: real-auth login prelude as `crm_verifier`/`Test1234!` → `dev_launcher` → `dev_open_crm_case` (CASE_E2E, CRM_REVIEW) → select `crm_outcome_returnForRecapture` → fill `crm_reason` → `crm_submit` → assert the success snackbar (`Decision recorded`) / navigation, matching how `crm_case_decision.yaml` asserts a successful approve. Wrap merged-node selectors in `.*…*` per the 2a/2b/3a/4a convention if needed.

- [ ] **Step 3: Supervisor override flow**

Create `.maestro/flows/crm_case_override.yaml`: real-auth login prelude as `crm_supervisor`/`Test1234!` → `dev_launcher` → `dev_open_crm_case_conflict` (CASE_CONFLICT, APPROVED v2) → toggle `crm_supervisor_override` (visible because the supervisor holds `verification_override`) → select `crm_outcome_rejected` → fill `crm_reason` → `crm_submit` → assert the success snackbar. (The client fetches version 2 and sends `If-Match: 2`; the override CAS matches on version, drops the status guard, and returns 200.)

- [ ] **Step 4: Add both flows to the `crm` CI matrix**

In `.github/workflows/ci.yml`, add `.maestro/flows/crm_case_recapture.yaml` and `.maestro/flows/crm_case_override.yaml` to the `crm` matrix entry's flow list (the entry that already runs `crm_case_decision.yaml` + `crm_case_conflict.yaml`, `useMock: '0'`, `E2E_REAL_AUTH=true`). No `ROLE` change is needed — real-auth flows log in explicitly via their prelude.

- [ ] **Step 5: Local validation (no emulator)**

Bring up the real server (Postgres native; a JWT secret ≥32 chars; `ENABLE_TEST_SEEDING=true` locally ONLY — never commit it enabled), `POST /__test__/reset`, and curl: log in as `crm_verifier`, `POST /verification/cases/CASE_E2E/decision` with `If-Match: 1` + `{outcome: RETURN_FOR_RECAPTURE, reason: …}` → 200 `{status: RETURNED}`; log in as `crm_supervisor`, `POST /verification/cases/CASE_CONFLICT/decision` with `If-Match: 2` + `{outcome: REJECTED, reason: …, supervisorOverride: true}` → 200 `{status: REJECTED}`; the same as `crm_verifier` → 403. Record the transcript in the report. (If a live server is impractical on Windows, drive these as the seed/route test instead and note it.)

- [ ] **Step 6: Commit**

```bash
git add server/lib/src/seed/seed_routes.dart .maestro/flows/crm_case_recapture.yaml .maestro/flows/crm_case_override.yaml .github/workflows/ci.yml
# include any seed test file you added
git commit -m "feat(e2e): crm recapture + supervisor override against the real service

crm_case_recapture returns CASE_E2E for recapture as crm_verifier;
crm_case_override re-decides the already-APPROVED CASE_CONFLICT as crm_supervisor
via supervisorOverride. Both run in the crm matrix on the real service."
```

---

## Self-Review

**1. Spec coverage.** Every 5b decision maps to a task:
- 5b.D1 (full outcomes + status side-effects) → Task 3 (return/escalate) + Task 4 (override completes the endpoint).
- 5b.D2 (reason required for reject/return/escalate/override) → Task 3 (reject/return/escalate) + Task 4 (override).
- 5b.D3 (supervisor override, 403 for non-supervisor) → Task 4.
- 5b.D4 (two-mode CAS) → Task 4 (built on Task 3's CAS).
- 5b.D5 (case wire `status`; `AttendanceStatus` → contracts) → Task 1 (contracts) + Task 5 (server emits) + Task 6 (client parses).
- 5b.D6 (malformed body → 400) → Task 4.
- 5b.D7 (migration 009) → Task 2.
- 5b.D8 (RBAC + org scope) → Task 4 (override gate); org scope preserved in every CAS (Tasks 3–4).
- Deferred 5a test gaps (multi-band ordering, media content-type) → Task 5.
- Mock parity → Task 7; e2e → Task 8.
- Out-of-scope (5c queue/assign, nid_reveal, real ML, media hardening, field re-capture loop) → not implemented, named in the spec.

**2. Placeholder scan.** Each code step carries concrete SQL/Dart and exact wire values; tests carry real assertions. The client test helpers (`asOk`, recording adapter, `lastRequest`) and the server test helpers (`decideAs`, `attendanceRow`, `latestDecision`, `errorCode`, `getCaseAs`, `queueAs`, `rawDecide`) are named to match the existing 5a test files — the implementer reuses those files' equivalents rather than inventing new harnesses; noted at each first use.

**3. Type consistency.** `AttendanceStatus.wireValue`/`tryParseWire` (Task 1) are parsed by the client (Task 6) and emitted as `status` by the server (Task 5). `VerificationOutcome` wire values (`APPROVED`/`REJECTED`/`RETURN_FOR_RECAPTURE`/`ESCALATED`) are stored on the decision row (Tasks 3–4), sent by the client (Task 6), and honoured by the mock (Task 7). `VerificationDecisionResult.finalStatus` carries the attendance status literal; `verification_decisions.outcome` carries the outcome wire — kept distinct throughout. The two-mode CAS (`whereOpenGuard`) is introduced in Task 3's single-mode form and generalised in Task 4; the escalation stamp params (`@escAt`/`@escBy`) are identical across both.
