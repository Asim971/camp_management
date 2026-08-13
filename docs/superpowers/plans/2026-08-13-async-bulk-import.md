# Sub-project 2b — Async Bulk Import (W-07) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the campaign service the authority for bulk registration import as an asynchronous job lifecycle (upload → 202 → background classify → poll → commit), and cut the Flutter Bulk Import screen (W-07) over to it.

**Architecture:** A new `server/lib/src/import_/` module: a pure CSV parser (`import_file.dart`, no IO), an `ImportRepo` (job storage + row classification against 2a's carpenter master + idempotent commit), and `import_routes.dart` (shelf_multipart upload, poll, commit, and the unawaited background classify task). The dry-run handler returns 202 with a durable `PROCESSING` job; an in-process background task with its own DB connection classifies rows and flips the job to `READY_TO_COMMIT`; a stuck-job reaper fails orphans. The client gains a `FileSource` seam (real `file_selector` + E2E fake) and a polling controller.

**Tech Stack:** Dart 3.12, `shelf` 1.4.2, `shelf_router` 1.1.4, `shelf_multipart` 2.0.1 (NEW), `csv` 8.0.0 (NEW), `postgres` 3.5.12, `uuid` 4.6.0, Postgres 16 in CI. Flutter client with Dio/Riverpod, `file_selector`, `csv` 8.0.0 (already present). Maestro for e2e.

**Spec:** `docs/superpowers/specs/2026-08-13-async-bulk-import-design.md`. Decisions cited **2b.D1**–**2b.D5**, deliverables **2b-A**–**2b-I**. §6a holds the web-validated dependency/pattern findings this plan builds on.

## Global Constraints

Every task's requirements implicitly include this section.

- **SDK floor `sdk: ">=3.12.0 <4.0.0"`** in every touched `pubspec.yaml`. Do not lower it.
- **`shelf`/`shelf_router` only — no ORM, no codegen** in `server/` or `packages/campaign_contracts`. `shelf_multipart` and `csv` are parser libraries, not codegen — permitted. The app's freezed/drift codegen is app-only.
- **Wire naming is SCREAMING_SNAKE** for every enum-ish value. New vocabulary: `DRY_RUN`, `READY_TO_COMMIT`, `PROCESSING`, `COMPLETED`, `PARTIALLY_COMPLETED`, `FAILED`, `CANCELLED`, `VALID`, `WARNING`, `DUPLICATE`, `NEEDS_PROFILE`, `UNAUTHORIZED`, `ERROR`, `IMPORT_FILE_INVALID`.
- **Unknown enum values never resolve to a default** — `tryParseWire` returns `null`; the client's `firstWhere(orElse:)` defaults are removed.
- **Out-of-scope resources return `404`, never `403`** (D7); org-scope inside the SQL.
- **Raw `phone`/`nid` never leave the server** — not in wire JSON, error details, or audit payloads (2a.D2). Row wire fields carry masked identifiers only when a carpenter is linked.
- **A fire-and-forget future's unhandled error kills the Dart process** (§6a). The background task is launched with `unawaited(...)` and its entire body wrapped so any fault flips the job to `FAILED` and never propagates.
- **The background task opens its OWN `Db` connection** (§6a, 2b.D1) — never the request-serving connection.
- **CSV eol normalization is required** (§6a): strip a leading UTF-8 BOM and normalize `\r\n`→`\n` before `CsvToListConverter`, whose default `eol` is `\r\n`.
- **`postgres` traps:** inside `Db.tx` use the `TxSession`, never `Db.execute`; `ResultRow` reads go through `row()` (`server/lib/src/db/pool.dart`); a `List<String>` param binds as `text[]` for `= ANY(@x)`; a `List` for jsonb needs `jsonEncode(...) + ::jsonb`.
- **Every migration is transactional + forward-only**, embedded as a Dart const, applied by the advisory-locked runner (2a Task 2).
- **`bulk_import` permission** is already in the client's fixed claim vocabulary (`campaign_creator`, `admin`) — invent nothing.
- **Timestamps:** UTC ISO-8601 on the wire, `timestamptz` in Postgres.
- **Tests run against** `DATABASE_URL=postgres://campaign:campaign@localhost:5432/campaign` (native PG locally; CI `postgres:16`).
- **Baselines that must not regress** (from `main` at 2b start): server suite green (run `dart test` once to capture the exact count before Task 1), contracts package green, app `flutter test` green, `flutter analyze --fatal-infos` clean, `dart format --set-exit-if-changed` clean repo-wide.
- **Maestro idioms hardened in 2a (mandatory for Task 11):** drive controls by semantics `id:`; wrap merged-node text asserts in `.*…​.*`; escape regex metacharacters (`\(` `\)`) in literal patterns; `hideKeyboard` only immediately after an `inputText`; never a stray `hideKeyboard` (it back-navigates on Android); use `extendedWaitUntil` for the poll wait, not a fixed sleep or bare `assertVisible`.

---

## File Structure

```
packages/campaign_contracts/
  lib/src/import_status.dart          NEW  ImportStatus + wireValue + tryParseWire
  lib/src/import_row_outcome.dart     NEW  ImportRowOutcome + wireValue + tryParseWire
  lib/src/error_codes.dart            MOD  + importFileInvalid
  lib/campaign_contracts.dart         MOD  barrel exports
  test/import_status_test.dart        NEW
  test/import_row_outcome_test.dart   NEW

server/
  pubspec.yaml                        MOD  + shelf_multipart, csv
  lib/src/db/migrations/embedded.dart MOD  + 005_imports
  lib/src/import_/import_file.dart          NEW  pure CSV parse + validate → ParsedImport
  lib/src/import_/import_repo.dart          NEW  job storage + classify + reaper + commit
  lib/src/import_/import_routes.dart        NEW  3 routes + background task launch
  lib/src/participant/participant_repo.dart MOD  extract insertProvisionalCarpenterTx
  lib/src/infra/error_envelope.dart   MOD  + importFileInvalid → 422
  lib/src/app.dart                    MOD  import Cascade leg
  lib/src/seed/seed_routes.dart       MOD  a carpenter fixture for import duplicate/match
  test/import_/import_file_test.dart          NEW
  test/import_/import_repo_test.dart          NEW
  test/import_/import_routes_test.dart        NEW
  test/db/migrator_test.dart          MOD  table inventory
  test/infra/error_envelope_test.dart MOD  status-table line
  test/support/seed_fixtures.dart     MOD  + seedImportJob helper
  test/contract/parity_test.dart      MOD  import parity

tool/mock_server/bin/server.dart      MOD  ratified async import shapes

lib/ (Flutter app)
  domain/common/status.dart                    MOD  ImportStatus → re-export
  domain/import/import_job.dart                 MOD  ImportRowOutcome → re-export; committable
  core/files/file_source.dart                  NEW  FileSource seam (real + fake)
  data/import/import_repository_impl.dart       MOD  poll, namespaced commit, explicit parse
  domain/import/import_repository.dart          MOD  + poll signature
  features/bulk_import/application/import_controller.dart  MOD  poll loop + progress
  features/bulk_import/presentation/bulk_import_screen.dart MOD  FileSource seam + ids
  app/di/providers.dart                         MOD  fileSourceProvider
  assets/e2e/bulk_import_sample.csv             NEW  bundled E2E CSV
  pubspec.yaml                                  MOD  register the asset
test/data/import/import_repository_impl_test.dart NEW
test/widget/bulk_import_screen_test.dart          MOD/NEW  polling lifecycle

.maestro/flows/bulk_import.yaml         NEW
.maestro/config.yaml                    MOD
.github/workflows/ci.yml                MOD  bulkImport matrix entry
```

**Why these boundaries.** `import_file.dart` is pure (no IO, no DB) so the parse/validate rules are unit-testable without Postgres — the same reasoning that keeps `status_machine.dart`/`validation.dart` pure in slice 1. `import_repo.dart` owns all SQL and the classify/commit logic; `import_routes.dart` owns only HTTP + the background-task launch. The provisional-carpenter INSERT is extracted to a tx-aware helper so 2b's single-transaction commit reuses it instead of copying it.

---

# Phase 1 — Contracts and schema

### Task 1: Dependencies + `ImportStatus`/`ImportRowOutcome` wire vocabulary + `IMPORT_FILE_INVALID`

**Files:**
- Modify: `server/pubspec.yaml`
- Create: `packages/campaign_contracts/lib/src/import_status.dart`, `lib/src/import_row_outcome.dart`, `test/import_status_test.dart`, `test/import_row_outcome_test.dart`
- Modify: `packages/campaign_contracts/lib/src/error_codes.dart`, `lib/campaign_contracts.dart`
- Modify: `server/lib/src/infra/error_envelope.dart`, `server/test/infra/error_envelope_test.dart`
- Modify: `lib/domain/common/status.dart`, `lib/domain/import/import_job.dart`

**Interfaces:**
- Produces: `enum ImportStatus { dryRun, readyToCommit, processing, completed, partiallyCompleted, failed, cancelled }` with `String get wireValue` / `static ImportStatus? tryParseWire(String)`; `enum ImportRowOutcome { valid, warning, duplicate, needsProfile, unauthorized, error }` with the same; `ApiErrorCode.importFileInvalid` → `IMPORT_FILE_INVALID` (HTTP 422).
- Consumes: nothing new.

- [ ] **Step 1: Capture baselines**

```bash
cd server && dart test 2>&1 | tail -1     # record the passing count
cd ../packages/campaign_contracts && dart test 2>&1 | tail -1
cd ../.. && flutter test 2>&1 | tail -1
```

Record the three counts in your report; every later "must not regress" is against these.

- [ ] **Step 2: Add the server dependencies (verified to resolve, §6a)**

In `server/pubspec.yaml` under `dependencies:` (keep alphabetical grouping consistent with the file):

```yaml
  csv: ^8.0.0
  shelf_multipart: ^2.0.1
```

```bash
cd server && dart pub get
```

Expected: resolves, adds `csv 8.0.0` and `shelf_multipart 2.0.1` (confirmed by dry-run during planning).

- [ ] **Step 3: Write the failing contracts tests**

`packages/campaign_contracts/test/import_status_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every import status has a distinct SCREAMING_SNAKE wire value', () {
    final wires = ImportStatus.values.map((s) => s.wireValue).toList();
    expect(wires.toSet().length, ImportStatus.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip', () {
    for (final s in ImportStatus.values) {
      expect(ImportStatus.tryParseWire(s.wireValue), s);
    }
  });

  test('an unknown wire value is null, never a default', () {
    expect(ImportStatus.tryParseWire('NOPE'), isNull);
    expect(ImportStatus.tryParseWire(''), isNull);
    expect(ImportStatus.tryParseWire('processing'), isNull,
        reason: 'case matters');
  });

  test('the exact vocabulary the server emits', () {
    expect(ImportStatus.readyToCommit.wireValue, 'READY_TO_COMMIT');
    expect(ImportStatus.partiallyCompleted.wireValue, 'PARTIALLY_COMPLETED');
    expect(ImportStatus.processing.wireValue, 'PROCESSING');
  });
}
```

`packages/campaign_contracts/test/import_row_outcome_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every outcome has a distinct SCREAMING_SNAKE wire value', () {
    final wires = ImportRowOutcome.values.map((o) => o.wireValue).toList();
    expect(wires.toSet().length, ImportRowOutcome.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip and unknown is null', () {
    for (final o in ImportRowOutcome.values) {
      expect(ImportRowOutcome.tryParseWire(o.wireValue), o);
    }
    expect(ImportRowOutcome.tryParseWire('NEEDS_PROFILE'),
        ImportRowOutcome.needsProfile);
    expect(ImportRowOutcome.tryParseWire('needsProfile'), isNull);
    expect(ImportRowOutcome.tryParseWire('WHAT'), isNull);
  });

  test('IMPORT_FILE_INVALID is in the error vocabulary', () {
    expect(ApiErrorCode.importFileInvalid.wireValue, 'IMPORT_FILE_INVALID');
    expect(ApiErrorCode.tryParseWire('IMPORT_FILE_INVALID'),
        ApiErrorCode.importFileInvalid);
  });
}
```

- [ ] **Step 4: Run — confirm compile failure**

```bash
cd packages/campaign_contracts && dart test
```

Expected: FAIL — `ImportStatus`/`ImportRowOutcome`/`importFileInvalid` undefined.

- [ ] **Step 5: Implement the enums and error code**

`packages/campaign_contracts/lib/src/import_status.dart`:

```dart
/// Bulk-import job lifecycle. Moved out of the app's
/// `lib/domain/common/status.dart` now that sub-project 2b defines its server
/// contract (the D5 rule: enums move only when their wire contract lands).
///
/// 2b implements PROCESSING → READY_TO_COMMIT → COMPLETED, plus FAILED. DRY_RUN,
/// PARTIALLY_COMPLETED and CANCELLED ship in the vocabulary but are produced by
/// a later slice (2c) — shipping them now means 2c needs no contract change.
enum ImportStatus {
  dryRun,
  readyToCommit,
  processing,
  completed,
  partiallyCompleted,
  failed,
  cancelled;

  String get wireValue => switch (this) {
    dryRun => 'DRY_RUN',
    readyToCommit => 'READY_TO_COMMIT',
    processing => 'PROCESSING',
    completed => 'COMPLETED',
    partiallyCompleted => 'PARTIALLY_COMPLETED',
    failed => 'FAILED',
    cancelled => 'CANCELLED',
  };

  static ImportStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
```

`packages/campaign_contracts/lib/src/import_row_outcome.dart`:

```dart
/// Per-row dry-run classification. Committable in 2b: VALID and NEEDS_PROFILE.
/// WARNING ships in the vocabulary but is not produced this slice (2c's
/// eligibility rule). DUPLICATE/UNAUTHORIZED/ERROR are never committable.
enum ImportRowOutcome {
  valid,
  warning,
  duplicate,
  needsProfile,
  unauthorized,
  error;

  String get wireValue => switch (this) {
    valid => 'VALID',
    warning => 'WARNING',
    duplicate => 'DUPLICATE',
    needsProfile => 'NEEDS_PROFILE',
    unauthorized => 'UNAUTHORIZED',
    error => 'ERROR',
  };

  static ImportRowOutcome? tryParseWire(String wire) {
    for (final o in values) {
      if (o.wireValue == wire) return o;
    }
    return null;
  }
}
```

In `packages/campaign_contracts/lib/src/error_codes.dart`, add to the enum (new comment group after `unknownCarpenter`):

```dart
  // bulk import (sub-project 2b)
  importFileInvalid;
```

and to the `wireValue` switch:

```dart
    importFileInvalid => 'IMPORT_FILE_INVALID',
```

In `packages/campaign_contracts/lib/campaign_contracts.dart`, add:

```dart
export 'src/import_row_outcome.dart';
export 'src/import_status.dart';
```

- [ ] **Step 6: Contracts tests pass**

```bash
cd packages/campaign_contracts && dart test
```

Expected: all pass (previous count + 8 new tests).

- [ ] **Step 7: Server envelope arm + status-table test**

`server/lib/src/infra/error_envelope.dart` — the `status` switch over `ApiErrorCode` is exhaustive, so the server will not compile until this arm exists. Add:

```dart
    ApiErrorCode.importFileInvalid => 422,
```

In `server/test/infra/error_envelope_test.dart`, find the hand-enumerated code→status table (the slice-1 M5 test) and add the pair `ApiErrorCode.importFileInvalid: 422`.

```bash
cd server && dart pub get && dart test test/infra/error_envelope_test.dart
```

Expected: pass.

- [ ] **Step 8: App shims**

In `lib/domain/common/status.dart`: delete the `enum ImportStatus { ... }` declaration and extend the existing re-export:

```dart
export 'package:campaign_contracts/campaign_contracts.dart'
    show CampaignStatus, RegistrationStatus, ImportStatus;
```

Update the file's doc comment: `ImportStatus` has now moved; `AttendanceStatus` and `IntegrityFlag` remain (attendance is sub-project 4).

In `lib/domain/import/import_job.dart`: delete the `enum ImportRowOutcome { ... }` declaration (lines 36-43) and add near the top, after the existing imports:

```dart
export 'package:campaign_contracts/campaign_contracts.dart'
    show ImportRowOutcome;
```

(The file already imports `../common/status.dart` for `ImportStatus`; that now resolves through the shim.)

- [ ] **Step 9: Verify the app is unmoved**

```bash
flutter pub get
flutter analyze --fatal-infos
flutter test
```

Expected: analyze clean; app test count **identical** to the Step 1 baseline (the shims are behaviorally invisible — `ImportRepositoryImpl` and `import_controller.dart` consume the same enum values). If a count changes, a shim altered behavior — investigate, do not accept.

- [ ] **Step 10: Format, full server suite, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
cd .. && dart format --set-exit-if-changed lib packages
git add server/pubspec.yaml server/pubspec.lock packages/campaign_contracts \
  server/lib/src/infra/error_envelope.dart server/test/infra/error_envelope_test.dart \
  lib/domain/common/status.dart lib/domain/import/import_job.dart pubspec.lock
git commit -m "feat(contracts): ImportStatus/ImportRowOutcome wire vocabulary + IMPORT_FILE_INVALID

Both enums move into campaign_contracts now that 2b defines their server
contract (the D5 rule; same shim pattern as RegistrationStatus). The full
vocabulary ships; 2b produces only the PROCESSING/READY_TO_COMMIT/COMPLETED/
FAILED subset, so 2c needs no contract change. Server gains csv 8.0.0 and
shelf_multipart 2.0.1 (resolution verified during planning)."
```

---

### Task 2: Migration `005_imports`

**Files:**
- Modify: `server/lib/src/db/migrations/embedded.dart`
- Modify: `server/test/db/migrator_test.dart` (table inventory)
- Modify: `server/test/support/seed_fixtures.dart` (add `seedImportJob`)

**Interfaces:**
- Consumes: the advisory-locked `Migrator` (2a Task 2).
- Produces: tables `import_jobs`, `import_job_rows`; test fixture `seedImportJob(Db, {required String id, String campaignId, String organizationId, String status, String uploadedBy, List<({String rowId, String name, String phone, String? outcome})> rows})`.

- [ ] **Step 1: Add migration `005_imports`**

In `server/lib/src/db/migrations/embedded.dart`, add `'005_imports': _imports,` to the map (after `004_identity`) and define:

```dart
const String _imports = r'''
CREATE TABLE import_jobs (
  id               TEXT PRIMARY KEY,
  campaign_id      TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  status           TEXT NOT NULL,              -- ImportStatus wire value
  filename         TEXT NOT NULL,
  file_hash        TEXT NOT NULL,              -- sha256 of the bytes (2b.D3)
  total_rows       INTEGER NOT NULL DEFAULT 0,
  processed_rows   INTEGER NOT NULL DEFAULT 0,
  config_version   TEXT,
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
  message              TEXT,
  linked_carpenter_id  TEXT REFERENCES carpenters(id),
  PRIMARY KEY (job_id, row_id)
);
''';
```

- [ ] **Step 2: Extend the table-inventory test**

In `server/test/db/migrator_test.dart`, add `'import_jobs', 'import_job_rows'` to the `containsAll` list in the "creates every table" test.

- [ ] **Step 3: Add the seed fixture**

Append to `server/test/support/seed_fixtures.dart`:

```dart
/// Inserts an import job and its rows directly, bypassing the route — for
/// poll/commit tests that need a job in a specific state.
Future<void> seedImportJob(
  Db db, {
  required String id,
  String campaignId = 'camp-1',
  String organizationId = 'org-1',
  String status = 'READY_TO_COMMIT',
  String uploadedBy = 'user-1',
  String filename = 'import.csv',
  List<({String rowId, String name, String phone, String? outcome})> rows =
      const [],
}) async {
  await db.execute(
    'INSERT INTO import_jobs '
    '(id, campaign_id, organization_id, status, filename, file_hash, '
    ' total_rows, processed_rows, uploaded_by, claimed_at) '
    "VALUES (@id, @c, @org, @s, @f, 'hash', @n, @n, @by, now())",
    params: {
      'id': id,
      'c': campaignId,
      'org': organizationId,
      's': status,
      'f': filename,
      'n': rows.length,
      'by': uploadedBy,
    },
  );
  for (final r in rows) {
    await db.execute(
      'INSERT INTO import_job_rows '
      '(job_id, row_id, name, phone, outcome) '
      'VALUES (@j, @r, @name, @phone, @o)',
      params: {
        'j': id,
        'r': r.rowId,
        'name': r.name,
        'phone': r.phone,
        'o': r.outcome,
      },
    );
  }
}
```

- [ ] **Step 4: Run db suites, format, analyze, full suite, commit**

```bash
cd server && dart test test/db/ && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server && git commit -m "feat(server): migration 005_imports (import_jobs, import_job_rows)

Durable job + row records for the async import lifecycle. file_hash (not the
raw bytes, 2b.D3); claimed_at feeds the stuck-job reaper (2b.D2); row_id is
the line-derived deterministic id (2b.D4). Applied after 004_identity by the
advisory-locked runner."
```

---

# Phase 2 — Parser, classification, engine

### Task 3: Pure CSV parser and validator (`import_file.dart`)

**Files:**
- Create: `server/lib/src/import_/import_file.dart`
- Create: `server/test/import_/import_file_test.dart`

**Interfaces:**
- Consumes: `csv` package; `ApiException`/`ApiErrorCode.importFileInvalid`.
- Produces:
  - `class ParsedRow { final String rowId; final String name; final String phone; final String? nid; final String? territory; final String? dealerContext; }`
  - `class ParsedImport { final List<ParsedRow> rows; }`
  - `ParsedImport parseImportCsv(List<int> bytes)` — throws `ApiException(importFileInvalid)` (422) with a specific message for: non-UTF-8, over 2 MB, empty, missing a required header column (`name`, `phone`), or zero data rows. Pure — no IO, no DB.

- [ ] **Step 1: Write the failing tests**

`server/test/import_/import_file_test.dart`:

```dart
import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/import_/import_file.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:test/test.dart';

void main() {
  List<int> utf8Bytes(String s) => utf8.encode(s);

  test('parses a well-formed CSV with the required + optional columns', () {
    final parsed = parseImportCsv(utf8Bytes(
      'name,phone,territory\n'
      'Md. Karim,+8801700004821,Dhaka North\n'
      'Karim Uddin,+8801700007734,Dhaka South\n',
    ));
    expect(parsed.rows, hasLength(2));
    expect(parsed.rows[0].rowId, 'row-1');
    expect(parsed.rows[0].name, 'Md. Karim');
    expect(parsed.rows[0].phone, '+8801700004821');
    expect(parsed.rows[0].territory, 'Dhaka North');
    expect(parsed.rows[1].rowId, 'row-2');
  });

  test('header matching is case-insensitive and trims whitespace', () {
    final parsed = parseImportCsv(utf8Bytes(
      ' Name , Phone \nA,+8801700000001\n',
    ));
    expect(parsed.rows.single.name, 'A');
    expect(parsed.rows.single.phone, '+8801700000001');
  });

  test('normalizes CRLF and a leading BOM before parsing', () {
    final withBom = <int>[0xEF, 0xBB, 0xBF, ...utf8Bytes(
      'name,phone\r\nA,+8801700000001\r\n',
    )];
    final parsed = parseImportCsv(withBom);
    expect(parsed.rows.single.name, 'A');
    expect(parsed.rows.single.rowId, 'row-1',
        reason: 'a BOM or CRLF must not shift/blank the first row');
  });

  test('a missing required column is IMPORT_FILE_INVALID', () {
    expect(
      () => parseImportCsv(utf8Bytes('name,territory\nA,North\n')),
      throwsA(isA<ApiException>().having(
          (e) => e.code, 'code', ApiErrorCode.importFileInvalid)),
    );
  });

  test('a header-only file (zero data rows) is IMPORT_FILE_INVALID', () {
    expect(
      () => parseImportCsv(utf8Bytes('name,phone\n')),
      throwsA(isA<ApiException>().having(
          (e) => e.code, 'code', ApiErrorCode.importFileInvalid)),
    );
  });

  test('non-UTF-8 bytes are IMPORT_FILE_INVALID, not an uncaught error', () {
    expect(
      () => parseImportCsv(<int>[0xFF, 0xFE, 0x00]),
      throwsA(isA<ApiException>().having(
          (e) => e.code, 'code', ApiErrorCode.importFileInvalid)),
    );
  });

  test('over the 2 MB cap is IMPORT_FILE_INVALID', () {
    final big = utf8Bytes('name,phone\n' +
        List.filled(200000, 'A,+8801700000001').join('\n'));
    expect(big.length, greaterThan(2 * 1024 * 1024));
    expect(
      () => parseImportCsv(big),
      throwsA(isA<ApiException>().having(
          (e) => e.code, 'code', ApiErrorCode.importFileInvalid)),
    );
  });

  test('a row missing name or phone still parses (classified ERROR later), '
      'never throws', () {
    final parsed = parseImportCsv(utf8Bytes('name,phone\n,\nB,\n'));
    expect(parsed.rows, hasLength(2));
    expect(parsed.rows[0].name, '');
    expect(parsed.rows[1].phone, '');
  });
}
```

- [ ] **Step 2: Run — confirm failure**

```bash
cd server && dart test test/import_/import_file_test.dart
```

Expected: FAIL — `import_file.dart` does not exist.

- [ ] **Step 3: Implement the parser**

`server/lib/src/import_/import_file.dart`:

```dart
import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:csv/csv.dart';

import '../infra/error_envelope.dart';

/// One parsed CSV data row. The row itself is not yet classified — that is
/// the DB-aware step in ImportRepo. Raw phone/nid are held here and never
/// serialized (2a.D2).
class ParsedRow {
  const ParsedRow({
    required this.rowId,
    required this.name,
    required this.phone,
    this.nid,
    this.territory,
    this.dealerContext,
  });

  final String rowId;
  final String name;
  final String phone;
  final String? nid;
  final String? territory;
  final String? dealerContext;
}

class ParsedImport {
  const ParsedImport(this.rows);
  final List<ParsedRow> rows;
}

const int _maxBytes = 2 * 1024 * 1024; // 2 MB (§6a)
const List<String> _required = ['name', 'phone'];

/// Parses and validates the uploaded CSV bytes. Pure: no IO, no DB. Throws
/// [ApiException] `IMPORT_FILE_INVALID` (422) for any content-level problem so
/// the route answers a specific, safe error and no job is created (2b.D5's
/// "unsafe file" acceptance criterion, pragmatic sense).
ParsedImport parseImportCsv(List<int> bytes) {
  if (bytes.length > _maxBytes) {
    _invalid('File exceeds the 2 MB limit.');
  }
  // Strip a leading UTF-8 BOM, then decode strictly — non-UTF-8 is a content
  // error, not a 500 (§6a).
  final withoutBom = (bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF)
      ? bytes.sublist(3)
      : bytes;
  String text;
  try {
    text = utf8.decode(withoutBom);
  } on FormatException {
    _invalid('File is not valid UTF-8 text.');
  }
  // csv's default eol is \r\n; normalize so a \n-only file parses (§6a).
  final normalized = text.replaceAll('\r\n', '\n');

  final table = const CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false,
  ).convert(normalized);

  if (table.isEmpty) _invalid('File is empty.');

  final header = table.first
      .map((c) => (c as String).trim().toLowerCase())
      .toList();
  final index = <String, int>{for (var i = 0; i < header.length; i++) header[i]: i};
  for (final col in _required) {
    if (!index.containsKey(col)) {
      _invalid('Missing required column "$col".');
    }
  }
  if (table.length < 2) {
    _invalid('File has a header but no data rows.');
  }

  String cell(List<Object?> r, String col) {
    final i = index[col];
    if (i == null || i >= r.length) return '';
    return (r[i] as String).trim();
  }

  String? optional(List<Object?> r, String col) {
    if (!index.containsKey(col)) return null;
    final v = cell(r, col);
    return v.isEmpty ? null : v;
  }

  final rows = <ParsedRow>[];
  for (var i = 1; i < table.length; i++) {
    final r = table[i];
    rows.add(ParsedRow(
      rowId: 'row-$i', // 1-based data line (2b.D4)
      name: cell(r, 'name'),
      phone: cell(r, 'phone'),
      nid: optional(r, 'nid'),
      territory: optional(r, 'territory'),
      dealerContext: optional(r, 'dealer_context'),
    ));
  }
  return ParsedImport(rows);
}

