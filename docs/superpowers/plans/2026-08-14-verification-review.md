# CRM Verification Review Round-Trip (sub-project 5a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `GET /verification/queue`, `GET /verification/cases/<id>`, and `POST /verification/cases/<id>/decision` on the real `campaign_service`, plus a deterministic machine-check adapter that runs inside 4a's attendance confirm, so the client's `crm_case` flow (`crm_case_decision` + `crm_case_conflict`) runs green against the real service.

**Architecture:** A pure `MachineCheck` adapter (deterministic stub) runs in the confirm transaction, storing a `MachineResult` and moving the attendance to `CRM_REVIEW`. A verification repo serves an org-scoped, band-then-age-ordered queue; a case read that mints short-lived HMAC signed READ URLs for the evidence (reusing 4a's signed-URL model via a new bearer-less `GET /media/<id>`) and writes an audit-on-view row; and a decision endpoint that enforces optimistic locking via `If-Match` → `412`, transitioning approve/reject in one transaction. The `MatchBand`/`ReferenceSource`/`VerificationOutcome` wire enums move to `campaign_contracts`.

**Tech Stack:** Dart 3.12, `shelf`/`shelf_router`, `postgres` 3.5.12 (hand-written SQL, no ORM), `cryptography` (HMAC via 4a's `signed_url`), `campaign_contracts`; Flutter/Riverpod client; Maestro e2e.

**Spec:** `docs/superpowers/specs/2026-08-14-verification-review-design.md`. Decisions **5a.D1**–**5a.D6**.

**Refinement vs spec (grounded in the client code):** the client hard-codes `AttendanceStatus.crmReview` for cases and never parses attendance status on the verification wire, so — per the codebase's "move an enum only when its wire is consumed" discipline — this plan moves **`MatchBand`, `ReferenceSource`, `VerificationOutcome`** (the genuinely wire-consumed enums), NOT `AttendanceStatus`. The server uses SCREAMING_SNAKE status *literals* (`'CRM_REVIEW'`, `'APPROVED'`, `'REJECTED'`) for the `attendance.status` column; nothing on the client parses them.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **SDK floor is exactly `sdk: ">=3.12.0 <4.0.0"`** in every `pubspec.yaml`.
- **`shelf`/`shelf_router` only. No ORM. No code generation** in `server/` or `packages/campaign_contracts`.
- **Wire naming is `SCREAMING_SNAKE`** for enum values: `MatchBand` → `HIGH/MEDIUM/LOW/NO_REFERENCE`; `ReferenceSource` → `VERIFIED_PROFILE_PHOTO/AUTHORIZED_NID_PHOTO/APPROVED_BASELINE_PHOTO/UNAVAILABLE`; `VerificationOutcome` → `APPROVED/REJECTED/RETURN_FOR_RECAPTURE/ESCALATED`. The `attendance.status` column uses `'CRM_REVIEW'/'APPROVED'/'REJECTED'`. Field names stay camelCase.
- **Unknown enum values never default** — `tryParseWire` returns null; the client surfaces a visible fallback, never a silent one.
- **Out-of-scope resources return `404`, never `403`** (**D7**). A case outside the caller's org is indistinguishable from missing.
- **Optimistic lock: a stale `If-Match` returns `412 PRECONDITION_FAILED`** (5a.D3) — the RFC code for a failed conditional header. The client maps `412 → conflict`.
- **`postgres` trap:** inside `Db.tx`, every statement goes through the `TxSession`; read every column via `row(...)`.
- **Timestamps:** UTC ISO-8601 on the wire; `timestamptz` in Postgres. `age` is emitted as `ageSeconds` (int), matching the client's `Duration(seconds:)` parse.
- **The claim vocabulary is fixed.** `verification_decide` gates all three endpoints; `GET /verification/cases/<id>` additionally requires `sensitive_media_view`. `crm_verifier` holds both.
- **Raw carpenter id/nid never on the wire (2a.D2):** the case emits `carpenterIdMasked` (the carpenter's `display_code`).
- **Server tests run against** `DATABASE_URL=postgres://campaign:campaign@localhost:5432/campaign` (native PG 16+). On this Windows dev box, `dart test` with no args crashes ~test #145 (a branch-independent `frontend_server` bug) — run specific files/dirs, or use PowerShell `dart test`, for the full suite; CI (ubuntu) is unaffected.

---

## File Structure

```
packages/campaign_contracts/
  lib/src/match_band.dart              NEW
  lib/src/reference_source.dart        NEW
  lib/src/verification_outcome.dart    NEW
  lib/src/error_codes.dart             MOD  + preconditionFailed, verificationOutcomeUnsupported
  lib/campaign_contracts.dart          MOD  export the three enums

server/
  lib/src/infra/error_envelope.dart    MOD  preconditionFailed->412, verificationOutcomeUnsupported->422
  lib/src/db/migrations/embedded.dart  MOD  + '008_verification'
  lib/src/verification/machine_check.dart NEW  MachineCheck interface + deterministic stub
  lib/src/attendance/attendance_repo.dart MOD  confirm runs MachineCheck -> CRM_REVIEW
  lib/src/media/signed_url.dart        MOD  + signReadUrl (reuse verifyUploadSignature)
  lib/src/media/media_routes.dart      MOD  + bearer-less GET /media/<id>?exp&sig
  lib/src/verification/verification_repo.dart   NEW  queue / case / decision
  lib/src/verification/verification_routes.dart NEW  the three endpoints
  lib/src/app.dart                     MOD  mount the verification leg
  lib/src/seed/seed_routes.dart        MOD  seed CASE_E2E + CASE_CONFLICT
  test/...                             NEW/MOD

lib/ (Flutter app)
  domain/verification/verification.dart         MOD  re-export the three enums from contracts
  data/verification/verification_repository_impl.dart MOD tryParseWire + outcome.wireValue
  core/network/dio_client.dart                  MOD  mapDioError: 412 -> conflict
  test/...                                       NEW/MOD

tool/mock_server/bin/server.dart       MOD  verification wire SCREAMING_SNAKE + 412
server/test/contract/parity_test.dart  MOD  pin the three shapes + 412

.maestro/flows/crm_case_decision.yaml  MOD  real-auth prelude
.maestro/flows/crm_case_conflict.yaml  MOD  real-auth prelude
.github/workflows/ci.yml               MOD  crm config -> useMock '0'
```

---

### Task 1: Contracts — the three verification enums + error codes

**Files:**
- Create: `packages/campaign_contracts/lib/src/match_band.dart`, `reference_source.dart`, `verification_outcome.dart`
- Modify: `packages/campaign_contracts/lib/campaign_contracts.dart`, `lib/src/error_codes.dart`
- Modify: `server/lib/src/infra/error_envelope.dart`
- Create/extend: contract tests

**Interfaces:**
- Produces: `enum MatchBand { high, medium, low, noReference }` (wire `HIGH/MEDIUM/LOW/NO_REFERENCE`), `enum ReferenceSource { verifiedProfilePhoto, authorizedNidPhoto, approvedBaselinePhoto, unavailable }` (wire `VERIFIED_PROFILE_PHOTO/AUTHORIZED_NID_PHOTO/APPROVED_BASELINE_PHOTO/UNAVAILABLE`), `enum VerificationOutcome { approved, rejected, returnForRecapture, escalated }` (wire `APPROVED/REJECTED/RETURN_FOR_RECAPTURE/ESCALATED`), each with `String get wireValue` + `static X? tryParseWire(String)`; `ApiErrorCode.preconditionFailed` (`PRECONDITION_FAILED`), `.verificationOutcomeUnsupported` (`VERIFICATION_OUTCOME_UNSUPPORTED`).

**Why the envelope is here:** adding enum members to `ApiErrorCode` breaks `error_envelope`'s exhaustive `status` switch; ship the two arms in the same task.

- [ ] **Step 1: Write the failing enum test**

`packages/campaign_contracts/test/verification_enums_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('MatchBand wire values are SCREAMING_SNAKE and round-trip', () {
    expect(MatchBand.noReference.wireValue, 'NO_REFERENCE');
    for (final b in MatchBand.values) {
      expect(b.wireValue, matches(RegExp(r'^[A-Z][A-Z_]*$')));
      expect(MatchBand.tryParseWire(b.wireValue), b);
    }
    expect(MatchBand.tryParseWire('high'), isNull, reason: 'camelCase is not the wire value');
    expect(MatchBand.tryParseWire('NOPE'), isNull);
  });

  test('ReferenceSource round-trips SCREAMING_SNAKE', () {
    expect(ReferenceSource.verifiedProfilePhoto.wireValue, 'VERIFIED_PROFILE_PHOTO');
    for (final r in ReferenceSource.values) {
      expect(ReferenceSource.tryParseWire(r.wireValue), r);
    }
    expect(ReferenceSource.tryParseWire('unavailable'), isNull);
  });

  test('VerificationOutcome round-trips SCREAMING_SNAKE', () {
    expect(VerificationOutcome.returnForRecapture.wireValue, 'RETURN_FOR_RECAPTURE');
    for (final o in VerificationOutcome.values) {
      expect(VerificationOutcome.tryParseWire(o.wireValue), o);
    }
    expect(VerificationOutcome.tryParseWire('approved'), isNull, reason: 'camelCase name is not the wire value');
  });
}
```

- [ ] **Step 2: Run it — confirm failure**

Run: `cd packages/campaign_contracts && dart pub get && dart test test/verification_enums_test.dart`
Expected: compile failure — the enums are not defined.

- [ ] **Step 3: Implement the three enums**

Each file mirrors `session_status.dart`. Example `match_band.dart`:

```dart
/// The machine's advisory match-confidence band (sub-project 5). Advisory only —
/// the human sees the band + reasons, never a raw score.
enum MatchBand {
  high,
  medium,
  low,
  noReference;

  String get wireValue => switch (this) {
    high => 'HIGH',
    medium => 'MEDIUM',
    low => 'LOW',
    noReference => 'NO_REFERENCE',
  };

  static MatchBand? tryParseWire(String wire) {
    for (final b in values) {
      if (b.wireValue == wire) return b;
    }
    return null;
  }
}
```

`reference_source.dart` — members `verifiedProfilePhoto→VERIFIED_PROFILE_PHOTO`, `authorizedNidPhoto→AUTHORIZED_NID_PHOTO`, `approvedBaselinePhoto→APPROVED_BASELINE_PHOTO`, `unavailable→UNAVAILABLE`. `verification_outcome.dart` — `approved→APPROVED`, `rejected→REJECTED`, `returnForRecapture→RETURN_FOR_RECAPTURE`, `escalated→ESCALATED`. Same `wireValue`/`tryParseWire` shape.

- [ ] **Step 4: Add the error codes + exports**

In `error_codes.dart`, append after the last member (rename the trailing `;`) and add the wire arms:

```dart
  // attendance & evidence (sub-project 4a)
  attendanceEvidenceMissing,
  // verification (sub-project 5a)
  preconditionFailed,
  verificationOutcomeUnsupported;
```
```dart
    attendanceEvidenceMissing => 'ATTENDANCE_EVIDENCE_MISSING',
    preconditionFailed => 'PRECONDITION_FAILED',
    verificationOutcomeUnsupported => 'VERIFICATION_OUTCOME_UNSUPPORTED',
```

In `campaign_contracts.dart`, add the three exports (alphabetical with the others):

```dart
export 'src/match_band.dart';
export 'src/reference_source.dart';
export 'src/verification_outcome.dart';
```

- [ ] **Step 5: Map the codes in the server envelope**

In `server/lib/src/infra/error_envelope.dart`, add to the `int get status => switch (code)` block:

```dart
    ApiErrorCode.preconditionFailed => 412,
    ApiErrorCode.verificationOutcomeUnsupported => 422,
```

- [ ] **Step 6: Run tests + server analyze — must pass**

Run: `cd packages/campaign_contracts && dart test` (incl. the generic `error_codes_test` round-trip), then `cd ../../server && dart analyze --fatal-infos` (must be clean — the switch is exhaustive again).

- [ ] **Step 7: Format, commit**

```bash
cd packages/campaign_contracts && dart format --set-exit-if-changed . && dart analyze
cd ../../server && dart format --set-exit-if-changed lib/src/infra/error_envelope.dart
cd .. && git add packages/campaign_contracts server/lib/src/infra/error_envelope.dart
git commit -m "feat(contracts): MatchBand/ReferenceSource/VerificationOutcome + 412/422 codes

The verification wire enums the CRM client consumes move to campaign_contracts
with SCREAMING_SNAKE wireValue + tryParseWire (AttendanceStatus stays client-side
— nothing parses it on the verification wire). PRECONDITION_FAILED (412, stale
If-Match) and VERIFICATION_OUTCOME_UNSUPPORTED (422) added and mapped in the
server envelope."
```

---

### Task 2: Migration `008_verification`

**Files:**
- Modify: `server/lib/src/db/migrations/embedded.dart`
- Modify: `server/test/db/migrator_test.dart`

**Interfaces:**
- Produces: `attendance.version`, `attendance.assignee_id`, `attendance.machine_band`, `attendance.machine_reference_src`, `attendance.machine_reasons`; table `verification_decisions`; index `attendance_status_idx`.

- [ ] **Step 1: Write the failing migrator test**

Add to `server/test/db/migrator_test.dart`:

```dart
  test('008 adds the verification columns and decisions table', () async {
    await Migrator(db).applyPending();
    final cols = await db.execute(
      "SELECT column_name FROM information_schema.columns WHERE table_name = 'attendance'",
    );
    final names = cols.map((r) => row(r)['column_name']! as String).toSet();
    expect(names, containsAll(<String>[
      'version', 'assignee_id', 'machine_band', 'machine_reference_src', 'machine_reasons',
    ]));
    final tables = await db.execute(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
    );
    expect(tables.map((r) => row(r)['tablename']), contains('verification_decisions'));
  });
```

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/db/migrator_test.dart -n '008 adds'`
Expected: FAIL.

- [ ] **Step 3: Add the migration**

In `embedded.dart`, add `'008_verification': _verification,` after `007_attendance`, and:

```dart
const String _verification = r'''
ALTER TABLE attendance ADD COLUMN version               INTEGER NOT NULL DEFAULT 1;
ALTER TABLE attendance ADD COLUMN assignee_id           TEXT REFERENCES staff_users(id);
ALTER TABLE attendance ADD COLUMN machine_band          TEXT;   -- MatchBand wire; null before the machine check
ALTER TABLE attendance ADD COLUMN machine_reference_src TEXT;   -- ReferenceSource wire
ALTER TABLE attendance ADD COLUMN machine_reasons       JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX attendance_status_idx ON attendance(organization_id, status);

CREATE TABLE verification_decisions (
  id                   TEXT PRIMARY KEY,
  attendance_id        TEXT        NOT NULL REFERENCES attendance(id) ON DELETE CASCADE,
  verifier_id          TEXT        NOT NULL REFERENCES staff_users(id),
  outcome              TEXT        NOT NULL,
  reason               TEXT,
  supervisor_override  BOOLEAN     NOT NULL DEFAULT FALSE,
  version_at_decision  INTEGER     NOT NULL,
  correlation_id       TEXT,
  decided_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX verification_decisions_attendance_idx ON verification_decisions(attendance_id);
''';
```

- [ ] **Step 4: Run migrator tests — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/db/migrator_test.dart`
Expected: all pass.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/db/migrations/embedded.dart server/test/db/migrator_test.dart
git commit -m "feat(server): migration 008 — attendance version/machine columns + verification_decisions"
```

---

### Task 3: Machine-check adapter + confirm extension

**Files:**
- Create: `server/lib/src/verification/machine_check.dart`
- Modify: `server/lib/src/attendance/attendance_repo.dart`
- Create: `server/test/verification/machine_check_test.dart`
- Modify: `server/test/attendance/attendance_routes_test.dart`

**Interfaces:**
- Consumes: `MatchBand`, `ReferenceSource` (Task 1); migration 008 (Task 2).
- Produces:
  - `class MachineResultData { final MatchBand band; final ReferenceSource referenceSource; final List<String> reasons; }`
  - `abstract interface class MachineCheck { MachineResultData check({required bool hasReference}); }`
  - `class StubMachineCheck implements MachineCheck` — deterministic.
  - `AttendanceRepo.confirm` now stores the machine result and sets `status = 'CRM_REVIEW'`.

- [ ] **Step 1: Write the failing adapter test**

`server/test/verification/machine_check_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/verification/machine_check.dart';
import 'package:test/test.dart';

void main() {
  const check = StubMachineCheck();

  test('with a reference photo -> MEDIUM, baseline source', () {
    final r = check.check(hasReference: true);
    expect(r.band, MatchBand.medium);
    expect(r.referenceSource, ReferenceSource.approvedBaselinePhoto);
    expect(r.reasons, isNotEmpty);
  });

  test('without a reference photo -> NO_REFERENCE, unavailable', () {
    final r = check.check(hasReference: false);
    expect(r.band, MatchBand.noReference);
    expect(r.referenceSource, ReferenceSource.unavailable);
  });
}
```

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && dart test test/verification/machine_check_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement the adapter**

`server/lib/src/verification/machine_check.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';

/// The machine verdict a captured attendance carries into CRM review — advisory
/// only. Real 1:1 face-match / PAD is ML that swaps in behind [MachineCheck]
/// later (sub-project 5a.D2); this slice ships a deterministic stub.
class MachineResultData {
  const MachineResultData({
    required this.band,
    required this.referenceSource,
    required this.reasons,
  });
  final MatchBand band;
  final ReferenceSource referenceSource;
  final List<String> reasons;
}

abstract interface class MachineCheck {
  MachineResultData check({required bool hasReference});
}

/// Deterministic stub: routes everything to human review. A carpenter with a
/// reference photo gets MEDIUM (inconclusive → review); none gets NO_REFERENCE.
/// Nothing auto-approves in 5a.
class StubMachineCheck implements MachineCheck {
  const StubMachineCheck();

  @override
  MachineResultData check({required bool hasReference}) => hasReference
      ? const MachineResultData(
          band: MatchBand.medium,
          referenceSource: ReferenceSource.approvedBaselinePhoto,
          reasons: ['Face comparison inconclusive — manual review required.'],
        )
      : const MachineResultData(
          band: MatchBand.noReference,
          referenceSource: ReferenceSource.unavailable,
          reasons: ['No reference photo on file for this carpenter.'],
        );
}
```

- [ ] **Step 4: Wire it into the confirm**

In `server/lib/src/attendance/attendance_repo.dart`:
1. Add `import 'package:campaign_contracts/campaign_contracts.dart';`, `import '../verification/machine_check.dart';`, and `import 'dart:convert';` (for the reasons JSON).
2. The confirm already checks the carpenter exists (`SELECT 1 FROM carpenters WHERE id=@c AND organization_id=@org`). Change that read to also fetch the reference: `SELECT thumbnail_url FROM carpenters WHERE id=@c AND organization_id=@org` — empty → `carpenterNotFound` (unchanged); else read `thumbnail_url` and compute `hasReference = thumbnailUrl != null`.
3. Run `const StubMachineCheck().check(hasReference: hasReference)` (inject a `MachineCheck` field defaulting to `const StubMachineCheck()` so a test can override).
4. Change the attendance INSERT: set `status = 'CRM_REVIEW'` (not `'MATCH_PROCESSING'`) and populate `machine_band`, `machine_reference_src`, `machine_reasons` from the result:

```dart
'INSERT INTO attendance '
'(id, organization_id, campaign_id, session_id, carpenter_id, media_ref, '
' status, captured_by, captured_at, machine_band, machine_reference_src, machine_reasons) '
"VALUES (@id, @org, @camp, @s, @c, @id, 'CRM_REVIEW', @by, @at, @mb, @mrs, @mr)",
```
with params `'mb': result.band.wireValue, 'mrs': result.referenceSource.wireValue, 'mr': jsonEncode(result.reasons)`.
5. Change the returned status literal from `'MATCH_PROCESSING'` to `'CRM_REVIEW'`.

- [ ] **Step 5: Update the confirm tests**

In `server/test/attendance/attendance_routes_test.dart`: the happy-path test now expects `status: 'CRM_REVIEW'` (and the persisted attendance row's status/`machine_band`). Keep the idempotent-replay, cross-org 404, and evidence-missing 422 cases green. Seed the carpenter with a `thumbnail_url` (so `machine_band = 'MEDIUM'`) in the happy path; add a case asserting a carpenter WITHOUT a thumbnail lands `machine_band = 'NO_REFERENCE'`.

> `seedCarpenter` takes `thumbnailUrl`? Check `server/test/support/seed_fixtures.dart` — if the helper doesn't set `thumbnail_url`, pass it (or add the param). Reference the 2a carpenters schema (`thumbnail_url TEXT`).

- [ ] **Step 6: Run the adapter + confirm tests — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/verification/machine_check_test.dart test/attendance/attendance_routes_test.dart`
Expected: all pass (confirm now lands `CRM_REVIEW` with a machine band).

- [ ] **Step 7: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/verification/machine_check.dart server/lib/src/attendance test/attendance 2>/dev/null; git add server/lib/src/attendance/attendance_repo.dart server/test/attendance/attendance_routes_test.dart server/lib/src/verification/machine_check.dart server/test/verification/machine_check_test.dart
git commit -m "feat(server): machine-check adapter runs in the confirm -> CRM_REVIEW

A deterministic StubMachineCheck (real ML swaps in behind the interface) runs in
the attendance confirm transaction: it produces a MachineResult (MEDIUM when the
carpenter has a reference photo, else NO_REFERENCE) and lands the attendance in
CRM_REVIEW, so a real capture flows straight into the verification queue."
```

---

### Task 4: Signed read URL + bearer-less media GET

**Files:**
- Modify: `server/lib/src/media/signed_url.dart`
- Modify: `server/lib/src/media/media_routes.dart`
- Modify: `server/test/media/media_routes_test.dart`

**Interfaces:**
- Consumes: `verifyUploadSignature` (4a, path-agnostic — verifies `id.exp`); `MediaRepo.get` (4a).
- Produces: `Future<String> signReadUrl({required String baseUrl, required String id, required String signingKey, required DateTime now, Duration ttl})` → `<base>/media/<id>?exp&sig`; `GET /media/<id>?exp&sig` serving the bytes.

- [ ] **Step 1: Write the failing media-read test**

Add to `server/test/media/media_routes_test.dart` a case: presign+upload bytes for id `read-1` (or seed a `media_objects` row directly), then a bearer-less `GET` to a URL built by `signReadUrl` returns 200 with the bytes and the stored content-type; a tampered/expired signature → 403; an unknown id with a valid signature → 404.

```dart
  test('signed GET /media/<id> serves the bytes; bad signature 403; unknown 404', () async {
    await db.execute(
      "INSERT INTO media_objects (id, content_type, bytes) VALUES ('read-1','image/png',@b)",
      params: {'b': Uint8List.fromList(const [9, 8, 7])},
    );
    final url = await signReadUrl(
      baseUrl: 'http://10.0.2.2:8080', id: 'read-1',
      signingKey: config.uploadSigningKey, now: DateTime.now());
    final ok = await handler(Request('GET', Uri.parse(url)));
    expect(ok.statusCode, 200);
    expect((await ok.read().expand((x) => x).toList()), const [9, 8, 7]);

    final signed = Uri.parse(url);
    final bad = signed.replace(queryParameters: {...signed.queryParameters, 'sig': 'forged'});
    expect((await handler(Request('GET', bad))).statusCode, 403);

    final missing = Uri.parse(await signReadUrl(
      baseUrl: 'http://h', id: 'nope', signingKey: config.uploadSigningKey, now: DateTime.now()));
    expect((await handler(Request('GET', missing))).statusCode, 404);
  });
```

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/media/media_routes_test.dart -n 'signed GET'`
Expected: FAIL — `signReadUrl` / the read route missing.

- [ ] **Step 3: Add `signReadUrl`**

In `signed_url.dart`, add (verification reuses the existing `verifyUploadSignature` — the signature is over `id.exp`, path-agnostic):

```dart
/// Signs a short-lived READ URL for a media object: `<base>/media/<id>?exp&sig`.
/// The signature is the same `id.exp` HMAC as the upload URL (verified by
/// [verifyUploadSignature]); only the path differs.
Future<String> signReadUrl({
  required String baseUrl,
  required String id,
  required String signingKey,
  required DateTime now,
  Duration ttl = const Duration(minutes: 15),
}) async {
  final exp = now.add(ttl).millisecondsSinceEpoch ~/ 1000;
  final sig = await _sign(id, exp, signingKey); // reuse the private _sign helper
  return '$baseUrl/media/$id?exp=$exp&sig=${Uri.encodeQueryComponent(sig)}';
}
```

(If `_sign` is private and not reusable from a new top-level fn in the same file, it is in the same library, so it is accessible. If the implementer prefers, factor the URL-building into a shared helper used by both `signUploadUrl` and `signReadUrl`.)

- [ ] **Step 4: Add the read route**

In `media_routes.dart` `mediaRouter`, add (bearer-less, signature-verified, before `return router;`):

```dart
  router.get('/media/<id>', (Request request, String id) async {
    final exp = int.tryParse(request.url.queryParameters['exp'] ?? '');
    final sig = request.url.queryParameters['sig'];
    if (exp == null || sig == null ||
        !await verifyUploadSignature(
          id: id, exp: exp, sig: sig, signingKey: signingKey, now: DateTime.now())) {
      throw ApiException(ApiErrorCode.forbidden, message: 'Invalid or expired media URL.');
    }
    final media = await repo.get(id);
    if (media == null) throw ApiException(ApiErrorCode.notFound);
    return Response.ok(media.bytes, headers: {'content-type': media.contentType});
  });
```

The media leg in `app.dart` already authenticates only `media/presign`, so `GET /media/<id>` passes through unauthenticated to this signature check — no `app.dart` change needed. Confirm `/media/<id>` does not collide with `/media/upload/<id>` (it does not — different path depth).

- [ ] **Step 5: Run media tests + the full server suite — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/media/`
Expected: the new read test + the existing upload/presign tests pass.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/media server/test/media/media_routes_test.dart
git commit -m "feat(server): bearer-less signed GET /media/<id> for evidence reads

signReadUrl mints a short-lived HMAC read URL (same id.exp signature as upload);
GET /media/<id> verifies it and serves the media_objects bytes. The <img> fetch
carries no bearer, so the signed URL is the authorization — the same capability
model as the 4a upload."
```

---

### Task 5: Verification repo + routes (queue + case + decision) + wiring

**Files:**
- Create: `server/lib/src/verification/verification_repo.dart`, `verification_routes.dart`
- Modify: `server/lib/src/app.dart`
- Create: `server/test/verification/verification_routes_test.dart`

**Interfaces:**
- Consumes: `Db`/`row`; `AuditWriter.writeTx`/`.write`; `authOf`/`requirePermission`/`_authenticateUnder`; `ApiException`/`ApiErrorCode`; `correlationOf`; `signReadUrl` (Task 4); `MatchBand`/`ReferenceSource`/`VerificationOutcome` (Task 1); `ServerConfig.uploadSigningKey`; migration 008.
- Produces:
  - `class VerificationRepo { VerificationRepo(Db db, {required String signingKey}); Future<List<Map<String,Object?>>> queue({required String organizationId}); Future<Map<String,Object?>?> loadCase({required String attendanceId, required String organizationId, required String viewerId, required String baseUrl, String? correlationId}); Future<VerificationDecisionResult> decide({required String attendanceId, required String organizationId, required String verifierId, required String outcomeWire, required String? reason, required bool supervisorOverride, required int ifMatchVersion, String? correlationId}); }`
  - `enum VerificationDecisionCode { applied, notFound, versionConflict, reasonRequired, unsupportedOutcome }` + `class VerificationDecisionResult { final VerificationDecisionCode code; }`
  - `Router verificationRouter({required Db db, required String signingKey})`.

- [ ] **Step 1: Write the failing routes tests**

`server/test/verification/verification_routes_test.dart` — model the harness on `import_routes_test.dart`. `setUp` seeds: a `crm_verifier` user (holds `verification_decide` + `sensitive_media_view`), a plain viewer, an APPROVED campaign + session + carpenter (with a `thumbnail_url`), and an attendance in `CRM_REVIEW` with a machine band + a `media_objects` row for the evidence (INSERT directly, or drive a confirm). Cover:

```dart
// - GET /verification/queue: lists the CRM_REVIEW attendance org-scoped, with
//   ageSeconds/band/carpenterName; a cross-org attendance never appears; 403 without
//   verification_decide.
// - GET /verification/cases/<id>: returns version, carpenterIdMasked (== display_code),
//   campaignName, sessionName, capturedImageUrl (a /media/<id>?sig url), band, reasons;
//   WRITES an audit_events row (action 'verification.case_viewed', actor = verifier);
//   403 without sensitive_media_view; 404 cross-org.
// - POST decision approve (If-Match matches version) -> 200; attendance.status = 'APPROVED',
//   version bumped, a verification_decisions row exists, an audit row exists.
// - POST decision reject with a reason -> 'REJECTED'. reject WITHOUT reason -> 422
//   (error code decisionReasonRequired).
// - POST decision with a STALE If-Match (version-1) -> 412 (preconditionFailed), and the
//   attendance status is UNCHANGED.
// - POST decision outcome RETURN_FOR_RECAPTURE / ESCALATED / supervisorOverride:true -> 422
//   (verificationOutcomeUnsupported).
// - 401 unauthenticated on each.
```
Write the concrete tests with real assertions and the exact `If-Match` header handling.

- [ ] **Step 2: Run — confirm failure**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/verification/verification_routes_test.dart`
Expected: FAIL — the verification leg does not exist.

- [ ] **Step 3: Implement the repo**

`server/lib/src/verification/verification_repo.dart` — the SQL (all org-scoped through `attendance ⋈ campaigns.organization_id`):

- `queue`: `SELECT a.id, a.machine_band, a.assignee_id, a.captured_at, cr.full_name AS carpenter_name, c.name AS campaign_name FROM attendance a JOIN campaigns c ON c.id = a.campaign_id JOIN carpenters cr ON cr.id = a.carpenter_id WHERE a.organization_id = @org AND a.status = 'CRM_REVIEW' ORDER BY <band severity>, a.captured_at`. Band severity: order `NO_REFERENCE`, `LOW`, `MEDIUM`, `HIGH` (worst first) — implement via a `CASE a.machine_band WHEN 'NO_REFERENCE' THEN 0 WHEN 'LOW' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END`. Map each row to the queue-item wire (`attendanceId, carpenterName, campaignName, ageSeconds` = `now - captured_at` in seconds, `band`, `referenceSource`, `assigneeId`). Compute `ageSeconds` in Dart from `captured_at`.
- `loadCase`: `SELECT a.*, cr.full_name, cr.display_code, cr.thumbnail_url, c.name AS campaign_name, s.venue AS session_name FROM attendance a JOIN carpenters cr ... JOIN campaigns c ... JOIN campaign_sessions s ON s.id = a.session_id WHERE a.id=@id AND a.organization_id=@org`. Null → return null (404). Else build the wire: `attendanceId, version, carpenterName, carpenterIdMasked=display_code, campaignName, sessionName=venue, capturedAt (ISO), capturedImageUrl = await signReadUrl(baseUrl, media_ref, signingKey, now), referenceImageUrl = thumbnail_url (or null), band=machine_band, referenceSource=machine_reference_src, padReview:false, lowQuality:false, reasons=jsonDecode(machine_reasons)`. **Write the audit-on-view row** (`_audit.write(action:'verification.case_viewed', resourceType:'attendance', resourceId:attendanceId, actorId:viewerId, correlationId:correlationId, payload:{})`).
- `decide`: load the attendance org-scoped → null → `notFound`. Parse `outcomeWire` via `VerificationOutcome.tryParseWire`; if it's `returnForRecapture`/`escalated` OR `supervisorOverride` is true → `unsupportedOutcome`. If `rejected` and (reason null/blank) → `reasonRequired`. Then an atomic CAS on version:
  ```sql
  UPDATE attendance SET status = @newStatus, version = version + 1
   WHERE id = @id AND version = @ifMatch
     AND organization_id = @org
  RETURNING version
  ```
  `@newStatus` = `'APPROVED'`/`'REJECTED'`. If the UPDATE returns 0 rows → re-check existence (org-scoped): exists → `versionConflict` (412); gone → `notFound`. If 1 row → in the SAME `_db.tx`, INSERT the `verification_decisions` row (`version_at_decision = @ifMatch`) and `writeTx` an audit `verification.decided`. Return `applied`.
  > Do the UPDATE + decision INSERT + audit in one `_db.tx` (the UPDATE is the CAS; run it via `tx.execute` inside the tx, and check its affected rows).

- [ ] **Step 4: Implement the routes**

`server/lib/src/verification/verification_routes.dart`:

```dart
Router verificationRouter({required Db db, required String signingKey}) {
  final router = Router();
  final repo = VerificationRepo(db, signingKey: signingKey);

  router.get('/verification/queue',
    const Pipeline().addMiddleware(requirePermission('verification_decide')).addHandler(
      (Request request) async {
        final auth = authOf(request);
        final items = await repo.queue(organizationId: auth.organizationId);
        return _json({'items': items});
      }));

  router.get('/verification/cases/<id>',
    const Pipeline()
        .addMiddleware(requirePermission('verification_decide'))
        .addMiddleware(requirePermission('sensitive_media_view'))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final u = request.requestedUri;
          final view = await repo.loadCase(
            attendanceId: request.params['id']!,
            organizationId: auth.organizationId,
            viewerId: auth.userId,
            baseUrl: '${u.scheme}://${u.authority}',
            correlationId: correlationOf(request));
          if (view == null) throw ApiException(ApiErrorCode.notFound);
          return _json(view);
        }));

  router.post('/verification/cases/<id>/decision',
    const Pipeline().addMiddleware(requirePermission('verification_decide')).addHandler(
      (Request request) async {
        final auth = authOf(request);
        final ifMatch = int.tryParse(request.headers['if-match'] ?? '');
        if (ifMatch == null) {
          throw ApiException(ApiErrorCode.badRequest, message: 'If-Match header is required.');
        }
        final body = (jsonDecode(await request.readAsString()) as Map).cast<String, Object?>();
        final result = await repo.decide(
          attendanceId: request.params['id']!,
          organizationId: auth.organizationId,
          verifierId: auth.userId,
          outcomeWire: body['outcome'] as String? ?? '',
          reason: body['reason'] as String?,
          supervisorOverride: (body['supervisorOverride'] as bool?) ?? false,
          ifMatchVersion: ifMatch,
          correlationId: correlationOf(request));
        switch (result.code) {
          case VerificationDecisionCode.applied:
            // Return the refreshed case so the client can re-render.
            final u = request.requestedUri;
            final view = await repo.loadCase(
              attendanceId: request.params['id']!, organizationId: auth.organizationId,
              viewerId: auth.userId, baseUrl: '${u.scheme}://${u.authority}',
              correlationId: correlationOf(request));
            return _json(view ?? {'status': 'done'});
          case VerificationDecisionCode.notFound:
            throw ApiException(ApiErrorCode.notFound);
          case VerificationDecisionCode.versionConflict:
            throw ApiException(ApiErrorCode.preconditionFailed,
                message: 'This case was decided by someone else; reload it.');
          case VerificationDecisionCode.reasonRequired:
            throw ApiException(ApiErrorCode.decisionReasonRequired,
                message: 'A reason is required to reject.');
          case VerificationDecisionCode.unsupportedOutcome:
            throw ApiException(ApiErrorCode.verificationOutcomeUnsupported,
                message: 'Only approve and reject are supported in this release.');
        }
      }));

  return router;
}
```

(Provide the `_json` helper as in the other routers. The `If-Match` outcome-note above: applied re-fetches the case — this issues a second audit-on-view; acceptable, or skip re-loading and return `{status: newStatus}`. Prefer returning `{'status': result.finalStatus}` to avoid a spurious second view-audit — carry `finalStatus` on the result. Confirm the client ignores the decision response body, so either is fine; the lighter `{'status': ...}` is preferred.)

> Adjust: have `VerificationDecisionResult` carry the `finalStatus` (`'APPROVED'`/`'REJECTED'`) so the `applied` branch returns `{'status': finalStatus}` without a second `loadCase` (avoids a duplicate audit-on-view). The client ignores the body.

- [ ] **Step 5: Wire the verification leg in `app.dart`**

`import 'verification/verification_routes.dart';`, build `verificationHandler` with `_authenticateUnder(const {'verification'}, db: db, tokens: tokens)` wrapping `verificationRouter(db: db, signingKey: config.uploadSigningKey).call`, and `.add(verificationHandler)`.

- [ ] **Step 6: Run the verification tests + full server suite — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/verification/verification_routes_test.dart` then the media/attendance/db suites.
Expected: queue, case (+ audit-on-view), decision (approve/reject, 412 stale, 422 reason-required, 422 unsupported), RBAC all pass.

- [ ] **Step 7: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/verification/verification_repo.dart server/lib/src/verification/verification_routes.dart server/lib/src/app.dart server/test/verification/verification_routes_test.dart
git commit -m "feat(server): verification queue + case (audit-on-view) + decision (412 If-Match)

GET /verification/queue (CRM_REVIEW, band-then-age, org-scoped); GET
/verification/cases/<id> (verification_decide + sensitive_media_view) mints
signed evidence URLs and writes an audit-on-view row; POST decision enforces
If-Match optimistic locking (412 on a stale version), approve/reject only
(reason required to reject; return/escalate/override -> 422 unsupported)."
```

---

### Task 6: Client — enum shims, safe parsing, 412 mapping

**Files:**
- Modify: `lib/domain/verification/verification.dart`
- Modify: `lib/data/verification/verification_repository_impl.dart`
- Modify: `lib/core/network/dio_client.dart`
- Create: `test/data/verification/verification_repository_impl_test.dart`

**Interfaces:**
- Consumes: `MatchBand`/`ReferenceSource`/`VerificationOutcome` from `campaign_contracts` (Task 1); the wire shapes (Task 5).
- Produces: no new server-facing interface; the client speaks SCREAMING_SNAKE and treats a 412 as a conflict.

- [ ] **Step 1: Write the failing client repo test**

`test/data/verification/verification_repository_impl_test.dart` (recording `HttpClientAdapter` + bare Dio, like `import_repository_impl_test.dart`): assert the queue/case parse `band`/`referenceSource` from SCREAMING_SNAKE (`'MEDIUM'`→`MatchBand.medium`, `'APPROVED_BASELINE_PHOTO'`→`ReferenceSource.approvedBaselinePhoto`); that an unknown band is a visible fallback (`noReference`), not a crash; that `submitDecision` posts `outcome` as the SCREAMING_SNAKE `wireValue` (`'APPROVED'`, not `'approved'`) and sends `If-Match`; and that a 412 response maps to `FailureKind.conflict`.

- [ ] **Step 2: Run — confirm failure**

Run: `flutter test test/data/verification/verification_repository_impl_test.dart`
Expected: FAIL (the parse is camelCase; outcome sends `.name`; 412 unmapped).

- [ ] **Step 3: Move the enums to contracts (shims)**

In `lib/domain/verification/verification.dart`, delete the local `enum MatchBand`, `enum ReferenceSource`, `enum VerificationOutcome`, and re-export from contracts (add after the imports, before `part`):

```dart
export 'package:campaign_contracts/campaign_contracts.dart'
    show MatchBand, ReferenceSource, VerificationOutcome;
```

Keep `MachineResult`, `VerificationDecision` (freezed) unchanged — their member names are identical, so nothing else needs editing. (Add a matching `import '...campaign_contracts...';` if the freezed part references the enums, as 3a needed.)

- [ ] **Step 4: Parse SCREAMING_SNAKE; send `wireValue`**

In `verification_repository_impl.dart`: replace `_band`/`_refSource` with `MatchBand.tryParseWire(s ?? '') ?? MatchBand.noReference` and `ReferenceSource.tryParseWire(s ?? '') ?? ReferenceSource.unavailable` (visible fallback — add a `debugPrint` naming the raw value). Change the decision POST body from `'outcome': decision.outcome.name` to `'outcome': decision.outcome.wireValue`.

- [ ] **Step 5: Map 412 → conflict**

In `lib/core/network/dio_client.dart` `mapDioError`, add a `412 => FailureKind.conflict` arm to the status switch (next to `409`), so an `If-Match` precondition failure surfaces as a conflict.

- [ ] **Step 6: Run the client test + full Flutter suite**

Run: `flutter gen-l10n && dart run build_runner build --delete-conflicting-outputs`, then `flutter test test/data/verification/verification_repository_impl_test.dart`, then `flutter test`.
Expected: the new test passes; the whole suite passes with the count up only by this task's tests (investigate any crm_case widget test that assumed camelCase — update the fixture to SCREAMING_SNAKE).

- [ ] **Step 7: Format, analyze, commit**

```bash
dart format --set-exit-if-changed lib test && flutter analyze --fatal-infos
git add lib/domain/verification lib/data/verification lib/core/network/dio_client.dart test/data/verification
git commit -m "feat(client): verification enums from contracts + 412-as-conflict

MatchBand/ReferenceSource/VerificationOutcome re-export from campaign_contracts;
the repo parses SCREAMING_SNAKE via tryParseWire (unknown -> visible fallback,
never a silent default) and sends outcome.wireValue; mapDioError treats a 412
(stale If-Match) as a conflict so the decision-conflict flow surfaces correctly."
```

---

### Task 7: Mock parity

**Files:**
- Modify: `tool/mock_server/bin/server.dart`
- Modify: `server/test/contract/parity_test.dart`

- [ ] **Step 1: Align the mock**

In `tool/mock_server/bin/server.dart`, update the verification handlers to the ratified wire: `/verification/queue` and `/verification/cases/<id>` emit `band`/`referenceSource` as SCREAMING_SNAKE (`MEDIUM`, `APPROVED_BASELINE_PHOTO`, …); the decision reads `outcome` as SCREAMING_SNAKE (`APPROVED`/`REJECTED`) and returns **412** when the `If-Match` header doesn't match the case's current version (the `CASE_CONFLICT` fixture's version is ahead). Keep the `CASE_E2E`/`CASE_CONFLICT` fixtures and their ids.

- [ ] **Step 2: Pin parity**

In `server/test/contract/parity_test.dart`, add a case asserting mock and real agree on: the queue item shape (keys incl. `band` a SCREAMING_SNAKE `MatchBand`); the case shape (keys + `band`/`referenceSource` parse via `tryParseWire` non-null on both); and that a decision with a stale `If-Match` returns **412** on both. Seed the real side (a `CRM_REVIEW` attendance + media + a `crm_verifier` token; for the conflict, bump the stored version) as the route tests do. Do not weaken existing parity cases.

- [ ] **Step 3: Run parity, format, analyze, commit**

```bash
cd tool/mock_server && dart pub get && dart analyze && dart format --set-exit-if-changed .
cd ../../server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/contract/parity_test.dart
cd .. && git add tool/mock_server/bin/server.dart server/test/contract/parity_test.dart
git commit -m "chore(mock): verification wire matches the real service (SCREAMING_SNAKE, 412)

Mock queue/case emit SCREAMING_SNAKE bands/sources and the decision returns 412
on a stale If-Match; parity pins the queue/case shapes and the 412 conflict."
```

---

### Task 8: E2E — crm on the real service + seed

**Files:**
- Modify: `server/lib/src/seed/seed_routes.dart`
- Modify: `.maestro/flows/crm_case_decision.yaml`, `.maestro/flows/crm_case_conflict.yaml`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the real endpoints (Tasks 3–5), the `crm_verifier` seed, the `CASE_E2E`/`CASE_CONFLICT` fixtures.
- Produces: a green `crm` matrix config against the real service.

- [ ] **Step 1: Seed the cases**

In `server/lib/src/seed/seed_routes.dart`, in the reset path, seed:
- A carpenter with a `thumbnail_url` (so its case has a reference + `MEDIUM` band) — reuse/extend the existing carpenter seed.
- A `media_objects` row for each case id (the evidence blob — a tiny byte string).
- An `attendance` row `CASE_E2E`: `status='CRM_REVIEW'`, `version=1`, `machine_band='MEDIUM'`, `machine_reference_src='APPROVED_BASELINE_PHOTO'`, `machine_reasons='["Face comparison inconclusive — manual review required."]'`, `media_ref='CASE_E2E'`, on the seeded APPROVED campaign + a session + the carpenter, `captured_by` a seeded user.
- An `attendance` row `CASE_CONFLICT`: same shape but `version=2` (ahead of the `1` a fresh client GET will present via `If-Match`, so its decision 412s) — OR seed it already-decided (`status='APPROVED'`, `version=2`). Confirm the client's fetched version vs the seeded version produces a mismatch. Add `CASE_E2E`/`CASE_CONFLICT`/`verification_decisions`/`media_objects`/`attendance` to the reset truncate list so a reset reseeds cleanly.

Add a server test (extend the seed test) asserting a reset then `GET /verification/cases/CASE_E2E` (with a crm_verifier token) returns a `CRM_REVIEW` case, and a decision on `CASE_CONFLICT` with `If-Match: 1` → 412.

- [ ] **Step 2: Move the crm flows to real auth**

In `.maestro/flows/crm_case_decision.yaml` and `crm_case_conflict.yaml`, replace `runFlow: ../subflows/launch_as_crm.yaml` with a real-auth login prelude (copy from `session_ops.yaml`, signing in as **`crm_verifier`** / `Test1234!` → `dev_launcher`), keeping the rest (`dev_open_crm_case` / `dev_open_crm_case_conflict` → the case → decision) intact. The dev launcher's `dev_open_crm_case` opens `/verification/cases/CASE_E2E`, which now resolves on the real service (seeded). If a merged-node selector needs a wrap or an id, add it per the 2a/2b/3a/4a convention.

- [ ] **Step 3: Flip the `crm` CI config to the real service**

In `.github/workflows/ci.yml`, change the `crm` matrix entry: `useMock: '0'`, `defines: '--dart-define=E2E_REAL_AUTH=true --dart-define=ROLE=crm_verifier'` (from its current mock config). Keep its two flows. This moves `crm` off `USE_MOCK` — the sub-project-5a deliverable.

- [ ] **Step 4: Local validation (no emulator) — the server contract the flows depend on**

Bring up the server, reset, log in as `crm_verifier`, and curl: `GET /verification/queue`, `GET /verification/cases/CASE_E2E` (assert the shape + a `/media/...` capturedImageUrl; assert an audit row was written), a decision approve on `CASE_E2E` with `If-Match: 1` → 200 + `APPROVED`, and a decision on `CASE_CONFLICT` with `If-Match: 1` → **412**. Record the transcript. If an emulator is available, run the crm flows via `run_maestro_flows.sh`.

- [ ] **Step 5: Commit**

```bash
git add server/lib/src/seed/seed_routes.dart .maestro/flows/crm_case_decision.yaml .maestro/flows/crm_case_conflict.yaml .github/workflows/ci.yml
# include any seed test file you added
git commit -m "feat(e2e): crm verification flows against the real service

Seeds CASE_E2E (CRM_REVIEW, evidence, reference) and CASE_CONFLICT (version
ahead, so its decision 412s). The crm flows sign in for real as crm_verifier and
drive the case -> approve / conflict against the real campaign_service; the crm
matrix config flips to useMock 0 — the sub-project 5a cut-over."
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task:
- §2 5a.D1 (wire enums) → Task 1 (contracts) + Task 6 (client shims) — refined to MatchBand/ReferenceSource/VerificationOutcome (AttendanceStatus is not wire-consumed; server uses status literals).
- 5a.D2 (machine adapter in confirm) → Task 3. 5a.D3 (If-Match → 412) → Task 1 (code), Task 5 (repo/routes), Task 6 (client 412→conflict). 5a.D4 (case audit-on-view + bearer-less signed media read) → Task 4 (media GET) + Task 5 (case). 5a.D5 (approve/reject; reason; unsupported → 422) → Task 5. 5a.D6 (RBAC + org scope) → Task 5.
- §3 endpoints/error codes → Tasks 1, 4, 5. §4 migration → Task 2. §5 files → Tasks 3–5. §6 client/mock → Tasks 6, 7. §6a validated patterns → folded into Tasks 3 (adapter), 4 (signed read), 5 (412 / audit-on-view). §7 e2e → Task 8. §8 testing → each task's tests incl. the 412 falsification and the audit-on-view assertion. §9 out-of-scope not implemented (returnForRecapture/escalated/override → 422; no real ML; no nid_reveal; media hardening stays 4b).

**Placeholder scan:** the prose-guided steps (Task 5 Step 1 test outline, Task 5 Step 3 repo SQL, Task 8 flow authoring) name concrete columns/assertions/ids and reference exact template files; no "handle edge cases"/"similar to Task N"/bare "write tests".

**Type consistency:** `MatchBand`/`ReferenceSource`/`VerificationOutcome` wireValues (Task 1) are parsed by the client (Task 6) and emitted by the repo/mock (Tasks 5, 7); `StubMachineCheck.check(hasReference:)`→`MachineResultData` (Task 3) is stored by the confirm and read by the case; `signReadUrl` (Task 4) is called by `loadCase` (Task 5) and verified by `GET /media/<id>` (Task 4); `ApiErrorCode.preconditionFailed`→412 (Task 1) is thrown on a stale `If-Match` (Task 5) and mapped to conflict by the client (Task 6). The status literals `'CRM_REVIEW'`/`'APPROVED'`/`'REJECTED'` are identical across the confirm, the queue filter, the decision, and the seed.