Never _invalid(String message) => throw ApiException(
  ApiErrorCode.importFileInvalid,
  message: message,
);
```

- [ ] **Step 4: Tests pass; format; analyze; commit**

```bash
cd server && dart test test/import_/import_file_test.dart && dart format --set-exit-if-changed . && dart analyze --fatal-infos
git add server/lib/src/import_/import_file.dart server/test/import_/import_file_test.dart
git commit -m "feat(server): pure CSV import parser + validator

Pure (no IO/DB) so the parse/validate rules are unit-testable without
Postgres. Strips a BOM and normalizes CRLF before csv's converter (whose
default eol is CRLF, §6a); rejects non-UTF-8, oversize, missing required
columns, and header-only files as IMPORT_FILE_INVALID (422) rather than
letting them reach the envelope as a 500. row_id is the 1-based data line."
```

---

### Task 4: Extract the provisional-carpenter tx helper

**Files:**
- Modify: `server/lib/src/participant/participant_repo.dart`

**Interfaces:**
- Produces: `Future<CarpenterView> ParticipantRepo.insertProvisionalCarpenterTx(TxSession tx, {required String organizationId, required String name, required String phone})` — the carpenter-INSERT half of `createProfileRequest`, callable inside an existing transaction. `createProfileRequest` is refactored to call it; behavior unchanged.
- Consumes: existing `_view`, `_uuid`.

**Why this task exists.** 2b's commit registers valid + needsProfile rows in ONE transaction (2b.D5). `createProfileRequest` opens its own tx, so it cannot be called per-row inside the commit's single tx. Extracting the INSERT lets both callers share it instead of duplicating the SQL (a review-flag otherwise).

- [ ] **Step 1: Add a characterization assertion to the existing repo test**

`server/test/participant/participant_repo_test.dart` already tests `createProfileRequest`. Confirm the existing test still asserts the provisional carpenter's `source`/`sync_status` (`PROFILE_REQUEST`/`PENDING_PROFILE_SYNC`). If it does not assert `source`, add one line to the existing createProfileRequest test:

```dart
      final stored = await db.execute(
        'SELECT source, sync_status FROM carpenters WHERE id = @id',
        params: {'id': carpenter.id},
      );
      expect(row(stored.single)['source'], 'PROFILE_REQUEST');
```

Run it — it must PASS now (characterizing current behavior before the refactor):

```bash
cd server && dart test test/participant/participant_repo_test.dart
```

- [ ] **Step 2: Extract the helper**

In `server/lib/src/participant/participant_repo.dart`, add a method (near `createProfileRequest`):

```dart
  /// The provisional-carpenter INSERT, callable inside a caller's own
  /// transaction. Both `createProfileRequest` (its own tx) and the bulk-import
  /// commit (one tx across many rows, 2b.D5) use this rather than duplicating
  /// the SQL. Source PROFILE_REQUEST / sync PENDING_PROFILE_SYNC, display_code
  /// from the shared sequence.
  Future<CarpenterView> insertProvisionalCarpenterTx(
    TxSession tx, {
    required String organizationId,
    required String name,
    required String phone,
  }) async {
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
        'id': _uuid.v4(),
        'org': organizationId,
        'name': name,
        'phone': phone,
      },
    );
    return _view(row(inserted.single));
  }
```

Then in `createProfileRequest`, replace the inline carpenter INSERT (the `final inserted = await tx.execute(... INSERT INTO carpenters ...)` block and the following `view = _view(row(inserted.single));`) with:

```dart
      view = await insertProvisionalCarpenterTx(
        tx,
        organizationId: organizationId,
        name: name,
        phone: phone,
      );
      final carpenterId = view.id;
```

and update the subsequent `profile_requests` INSERT to use `carpenterId` (it currently references the locally-generated `carpenterId` — now sourced from `view.id`). Remove the now-unused local `carpenterId = _uuid.v4();` line at the top of the method (the id now comes from the helper's RETURNING).

- [ ] **Step 3: Run the participant suite — behavior unchanged**

```bash
cd server && dart test test/participant/
```

Expected: all pass (the createProfileRequest tests are the safety net — a true extraction changes nothing observable).

- [ ] **Step 4: Format, analyze, full suite, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server && git commit -m "refactor(server): extract insertProvisionalCarpenterTx for reuse

The provisional-carpenter INSERT is now a tx-aware helper both
createProfileRequest and (next) the bulk-import commit call, so 2b's
single-transaction commit reuses it instead of copying the SQL. Pure
extraction; the participant suite is the unchanged-behavior net."
```

---

### Task 5: `ImportRepo` — job creation, classification, reaper

**Files:**
- Create: `server/lib/src/import_/import_repo.dart`
- Create: `server/test/import_/import_repo_test.dart`

**Interfaces:**
- Consumes: `Db`/`row`/`Db.tx`; `ParsedImport`/`ParsedRow` (Task 3); `AuditWriter`; `ParticipantRepo.insertProvisionalCarpenterTx` (Task 4); `ImportStatus`/`ImportRowOutcome` (Task 1).
- Produces (Task 6 & 7 build on these exactly):
  - `class ImportRowView { final String rowId; final String name; final String? outcome; final String? message; final String? linkedCarpenterId; Map<String, Object?> toWireJson(); }`
  - `class ImportJobView { final String id; final String campaignId; final String status; final int totalRows; final int processedRows; final List<ImportRowView> rows; Map<String, Object?> toWireJson(); }`
  - `class ImportRepo { ImportRepo(Db db); Future<ImportJobView?> createJob({required String campaignId, required String organizationId, required ParsedImport parsed, required String filename, required String fileHash, required String uploadedBy}); Future<void> classify(String jobId); Future<int> reapStale(); Future<ImportJobView?> find(String jobId, {required String organizationId}); Future<ImportJobView?> commit({required String campaignId, required String organizationId, required String jobId, required String committedBy, String? correlationId}); }`
  - `createJob` returns `null` when the campaign is not visible in the org (route → 404). Otherwise inserts the job (`PROCESSING`, `claimed_at = now()`) + rows (`outcome` NULL) in one tx and returns the job.
  - `classify(jobId)` is the background-task body: matches each row against the carpenter master, writes `outcome`/`message`/`linked_carpenter_id`, bumps `processed_rows`, flips to `READY_TO_COMMIT`; on any fault flips to `FAILED` (it swallows internally so the caller's `unawaited` never sees an error).
  - `reapStale()` flips `PROCESSING` jobs older than 5 min to `FAILED`; returns the count.
  - `commit` is Task 6.

- [ ] **Step 1: Write the failing classification + reaper tests**

`server/test/import_/import_repo_test.dart` (classification + reaper portions; commit tests come in Task 6):

```dart
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/import_/import_file.dart';
import 'package:campaign_service/src/import_/import_repo.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

ParsedImport parsedOf(List<ParsedRow> rows) => ParsedImport(rows);

void main() {
  late Db db;
  late ImportRepo repo;

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // org-1 / user-1 / campaign_creator
    await seedCampaign(db, id: 'camp-1');
    repo = ImportRepo(db);
  });
  tearDown(() async => db.close());

  ParsedRow r(String id, String name, String phone) =>
      ParsedRow(rowId: id, name: name, phone: phone);

  test('createJob returns null for a cross-org campaign (route → 404)',
      () async {
    await seedOrganizationWithUser(db,
        orgId: 'org-2', territoryId: 't2', userId: 'u2', username: 'other');
    await seedCampaign(db, id: 'camp-2', organizationId: 'org-2', ownerId: 'u2');
    final result = await repo.createJob(
      campaignId: 'camp-2',
      organizationId: 'org-1',
      parsed: parsedOf([r('row-1', 'A', '+8801700000001')]),
      filename: 'x.csv',
      fileHash: 'h',
      uploadedBy: 'user-1',
    );
    expect(result, isNull);
  });

  test('createJob stores a PROCESSING job with rows unclassified', () async {
    final job = await repo.createJob(
      campaignId: 'camp-1',
      organizationId: 'org-1',
      parsed: parsedOf([
        r('row-1', 'Md. Karim', '+8801700004821'),
        r('row-2', 'New Person', '+8801711112222'),
      ]),
      filename: 'x.csv',
      fileHash: 'h',
      uploadedBy: 'user-1',
    );
    expect(job!.status, 'PROCESSING');
    expect(job.totalRows, 2);
    expect(job.rows.every((row) => row.outcome == null), isTrue);
  });

  test('classify assigns each of the four produced outcomes correctly',
      () async {
    // A master carpenter that a row will match (VALID), and a registration
    // that makes another row DUPLICATE.
    await seedCarpenter(db, id: 'c-1', phone: '+8801700004821',
        displayCode: 'CARP-00004821'); // Md. Karim (default name)
    await seedCarpenter(db, id: 'c-dup', name: 'Already Reg',
        phone: '+8801700009999', displayCode: 'CARP-00009999');
    await seedRegistration(db, campaignId: 'camp-1', carpenterId: 'c-dup');

    final job = await repo.createJob(
      campaignId: 'camp-1',
      organizationId: 'org-1',
      parsed: parsedOf([
        r('row-1', 'Md. Karim', '+8801700004821'),   // matches c-1 → VALID
        r('row-2', 'Already Reg', '+8801700009999'),  // c-dup registered → DUPLICATE
        r('row-3', 'Brand New', '+8801733334444'),     // no match → NEEDS_PROFILE
        r('row-4', '', ''),                             // malformed → ERROR
      ]),
      filename: 'x.csv',
      fileHash: 'h',
      uploadedBy: 'user-1',
    );

    await repo.classify(job!.id);

    final done = await repo.find(job.id, organizationId: 'org-1');
    expect(done!.status, 'READY_TO_COMMIT');
    expect(done.processedRows, 4);
    final byRow = {for (final row in done.rows) row.rowId: row.outcome};
    expect(byRow['row-1'], 'VALID');
    expect(byRow['row-2'], 'DUPLICATE');
    expect(byRow['row-3'], 'NEEDS_PROFILE');
    expect(byRow['row-4'], 'ERROR');
    // VALID row is linked to the matched carpenter.
    final valid = done.rows.firstWhere((row) => row.rowId == 'row-1');
    expect(valid.linkedCarpenterId, 'c-1');
  });

  test('classify never emits raw phone in a row message or wire JSON',
      () async {
    final job = await repo.createJob(
      campaignId: 'camp-1',
      organizationId: 'org-1',
      parsed: parsedOf([r('row-1', 'X', 'not-a-phone')]),
      filename: 'x.csv',
      fileHash: 'h',
      uploadedBy: 'user-1',
    );
    await repo.classify(job!.id);
    final done = await repo.find(job.id, organizationId: 'org-1');
    expect(jsonEncodeSafe(done!), isNot(contains('not-a-phone')));
  });

  test('reapStale fails a PROCESSING job older than the TTL', () async {
    await seedImportJob(db, id: 'stale', status: 'PROCESSING', rows: const []);
    // Age its claimed_at past the 5-minute TTL.
    await db.execute(
      "UPDATE import_jobs SET claimed_at = now() - interval '6 minutes' "
      "WHERE id = 'stale'",
    );
    final reaped = await repo.reapStale();
    expect(reaped, greaterThanOrEqualTo(1));
    final job = await repo.find('stale', organizationId: 'org-1');
    expect(job!.status, 'FAILED');
  });

  test('reapStale leaves a fresh PROCESSING job alone', () async {
    await seedImportJob(db, id: 'fresh', status: 'PROCESSING', rows: const []);
    await repo.reapStale();
    final job = await repo.find('fresh', organizationId: 'org-1');
    expect(job!.status, 'PROCESSING');
  });
}

/// jsonEncode over the job's wire JSON — a tiny local helper so the PII
/// assertion reads the actual serialized surface.
String jsonEncodeSafe(ImportJobView j) => jsonEncode(j.toWireJson());
```

Add `import 'dart:convert';` at the top of the test file for `jsonEncode`.

- [ ] **Step 2: Run — confirm failure**

```bash
cd server && docker compose ps >/dev/null 2>&1; dart test test/import_/import_repo_test.dart
```

Expected: FAIL — `import_repo.dart` does not exist.

- [ ] **Step 3: Implement `ImportRepo` (createJob, classify, reaper, find, views)**

`server/lib/src/import_/import_repo.dart`:

```dart
import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:uuid/uuid.dart';

import '../db/pool.dart';
import '../infra/audit.dart';
import 'import_file.dart';

const Uuid _uuid = Uuid();
const Duration _staleTtl = Duration(minutes: 5); // 2b.D2

/// A row as the API presents it. Never carries raw phone/nid (2a.D2) — only
/// the classification and, when linked, the carpenter id (itself already
/// masked at read time via the join in [ImportRepo.find]).
class ImportRowView {
  const ImportRowView({
    required this.rowId,
    required this.name,
    required this.outcome,
    required this.message,
    required this.linkedCarpenterId,
  });

  final String rowId;
  final String name;
  final String? outcome;
  final String? message;
  final String? linkedCarpenterId;

  Map<String, Object?> toWireJson() => {
    'rowId': rowId,
    'name': name,
    'outcome': outcome,
    'message': message,
    'linkedCarpenterId': linkedCarpenterId,
  };
}

class ImportJobView {
  const ImportJobView({
    required this.id,
    required this.campaignId,
    required this.status,
    required this.totalRows,
    required this.processedRows,
    required this.rows,
  });

  final String id;
  final String campaignId;
  final String status;
  final int totalRows;
  final int processedRows;
  final List<ImportRowView> rows;

  Map<String, Object?> toWireJson() => {
    'id': id,
    'campaignId': campaignId,
    'status': status,
    'totalRows': totalRows,
    'processedRows': processedRows,
    'rows': [for (final r in rows) r.toWireJson()],
  };
}

/// Owns all import SQL. Every query is org-scoped inside the SQL (D7); raw
/// phone/nid never reach a view (2a.D2).
class ImportRepo {
  ImportRepo(this._db) : _audit = AuditWriter(_db);

  final Db _db;
  final AuditWriter _audit;

  Future<ImportJobView?> createJob({
    required String campaignId,
    required String organizationId,
    required ParsedImport parsed,
    required String filename,
    required String fileHash,
    required String uploadedBy,
  }) async {
    final campaign = await _db.execute(
      'SELECT 1 FROM campaigns WHERE id = @id AND organization_id = @org',
      params: {'id': campaignId, 'org': organizationId},
    );
    if (campaign.isEmpty) return null;

    final jobId = _uuid.v4();
    await _db.tx((tx) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO import_jobs '
          '(id, campaign_id, organization_id, status, filename, file_hash, '
          ' total_rows, processed_rows, uploaded_by, claimed_at) '
          "VALUES (@id, @c, @org, 'PROCESSING', @f, @h, @n, 0, @by, now())",
        ),
        parameters: {
          'id': jobId,
          'c': campaignId,
          'org': organizationId,
          'f': filename,
          'h': fileHash,
          'n': parsed.rows.length,
          'by': uploadedBy,
        },
      );
      for (final r in parsed.rows) {
        await tx.execute(
          Sql.named(
            'INSERT INTO import_job_rows '
            '(job_id, row_id, name, phone, nid, territory_hint, dealer_context) '
            'VALUES (@j, @r, @name, @phone, @nid, @terr, @dealer)',
          ),
          parameters: {
            'j': jobId,
            'r': r.rowId,
            'name': r.name,
            'phone': r.phone,
            'nid': r.nid,
            'terr': r.territory,
            'dealer': r.dealerContext,
          },
        );
      }
    });
    return find(jobId, organizationId: organizationId);
  }

  /// Background-task body (2b.D1). Classifies each row, then flips to
  /// READY_TO_COMMIT. Swallows its own faults into a FAILED flip so the
  /// caller's `unawaited(...)` never sees an unhandled error (§6a: an
  /// unhandled future error kills the process).
  Future<void> classify(String jobId) async {
    try {
      final job = await _jobRow(jobId);
      if (job == null) return;
      final orgId = job['organization_id']! as String;
      final campaignId = job['campaign_id']! as String;

      final rows = await _db.execute(
        'SELECT row_id, name, phone FROM import_job_rows '
        'WHERE job_id = @j ORDER BY row_id',
        params: {'j': jobId},
      );

      final seenPhones = <String>{};
      var processed = 0;
      for (final rr in rows.map(row)) {
        final rowId = rr['row_id']! as String;
        final name = rr['name']! as String;
        final phone = rr['phone']! as String;

        final (outcome, message, linked) = await _classifyRow(
          organizationId: orgId,
          campaignId: campaignId,
          name: name,
          phone: phone,
          seenPhones: seenPhones,
        );

        await _db.execute(
          'UPDATE import_job_rows SET outcome = @o, message = @m, '
          '  linked_carpenter_id = @l '
          'WHERE job_id = @j AND row_id = @r',
          params: {
            'o': outcome.wireValue,
            'm': message,
            'l': linked,
            'j': jobId,
            'r': rowId,
          },
        );
        processed++;
        await _db.execute(
          'UPDATE import_jobs SET processed_rows = @p, updated_at = now() '
          'WHERE id = @j',
          params: {'p': processed, 'j': jobId},
        );
      }

      await _db.execute(
        "UPDATE import_jobs SET status = 'READY_TO_COMMIT', updated_at = now() "
        'WHERE id = @j',
        params: {'j': jobId},
      );
      await _audit.write(
        action: 'import.dry_run',
        resourceType: 'import_job',
        resourceId: jobId,
        payload: {'totalRows': rows.length, 'processed': processed},
      );
    } on Object catch (error, stack) {
      // Never let this reach the top level (§6a). Flip to FAILED and log.
      // ignore: avoid_print — stderr is the server's log surface here.
      await _failJob(jobId, error, stack);
    }
  }

  Future<(ImportRowOutcome, String?, String?)> _classifyRow({
    required String organizationId,
    required String campaignId,
    required String name,
    required String phone,
    required Set<String> seenPhones,
  }) async {
    final phoneOk = RegExp(r'^\+?\d{8,15}$')
        .hasMatch(phone.replaceAll(RegExp(r'[ -]'), ''));
    if (name.trim().isEmpty || !phoneOk) {
      return (ImportRowOutcome.error, 'Row is missing a valid name or phone.',
          null);
    }
    if (!seenPhones.add(phone)) {
      return (ImportRowOutcome.duplicate, 'Duplicated within this file.', null);
    }

    // Exact-phone match against the org's master.
    final match = await _db.execute(
      'SELECT id FROM carpenters '
      'WHERE organization_id = @org AND phone = @phone LIMIT 1',
      params: {'org': organizationId, 'phone': phone},
    );
    if (match.isEmpty) {
      return (ImportRowOutcome.needsProfile,
          'No master match — a new profile will be created on commit.', null);
    }
    final carpenterId = row(match.single)['id']! as String;

    final already = await _db.execute(
      'SELECT 1 FROM registrations '
      'WHERE campaign_id = @c AND carpenter_id = @id',
      params: {'c': campaignId, 'id': carpenterId},
    );
    if (already.isNotEmpty) {
      return (ImportRowOutcome.duplicate, 'Already registered to this campaign.',
          carpenterId);
    }
    return (ImportRowOutcome.valid, null, carpenterId);
  }

  Future<int> reapStale() async {
    final res = await _db.execute(
      "UPDATE import_jobs SET status = 'FAILED', updated_at = now() "
      "WHERE status = 'PROCESSING' AND claimed_at <= @cutoff",
      params: {
        'cutoff': DateTime.now().toUtc().subtract(_staleTtl),
      },
    );
    return res.affectedRows;
  }

  Future<ImportJobView?> find(
    String jobId, {
    required String organizationId,
  }) async {
    final jobs = await _db.execute(
      'SELECT id, campaign_id, status, total_rows, processed_rows '
      'FROM import_jobs WHERE id = @j AND organization_id = @org',
      params: {'j': jobId, 'org': organizationId},
    );
    if (jobs.isEmpty) return null;
    final j = row(jobs.single);

    final rows = await _db.execute(
      'SELECT row_id, name, outcome, message, linked_carpenter_id '
      'FROM import_job_rows WHERE job_id = @j ORDER BY row_id',
      params: {'j': jobId},
    );
    return ImportJobView(
      id: j['id']! as String,
      campaignId: j['campaign_id']! as String,
      status: j['status']! as String,
      totalRows: j['total_rows']! as int,
      processedRows: j['processed_rows']! as int,
      rows: [
        for (final rr in rows.map(row))
          ImportRowView(
            rowId: rr['row_id']! as String,
            name: rr['name']! as String,
            outcome: rr['outcome'] as String?,
            message: rr['message'] as String?,
            linkedCarpenterId: rr['linked_carpenter_id'] as String?,
          ),
      ],
    );
  }

  Future<Map<String, Object?>?> _jobRow(String jobId) async {
    final res = await _db.execute(
      'SELECT organization_id, campaign_id FROM import_jobs WHERE id = @j',
      params: {'j': jobId},
    );
    return res.isEmpty ? null : row(res.single);
  }

  Future<void> _failJob(String jobId, Object error, StackTrace stack) async {
    try {
      await _db.execute(
        "UPDATE import_jobs SET status = 'FAILED', updated_at = now() "
        'WHERE id = @j',
        params: {'j': jobId},
      );
    } on Object {
      // If even the FAILED flip fails, there is nothing more to do here; the
      // reaper will catch the still-PROCESSING job by TTL.
    }
  }
}
```

Note the `avoid_print`/stderr detail: if `server/analysis_options.yaml` has `avoid_print`, do NOT add a `print`; the `_failJob` path is silent by design (the reaper is the backstop, and slice-1 deferred "log the swallowed sweep failure" as a minor). If you want a log line, use `stderr.writeln` with `import 'dart:io'`.

- [ ] **Step 4: Run the classification + reaper tests — must pass**

```bash
cd server && dart test test/import_/import_repo_test.dart
```

Expected: the createJob/classify/reaper tests pass (commit tests are added in Task 6).

- [ ] **Step 5: Prove classify's FAILED path is real**

Add one test that a job whose row references a dropped table can't classify — simpler: temporarily rename `carpenters` in a scratch run is overkill. Instead assert the swallow contract directly: call `classify('does-not-exist')` and confirm it returns without throwing (the `_jobRow == null` early return), then that a genuine mid-classify fault flips FAILED — force it by seeding a job row whose `name` is fine but stubbing is hard. Minimum bar: the "returns without throwing for an unknown job id" assertion:

```dart
  test('classify of an unknown job id is a no-op, never throws', () async {
    await repo.classify('nope'); // must not throw
  });
```

Add it, run, commit.

- [ ] **Step 6: Format, analyze, full suite, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server/lib/src/import_/import_repo.dart server/test/import_/import_repo_test.dart
git commit -m "feat(server): ImportRepo — durable job, row classification, stale-job reaper

createJob stores a PROCESSING job + unclassified rows (org-scoped, 404 for a
cross-org campaign). classify is the background-task body: exact-phone match
against the org master → VALID/DUPLICATE/NEEDS_PROFILE/ERROR (WARNING is 2c),
bumps processed_rows, flips READY_TO_COMMIT; it swallows its own faults into a
FAILED flip so the caller's unawaited never sees an unhandled error that would
kill the process (§6a). reapStale fails PROCESSING jobs past the 5-min TTL
(2b.D2). Raw phone never reaches a view (2a.D2)."
```

---

### Task 6: `ImportRepo.commit`

**Files:**
- Modify: `server/lib/src/import_/import_repo.dart`
- Modify: `server/test/import_/import_repo_test.dart`

**Interfaces:**
- Consumes: `ParticipantRepo.insertProvisionalCarpenterTx` (Task 4).
- Produces: `Future<ImportJobView?> commit(...)` — see Task 5's interface block. Returns `null` for a cross-org campaign/job (404). Throws `ApiException(conflictStaleVersion)`... no — throws `ApiException(campaignInvalidTransition)`? Use a dedicated shape: the route returns **409** when the job is not `READY_TO_COMMIT`. Implement by returning a sentinel the route maps, OR throw `ApiException(ApiErrorCode.conflictStaleVersion)` (409). Decision: throw `ApiException(ApiErrorCode.conflictStaleVersion, message: 'Import job is not ready to commit.')` — reuses the existing 409 code; no new vocabulary.

- [ ] **Step 1: Write the failing commit tests**

Append to `server/test/import_/import_repo_test.dart`:

```dart
  group('commit', () {
    setUp(() async {
      await seedCarpenter(db, id: 'c-1', phone: '+8801700004821',
          displayCode: 'CARP-00004821');
    });

    Future<ImportJobView> readyJob() async {
      final job = await repo.createJob(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        parsed: parsedOf([
          r('row-1', 'Md. Karim', '+8801700004821'),  // VALID (matches c-1)
          r('row-2', 'Brand New', '+8801733334444'),   // NEEDS_PROFILE
          r('row-3', '', ''),                            // ERROR (not committable)
        ]),
        filename: 'x.csv',
        fileHash: 'h',
        uploadedBy: 'user-1',
      );
      await repo.classify(job!.id);
      return (await repo.find(job.id, organizationId: 'org-1'))!;
    }

    test('registers the committable set (valid + needsProfile) and completes',
        () async {
      final job = await readyJob();
      final done = await repo.commit(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        jobId: job.id,
        committedBy: 'user-1',
      );
      expect(done!.status, 'COMPLETED');

      // c-1 registered; a provisional carpenter created + registered for row-2.
      final regs = await db.execute(
        'SELECT carpenter_id FROM registrations WHERE campaign_id = @c',
        params: {'c': 'camp-1'},
      );
      expect(regs, hasLength(2));
      final provisional = await db.execute(
        "SELECT 1 FROM carpenters WHERE source = 'PROFILE_REQUEST' "
        "AND full_name = 'Brand New'",
      );
      expect(provisional, hasLength(1));
    });

    test('a replayed commit registers each row at most once (idempotent set)',
        () async {
      final job = await readyJob();
      await repo.commit(
        campaignId: 'camp-1', organizationId: 'org-1',
        jobId: job.id, committedBy: 'user-1');
      // The job is COMPLETED now, so a second commit is a 409 at the route;
      // at the repo level, re-committing a COMPLETED job is a no-op guarded by
      // the status check.
      expect(
        () => repo.commit(
          campaignId: 'camp-1', organizationId: 'org-1',
          jobId: job.id, committedBy: 'user-1'),
        throwsA(isA<Object>()),
      );
      final regs = await db.execute(
        'SELECT 1 FROM registrations WHERE campaign_id = @c',
        params: {'c': 'camp-1'});
      expect(regs, hasLength(2), reason: 'no duplicate registrations');
    });

    test('commit of a not-ready job throws (route → 409)', () async {
      await seedImportJob(db, id: 'proc', status: 'PROCESSING', rows: const []);
      expect(
        () => repo.commit(
          campaignId: 'camp-1', organizationId: 'org-1',
          jobId: 'proc', committedBy: 'user-1'),
        throwsA(isA<Object>()),
      );
    });

    test('commit of a cross-org job is null (route → 404)', () async {
      final job = await readyJob();
      final result = await repo.commit(
        campaignId: 'camp-1', organizationId: 'org-2',
        jobId: job.id, committedBy: 'user-1');
      expect(result, isNull);
    });
  });
```

- [ ] **Step 2: Run — confirm failure**

```bash
cd server && dart test test/import_/import_repo_test.dart -n commit
```

Expected: FAIL — `commit` not defined.

- [ ] **Step 3: Implement `commit`**

Add to `ImportRepo` (needs a `ParticipantRepo` for the provisional helper — construct one from the same `Db`):

```dart
import '../participant/participant_repo.dart';
```

and in the class:

```dart
  /// Registers the committable set (VALID + NEEDS_PROFILE, 2b.D5) in ONE
  /// transaction: any row failing rolls it all back. NEEDS_PROFILE rows create
  /// a provisional carpenter via the shared tx helper, then register. Returns
  /// null for a cross-org campaign/job (route → 404); throws 409 when the job
  /// is not READY_TO_COMMIT.
  Future<ImportJobView?> commit({
    required String campaignId,
    required String organizationId,
    required String jobId,
    required String committedBy,
    String? correlationId,
  }) async {
    final jobs = await _db.execute(
      'SELECT status FROM import_jobs '
      'WHERE id = @j AND campaign_id = @c AND organization_id = @org',
      params: {'j': jobId, 'c': campaignId, 'org': organizationId},
    );
    if (jobs.isEmpty) return null; // 404
    final status = row(jobs.single)['status']! as String;
    if (status != ImportStatus.readyToCommit.wireValue) {
      throw ApiException(
        ApiErrorCode.conflictStaleVersion,
        message: 'Import job is not ready to commit.',
      );
    }

    final participants = ParticipantRepo(_db);
    await _db.tx((tx) async {
      final committable = await tx.execute(
        Sql.named(
          'SELECT row_id, name, phone, outcome, linked_carpenter_id '
          'FROM import_job_rows '
          "WHERE job_id = @j AND outcome IN ('VALID', 'NEEDS_PROFILE') "
          'ORDER BY row_id',
        ),
        parameters: {'j': jobId},
      );

      for (final rr in committable.map(row)) {
        final outcome = rr['outcome']! as String;
        String carpenterId;
        if (outcome == ImportRowOutcome.needsProfile.wireValue) {
          final view = await participants.insertProvisionalCarpenterTx(
            tx,
            organizationId: organizationId,
            name: rr['name']! as String,
            phone: rr['phone']! as String,
          );
          carpenterId = view.id;
        } else {
          carpenterId = rr['linked_carpenter_id']! as String;
        }

        await tx.execute(
          Sql.named(
            'INSERT INTO registrations '
            '(campaign_id, carpenter_id, status, registered_by) '
            "SELECT @c, @id, "
            "  CASE WHEN sync_status = 'PENDING_PROFILE_SYNC' "
            "       THEN 'PENDING_PROFILE_SYNC' ELSE 'REGISTERED' END, @by "
            'FROM carpenters WHERE id = @id AND organization_id = @org '
            'ON CONFLICT (campaign_id, carpenter_id) DO NOTHING',
          ),
          parameters: {
            'c': campaignId,
            'id': carpenterId,
            'org': organizationId,
            'by': committedBy,
          },
        );
        await tx.execute(
          Sql.named('UPDATE import_job_rows SET linked_carpenter_id = @id '
              'WHERE job_id = @j AND row_id = @r'),
          parameters: {'id': carpenterId, 'j': jobId, 'r': rr['row_id']},
        );
      }

      await tx.execute(
        Sql.named("UPDATE import_jobs SET status = 'COMPLETED', "
            'updated_at = now() WHERE id = @j'),
        parameters: {'j': jobId},
      );
      await _audit.writeTx(
        tx,
        action: 'import.commit',
        resourceType: 'import_job',
        resourceId: jobId,
        actorId: committedBy,
        correlationId: correlationId,
        payload: {'committed': committable.length},
      );
    });

    return find(jobId, organizationId: organizationId);
  }
```

- [ ] **Step 4: Commit tests pass; format; analyze; full suite; commit**

```bash
cd server && dart test test/import_/import_repo_test.dart && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server/lib/src/import_/import_repo.dart server/test/import_/import_repo_test.dart
git commit -m "feat(server): ImportRepo.commit — idempotent committable-set registration

Registers VALID + NEEDS_PROFILE rows in one transaction (2b.D5): NEEDS_PROFILE
creates a provisional carpenter via the shared tx helper then registers, VALID
uses its matched id; ON CONFLICT DO NOTHING makes a replay register each row at
most once. Returns null cross-org (404), throws 409 when the job is not
READY_TO_COMMIT. Org predicate lives in the write SQL (D7)."
```

---

# Phase 3 — Routes, composition, seed

### Task 7: Import routes + background task + composition

**Files:**
- Create: `server/lib/src/import_/import_routes.dart`
- Modify: `server/lib/src/app.dart`
- Create: `server/test/import_/import_routes_test.dart`
- Modify: `server/test/app_test.dart` (401 gate for an import path)

**Interfaces:**
- Consumes: `ImportRepo` (Tasks 5-6), `parseImportCsv` (Task 3), `shelf_multipart`, `requirePermission`/`authOf`/`authenticate`, `idempotency`, `correlationOf`, `ApiException`.
- Produces: `Router importRouter({required Db db, required String databaseUrl})` serving `POST /campaigns/<id>/imports/dry-run`, `GET /imports/<jobId>`, `POST /campaigns/<id>/imports/<jobId>/commit`. `databaseUrl` is needed so the background task can open its OWN connection (2b.D1).

- [ ] **Step 1: Write the failing route tests (real buildApp tree)**

`server/test/import_/import_routes_test.dart`:

```dart
import 'dart:convert';

import 'package:campaign_service/src/app.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late Handler handler;
  late String creatorToken; // has bulk_import
  late String viewerToken;  // reporting_viewer, no bulk_import
  var seq = 0;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // user-1 campaign_creator (bulk_import)
    await seedOrganizationWithUser(db,
        userId: 'user-2', username: 'viewer', roles: const ['reporting_viewer']);
    final tokens = TokenService(db: db, config: config);
    creatorToken = (await tokens.issueFor('user-1')).accessToken;
    viewerToken = (await tokens.issueFor('user-2')).accessToken;
    handler = buildApp(db: db, config: config);
    await seedCampaign(db, id: 'camp-1');
    await seedCarpenter(db, id: 'c-1', phone: '+8801700004821',
        displayCode: 'CARP-00004821');
  });
  tearDown(() async => db.close());

  String nextKey() => 'key-${seq++}';

  /// Builds a multipart/form-data body with a single `file` part.
  Request uploadRequest(String path, String csv, {String? bearer}) {
    const boundary = 'X-BOUNDARY';
    final body = '--$boundary\r\n'
        'content-disposition: form-data; name="file"; filename="import.csv"\r\n'
        'content-type: text/csv\r\n\r\n'
        '$csv\r\n'
        '--$boundary--\r\n';
    return Request('POST', Uri.parse('http://localhost$path'),
        headers: {
          if (bearer != null) 'authorization': 'Bearer $bearer',
          'content-type': 'multipart/form-data; boundary=$boundary',
        },
        body: body);
  }

  Future<Map<String, Object?>> decode(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  Future<Response> get(String path, {String? bearer}) => handler(Request(
      'GET', Uri.parse('http://localhost$path'),
      headers: {if (bearer != null) 'authorization': 'Bearer $bearer'}));

  test('unauthenticated dry-run is 401 through the real tree', () async {
    final res = await handler(
        uploadRequest('/campaigns/camp-1/imports/dry-run', 'name,phone\nA,+8801700000001\n'));
    expect(res.statusCode, 401);
  });

  test('403 without bulk_import', () async {
    final res = await handler(uploadRequest(
        '/campaigns/camp-1/imports/dry-run', 'name,phone\nA,+8801700000001\n',
        bearer: viewerToken));
    expect(res.statusCode, 403);
  });

  test('422 IMPORT_FILE_INVALID for a bad file, no job created', () async {
    final res = await handler(uploadRequest(
        '/campaigns/camp-1/imports/dry-run', 'name,territory\nA,North\n',
        bearer: creatorToken));
    expect(res.statusCode, 422);
    expect(((await decode(res))['error']! as Map)['code'], 'IMPORT_FILE_INVALID');
  });

  test('202 then poll reaches READY_TO_COMMIT with classified rows', () async {
    final res = await handler(uploadRequest(
        '/campaigns/camp-1/imports/dry-run',
        'name,phone\nMd. Karim,+8801700004821\nBrand New,+8801733334444\n',
        bearer: creatorToken));
    expect(res.statusCode, 202);
    final job = await decode(res);
    expect(job['status'], 'PROCESSING');
    final jobId = job['id']! as String;

    // Poll until terminal (the background task is fast; bound the loop).
    Map<String, Object?> polled = job;
    for (var i = 0; i < 50 && polled['status'] == 'PROCESSING'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      polled = await decode(await get('/imports/$jobId', bearer: creatorToken));
    }
    expect(polled['status'], 'READY_TO_COMMIT');
    final rows = (polled['rows']! as List).cast<Map<String, Object?>>();
    expect(rows.map((r) => r['outcome']).toSet(),
        containsAll(<String>['VALID', 'NEEDS_PROFILE']));
    expect(jsonEncode(polled), isNot(contains('+8801700004821')),
        reason: 'raw phone never on the wire (2a.D2)');
  });

  test('404 for a cross-org campaign on dry-run', () async {
    final res = await handler(uploadRequest(
        '/campaigns/not-mine/imports/dry-run', 'name,phone\nA,+8801700000001\n',
        bearer: creatorToken));
    expect(res.statusCode, 404);
  });

  test('commit registers the committable set and completes; replay is 409',
      () async {
    // Seed a ready job directly for a deterministic commit test.
    await seedImportJob(db, id: 'job-1', status: 'READY_TO_COMMIT', rows: [
      (rowId: 'row-1', name: 'Md. Karim', phone: '+8801700004821',
       outcome: 'VALID'),
    ]);
    // The VALID row needs its linked carpenter id set (seed helper leaves it
    // null); set it so commit uses the matched path.
    await db.execute(
      "UPDATE import_job_rows SET linked_carpenter_id = 'c-1' "
      "WHERE job_id = 'job-1' AND row_id = 'row-1'");

    final res = await handler(Request(
        'POST', Uri.parse('http://localhost/campaigns/camp-1/imports/job-1/commit'),
        headers: {
          'authorization': 'Bearer $creatorToken',
          'Idempotency-Key': nextKey(),
        }));
    expect(res.statusCode, 200);
    expect((await decode(res))['status'], 'COMPLETED');

    final replay = await handler(Request(
        'POST', Uri.parse('http://localhost/campaigns/camp-1/imports/job-1/commit'),
        headers: {
          'authorization': 'Bearer $creatorToken',
          'Idempotency-Key': nextKey(),
        }));
    expect(replay.statusCode, 409, reason: 'a COMPLETED job is not committable');
  });
}
```

- [ ] **Step 2: Run — confirm failure**

```bash
cd server && dart test test/import_/import_routes_test.dart
```

Expected: FAIL — routes not mounted (404s / no importRouter).

- [ ] **Step 3: Implement the routes + background task**

`server/lib/src/import_/import_routes.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/correlation.dart';
import '../infra/error_envelope.dart';
import '../infra/idempotency.dart';
import 'import_file.dart';
import 'import_repo.dart';

/// `/campaigns/<id>/imports/*` and `/imports/<jobId>`. Reads and writes all
/// require `bulk_import` (no read-only import role in the claim vocabulary).
///
/// [databaseUrl] lets the background classify task open its OWN Db connection
/// (2b.D1) — the request-serving connection must never be held for a classify.
Router importRouter({required Db db, required String databaseUrl}) {
  final router = Router();
  final repo = ImportRepo(db);

  router.post(
    '/campaigns/<id>/imports/dry-run',
    const Pipeline()
        .addMiddleware(requirePermission('bulk_import'))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final campaignId = request.params['id']!;

          // Opportunistic reaper on the write path (2b.D2), same shape as
          // idempotency's sweep.
          await repo.reapStale();

          final upload = await _readFilePart(request);
          if (upload == null) {
            throw ApiException(ApiErrorCode.badRequest,
                message: 'Expected a multipart "file" part.');
          }
          final parsed = parseImportCsv(upload.bytes); // throws 422 on bad file
          final fileHash = base64
              .encode(const DartSha256().hashSync(upload.bytes).bytes);

          final job = await repo.createJob(
            campaignId: campaignId,
            organizationId: auth.organizationId,
            parsed: parsed,
            filename: upload.filename ?? 'import.csv',
            fileHash: fileHash,
            uploadedBy: auth.userId,
          );
          if (job == null) throw ApiException(ApiErrorCode.notFound);

          // Fire-and-forget classify on its OWN connection (2b.D1). unawaited
          // satisfies the lint; the task swallows its own faults into a FAILED
          // flip (§6a), so no unhandled error can reach the top level.
          unawaited(_classifyInBackground(databaseUrl, job.id));

          return Response(202,
              body: jsonEncode(job.toWireJson()),
              headers: {'content-type': 'application/json'});
        }),
  );

  router.get('/imports/<jobId>', (Request request, String jobId) async {
    final auth = authOf(request);
    await repo.reapStale();
    final job = await repo.find(jobId, organizationId: auth.organizationId);
    if (job == null) throw ApiException(ApiErrorCode.notFound);
    return Response.ok(jsonEncode(job.toWireJson()),
        headers: {'content-type': 'application/json'});
  });

  router.post(
    '/campaigns/<id>/imports/<jobId>/commit',
    const Pipeline()
        .addMiddleware(requirePermission('bulk_import'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final campaignId = request.params['id']!;
          final jobId = request.params['jobId']!;
          final job = await repo.commit(
            campaignId: campaignId,
            organizationId: auth.organizationId,
            jobId: jobId,
            committedBy: auth.userId,
            correlationId: correlationOf(request),
          );
          if (job == null) throw ApiException(ApiErrorCode.notFound);
          return Response.ok(jsonEncode(job.toWireJson()),
              headers: {'content-type': 'application/json'});
        }),
  );

  return router;
}

/// Opens a fresh connection and runs the classify, closing after. Any error
/// is already swallowed inside [ImportRepo.classify]; this wrapper also guards
/// the open/close so a connection fault cannot escape either (§6a).
Future<void> _classifyInBackground(String databaseUrl, String jobId) async {
  Db? worker;
  try {
    worker = await Db.open(databaseUrl);
    await ImportRepo(worker).classify(jobId);
  } on Object {
    // The job stays PROCESSING and the reaper (TTL) will fail it.
  } finally {
    await worker?.close();
  }
}

/// Reads the single `file` part from a multipart/form-data request, or null if
/// there is no such part. API verified against shelf_multipart 2.0.1 source:
/// `request.formData()` → `FormDataRequest?`; `form.formData` is a
/// `Stream<FormData>`; `FormData` exposes `.name` (String), `.filename`
/// (String?), and `.part` (a `Multipart` with `.readBytes() → Future<Uint8List>`).
Future<({List<int> bytes, String? filename})?> _readFilePart(
  Request request,
) async {
  final form = request.formData();
  if (form == null) return null;
  await for (final formData in form.formData) {
    if (formData.name == 'file') {
      return (bytes: await formData.part.readBytes(), filename: formData.filename);
    }
  }
  return null;
}
```

> **`shelf_multipart` 2.0.1 API verified during planning** by reading the installed
> `~/.pub-cache/hosted/pub.dev/shelf_multipart-2.0.1/lib/shelf_multipart.dart`:
> `request.formData()` returns a `FormDataRequest?`; `form.formData` is a
> `Stream<FormData>` whose elements carry `.name` / `.filename` / `.part`, and
> `part.readBytes()` returns the bytes directly (no manual chunk loop). The code
> above uses this real surface.

- [ ] **Step 4: Compose in `buildApp`**

In `server/lib/src/app.dart`:
1. Add the participant-style leg after the participant leg, before seed. The import routes live under `/campaigns/*` and `/imports/*`, so extend the authenticate roots. Add `imports` to a new leg (reuse `_authenticateUnder`):

```dart
  final importHandler = const Pipeline()
      .addMiddleware(
        _authenticateUnder(
          const {'campaigns', 'imports'},
          db: db,
          tokens: tokens,
        ),
      )
      .addHandler(
        importRouter(db: db, databaseUrl: config.databaseUrl).call,
      );
```

and add `.add(importHandler)` to the Cascade AFTER `participantHandler`, BEFORE the seed leg.

2. Add the import for `import_/import_routes.dart`.
3. Confirm `ServerConfig` exposes `databaseUrl` (it does — `config.databaseUrl` is used in `bin/server.dart`).

In `server/test/app_test.dart`, add:

```dart
  test('an unauthenticated GET /imports/x is 401 through the real tree',
      () async {
    final handler = buildApp(db: db, config: _config());
    final res = await handler(
        Request('GET', Uri.parse('http://localhost/imports/x')));
    expect(res.statusCode, 401);
  });
```

- [ ] **Step 5: Run route + app + prior suites**

```bash
cd server && dart test test/import_/ test/app_test.dart test/campaign/ test/participant/ test/seed/
```

Expected: all green (the async poll test may take a couple of seconds — that's the real background task running).

- [ ] **Step 6: Format, analyze, full suite, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add server && git commit -m "feat(server): import routes — dry-run (202), poll, commit; background classify

shelf_multipart parses the file part; dry-run validates, creates the job,
returns 202, and kicks classify on its OWN connection via unawaited (2b.D1) —
the task swallows faults into FAILED so no unhandled error kills the process
(§6a). Poll and commit are org-scoped (404/D7); commit requires bulk_import +
idempotency; a not-ready job is 409. The reaper runs opportunistically on the
dry-run and poll paths. New import Cascade leg; app_test pins the 401 gate."
```

---

### Task 8: Seed fixture for import

**Files:**
- Modify: `server/lib/src/seed/seed_routes.dart`

**Interfaces:**
- Produces: `POST /__test__/reset` also seeds a carpenter whose phone makes one sample-CSV row a master match and (via a registration) another a duplicate — so the e2e's bundled CSV produces a mix of outcomes deterministically.

- [ ] **Step 1: Extend the truncate list**

In `_allSeedableTables`, add at the top: `'import_job_rows', 'import_jobs',`.

- [ ] **Step 2: Reuse the existing carpenter fixtures**

Task 7 of 2a already seeds `CARP_E2E` (Md. Karim, `+8801700004821`) and `CARP_E2E_2` (Karim Uddin, `+8801700007734`). The e2e CSV (Task 10) will include a `Md. Karim,+8801700004821` row (→ VALID match) and a brand-new row (→ NEEDS_PROFILE); no new carpenter seed is required. Confirm the existing `_seedCarpenterFixture` runs in `/reset` (it does, from 2a Task 7). Add a one-line comment in `_seedCarpenterFixture` noting the phones double as the bulk-import e2e's match fixtures.

- [ ] **Step 3: Format, analyze, seed suite, commit**

```bash
cd server && dart test test/seed/ && dart format --set-exit-if-changed . && dart analyze --fatal-infos
git add server && git commit -m "chore(server): note the carpenter seed doubles as the import e2e match fixture

The 2a CARP_E2E phone (+8801700004821) is what the bulk-import e2e CSV's
VALID row matches; the truncate list gains the 005_imports tables so reset
clears jobs between flows."
```

---

# Phase 4 — Mock, client, e2e

### Task 9: Mock ratified async shapes + parity

**Files:**
- Modify: `tool/mock_server/bin/server.dart`
- Modify: `server/test/contract/parity_test.dart`

**Interfaces:**
- Produces: the mock's dry-run returns 202 + a `PROCESSING` job that a subsequent `GET /imports/<id>` reports `READY_TO_COMMIT`; commit → `COMPLETED`. Parity pins the job shape, both vocabularies, and mask formats.

- [ ] **Step 1: Update the mock routes**

In `tool/mock_server/bin/server.dart`, replace the bulk-import routes. The mock keeps an in-memory job map so a poll returns a terminal state on the second call:

```dart
  final importJobs = <String, Map<String, dynamic>>{};

  r.post('/campaigns/<id>/imports/dry-run', (Request req, String id) async {
    await req.read().drain<void>(); // consume the multipart body
    final jobId = 'IMPORT-${store.nextId()}';
    final job = {
      'id': jobId,
      'campaignId': id,
      'status': 'PROCESSING',
      'totalRows': 2,
      'processedRows': 0,
      'rows': [
        {'rowId': 'row-1', 'name': 'Md. Karim', 'outcome': null,
         'message': null, 'linkedCarpenterId': null},
        {'rowId': 'row-2', 'name': 'Brand New', 'outcome': null,
         'message': null, 'linkedCarpenterId': null},
      ],
    };
    importJobs[jobId] = job;
    return _json(job, status: 202);
  });

  r.get('/imports/<jobId>', (Request req, String jobId) {
    final job = importJobs[jobId];
    if (job == null) {
      return _json({'error': {'code': 'NOT_FOUND', 'message': 'no job'}},
          status: 404);
    }
    // First poll flips it to ready with classified rows.
    job['status'] = 'READY_TO_COMMIT';
    job['processedRows'] = 2;
    (job['rows'] as List)[0]['outcome'] = 'VALID';
    (job['rows'] as List)[1]['outcome'] = 'NEEDS_PROFILE';
    return _json(job);
  });

  r.post('/campaigns/<id>/imports/<jobId>/commit',
      (Request req, String id, String jobId) {
    final job = importJobs[jobId] ?? {
      'id': jobId, 'campaignId': id, 'status': 'READY_TO_COMMIT',
      'totalRows': 2, 'processedRows': 2, 'rows': const [],
    };
    job['status'] = 'COMPLETED';
    return _json(job);
  });
```

Remove the old `/imports/<jobId>/commit` (un-namespaced) route.

- [ ] **Step 2: Add parity tests**

In `server/test/contract/parity_test.dart`, add tests using the existing `postJson`/`getJson` targets. The real side needs a seeded ready job; the mock ignores ids. Add (mirroring the file's loop structure):

```dart
    test('$targetName: import job wire shape has status + rows vocabulary',
        () async {
      final targets = await buildTargets(campaignCount: 1, seedCarpenters: true);
      final target = targetName == 'real' ? targets.real : targets.mock;
      // Real: seed a ready job; mock: any id works.
      // (For the real target, buildTargets seeds camp seed-0; insert a job.)
      // Poll shape check only — both must expose {id,campaignId,status,rows}.
      // ... see the file's existing helper for seeding the real side ...
    });
```

(Follow `parity_test.dart`'s established pattern for seeding the real side and asserting shape; pin: `status` ∈ the `ImportStatus` vocabulary via `ImportStatus.tryParseWire(...) != null`; each row's `outcome` is null or in the `ImportRowOutcome` vocabulary; commit answers `COMPLETED`. Keep the assertions identical for both targets.)

- [ ] **Step 3: Run parity, format both packages, commit**

```bash
cd tool/mock_server && dart pub get && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd ../../server && dart test test/contract/parity_test.dart && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
git add tool/mock_server server
git commit -m "feat(mock): ratified async import shapes; parity pins the contract

The mock's dry-run returns 202 PROCESSING; the first poll flips to
READY_TO_COMMIT with classified rows; commit → COMPLETED, under the namespaced
/campaigns/{id}/imports/{jobId}/commit path. Parity tests pin the job shape and
both enum vocabularies on real and mock."
```

---

### Task 10: Client cut-over — FileSource seam, polling, explicit parsing

**Files:**
- Create: `lib/core/files/file_source.dart`
- Modify: `lib/app/di/providers.dart`, `lib/domain/import/import_repository.dart`, `lib/data/import/import_repository_impl.dart`, `lib/features/bulk_import/application/import_controller.dart`, `lib/features/bulk_import/presentation/bulk_import_screen.dart`
- Create: `assets/e2e/bulk_import_sample.csv`; Modify: `pubspec.yaml` (asset)
- Create: `test/data/import/import_repository_impl_test.dart`
- Modify/Create: `test/widget/bulk_import_screen_test.dart`

**Interfaces:**
- Produces: `abstract interface class FileSource { Future<({List<int> bytes, String name})?> pickCsv(); }` with `RealFileSource` (file_selector) and `FakeFileSource` (bundled asset); `fileSourceProvider`. `ImportRepository.poll(String jobId)`; controller polls to terminal.

- [ ] **Step 1: The bundled E2E CSV + asset registration**

`assets/e2e/bulk_import_sample.csv`:

```
name,phone,territory
Md. Karim,+8801700004821,Dhaka North
Brand New Person,+8801799990002,Dhaka South
,,
```

(Row 1 → VALID match against the seeded CARP_E2E; row 2 → NEEDS_PROFILE; row 3 → ERROR.)

In `pubspec.yaml` under `flutter: assets:`, add `- assets/e2e/bulk_import_sample.csv` (create the `assets:` list if absent; check current pubspec).

- [ ] **Step 2: Write the failing repository tests**

`test/data/import/import_repository_impl_test.dart` — mirror 2a's `_RecordingAdapter` transport test (`test/data/registration/registration_repository_impl_test.dart`), asserting: `commit` hits `/campaigns/{id}/imports/{jobId}/commit`; `poll` hits `/imports/{jobId}` and parses status/outcomes via the contracts enums (an unknown status/outcome → a visible unknown, not a silent default). Use the same adapter idiom; the app package name is `acsl_campaign`.

Key assertions:

```dart
  test('poll parses the job and its row outcomes explicitly', () async {
    repo = build((_) => _jsonBody({
      'id': 'IMPORT-1', 'campaignId': 'camp-1', 'status': 'READY_TO_COMMIT',
      'totalRows': 2, 'processedRows': 2,
      'rows': [
        {'rowId': 'row-1', 'name': 'Md. Karim', 'outcome': 'VALID'},
        {'rowId': 'row-2', 'name': 'X', 'outcome': 'NEEDS_PROFILE'},
      ],
    }));
    final res = await repo.poll('IMPORT-1');
    final job = res.fold((j) => j, (f) => fail('expected Ok: $f'));
    expect(job.status, ImportStatus.readyToCommit);
    expect(job.rows.map((r) => r.outcome),
        [ImportRowOutcome.valid, ImportRowOutcome.needsProfile]);
  });

  test('commit posts to the namespaced path with a UUID idempotency key',
      () async {
    repo = build((_) => _jsonBody({
      'id': 'IMPORT-1', 'campaignId': 'camp-1', 'status': 'COMPLETED', 'rows': []}));
    await repo.commit('camp-1', 'IMPORT-1');
    final req = adapter.requests.single;
    expect(req.path, '/campaigns/camp-1/imports/IMPORT-1/commit');
    expect(req.headers['Idempotency-Key'], matches(_uuidV4));
  });
```

- [ ] **Step 3: Run — confirm failure**

```bash
flutter test test/data/import/import_repository_impl_test.dart
```

Expected: FAIL — `poll` undefined; `commit` on the old path.

- [ ] **Step 4: Implement the FileSource seam**

`lib/core/files/file_source.dart`:

```dart
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Where a CSV upload comes from. Abstracted (like CaptureSource) so E2E can
/// inject a bundled file without the native picker Maestro cannot drive.
abstract interface class FileSource {
  Future<({List<int> bytes, String name})?> pickCsv();
}

class RealFileSource implements FileSource {
  const RealFileSource();

  @override
  Future<({List<int> bytes, String name})?> pickCsv() async {
    const csvGroup = XTypeGroup(
      label: 'CSV',
      extensions: <String>['csv'],
      mimeTypes: <String>['text/csv'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[csvGroup]);
    if (file == null) return null;
    return (bytes: await file.readAsBytes(), name: file.name);
  }
}

/// Returns a bundled sample CSV, no native picker. Selected under E2E.
class FakeFileSource implements FileSource {
  const FakeFileSource();

  @override
  Future<({List<int> bytes, String name})?> pickCsv() async {
    final data = await rootBundle.load('assets/e2e/bulk_import_sample.csv');
    return (bytes: data.buffer.asUint8List(), name: 'bulk_import_sample.csv');
  }
}
```

In `lib/app/di/providers.dart`, add (mirroring `captureSourceProvider`):

```dart
final fileSourceProvider = Provider<FileSource>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.e2e ? const FakeFileSource() : const RealFileSource();
});
```

with `import '../../core/files/file_source.dart';`.

- [ ] **Step 5: Domain + data: poll and namespaced commit**

In `lib/domain/import/import_repository.dart`, add:

```dart
  Future<Result<ImportJob>> poll(String jobId);
```

and change `commit`'s doc to note the namespaced path (signature unchanged: `commit(String campaignId, String jobId, {TraceId? trace})` — **note the added `campaignId`**; update the interface and the controller call).

In `lib/data/import/import_repository_impl.dart`:
- Add `import 'package:uuid/uuid.dart';` + `const _uuid = Uuid();`.
- `commit(String campaignId, String jobId, {TraceId? trace})` → `POST /campaigns/$campaignId/imports/$jobId/commit`, `Idempotency-Key: _uuid.v4()`.
- Add `poll(String jobId)` → `GET /imports/$jobId`, parse via `_fromJson`.
- Replace `_fromJson`/`_rowFromJson`'s `firstWhere(orElse:)` with `ImportStatus.tryParseWire`/`ImportRowOutcome.tryParseWire` and explicit unknown handling (an unknown status → treat the job as `failed` with a message; an unknown row outcome → `error`), documented as a visible, chosen fallback (not a silent default). `ImportStatus`/`ImportRowOutcome` now come from `campaign_contracts` via the shims.

- [ ] **Step 6: Controller poll loop**

In `lib/features/bulk_import/application/import_controller.dart`, after `uploadDryRun` receives the 202 job, start a `Timer.periodic` (1s) that calls `poll`, updates progress, and cancels on a terminal state (`readyToCommit`/`failed`) or a 30s cap; register cancellation with `ref.onDispose(timer.cancel)` (§6a). Use `ref.read` inside the callback, never `ref.watch`. `commit` passes `arg` (the campaignId) and `job.id`.

Reference shape:

```dart
  Timer? _pollTimer;

  Future<void> uploadDryRun(List<int> bytes, String filename) async {
    state = state.copyWith(job: const AsyncLoading());
    final res = await ref
        .read(importRepositoryProvider)
        .uploadDryRun(arg, bytes: bytes, filename: filename);
    res.fold((job) {
      state = state.copyWith(job: AsyncData(job));
      if (job.status == ImportStatus.processing) _startPolling(job.id);
    }, (f) => state = state.copyWith(job: AsyncError(f, StackTrace.current)));
  }

  void _startPolling(String jobId) {
    final started = DateTime.now();
    ref.onDispose(() => _pollTimer?.cancel());
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (DateTime.now().difference(started) > const Duration(seconds: 30)) {
        t.cancel();
        return;
      }
      final res = await ref.read(importRepositoryProvider).poll(jobId);
      res.fold((job) {
        state = state.copyWith(job: AsyncData(job));
        if (job.status != ImportStatus.processing) t.cancel();
      }, (_) {});
    });
  }
```

(Adjust `ImportState` if it needs a progress field; the `job` already carries `processedRows`/`totalRows`.)

- [ ] **Step 7: Screen: FileSource seam + semantics ids**

In `lib/features/bulk_import/presentation/bulk_import_screen.dart`: replace the inline `openFile(...)` with `ref.read(fileSourceProvider).pickCsv()`; on a non-null result call `c.uploadDryRun(result.bytes, result.name)`. Add semantics ids to the driven controls (mirroring 2a's `dev_launcher`/Bmd pattern): the pick button (`import_pick`), the commit button (`import_commit`), and ensure the outcome-count review area renders a stable text the flow can assert (e.g. a "Ready to commit" header). Verify the design-system buttons take an `identifier:` param (2a confirmed `BmdButton` does).

- [ ] **Step 8: Run app suites**

```bash
flutter analyze --fatal-infos && flutter test
```

Expected: analyze clean; app test count = baseline + the new import repository tests + the widget test; no regression. Update any pre-existing bulk-import test that pinned the old `commit(jobId)` signature or the old inline picker; list each in the report.

- [ ] **Step 9: Format, commit**

```bash
dart format --set-exit-if-changed lib test
git add lib test assets pubspec.yaml pubspec.lock
git commit -m "feat(client): bulk import speaks the async contract — FileSource seam + polling

FileSource abstracts the CSV pick (real file_selector + E2E fake injecting a
bundled asset), mirroring CaptureSource so Maestro can drive it. The controller
polls GET /imports/{id} every 1s to a terminal state (Timer cancelled via
ref.onDispose, 30s cap); commit hits the namespaced path with a UUID key.
Status/outcome parsing is explicit via tryParseWire — the firstWhere-orElse
silent defaults are gone. Semantics ids for the e2e."
```

---

### Task 11: Maestro flow + CI matrix entry

**Files:**
- Create: `.maestro/flows/bulk_import.yaml`
- Modify: `.maestro/config.yaml`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the seeded campaign (`ACSL Pilot Carpenter Drive`, APPROVED), the seeded carpenter (`+8801700004821`), the bundled CSV (Task 10), the `FakeFileSource`, semantics ids (Task 10), the real-auth login prelude.

- [ ] **Step 1: Study the precedents**

Open `.maestro/flows/registration_workspace.yaml` (the 2a flow — copy its real-auth login prelude verbatim, and reuse its hardened idioms) and `.maestro/config.yaml`. Confirm the exact semantics ids Task 10 added by grepping `identifier:` in `bulk_import_screen.dart`.

- [ ] **Step 2: Write the flow**

`.maestro/flows/bulk_import.yaml` — the login prelude is the 2a flow's verbatim; then:

```yaml
# W-07 async bulk import against the REAL campaign service (2b-I).
# Fixtures: POST /__test__/reset seeds campaign seed-camp-1 ("ACSL Pilot
# Carpenter Drive", APPROVED) and carpenter Md. Karim (+8801700004821). The
# E2E build injects assets/e2e/bulk_import_sample.csv via FakeFileSource
# (no native picker — Maestro can't drive one). CSV rows → VALID / NEEDS_PROFILE
# / ERROR.
appId: ${APP_ID}
tags: [bulkImport, critical, android]
---
# ... verbatim real-auth login prelude from registration_workspace.yaml,
#     username campaign_creator ...
- tapOn: { id: "dev_open_campaigns" }
- assertVisible: ".*ACSL Pilot Carpenter Drive.*"
- tapOn: ".*ACSL Pilot Carpenter Drive.*"
# Navigate to bulk import (adjust to the real detail-screen affordance / route).
- tapOn: "Import"        # the bulk-import entry on the campaign detail screen
- tapOn: { id: "import_pick" }   # FakeFileSource injects the bundled CSV
# Poll: classification is async; wait for the ready state longer than
# assertVisible's 7s default (§6a).
- extendedWaitUntil:
    visible: ".*Ready to commit.*"
    timeout: 30000
- tapOn: { id: "import_commit" }
- extendedWaitUntil:
    visible: ".*Completed.*"
    timeout: 20000
```

Resolve the two commented locators (the bulk-import entry, the ready/completed review copy) against the real screen code; every literal must match the widget text/ids exactly. Escape any literal parens; wrap merged-node asserts in `.*`.

- [ ] **Step 3: Register the flow + CI config**

Add the flow to `.maestro/config.yaml`. In `.github/workflows/ci.yml`, add a matrix entry mirroring `registration`:

```yaml
          - key: bulkImport
            useMock: 0
            defines: '--dart-define=E2E_REAL_AUTH=true'
            flows: .maestro/flows/bulk_import.yaml
```

- [ ] **Step 4: Verify locally if the emulator is available; else rely on CI**

If a local emulator + the 2a rig is available, drive the flow (the crash-fix/basket-first reports document the adb approach) and confirm upload → ready → commit → completed with no scroll/keyboard/back-nav issues. Otherwise CI's `bulkImport` config is the authoritative verdict (Maestro does not run on native Windows). Do NOT commit a claim of a local run that did not happen.

- [ ] **Step 5: Commit, push, watch CI**

```bash
git add .maestro .github/workflows/ci.yml
git commit -m "feat(e2e): bulk import flow against the real service (2b-I)

Real-auth login → open the seeded campaign's bulk import → FakeFileSource
injects the bundled CSV → upload → extendedWaitUntil the async classify
reaches 'Ready to commit' → commit → 'Completed'. New bulkImport CI matrix
config (useMock: 0). Uses the 2a-hardened Maestro idioms; extendedWaitUntil
(not a fixed sleep) for the poll wait."
git push
```

Expected: the full matrix green including `bulkImport`. If the poll flow flakes on CI's slow emulator, raise the `extendedWaitUntil` timeout before touching anything else; the classify is genuinely async.

---

## Self-Review (performed while writing)

- **Spec coverage:** 2b-A → Task 2; 2b-B → Task 1; 2b-C → Tasks 3+5; 2b-D → Tasks 5+7; 2b-E → Task 7; 2b-F → Tasks 4+6; 2b-G → Task 10; 2b-H → Task 9; 2b-I → Tasks 8+10+11. Decisions: 2b.D1 (Task 7 unawaited+own connection), 2b.D2 (Task 5 reaper), 2b.D3 (Task 2 file_hash), 2b.D4 (Task 3 row-id), 2b.D5 (Task 6 committable set). §6a: shelf_multipart/csv (Task 1+3+7), error boundary (Tasks 5+7), eol normalization (Task 3), Timer polling (Task 10), extendedWaitUntil (Task 11).
- **Type consistency:** `ImportJobView`/`ImportRowView`/`toWireJson` used identically across Tasks 5-7; `createJob`/`classify`/`reapStale`/`find`/`commit` signatures match between the interface blocks and call sites; `insertProvisionalCarpenterTx(TxSession, {organizationId, name, phone}) → CarpenterView` consistent between Task 4 (produce) and Task 6 (consume); `parseImportCsv(List<int>) → ParsedImport` consistent Task 3↔5; client `poll`/`commit(campaignId, jobId)` consistent Task 10.
- **`shelf_multipart` API verified against the installed 2.0.1 source during planning** (not left as a "verify later"): the real accessors are `request.formData()` → `FormDataRequest?`, `form.formData` as `Stream<FormData>` with `.name`/`.filename`/`.part`, and `part.readBytes()`. Task 7's `_readFilePart` uses this surface — an earlier draft that referenced `part.name` and a manual chunk loop was corrected. The deps resolve (`dart pub add` run; `csv 8.0.0` + `shelf_multipart 2.0.1` added to `server/pubspec.yaml`).
- **Committable set** is `valid`+`needsProfile` everywhere (Task 1 enum doc, Task 6 SQL `IN ('VALID','NEEDS_PROFILE')`, spec 2b.D5); `warning` is shipped-unproduced consistently.
