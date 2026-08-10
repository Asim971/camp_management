# Campaign Management Service — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Campaign Management Service — a Dart/Postgres backend — far enough that the existing Flutter app runs against it instead of `tool/mock_server` with all five Maestro e2e configs green.

**Architecture:** Two new sibling packages in this repo: `packages/campaign_contracts` (pure-Dart wire vocabulary shared by app and server) and `server/` (shelf + shelf_router over Postgres, hand-written SQL, no ORM, no codegen). Middleware composes as correlation → error-envelope → authenticate → authorise → scope → idempotency → handler. The server owns the campaign status machine; the client renders it.

**Tech Stack:** Dart 3.12, `shelf` 1.4.2, `shelf_router` 1.1.4, `postgres` 3.5.12, `cryptography` 2.9.0 (`DartArgon2id`), `dart_jsonwebtoken` 3.4.1, `uuid` 4.6.0, `test` 1.31.2, Postgres 16.

**Spec:** `docs/superpowers/specs/2026-08-10-campaign-service-foundation-design.md`. Decisions are cited as **D1**–**D7**, deliverables as **D-A**–**D-I**.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **SDK floor is exactly `sdk: ">=3.12.0 <4.0.0"`** in every new `pubspec.yaml`. Not lower. `dart_style` picks its formatting from the language version, so a lower floor makes `dart format --set-exit-if-changed` environment-dependent — a resolved `.dart_tool` locally versus a fresh CI checkout produced a red gate on a file that looked clean. This is recorded in `tool/mock_server/pubspec.yaml` and cost real time once already.
- **Verified package versions** (resolved 2026-08-10, do not guess others): `shelf: ^1.4.1` → 1.4.2 · `shelf_router: ^1.1.4` → 1.1.4 · `postgres: ^3.5.12` · `cryptography: ^2.9.0` · `dart_jsonwebtoken: ^3.4.1` · `uuid: ^4.6.0` · `test: ^1.31.2` · `lints: ^4.0.0`.
- **`shelf`/`shelf_router` only — never `dart_frog`. No ORM. No code generation** anywhere in `server/` or `packages/campaign_contracts` (**D2**). The repo hand-writes its Riverpod providers for this reason, and the README already warns that codegen ordering is fragile.
- **Wire naming is `SCREAMING_SNAKE` for every enum-ish value**, including decisions: `APPROVE`, `RETURN_FOR_CORRECTION`, `REJECT`. Today the client sends Dart enum names (`returnForCorrection`) while statuses are already `PENDING_APPROVAL`. This changes client, server and mock together.
- **Unknown enum values never resolve to a default.** `lib/data/campaign/campaign_dto.dart:62` currently uses `orElse: () => CampaignStatus.draft`, so a `CANCELLED` campaign renders as an *editable draft*. Parsing must yield an explicit unknown or fail.
- **Out-of-scope resources return `404`, never `403`** (**D7**). `403` confirms an ID exists.
- **Every migration wraps its DDL *and* its version-row insert in one transaction** (spec §8). Writing the version row afterwards is the P0.R5 bug in a different database.
- **`postgres` trap:** calling `execute` on the `Connection` while inside `runTx` throws `PgException('Attempting to execute query on connection while inside a `runTx` call.')`. Inside a transaction, use the `TxSession` passed to the callback. Every migration and multi-statement write is affected.
- **`ResultRow.toColumnMap()` returns `Map<String, dynamic>`.** With `strict-casts` enabled, every read needs an explicit cast; Task 3 provides one helper so this is not repeated 40 times.
- **Timestamps:** UTC ISO-8601 on the wire, `timestamptz` in Postgres.
- **The claim vocabulary is fixed by the client and must be emitted exactly.** `lib/core/auth/scope_claims.dart` is a trust boundary that *rejects* sign-in on any unrecognised role or permission. Roles: `campaign_creator`, `marketing_approver`, `crm_verifier`, `crm_supervisor`, `field_user`, `admin`, `reporting_viewer`. Permissions: `campaign_create`, `campaign_approve`, `campaign_cancel`, `bulk_import`, `attendance_capture`, `verification_decide`, `verification_override`, `sensitive_media_view`, `nid_reveal`, `config_manage`, `export`. Inventing one name breaks login entirely.
- **The login response shape is fixed by the client**, which never decodes the JWT: `{"accessToken": …, "refreshToken": …, "expiresInSeconds": <num>, "claims": {"userId", "displayName", "organizationId", "territoryIds": [], "roles": [], "permissions": []}}`. Read `lib/core/auth/auth_service.dart:70-94`.
- **`tool/mock_server` is not deleted in this plan.** It is the harness the last two epics depended on. It changes only where the wire contract changes, and is removed in a later plan once the real service has been green for a while.

---

## File Structure

```
packages/campaign_contracts/
  pubspec.yaml
  lib/campaign_contracts.dart          barrel
  lib/src/campaign_status.dart         CampaignStatus + wireValue + tryParse
  lib/src/campaign_decision.dart       CampaignDecisionInput wire enum
  lib/src/error_codes.dart             ApiErrorCode — the stable machine vocabulary
  test/campaign_status_test.dart
  test/error_codes_test.dart

lib/domain/common/status.dart          becomes a re-export shim (28 importers unchanged)

server/
  pubspec.yaml
  analysis_options.yaml
  Dockerfile
  docker-compose.yaml                  local Postgres 16
  bin/server.dart                      entrypoint: config → pool → migrate → serve
  lib/src/config.dart                  ServerConfig.fromEnvironment
  lib/src/db/pool.dart                 Db wrapper: open, tx, typed row reads
  lib/src/db/migrator.dart             transactional, forward-only runner
  lib/src/db/migrations/embedded.dart  SQL as Dart consts (compile-exe safe)
  lib/src/infra/error_envelope.dart    ApiException + envelope middleware
  lib/src/infra/correlation.dart       correlation id in/out
  lib/src/infra/idempotency.dart       (user,key) + body-hash guard
  lib/src/infra/audit.dart             audit_events writer
  lib/src/auth/password.dart           argon2id hash/verify with encoded params
  lib/src/auth/tokens.dart             JWT issue/verify + refresh rotation
  lib/src/auth/auth_routes.dart        /auth/login /refresh /logout
  lib/src/auth/middleware.dart         authenticate → authorise → scope
  lib/src/campaign/campaign_model.dart server-side entity
  lib/src/campaign/status_machine.dart legal transitions — pure, no IO
  lib/src/campaign/validation.dart     submit revalidation, field-keyed
  lib/src/campaign/campaign_repo.dart  SQL
  lib/src/campaign/campaign_routes.dart
  lib/src/seed/seed_routes.dart        test-only, gated
  test/…                               mirrors lib/src
```

**Why these boundaries.** `status_machine.dart` and `validation.dart` hold zero IO so the two hardest-to-get-right rules are unit-testable without a database. `migrator.dart` is separate from `pool.dart` because its transactional guarantee is the thing being tested. `seed_routes.dart` is one file so the production gate has exactly one place to fail closed.

---

# Phase 1 — Foundation (D-A … D-F)

Tasks 1–6. Verifiable by unit and integration tests alone; nothing here proves the foundation works end to end, which is what Phase 2 is for.

---

### Task 1: Shared contracts package and the re-export shim

**Files:**
- Create: `packages/campaign_contracts/pubspec.yaml`
- Create: `packages/campaign_contracts/lib/campaign_contracts.dart`
- Create: `packages/campaign_contracts/lib/src/campaign_status.dart`
- Create: `packages/campaign_contracts/lib/src/campaign_decision.dart`
- Create: `packages/campaign_contracts/lib/src/error_codes.dart`
- Create: `packages/campaign_contracts/test/campaign_status_test.dart`
- Modify: `lib/domain/common/status.dart` (becomes a shim)
- Modify: `pubspec.yaml` (path dependency)
- Modify: `analysis_options.yaml` (excludes)

**Interfaces:**
- Produces: `enum CampaignStatus { draft, pendingApproval, returned, approved, active, paused, completed, cancelled }` with `String get wireValue` and `static CampaignStatus? tryParseWire(String)`; `enum CampaignDecisionInput { approve, returnForCorrection, reject }` with `String get wireValue` and `static CampaignDecisionInput? tryParseWire(String)`; `enum ApiErrorCode` with `String get wireValue` / `tryParseWire`.
- Consumes: nothing.

**Scope note — read before starting.** The spec's **D5** says "the five status enums and their `wireValue` getters move". That is wrong, and verifying it is why this note exists: in `lib/domain/common/status.dart`, **only `CampaignStatus` has a `wireValue` getter** (line 19). `RegistrationStatus`, `AttendanceStatus`, `ImportStatus` and `IntegrityFlag` have none, and the file's own doc comment ("Each enum exposes a stable `wireValue` … and a localization key") is false for four of five enums — there is no localization-key member at all. Moving all five would mean **inventing four wire vocabularies** for features whose server contracts are still blocked. So this task moves `CampaignStatus` only. `StatusTone` stays in the app: it is presentation.

- [ ] **Step 1: Create the package manifest**

`packages/campaign_contracts/pubspec.yaml`:

```yaml
name: campaign_contracts
description: Wire vocabulary shared by the ACSL campaign app and the campaign service.
publish_to: "none"
version: 0.1.0

environment:
  # Must match the root package. A lower floor makes `dart format` output
  # depend on whether .dart_tool was resolved — see Global Constraints.
  sdk: ">=3.12.0 <4.0.0"

dev_dependencies:
  lints: ^4.0.0
  test: ^1.31.2
```

- [ ] **Step 2: Write the failing status test**

`packages/campaign_contracts/test/campaign_status_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('every status has a distinct SCREAMING_SNAKE wire value', () {
    final wires = CampaignStatus.values.map((s) => s.wireValue).toList();
    expect(wires.toSet().length, CampaignStatus.values.length);
    for (final w in wires) {
      expect(w, matches(RegExp(r'^[A-Z][A-Z_]*$')), reason: w);
    }
  });

  test('wire values round-trip', () {
    for (final s in CampaignStatus.values) {
      expect(CampaignStatus.tryParseWire(s.wireValue), s);
    }
  });

  // The whole reason this enum moved into a shared package: an unrecognised
  // value must NOT become an editable draft. campaign_dto.dart used
  // `orElse: () => CampaignStatus.draft`, so a CANCELLED campaign arriving
  // with an unexpected value rendered as editable — a silent misclassification
  // in the direction that grants more permission.
  test('an unknown wire value is null, never a default', () {
    expect(CampaignStatus.tryParseWire('NOT_A_STATUS'), isNull);
    expect(CampaignStatus.tryParseWire(''), isNull);
    expect(CampaignStatus.tryParseWire('draft'), isNull, reason: 'case matters');
  });

  test('decision inputs use SCREAMING_SNAKE, not Dart enum names', () {
    expect(CampaignDecisionInput.returnForCorrection.wireValue,
        'RETURN_FOR_CORRECTION');
    expect(CampaignDecisionInput.tryParseWire('returnForCorrection'), isNull);
  });
}
```

- [ ] **Step 3: Run it and confirm it fails for the right reason**

```bash
cd packages/campaign_contracts && dart pub get && dart test
```

Expected: compile failure — `Error: Couldn't resolve the package 'campaign_contracts'` / `campaign_contracts.dart` not found. Not a passing test.

- [ ] **Step 4: Implement the status and decision enums**

`packages/campaign_contracts/lib/src/campaign_status.dart`:

```dart
/// Controlled campaign status vocabulary. The wire value is the contract;
/// the Dart name is an implementation detail on either side.
///
/// Moved out of the app's `lib/domain/common/status.dart` so the server and
/// the client cannot disagree about it (spec D5).
enum CampaignStatus {
  draft,
  pendingApproval,
  returned,
  approved,
  active,
  paused,
  completed,
  cancelled;

  String get wireValue => switch (this) {
    draft => 'DRAFT',
    pendingApproval => 'PENDING_APPROVAL',
    returned => 'RETURNED',
    approved => 'APPROVED',
    active => 'ACTIVE',
    paused => 'PAUSED',
    completed => 'COMPLETED',
    cancelled => 'CANCELLED',
  };

  /// Returns `null` for anything unrecognised — deliberately not a default.
  /// A caller that wants a fallback must choose it explicitly and visibly.
  static CampaignStatus? tryParseWire(String wire) {
    for (final s in values) {
      if (s.wireValue == wire) return s;
    }
    return null;
  }
}
```

`packages/campaign_contracts/lib/src/campaign_decision.dart`:

```dart
/// What an approver submits. Distinct from [CampaignStatus]: `APPROVE` is an
/// action, `APPROVED` is a state, and conflating them is how "reject" ended up
/// mapping to CANCELLED with no record of which action caused it.
enum CampaignDecisionInput {
  approve,
  returnForCorrection,
  reject;

  String get wireValue => switch (this) {
    approve => 'APPROVE',
    returnForCorrection => 'RETURN_FOR_CORRECTION',
    reject => 'REJECT',
  };

  static CampaignDecisionInput? tryParseWire(String wire) {
    for (final d in values) {
      if (d.wireValue == wire) return d;
    }
    return null;
  }
}
```

- [ ] **Step 5: Implement the error-code vocabulary**

`packages/campaign_contracts/lib/src/error_codes.dart`:

```dart
/// Stable machine-readable error vocabulary. Clients switch on `code` and
/// never parse `message`, so a wording change is never a breaking change.
enum ApiErrorCode {
  // transport / generic
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  internal,
  // concurrency and replay
  conflictStaleVersion,
  idempotencyKeyRequired,
  idempotencyKeyReused,
  // campaign lifecycle
  campaignInvalidTransition,
  campaignValidationFailed,
  decisionReasonRequired,
  warningsUnacknowledged,
  segregationOfDutiesViolation;

  String get wireValue => switch (this) {
    badRequest => 'BAD_REQUEST',
    unauthorized => 'UNAUTHORIZED',
    forbidden => 'FORBIDDEN',
    notFound => 'NOT_FOUND',
    internal => 'INTERNAL',
    conflictStaleVersion => 'CONFLICT_STALE_VERSION',
    idempotencyKeyRequired => 'IDEMPOTENCY_KEY_REQUIRED',
    idempotencyKeyReused => 'IDEMPOTENCY_KEY_REUSED',
    campaignInvalidTransition => 'CAMPAIGN_INVALID_TRANSITION',
    campaignValidationFailed => 'CAMPAIGN_VALIDATION_FAILED',
    decisionReasonRequired => 'DECISION_REASON_REQUIRED',
    warningsUnacknowledged => 'WARNINGS_UNACKNOWLEDGED',
    segregationOfDutiesViolation => 'SEGREGATION_OF_DUTIES_VIOLATION',
  };

  static ApiErrorCode? tryParseWire(String wire) {
    for (final c in values) {
      if (c.wireValue == wire) return c;
    }
    return null;
  }
}
```

`packages/campaign_contracts/lib/campaign_contracts.dart`:

```dart
/// Wire vocabulary shared by the app and the campaign service.
///
/// Holds the WIRE only — no domain entities, no validation, no status machine
/// (spec D5). The server's campaign carries org scope, audit columns and a
/// version; the app's carries presentation concerns. Sharing entities would
/// drag each side's incidental needs into the other.
library;

export 'src/campaign_decision.dart';
export 'src/campaign_status.dart';
export 'src/error_codes.dart';
```

- [ ] **Step 6: Run the tests — they must now pass**

```bash
cd packages/campaign_contracts && dart pub get && dart test
```

Expected: 4 tests pass.

- [ ] **Step 7: Turn the app's status file into a shim**

Replace the `CampaignStatus` enum in `lib/domain/common/status.dart` with a re-export, keeping every other enum and `StatusTone` exactly as they are. The file's opening doc comment must also stop claiming that every enum exposes a `wireValue` and a localization key, because it never did.

```dart
/// Controlled status vocabulary — the single source of truth used identically
/// across list pages, detail pages, notifications, mobile sync and analytics
/// (UI/UX Guideline §1.1, §5.4, Appendix B). Status is NEVER a raw string.
///
/// [CampaignStatus] now lives in `package:campaign_contracts` so the server
/// cannot disagree with the client about it (spec D5). It is re-exported here
/// rather than moved-and-reimported because 28 files import this path and the
/// enum name is unchanged: a shim keeps that diff at one file instead of 28.
///
/// The other enums below have NO wire value yet — their server contracts are
/// blocked — so they stay here until the sub-project that defines them lands.
/// Do not invent wire values for them to make this file look symmetrical.
library;

export 'package:campaign_contracts/campaign_contracts.dart'
    show CampaignStatus;

enum RegistrationStatus { … }   // unchanged
enum AttendanceStatus { … }     // unchanged
enum ImportStatus { … }         // unchanged
enum IntegrityFlag { … }        // unchanged
enum StatusTone { neutral, info, success, warning, error }  // unchanged
```

- [ ] **Step 8: Wire the path dependency and the analyzer excludes**

In root `pubspec.yaml`, under `dependencies:`:

```yaml
  campaign_contracts:
    path: packages/campaign_contracts
```

In root `analysis_options.yaml`, extend the existing `exclude:` list (which already carries `tool/**` for the same reason):

```yaml
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "lib/l10n/generated/**"
    - "tool/**" # standalone mock_server package with its own pubspec
    - "server/**" # standalone Dart service with its own pubspec + analysis_options
    - "packages/**" # standalone packages with their own pubspecs
```

- [ ] **Step 9: Verify the shim did not break the app**

```bash
flutter pub get --enforce-lockfile || flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
dart format --set-exit-if-changed lib packages
flutter analyze --fatal-infos
flutter test
```

Expected: analyze clean, **392 passing / 29 skipped** — the same counts as before this task. A changed count means the shim altered behaviour and must be investigated, not accepted.

- [ ] **Step 10: Commit**

```bash
git add packages/campaign_contracts pubspec.yaml pubspec.lock analysis_options.yaml lib/domain/common/status.dart
git commit -m "feat(contracts): share CampaignStatus and the error vocabulary

Only CampaignStatus moves. The spec said all five status enums carry a
wireValue; only this one does, and the file's own doc comment claiming
otherwise was false for four of five. Moving the rest would mean inventing
four wire vocabularies for features whose contracts are still blocked.

lib/domain/common/status.dart becomes a re-export shim: 28 files import that
path and the enum name is unchanged, so the diff is 1 file rather than 28."
```

---

### Task 2: Server skeleton, config, health and local Postgres

**Files:**
- Create: `server/pubspec.yaml`, `server/analysis_options.yaml`
- Create: `server/lib/src/config.dart`
- Create: `server/bin/server.dart`
- Create: `server/Dockerfile`, `server/docker-compose.yaml`
- Create: `server/test/config_test.dart`
- Create: `server/.dockerignore`

**Interfaces:**
- Consumes: `campaign_contracts` (path dependency).
- Produces: `class ServerConfig { final int port; final String databaseUrl; final String jwtSecret; final Duration accessTokenTtl; final bool seedingEnabled; static ServerConfig fromEnvironment(Map<String,String> env); }` and `Future<void> main(List<String> args)` serving `GET /health`.

- [ ] **Step 1: Create the manifests**

`server/pubspec.yaml`:

```yaml
name: campaign_service
description: Campaign Management Service — BMD Sales Eco microservice.
publish_to: "none"
version: 0.1.0

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  campaign_contracts:
    path: ../packages/campaign_contracts
  cryptography: ^2.9.0
  dart_jsonwebtoken: ^3.4.1
  postgres: ^3.5.12
  shelf: ^1.4.1
  shelf_router: ^1.1.4
  uuid: ^4.6.0

dev_dependencies:
  lints: ^4.0.0
  test: ^1.31.2
```

`server/analysis_options.yaml` — same strictness as the app, because this code holds the authority the clients are thin over:

```yaml
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true

linter:
  rules:
    - always_declare_return_types
    - avoid_dynamic_calls
    - avoid_print
    - directives_ordering
    - prefer_final_locals
    - require_trailing_commas
    - unawaited_futures
```

- [ ] **Step 2: Write the failing config test**

`server/test/config_test.dart`:

```dart
import 'package:campaign_service/src/config.dart';
import 'package:test/test.dart';

void main() {
  const required = {
    'DATABASE_URL': 'postgres://u:p@localhost:5432/campaign',
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  };

  test('reads required values and defaults the port', () {
    final c = ServerConfig.fromEnvironment(required);
    expect(c.databaseUrl, required['DATABASE_URL']);
    expect(c.port, 8080);
    expect(c.accessTokenTtl, const Duration(minutes: 15));
  });

  test('a missing DATABASE_URL fails at startup, not at first request', () {
    expect(
      () => ServerConfig.fromEnvironment({'JWT_SECRET': required['JWT_SECRET']!}),
      throwsA(isA<StateError>()),
    );
  });

  // A short secret is worse than no secret: it starts, signs tokens, and is
  // brute-forceable. Fail loudly at boot.
  test('a short JWT secret is rejected', () {
    expect(
      () => ServerConfig.fromEnvironment({...required, 'JWT_SECRET': 'short'}),
      throwsA(isA<StateError>()),
    );
  });

  // Seeding must fail CLOSED. An unset variable in production must not enable
  // it, and it is the single gate for the test-only routes in Task 10.
  test('seeding is disabled unless explicitly enabled', () {
    expect(ServerConfig.fromEnvironment(required).seedingEnabled, isFalse);
    expect(
      ServerConfig.fromEnvironment({...required, 'ENABLE_TEST_SEEDING': 'yes'})
          .seedingEnabled,
      isFalse,
      reason: 'only the exact string "true" enables it',
    );
    expect(
      ServerConfig.fromEnvironment({...required, 'ENABLE_TEST_SEEDING': 'true'})
          .seedingEnabled,
      isTrue,
    );
  });
}
```

- [ ] **Step 3: Run it and confirm it fails**

```bash
cd server && dart pub get && dart test test/config_test.dart
```

Expected: FAIL — `config.dart` does not exist.

- [ ] **Step 4: Implement the config**

`server/lib/src/config.dart`:

```dart
/// Startup configuration. Every value is validated here so a misconfigured
/// deploy fails at boot with a precise message rather than at the first
/// request with a stack trace.
class ServerConfig {
  const ServerConfig({
    required this.port,
    required this.databaseUrl,
    required this.jwtSecret,
    required this.accessTokenTtl,
    required this.refreshTokenTtl,
    required this.seedingEnabled,
  });

  final int port;
  final String databaseUrl;
  final String jwtSecret;
  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;

  /// Gates the test-only seeding routes. Defaults to false and requires the
  /// exact string 'true': a typo must not open a data-mutating surface.
  final bool seedingEnabled;

  static ServerConfig fromEnvironment(Map<String, String> env) {
    final databaseUrl = env['DATABASE_URL'];
    if (databaseUrl == null || databaseUrl.isEmpty) {
      throw StateError('DATABASE_URL is required.');
    }
    final secret = env['JWT_SECRET'];
    if (secret == null || secret.length < 32) {
      throw StateError(
        'JWT_SECRET is required and must be at least 32 characters.',
      );
    }
    final rawPort = env['PORT'];
    final port = rawPort == null ? 8080 : int.tryParse(rawPort);
    if (port == null || port <= 0 || port > 65535) {
      throw StateError('PORT must be a valid port number, got "$rawPort".');
    }
    return ServerConfig(
      port: port,
      databaseUrl: databaseUrl,
      jwtSecret: secret,
      accessTokenTtl: const Duration(minutes: 15),
      refreshTokenTtl: const Duration(days: 30),
      seedingEnabled: env['ENABLE_TEST_SEEDING'] == 'true',
    );
  }
}
```

- [ ] **Step 5: Run the config tests — must pass**

```bash
cd server && dart test test/config_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 6: Implement the entrypoint with a health route**

`server/bin/server.dart`:

```dart
import 'dart:io';

import 'package:campaign_service/src/config.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main(List<String> args) async {
  final config = ServerConfig.fromEnvironment(Platform.environment);

  final router = Router()
    ..get('/health', (Request req) => Response.ok('{"status":"ok"}',
        headers: {'content-type': 'application/json'}));

  final server = await io.serve(
    const Pipeline().addHandler(router.call),
    InternetAddress.anyIPv4,
    config.port,
  );
  stdout.writeln('campaign_service listening on :${server.port}');
}
```

- [ ] **Step 7: Add the container files**

`server/docker-compose.yaml`:

```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: campaign
      POSTGRES_PASSWORD: campaign
      POSTGRES_DB: campaign
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U campaign"]
      interval: 2s
      timeout: 3s
      retries: 20
```

`server/Dockerfile`:

```dockerfile
FROM dart:3.12 AS build
WORKDIR /app
COPY packages/campaign_contracts ../packages/campaign_contracts
COPY server/pubspec.* ./
RUN dart pub get
COPY server/ ./
RUN dart pub get --offline && dart compile exe bin/server.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
EXPOSE 8080
ENTRYPOINT ["/app/server"]
```

`server/.dockerignore`:

```
.dart_tool/
build/
test/
```

- [ ] **Step 8: Verify it boots and answers**

```bash
cd server
docker compose up -d db
DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' \
  JWT_SECRET='a-secret-at-least-32-characters-long!!' \
  dart run bin/server.dart &
sleep 2
curl -s localhost:8080/health
```

Expected: `{"status":"ok"}`. Stop the process afterwards.

- [ ] **Step 9: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server && git commit -m "feat(server): skeleton, validated config, health route, local Postgres

Config validates at boot rather than at first request: a missing DATABASE_URL,
a JWT secret under 32 chars, or a bad PORT all fail immediately. Test-only
seeding is off unless ENABLE_TEST_SEEDING is exactly 'true' — it fails closed
because it is the one gate on a data-mutating surface."
```

---


---

### Task 3: Transactional migration runner and the foundation schema

**Files:**
- Create: `server/lib/src/db/pool.dart`
- Create: `server/lib/src/db/migrator.dart`
- Create: `server/lib/src/db/migrations/embedded.dart`
- Create: `server/test/db/migrator_test.dart`
- Create: `server/test/support/test_db.dart`
- Modify: `server/bin/server.dart` (migrate on boot)

**Interfaces:**
- Consumes: `ServerConfig` from Task 2.
- Produces:
  - `class Db { static Future<Db> open(String url); Future<Result> execute(String sql, {Map<String, Object?>? params}); Future<R> tx<R>(Future<R> Function(TxSession tx) fn); Future<void> close(); }`
  - `Map<String, Object?> row(ResultRow r)` — the single place `toColumnMap()`'s `dynamic` is cast.
  - `class Migrator { Migrator(Db db, {Map<String, String> extra}); Future<List<String>> applyPending(); }` returning applied ids in order.
  - `const Map<String, String> embeddedMigrations` keyed `001_foundation`.

**Why this is its own task.** Its guarantee — a killed migration applies wholly or not at all — is the exact thing P0.R5 got wrong on the client, and is testable only in isolation.

- [ ] **Step 1: Write the test-database helper**

`server/test/support/test_db.dart`:

```dart
import 'dart:io';

import 'package:campaign_service/src/db/pool.dart';

/// CI sets DATABASE_URL for its service container; locally use
/// `docker compose up -d db`.
String get testDatabaseUrl =>
    Platform.environment['DATABASE_URL'] ??
    'postgres://campaign:campaign@localhost:5432/campaign';

/// Drops every table so each test starts from nothing. A migration test that
/// inherits another test's schema proves nothing.
Future<Db> freshDb() async {
  final db = await Db.open(testDatabaseUrl);
  await db.execute('DROP SCHEMA public CASCADE');
  await db.execute('CREATE SCHEMA public');
  return db;
}
```

- [ ] **Step 2: Write the failing migrator tests**

`server/test/db/migrator_test.dart`:

```dart
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:test/test.dart';

import '../support/test_db.dart';

void main() {
  late Db db;

  setUp(() async => db = await freshDb());
  tearDown(() async => db.close());

  test('applies pending migrations in id order and records them', () async {
    final applied = await Migrator(db).applyPending();

    expect(applied, contains('001_foundation'));
    expect(applied, equals(List<String>.of(applied)..sort()),
        reason: 'ids must be applied in lexical order');

    final res = await db.execute('SELECT id FROM schema_migrations ORDER BY id');
    expect(res.map((r) => row(r)['id']), applied);
  });

  test('is idempotent: a second run applies nothing', () async {
    await Migrator(db).applyPending();
    expect(await Migrator(db).applyPending(), isEmpty);
  });

  // The P0.R5 lesson transplanted. On the client, drift ran each step bare and
  // bumped user_version only after onUpgrade returned, so a kill mid-step left a
  // device durably on the old version with half the work committed, and the
  // retry threw out of beforeOpen on EVERY later launch. Postgres has
  // transactional DDL, so if the DDL and the version row share one transaction,
  // a failure leaves nothing behind.
  test('a failing migration leaves no partial schema and no version row',
      () async {
    final migrator = Migrator(db, extra: const {
      '999_broken':
          'CREATE TABLE half_applied (id TEXT PRIMARY KEY); '
          'SELECT this_function_does_not_exist();',
    });

    await expectLater(migrator.applyPending(), throwsA(isA<Exception>()));

    final tables = await db.execute(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
    );
    expect(tables.map((r) => row(r)['tablename']).toSet(),
        isNot(contains('half_applied')),
        reason: 'the CREATE TABLE must roll back with the failure');

    final versions = await db.execute('SELECT id FROM schema_migrations');
    expect(versions.map((r) => row(r)['id']), isNot(contains('999_broken')));
  });

  test('the foundation schema creates every table the slice needs', () async {
    await Migrator(db).applyPending();
    final res = await db.execute(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
    );
    final names = res.map((r) => row(r)['tablename']! as String).toSet();
    expect(names, containsAll(<String>[
      'organizations', 'territories',
      'staff_users', 'staff_user_roles', 'staff_user_territories',
      'refresh_tokens',
      'campaigns', 'campaign_territories', 'campaign_sessions',
      'campaign_submissions', 'campaign_decisions',
      'idempotency_keys', 'audit_events', 'app_config',
      'schema_migrations',
    ]));
  });

  test('SoD defaults to enforced', () async {
    await Migrator(db).applyPending();
    final res = await db.execute(
      "SELECT value FROM app_config WHERE key = 'sod.enforced'",
    );
    expect(row(res.single)['value'], 'true');
  });
}
```

- [ ] **Step 3: Run and confirm failure**

```bash
cd server && docker compose up -d db && dart test test/db/migrator_test.dart
```

Expected: FAIL — `pool.dart` and `migrator.dart` do not exist.

- [ ] **Step 4: Implement the Db wrapper**

`server/lib/src/db/pool.dart`:

```dart
import 'package:postgres/postgres.dart';

/// Thin wrapper over a single Postgres connection. Deliberately not a pool:
/// one connection serves this slice and the e2e suite, and a pool would hide
/// the runTx constraint documented on [tx].
class Db {
  Db(this._connection);

  final Connection _connection;

  static Future<Db> open(String url) async {
    final uri = Uri.parse(url);
    final userInfo = uri.userInfo.split(':');
    final endpoint = Endpoint(
      host: uri.host,
      port: uri.port == 0 ? 5432 : uri.port,
      database: uri.pathSegments.isEmpty ? 'campaign' : uri.pathSegments.first,
      username: Uri.decodeComponent(userInfo.first),
      password:
          userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : null,
    );
    final connection = await Connection.open(
      endpoint,
      // Local docker and the CI service container speak plaintext. A deploy
      // target requiring TLS must override this; it is not a default.
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    return Db(connection);
  }

  Future<Result> execute(String sql, {Map<String, Object?>? params}) =>
      params == null
          ? _connection.execute(sql)
          : _connection.execute(Sql.named(sql), parameters: params);

  /// Runs [fn] in a transaction.
  ///
  /// Use the [TxSession] passed to [fn] for every statement inside. Calling
  /// [execute] on this Db while a transaction is active throws
  /// PgException("Attempting to execute query on connection while inside a
  /// runTx call") — at protocol level the whole connection is in the
  /// transaction.
  Future<R> tx<R>(Future<R> Function(TxSession tx) fn) => _connection.runTx(fn);

  Future<void> close() => _connection.close();
}

/// ResultRow.toColumnMap() returns Map<String, dynamic>, which every read would
/// otherwise cast under strict-casts. Cast once, here.
Map<String, Object?> row(ResultRow r) =>
    r.toColumnMap().cast<String, Object?>();
```

- [ ] **Step 5: Implement the migrator**

`server/lib/src/db/migrator.dart`:

```dart
import 'package:postgres/postgres.dart';

import 'migrations/embedded.dart';
import 'pool.dart';

/// Forward-only migration runner.
///
/// Each migration and its schema_migrations row commit in ONE transaction. That
/// ordering is the entire guarantee: writing the version row after the DDL
/// commits is the defect filed as P0.R5 on the client, where a kill between the
/// two left the database durably half-migrated and unopenable on every later
/// launch. Postgres has transactional DDL, so the cure here is structural
/// rather than per-statement idempotency.
///
/// No down-migrations: a failed deploy rolls forward.
class Migrator {
  Migrator(this._db, {Map<String, String> extra = const {}})
      : _migrations = {...embeddedMigrations, ...extra};

  final Db _db;
  final Map<String, String> _migrations;

  Future<List<String>> applyPending() async {
    await _db.execute(
      'CREATE TABLE IF NOT EXISTS schema_migrations ('
      '  id TEXT PRIMARY KEY,'
      '  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()'
      ')',
    );

    final done = (await _db.execute('SELECT id FROM schema_migrations'))
        .map((r) => row(r)['id']! as String)
        .toSet();

    final pending = _migrations.keys.where((id) => !done.contains(id)).toList()
      ..sort();

    final applied = <String>[];
    for (final id in pending) {
      await _db.tx((tx) async {
        // Every statement here goes through `tx`, never `_db` — see Db.tx.
        await tx.execute(_migrations[id]!);
        await tx.execute(
          Sql.named('INSERT INTO schema_migrations (id) VALUES (@id)'),
          parameters: {'id': id},
        );
      });
      applied.add(id);
    }
    return applied;
  }
}
```

- [ ] **Step 6: Write the foundation schema as an embedded constant**

`server/lib/src/db/migrations/embedded.dart` — the SQL lives as a Dart string, not a file asset: `dart compile exe` produces a binary with no access to the source tree, so a `File('migrations/001.sql')` read would work in `dart run` and fail in the container.

```dart
/// Migrations, embedded as source. Keyed by id; applied in lexical order.
const Map<String, String> embeddedMigrations = {
  '001_foundation': _foundation,
};

const String _foundation = r'''
CREATE TABLE organizations (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE territories (
  id               TEXT PRIMARY KEY,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  name             TEXT NOT NULL
);

CREATE TABLE staff_users (
  id               TEXT PRIMARY KEY,
  username         TEXT NOT NULL UNIQUE,
  display_name     TEXT NOT NULL,
  password_hash    TEXT NOT NULL,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Roles and territories are rows, not arrays: sub-project 7 administers them
-- individually and must audit each grant.
CREATE TABLE staff_user_roles (
  user_id  TEXT NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  role     TEXT NOT NULL,
  PRIMARY KEY (user_id, role)
);

CREATE TABLE staff_user_territories (
  user_id       TEXT NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  territory_id  TEXT NOT NULL REFERENCES territories(id),
  PRIMARY KEY (user_id, territory_id)
);

-- family_id groups a rotation chain. Presenting an already-rotated token
-- revokes the whole family: the standard stolen-refresh-token defence.
CREATE TABLE refresh_tokens (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  family_id   TEXT NOT NULL,
  token_hash  TEXT NOT NULL UNIQUE,
  issued_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL,
  used_at     TIMESTAMPTZ,
  revoked_at  TIMESTAMPTZ
);
CREATE INDEX refresh_tokens_family_idx ON refresh_tokens(family_id);

CREATE TABLE campaigns (
  id                TEXT PRIMARY KEY,
  organization_id   TEXT NOT NULL REFERENCES organizations(id),
  name              TEXT NOT NULL,
  type              TEXT NOT NULL,
  objective         TEXT,
  status            TEXT NOT NULL,
  owner_id          TEXT NOT NULL REFERENCES staff_users(id),
  approver_id       TEXT REFERENCES staff_users(id),
  start_at          TIMESTAMPTZ,
  end_at            TIMESTAMPTZ,
  venue             TEXT,
  target_audience   INTEGER NOT NULL DEFAULT 0,
  budget_reference  TEXT,
  geofence_enabled  BOOLEAN NOT NULL DEFAULT FALSE,
  -- Bumped on every mutation. The conflict check is
  -- "WHERE id = @id AND version = @version" returning zero rows, so a code
  -- path that forgets to compare cannot silently overwrite.
  version           INTEGER NOT NULL DEFAULT 1,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX campaigns_org_status_idx ON campaigns(organization_id, status);
CREATE INDEX campaigns_name_idx ON campaigns(lower(name));

CREATE TABLE campaign_territories (
  campaign_id   TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  territory_id  TEXT NOT NULL REFERENCES territories(id),
  PRIMARY KEY (campaign_id, territory_id)
);

CREATE TABLE campaign_sessions (
  id           TEXT PRIMARY KEY,
  campaign_id  TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  venue        TEXT,
  capacity     INTEGER,
  start_at     TIMESTAMPTZ,
  end_at       TIMESTAMPTZ,
  status       TEXT NOT NULL DEFAULT 'PLANNED'
);
CREATE INDEX campaign_sessions_campaign_idx ON campaign_sessions(campaign_id);

-- Immutable snapshot per submit. Without it a resubmission has nothing to diff
-- against, and sub-project 3's changed-field view becomes unimplementable
-- after the fact.
CREATE TABLE campaign_submissions (
  id            TEXT PRIMARY KEY,
  campaign_id   TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  version       INTEGER NOT NULL,
  submitted_by  TEXT NOT NULL REFERENCES staff_users(id),
  submitted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  snapshot      JSONB NOT NULL
);
CREATE INDEX campaign_submissions_campaign_idx
  ON campaign_submissions(campaign_id, submitted_at DESC);

-- Exactly what the approval PRD requires recorded: reviewer, decision, reason,
-- warning acknowledgements, version, time and correlation id.
CREATE TABLE campaign_decisions (
  id                     TEXT PRIMARY KEY,
  campaign_id            TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  submission_id          TEXT REFERENCES campaign_submissions(id),
  reviewer_id            TEXT NOT NULL REFERENCES staff_users(id),
  decision               TEXT NOT NULL,
  reason                 TEXT,
  acknowledged_warnings  JSONB NOT NULL DEFAULT '[]'::jsonb,
  version_at_decision    INTEGER NOT NULL,
  correlation_id         TEXT,
  decided_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX campaign_decisions_campaign_idx ON campaign_decisions(campaign_id);

-- Scoped per user so one user's key cannot replay another's response.
-- request_hash guards a key reused with a different body.
CREATE TABLE idempotency_keys (
  key              TEXT NOT NULL,
  user_id          TEXT NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  request_hash     TEXT NOT NULL,
  response_status  INTEGER NOT NULL,
  response_body    TEXT NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, key)
);

CREATE TABLE audit_events (
  id              TEXT PRIMARY KEY,
  actor_id        TEXT,
  action          TEXT NOT NULL,
  resource_type   TEXT NOT NULL,
  resource_id     TEXT,
  correlation_id  TEXT,
  payload         JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_events_resource_idx
  ON audit_events(resource_type, resource_id, occurred_at DESC);

CREATE TABLE app_config (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enforced by default: a missing or unreadable config row must not silently
-- disable a governance control (spec section 6).
INSERT INTO app_config (key, value) VALUES ('sod.enforced', 'true');
''';
```

- [ ] **Step 7: Run the migrator tests — must pass**

```bash
cd server && dart test test/db/migrator_test.dart
```

Expected: 5 tests pass, including the rollback test.

- [ ] **Step 8: Prove the rollback test is not vacuous**

Temporarily move the `INSERT INTO schema_migrations` statement *outside* the `_db.tx` block — reintroducing the P0.R5 shape — and re-run just that test.

```bash
cd server && dart test test/db/migrator_test.dart -n 'leaves no partial schema'
```

Expected: **FAIL** — `half_applied` survives and/or the version row was written. Revert and confirm it passes again. A rollback test that passes either way tests nothing; this repo has shipped several such tests and caught them only by probing.

- [ ] **Step 9: Migrate on boot**

In `server/bin/server.dart`, after config: `final db = await Db.open(config.databaseUrl);`, then `final applied = await Migrator(db).applyPending();` and log the ids. Hold `db` for the handlers.

- [ ] **Step 10: Format, analyze, test, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
cd .. && git add server && git commit -m "feat(server): transactional forward-only migrator and foundation schema

Each migration and its schema_migrations row commit in ONE transaction. That
ordering is the guarantee: writing the version row after the DDL is exactly the
P0.R5 defect on the client, where a kill between the two left a device durably
half-migrated and unopenable on every subsequent launch. Postgres has
transactional DDL, so the cure is structural rather than per-statement
idempotency.

Migrations are embedded as Dart strings, not read as files: dart compile exe
has no access to the source tree, so a file read would work under dart run and
fail in the container.

The rollback test was verified non-vacuous by moving the version insert outside
the transaction and watching it fail."
```

---

### Task 4: Password hashing, token issuance and refresh rotation

**Files:**
- Create: `server/lib/src/auth/password.dart`
- Create: `server/lib/src/auth/tokens.dart`
- Create: `server/lib/src/auth/auth_routes.dart`
- Create: `server/test/auth/password_test.dart`
- Create: `server/test/auth/tokens_test.dart`
- Create: `server/test/auth/auth_routes_test.dart`
- Create: `server/test/support/seed_fixtures.dart`

**Interfaces:**
- Consumes: `Db`, `row` (Task 3); `ServerConfig` (Task 2).
- Produces:
  - `class PasswordHasher { const PasswordHasher({Argon2Params params}); Future<String> hash(String password); Future<bool> verify(String password, String encoded); }`
  - `class Argon2Params { const Argon2Params({required int memory, required int iterations, required int parallelism}); static const production = …; static const fastForTests = …; }`
  - `class TokenService { TokenService({required Db db, required ServerConfig config, Uuid uuid}); Future<IssuedTokens> issueFor(String userId); Future<IssuedTokens> rotate(String presentedRefreshToken); Future<void> revokeFamilyOf(String presentedRefreshToken); String? userIdFromAccessToken(String jwt); }`
  - `class IssuedTokens { final String accessToken; final String refreshToken; final int expiresInSeconds; final Map<String, Object?> claims; }`
  - `Router authRouter({required Db db, required TokenService tokens, required PasswordHasher hasher})`
- Later tasks rely on: `TokenService.userIdFromAccessToken` (Task 5's authenticate step) and `seedOrganizationWithUser` from `seed_fixtures.dart` (Tasks 5–9 tests).

**Two things to get right.** Argon2id parameters must be stored *inside* the hash string, so raising cost later does not invalidate every existing password. And the refresh chain must detect reuse: a token presented twice means one copy was stolen, and the correct response is to revoke the whole family rather than the presented token alone.

- [ ] **Step 1: Write the failing password tests**

`server/test/auth/password_test.dart`:

```dart
import 'package:campaign_service/src/auth/password.dart';
import 'package:test/test.dart';

void main() {
  // Production params (19 MiB, t=2) cost ~155ms per hash, measured on this
  // repo's dev machine. Tests use cheap params so a suite that hashes dozens of
  // times stays fast; the encoded format carries the params either way.
  const hasher = PasswordHasher(params: Argon2Params.fastForTests);

  test('a hash verifies against its own password', () async {
    final encoded = await hasher.hash('correct horse battery staple');
    expect(await hasher.verify('correct horse battery staple', encoded), isTrue);
  });

  test('a wrong password does not verify', () async {
    final encoded = await hasher.hash('correct horse battery staple');
    expect(await hasher.verify('Correct horse battery staple', encoded), isFalse);
    expect(await hasher.verify('', encoded), isFalse);
  });

  test('two hashes of the same password differ (per-hash salt)', () async {
    final a = await hasher.hash('same');
    final b = await hasher.hash('same');
    expect(a, isNot(b));
    expect(await hasher.verify('same', a), isTrue);
    expect(await hasher.verify('same', b), isTrue);
  });

  test('the encoded form records the algorithm and its parameters', () async {
    final encoded = await hasher.hash('pw');
    expect(encoded, startsWith(r'$argon2id$v=19$'));
    expect(encoded.split(r'$').length, 6, reason: 'alg, v, params, salt, hash');
  });

  // The reason parameters live in the string: raising cost must not lock out
  // every existing user. A hash made with cheap params must still verify after
  // the hasher's own defaults change.
  test('verification uses the parameters stored in the hash, not its own',
      () async {
    final cheap = await const PasswordHasher(params: Argon2Params.fastForTests)
        .hash('shared');
    const expensive = PasswordHasher(params: Argon2Params.production);
    expect(await expensive.verify('shared', cheap), isTrue);
  });

  test('a malformed encoded hash returns false rather than throwing', () async {
    expect(await hasher.verify('pw', 'not-a-hash'), isFalse);
    expect(await hasher.verify('pw', r'$argon2id$v=19$m=x,t=y,p=z$aaaa$bbbb'),
        isFalse);
  });
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
cd server && dart test test/auth/password_test.dart
```

Expected: FAIL — `password.dart` does not exist.

- [ ] **Step 3: Implement the hasher**

`server/lib/src/auth/password.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Argon2id cost parameters. Stored inside every encoded hash so raising cost
/// later does not invalidate existing passwords.
class Argon2Params {
  const Argon2Params({
    required this.memory,
    required this.iterations,
    required this.parallelism,
  });

  /// Minimum number of 1 kB blocks.
  final int memory;
  final int iterations;
  final int parallelism;

  /// OWASP-recommended baseline: 19 MiB, t=2, p=1. Measured at ~155ms per hash
  /// with DartArgon2id on a dev machine — an acceptable login cost.
  static const production =
      Argon2Params(memory: 19456, iterations: 2, parallelism: 1);

  /// For tests only. Fast enough to hash dozens of times per suite.
  static const fastForTests =
      Argon2Params(memory: 256, iterations: 1, parallelism: 1);
}

/// Argon2id password hashing, pure Dart (no FFI): [DartArgon2id] is
/// package:cryptography's own implementation, so the server needs no native
/// build step.
class PasswordHasher {
  const PasswordHasher({this.params = Argon2Params.production});

  final Argon2Params params;

  static const int _saltLength = 16;
  static const int _hashLength = 32;

  Future<String> hash(String password) async {
    final salt = _randomBytes(_saltLength);
    final digest = await _derive(password, salt, params);
    return r'$argon2id$v=19'
        r'$m=${params.memory},t=${params.iterations},p=${params.parallelism}'
        r'$${base64.encode(salt)}$${base64.encode(digest)}';
  }

  /// Verifies against the parameters recorded in [encoded], NOT [params].
  /// Returns false on any malformed input rather than throwing: a corrupt row
  /// must fail authentication, not crash the login route.
  Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split(r'$');
    if (parts.length != 6 || parts[1] != 'argon2id' || parts[2] != 'v=19') {
      return false;
    }
    final parsed = _parseParams(parts[3]);
    if (parsed == null) return false;
    final Uint8List salt;
    final Uint8List expected;
    try {
      salt = base64.decode(parts[4]);
      expected = base64.decode(parts[5]);
    } on FormatException {
      return false;
    }
    final actual = await _derive(password, salt, parsed,
        hashLength: expected.length);
    return _constantTimeEquals(actual, expected);
  }

  Future<Uint8List> _derive(
    String password,
    List<int> salt,
    Argon2Params p, {
    int hashLength = _hashLength,
  }) async {
    final algorithm = DartArgon2id(
      memory: p.memory,
      iterations: p.iterations,
      parallelism: p.parallelism,
      hashLength: hashLength,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Argon2Params? _parseParams(String segment) {
    final values = <String, int>{};
    for (final pair in segment.split(',')) {
      final kv = pair.split('=');
      if (kv.length != 2) return null;
      final n = int.tryParse(kv[1]);
      if (n == null || n <= 0) return null;
      values[kv[0]] = n;
    }
    final m = values['m'], t = values['t'], p = values['p'];
    if (m == null || t == null || p == null) return null;
    return Argon2Params(memory: m, iterations: t, parallelism: p);
  }

  static Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < n; i++) rng.nextInt(256)]);
  }

  /// Length-independent comparison, so a mismatch's position is not timeable.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
```

Note the string in `hash`: raw strings (`r'…'`) do not interpolate, so build the encoded value with a normal interpolated string and escape the literal dollars — e.g. `'\$argon2id\$v=19\$m=${params.memory},…'`. Verify with the "records the algorithm" test rather than by eye.

- [ ] **Step 4: Run password tests — must pass**

```bash
cd server && dart test test/auth/password_test.dart
```

Expected: 6 tests pass.

- [ ] **Step 5: Write the seed fixture helper**

`server/test/support/seed_fixtures.dart`:

```dart
import 'package:campaign_service/src/auth/password.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:postgres/postgres.dart';

/// Inserts an organization, a territory, and one staff user with the given
/// roles and permissions. Returns the user id.
///
/// Roles and permissions MUST come from the vocabulary in
/// lib/core/auth/scope_claims.dart — the client rejects sign-in on any name it
/// does not recognise, so an invented one fails the whole login, not one route.
Future<String> seedOrganizationWithUser(
  Db db, {
  String orgId = 'org-1',
  String territoryId = 'terr-1',
  String userId = 'user-1',
  String username = 'creator',
  String password = 'pw',
  List<String> roles = const ['campaign_creator'],
  PasswordHasher hasher = const PasswordHasher(params: Argon2Params.fastForTests),
}) async {
  await db.execute(
    'INSERT INTO organizations (id, name) VALUES (@id, @name) '
    'ON CONFLICT (id) DO NOTHING',
    params: {'id': orgId, 'name': 'Org'},
  );
  await db.execute(
    'INSERT INTO territories (id, organization_id, name) '
    'VALUES (@id, @org, @name) ON CONFLICT (id) DO NOTHING',
    params: {'id': territoryId, 'org': orgId, 'name': 'Territory'},
  );
  await db.execute(
    'INSERT INTO staff_users '
    '(id, username, display_name, password_hash, organization_id) '
    'VALUES (@id, @u, @d, @h, @org)',
    params: {
      'id': userId,
      'u': username,
      'd': 'Test User',
      'h': await hasher.hash(password),
      'org': orgId,
    },
  );
  for (final role in roles) {
    await db.execute(
      'INSERT INTO staff_user_roles (user_id, role) VALUES (@u, @r)',
      params: {'u': userId, 'r': role},
    );
  }
  await db.execute(
    'INSERT INTO staff_user_territories (user_id, territory_id) '
    'VALUES (@u, @t)',
    params: {'u': userId, 't': territoryId},
  );
  return userId;
}
```

- [ ] **Step 6: Write the failing token tests**

`server/test/auth/tokens_test.dart`:

```dart
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late TokenService tokens;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db);
    tokens = TokenService(db: db, config: config);
  });
  tearDown(() async => db.close());

  test('issues an access token that resolves back to the user', () async {
    final issued = await tokens.issueFor('user-1');
    expect(tokens.userIdFromAccessToken(issued.accessToken), 'user-1');
    expect(issued.expiresInSeconds, 15 * 60);
  });

  test('claims carry only names the client recognises', () async {
    final issued = await tokens.issueFor('user-1');
    expect(issued.claims['userId'], 'user-1');
    expect(issued.claims['organizationId'], 'org-1');
    expect(issued.claims['roles'], ['campaign_creator']);
    expect(issued.claims['territoryIds'], ['terr-1']);
    // campaign_creator's permission set, per the client's vocabulary.
    expect(issued.claims['permissions'],
        containsAll(<String>['campaign_create', 'bulk_import', 'export']));
  });

  test('a tampered access token does not resolve', () async {
    final issued = await tokens.issueFor('user-1');
    final tampered = '${issued.accessToken.substring(0, issued.accessToken.length - 4)}AAAA';
    expect(tokens.userIdFromAccessToken(tampered), isNull);
  });

  test('rotation issues a new refresh token and retires the old one', () async {
    final first = await tokens.issueFor('user-1');
    final second = await tokens.rotate(first.refreshToken);

    expect(second.refreshToken, isNot(first.refreshToken));
    expect(tokens.userIdFromAccessToken(second.accessToken), 'user-1');
  });

  // Reuse means a copy leaked. Revoking only the presented token would leave
  // the attacker's newer token valid, so the whole family goes.
  test('presenting a rotated token twice revokes the entire family', () async {
    final first = await tokens.issueFor('user-1');
    final second = await tokens.rotate(first.refreshToken);

    await expectLater(tokens.rotate(first.refreshToken), throwsA(anything));

    // The legitimate holder's newer token is dead too — that is the point.
    await expectLater(tokens.rotate(second.refreshToken), throwsA(anything));
  });

  test('an unknown refresh token is rejected', () async {
    await expectLater(tokens.rotate('never-issued'), throwsA(anything));
  });

  test('the stored token is hashed, not the token itself', () async {
    final issued = await tokens.issueFor('user-1');
    final res = await db.execute('SELECT token_hash FROM refresh_tokens');
    final stored = row(res.single)['token_hash']! as String;
    expect(stored, isNot(issued.refreshToken),
        reason: 'a database dump must not yield usable refresh tokens');
  });
}
```

- [ ] **Step 7: Run and confirm failure**

```bash
cd server && dart test test/auth/tokens_test.dart
```

Expected: FAIL — `tokens.dart` does not exist.

- [ ] **Step 8: Implement the token service**

`server/lib/src/auth/tokens.dart`. Key implementation points, all load-bearing:

- **Access token:** `dart_jsonwebtoken`, HS256, signed with `config.jwtSecret`, subject = user id, `exp` from `config.accessTokenTtl`. `userIdFromAccessToken` verifies and returns `null` on any `JWTException` — never throws to the caller, so Task 5's middleware has one code path for "not authenticated".
- **Refresh token:** 32 bytes from `Random.secure()`, base64url. Only its `sha256` goes in `refresh_tokens.token_hash`; the plaintext is returned once and never stored.
- **Claims:** built by one query joining `staff_users`, `staff_user_roles`, `staff_user_territories`, then mapping roles to permissions with the table below. Emit exactly these names — the client rejects anything else.
- **Rotation:** inside `db.tx`, select the row by `token_hash`; reject if absent, expired or `revoked_at IS NOT NULL`; **if `used_at IS NOT NULL`, revoke every row sharing `family_id` and throw**; otherwise stamp `used_at`, insert a new row with the same `family_id`, and return new tokens.

Role → permission mapping (the server's authority; the client only renders what it is told):

```dart
const Map<String, List<String>> permissionsByRole = {
  'campaign_creator': ['campaign_create', 'bulk_import', 'export'],
  'marketing_approver': ['campaign_approve', 'campaign_cancel', 'export'],
  'crm_verifier': ['verification_decide', 'sensitive_media_view'],
  'crm_supervisor': [
    'verification_decide',
    'verification_override',
    'sensitive_media_view',
    'nid_reveal',
    'export',
  ],
  'field_user': ['attendance_capture'],
  'admin': [
    'campaign_create',
    'campaign_approve',
    'campaign_cancel',
    'bulk_import',
    'config_manage',
    'export',
  ],
  'reporting_viewer': ['export'],
};
```

- [ ] **Step 9: Run token tests — must pass**

```bash
cd server && dart test test/auth/tokens_test.dart
```

Expected: 7 tests pass.

- [ ] **Step 10: Prove the reuse-detection test is not vacuous**

Change the rotation branch so a reused token revokes only the presented row instead of the family, then re-run.

```bash
cd server && dart test test/auth/tokens_test.dart -n 'revokes the entire family'
```

Expected: **FAIL** on the second `expectLater` — `second.refreshToken` still rotates successfully. Revert and confirm it passes. Without this probe the test would pass on an implementation that revokes nothing useful.

- [ ] **Step 11: Write the failing auth-route tests, then implement the routes**

`server/test/auth/auth_routes_test.dart` asserts the response shape the client parses in `lib/core/auth/auth_service.dart:70-94` — this is the contract, not a preference:

```dart
test('login returns the exact shape the client parses', () async {
  final res = await _post(handler, '/auth/login',
      {'username': 'creator', 'password': 'pw'});

  expect(res.statusCode, 200);
  final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
  expect(body.keys, containsAll(
      <String>['accessToken', 'refreshToken', 'expiresInSeconds', 'claims']));
  expect(body['expiresInSeconds'], isA<num>());

  final claims = body['claims']! as Map<String, Object?>;
  expect(claims.keys, containsAll(<String>[
    'userId', 'displayName', 'organizationId', 'territoryIds',
    'roles', 'permissions',
  ]));
});

test('a wrong password is 401 with no hint about which field failed', () async {
  final res = await _post(handler, '/auth/login',
      {'username': 'creator', 'password': 'wrong'});
  expect(res.statusCode, 401);
  expect(await res.readAsString(), isNot(contains('password')));
});

test('an unknown username is also 401, not 404', () async {
  final res = await _post(handler, '/auth/login',
      {'username': 'nobody', 'password': 'pw'});
  expect(res.statusCode, 401,
      reason: '404 would confirm which usernames exist');
});

test('an inactive user cannot log in', () async {
  await db.execute("UPDATE staff_users SET is_active = FALSE WHERE id = 'user-1'");
  final res = await _post(handler, '/auth/login',
      {'username': 'creator', 'password': 'pw'});
  expect(res.statusCode, 401);
});

test('logout is 204 and is idempotent', () async {
  final issued = await tokens.issueFor('user-1');
  expect((await _post(handler, '/auth/logout',
      {'refreshToken': issued.refreshToken})).statusCode, 204);
  expect((await _post(handler, '/auth/logout',
      {'refreshToken': issued.refreshToken})).statusCode, 204);
});
```

Then implement `authRouter` with `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`. `logout` revokes the family and always answers `204` — the client treats a logout failure as non-fatal (`auth_service.dart:37-39`), so returning an error would only produce noise. **No `Idempotency-Key` is required on any `/auth/*` route** (spec §5): replaying a cached token response would be a defect.

- [ ] **Step 12: Format, analyze, test, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
cd .. && git add server && git commit -m "feat(server): argon2id passwords, JWT issuance, refresh rotation with reuse detection

Cost parameters are stored inside each encoded hash and verification reads them
from there, so raising cost later does not lock out existing users. Pure Dart
via DartArgon2id — no FFI, no native build step; measured ~155ms per hash at
OWASP parameters, and tests use cheap parameters.

Refresh tokens are stored only as sha256, so a database dump yields nothing
usable. Presenting a rotated token twice means a copy leaked, so the whole
rotation family is revoked rather than the presented row — verified
non-vacuous by weakening the branch and watching the test fail.

Claims emit exactly the role and permission names lib/core/auth/scope_claims.dart
recognises; that parser rejects sign-in on any unknown name, so an invented one
breaks login entirely rather than degrading one route."
```

---

### Task 5: Enforcement middleware — authenticate, authorise, scope

**Files:**
- Create: `server/lib/src/auth/auth_context.dart`
- Create: `server/lib/src/auth/middleware.dart`
- Create: `server/test/auth/middleware_test.dart`

**Interfaces:**
- Consumes: `TokenService.userIdFromAccessToken` (Task 4); `Db`, `row` (Task 3).
- Produces:
  - `class AuthContext { final String userId; final String organizationId; final Set<String> roles; final Set<String> permissions; final Set<String> territoryIds; bool can(String permission); }`
  - `Middleware authenticate({required Db db, required TokenService tokens})` — attaches `AuthContext` under request context key `'auth'`, or `401`.
  - `AuthContext authOf(Request request)` — throws `StateError` if `authenticate` did not run, so a route wired without it fails loudly in tests rather than silently treating the caller as anonymous.
  - `Middleware requirePermission(String permission)` — `403` when absent.

**How scope is enforced — read this before writing any query.** Scope is **not** a middleware and **not** a post-fetch `if`. Every campaign query carries `AND organization_id = @org` in its `WHERE` clause, so a row outside the caller's organisation is simply *not found*, and the handler's ordinary not-found path returns `404` (**D7**). This is the same reasoning as the `version` check in Task 3: a rule enforced by the query cannot be forgotten by a code path, whereas a rule enforced by a separate check can. A `403` here would confirm that an ID exists in another organisation.

- [ ] **Step 1: Write the failing middleware tests**

`server/test/auth/middleware_test.dart`:

```dart
import 'dart:convert';

import 'package:campaign_service/src/auth/middleware.dart';
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
  late TokenService tokens;
  late Handler handler;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // campaign_creator
    tokens = TokenService(db: db, config: config);

    handler = const Pipeline()
        .addMiddleware(authenticate(db: db, tokens: tokens))
        .addMiddleware(requirePermission('campaign_create'))
        .addHandler((req) {
          final auth = authOf(req);
          return Response.ok(jsonEncode({
            'userId': auth.userId,
            'organizationId': auth.organizationId,
            'territoryIds': auth.territoryIds.toList(),
          }));
        });
  });
  tearDown(() async => db.close());

  Future<Response> call({String? bearer}) => handler(Request(
        'GET',
        Uri.parse('http://localhost/protected'),
        headers: bearer == null ? null : {'authorization': 'Bearer $bearer'},
      ));

  test('no Authorization header is 401', () async {
    expect((await call()).statusCode, 401);
  });

  test('a malformed or tampered token is 401, never 500', () async {
    expect((await call(bearer: 'not-a-jwt')).statusCode, 401);
    expect((await call(bearer: '')).statusCode, 401);
  });

  test('a valid token with the permission passes and carries scope', () async {
    final issued = await tokens.issueFor('user-1');
    final res = await call(bearer: issued.accessToken);

    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    expect(body['userId'], 'user-1');
    expect(body['organizationId'], 'org-1');
    expect(body['territoryIds'], ['terr-1']);
  });

  test('a valid token WITHOUT the permission is 403', () async {
    await seedOrganizationWithUser(db,
        userId: 'user-2', username: 'field', roles: ['field_user']);
    final issued = await tokens.issueFor('user-2');
    expect((await call(bearer: issued.accessToken)).statusCode, 403);
  });

  // A route wired without `authenticate` must fail loudly. Returning an
  // anonymous context would let a protected handler run unauthenticated and
  // look fine in every test.
  test('authOf throws when authenticate did not run', () async {
    final unguarded = const Pipeline().addHandler((req) {
      authOf(req);
      return Response.ok('unreachable');
    });
    await expectLater(
      unguarded(Request('GET', Uri.parse('http://localhost/x'))),
      throwsA(isA<StateError>()),
    );
  });

  test('a user deactivated after issuance is rejected', () async {
    final issued = await tokens.issueFor('user-1');
    await db.execute(
      "UPDATE staff_users SET is_active = FALSE WHERE id = 'user-1'",
    );
    expect((await call(bearer: issued.accessToken)).statusCode, 401,
        reason: 'a still-valid JWT must not outlive deactivation');
  });
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
cd server && dart test test/auth/middleware_test.dart
```

Expected: FAIL — `middleware.dart` does not exist.

- [ ] **Step 3: Implement `AuthContext` and the middleware**

`server/lib/src/auth/auth_context.dart`:

```dart
/// The caller's identity and scope for one request.
class AuthContext {
  const AuthContext({
    required this.userId,
    required this.organizationId,
    required this.roles,
    required this.permissions,
    required this.territoryIds,
  });

  final String userId;
  final String organizationId;
  final Set<String> roles;
  final Set<String> permissions;
  final Set<String> territoryIds;

  bool can(String permission) => permissions.contains(permission);
}
```

`server/lib/src/auth/middleware.dart`:

```dart
import 'package:shelf/shelf.dart';

import '../db/pool.dart';
import 'auth_context.dart';
import 'tokens.dart';

const String _contextKey = 'auth';

/// Resolves a Bearer token to an [AuthContext], or answers 401.
///
/// The user's row is re-read on every request, so deactivation takes effect
/// immediately instead of waiting out the access token's 15 minutes. That costs
/// one indexed query per request and removes a whole class of "revoked user is
/// still working" incident.
Middleware authenticate({required Db db, required TokenService tokens}) {
  return (Handler inner) {
    return (Request request) async {
      final header = request.headers['authorization'] ?? '';
      if (!header.startsWith('Bearer ')) return _unauthorized();

      final userId = tokens.userIdFromAccessToken(header.substring(7));
      if (userId == null) return _unauthorized();

      final res = await db.execute(
        'SELECT u.id, u.organization_id, '
        '  COALESCE(array_agg(DISTINCT r.role) '
        '    FILTER (WHERE r.role IS NOT NULL), ARRAY[]::text[]) AS roles, '
        '  COALESCE(array_agg(DISTINCT t.territory_id) '
        '    FILTER (WHERE t.territory_id IS NOT NULL), ARRAY[]::text[]) '
        '    AS territory_ids '
        'FROM staff_users u '
        'LEFT JOIN staff_user_roles r ON r.user_id = u.id '
        'LEFT JOIN staff_user_territories t ON t.user_id = u.id '
        'WHERE u.id = @id AND u.is_active '
        'GROUP BY u.id, u.organization_id',
        params: {'id': userId},
      );
      if (res.isEmpty) return _unauthorized();

      final r = row(res.single);
      final roles = (r['roles']! as List).cast<String>().toSet();
      final context = AuthContext(
        userId: r['id']! as String,
        organizationId: r['organization_id']! as String,
        roles: roles,
        permissions: {
          for (final role in roles) ...?permissionsByRole[role],
        },
        territoryIds: (r['territory_ids']! as List).cast<String>().toSet(),
      );

      return inner(request.change(context: {_contextKey: context}));
    };
  };
}

/// The [AuthContext] for [request].
///
/// Throws if [authenticate] did not run. Returning an anonymous context would
/// let a protected handler execute unauthenticated and pass its tests.
AuthContext authOf(Request request) {
  final value = request.context[_contextKey];
  if (value is! AuthContext) {
    throw StateError(
      'authOf() called on a request that did not pass through authenticate(). '
      'Wire the route behind the authenticate middleware.',
    );
  }
  return value;
}

Middleware requirePermission(String permission) {
  return (Handler inner) {
    return (Request request) async {
      if (!authOf(request).can(permission)) {
        return Response.forbidden(null);
      }
      return inner(request);
    };
  };
}

Response _unauthorized() => Response.unauthorized(null);
```

Note: the 401/403 bodies are filled in by Task 6's envelope middleware, which sits *outside* these. Returning bare responses here keeps this file free of the envelope's concerns.

- [ ] **Step 4: Run middleware tests — must pass**

```bash
cd server && dart test test/auth/middleware_test.dart
```

Expected: 6 tests pass.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
cd .. && git add server && git commit -m "feat(server): authenticate, authorise and the scope rule

The user row is re-read per request so deactivation takes effect immediately
rather than after the access token's 15 minutes expire.

authOf() throws when authenticate() did not run. An anonymous fallback would let
a protected handler execute unauthenticated and still pass its tests, which is
the failure mode this project keeps finding: a guard that appears to hold.

Scope is deliberately NOT implemented here. It belongs in every query's WHERE
clause so an out-of-scope row is simply not found and returns 404 — a rule the
query enforces cannot be forgotten by a code path, and 403 would confirm that
an id exists in another organisation (D7)."
```

---

### Task 6: Error envelope, correlation, idempotency and audit

**Files:**
- Create: `server/lib/src/infra/error_envelope.dart`
- Create: `server/lib/src/infra/correlation.dart`
- Create: `server/lib/src/infra/idempotency.dart`
- Create: `server/lib/src/infra/audit.dart`
- Create: `server/test/infra/error_envelope_test.dart`
- Create: `server/test/infra/idempotency_test.dart`
- Create: `server/test/infra/audit_test.dart`

**Interfaces:**
- Consumes: `ApiErrorCode` (Task 1); `Db` (Task 3); `authOf` (Task 5).
- Produces:
  - `class ApiException implements Exception { ApiException(ApiErrorCode code, {String? message, Map<String, Object?>? details}); final ApiErrorCode code; int get status; }`
  - `Middleware errorEnvelope()` — converts `ApiException` and anything unhandled into the envelope; attaches `traceId`.
  - `Middleware correlation()` — resolves the id from `X-Correlation-Id` or mints one; echoes it on the response; exposes `String correlationOf(Request)`.
  - `Middleware idempotency({required Db db})` — for POSTs outside `/auth/`.
  - `class AuditWriter { AuditWriter(Db db); Future<void> write({required String action, required String resourceType, String? resourceId, String? actorId, String? correlationId, Map<String, Object?> payload}); }`

**Header names are fixed by the client, verified in source:** `X-Correlation-Id` and `Idempotency-Key` (`lib/core/network/correlation_interceptor.dart:16-17`). Do not rename them.

**Status codes are fixed by the client's `mapDioError`** (`lib/core/network/dio_client.dart:67-86`), which maps 401→unauthorized, 403→forbidden, 404→notFound, 409→conflict, 422→validation, ≥500→server. `ApiException.status` must agree with that table or a typed `Failure` reaches the UI as the wrong kind.

- [ ] **Step 1: Write the failing envelope tests**

`server/test/infra/error_envelope_test.dart`:

```dart
import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  Handler wrap(Handler inner) => const Pipeline()
      .addMiddleware(correlation())
      .addMiddleware(errorEnvelope())
      .addHandler(inner);

  Future<Map<String, Object?>> errorBody(Response res) async =>
      (jsonDecode(await res.readAsString()) as Map<String, Object?>)['error']!
          as Map<String, Object?>;

  test('an ApiException becomes the documented envelope', () async {
    final res = await wrap((_) => throw ApiException(
          ApiErrorCode.campaignInvalidTransition,
          message: 'Cannot approve a DRAFT campaign.',
          details: {'currentStatus': 'DRAFT'},
        ))(Request('POST', Uri.parse('http://localhost/x')));

    expect(res.statusCode, 409);
    final error = await errorBody(res);
    expect(error['code'], 'CAMPAIGN_INVALID_TRANSITION');
    expect(error['message'], 'Cannot approve a DRAFT campaign.');
    expect((error['details']! as Map)['currentStatus'], 'DRAFT');
    expect(error['traceId'], isA<String>());
  });

  test('status codes match the client mapDioError table', () async {
    Future<int> statusFor(ApiErrorCode code) async =>
        (await wrap((_) => throw ApiException(code))(
                Request('POST', Uri.parse('http://localhost/x'))))
            .statusCode;

    expect(await statusFor(ApiErrorCode.unauthorized), 401);
    expect(await statusFor(ApiErrorCode.forbidden), 403);
    expect(await statusFor(ApiErrorCode.notFound), 404);
    expect(await statusFor(ApiErrorCode.conflictStaleVersion), 409);
    expect(await statusFor(ApiErrorCode.campaignInvalidTransition), 409);
    expect(await statusFor(ApiErrorCode.campaignValidationFailed), 422);
    expect(await statusFor(ApiErrorCode.decisionReasonRequired), 422);
    expect(await statusFor(ApiErrorCode.warningsUnacknowledged), 422);
    expect(await statusFor(ApiErrorCode.idempotencyKeyReused), 422);
  });

  // An unexpected exception must not leak its message: a SQL error naming a
  // column is reconnaissance. The trace id is the bridge to the server log.
  test('an unexpected error is a generic 500 that still carries the trace id',
      () async {
    final res = await wrap((_) => throw StateError('column "secret" not found'))(
        Request('GET', Uri.parse('http://localhost/x')));

    expect(res.statusCode, 500);
    final error = await errorBody(res);
    expect(error['code'], 'INTERNAL');
    expect(error['message'], isNot(contains('secret')));
    expect(error['traceId'], isA<String>());
  });

  test('the client correlation id is honoured and echoed', () async {
    final res = await wrap((req) => Response.ok(correlationOf(req)))(Request(
      'GET',
      Uri.parse('http://localhost/x'),
      headers: {'X-Correlation-Id': 'client-supplied-id'},
    ));

    expect(await res.readAsString(), 'client-supplied-id');
    expect(res.headers['x-correlation-id'], 'client-supplied-id');
  });

  test('a missing correlation id is minted, not left empty', () async {
    final res = await wrap((req) => Response.ok(correlationOf(req)))(
        Request('GET', Uri.parse('http://localhost/x')));
    expect((await res.readAsString()).length, greaterThan(8));
  });
}
```

- [ ] **Step 2: Run, confirm failure, then implement**

```bash
cd server && dart test test/infra/error_envelope_test.dart
```

Expected: FAIL (missing files). Then implement `ApiException` with this status mapping — it must agree with the client table above:

```dart
int get status => switch (code) {
  ApiErrorCode.badRequest => 400,
  ApiErrorCode.unauthorized => 401,
  ApiErrorCode.forbidden => 403,
  ApiErrorCode.notFound => 404,
  ApiErrorCode.conflictStaleVersion => 409,
  ApiErrorCode.campaignInvalidTransition => 409,
  ApiErrorCode.segregationOfDutiesViolation => 403,
  ApiErrorCode.campaignValidationFailed => 422,
  ApiErrorCode.decisionReasonRequired => 422,
  ApiErrorCode.warningsUnacknowledged => 422,
  ApiErrorCode.idempotencyKeyRequired => 400,
  ApiErrorCode.idempotencyKeyReused => 422,
  ApiErrorCode.internal => 500,
};
```

`errorEnvelope()` catches `ApiException` → its status and code; catches everything else → `500` with `ApiErrorCode.internal`, a fixed message (`'An unexpected error occurred.'`) and the trace id, while logging the real error server-side. `correlation()` must run *outside* `errorEnvelope()` so the id exists even when the handler throws.

- [ ] **Step 3: Run envelope tests — must pass**

```bash
cd server && dart test test/infra/error_envelope_test.dart
```

Expected: 5 tests pass.

- [ ] **Step 4: Write the failing idempotency tests**

`server/test/infra/idempotency_test.dart` — the behaviours that matter:

```dart
test('a repeated key replays the first response verbatim', () async {
  var calls = 0;
  final handler = wrapWithAuth((req) {
    calls++;
    return Response(201, body: jsonEncode({'id': 'campaign-$calls'}));
  });

  final first = await post(handler, key: 'k1', body: {'name': 'A'});
  final second = await post(handler, key: 'k1', body: {'name': 'A'});

  expect(calls, 1, reason: 'the handler must run exactly once');
  expect(second.statusCode, first.statusCode);
  expect(await second.readAsString(), await first.readAsString());
});

// The guard that stops a client's key collision from returning someone else's
// answer. Without the body hash, reusing a key with different content silently
// replays the wrong response.
test('the same key with a different body is rejected, not replayed', () async {
  final handler = wrapWithAuth((_) => Response(201, body: '{"id":"c1"}'));
  await post(handler, key: 'k1', body: {'name': 'A'});

  final res = await post(handler, key: 'k1', body: {'name': 'B'});
  expect(res.statusCode, 422);
  expect(jsonDecode(await res.readAsString())['error']['code'],
      'IDEMPOTENCY_KEY_REUSED');
});

test('two users may use the same key independently', () async {
  // Keys are scoped per user: PRIMARY KEY (user_id, key).
});

test('a POST without a key is rejected on a domain route', () async {
  final res = await post(handler, key: null, body: {'name': 'A'});
  expect(res.statusCode, 400);
  expect(jsonDecode(await res.readAsString())['error']['code'],
      'IDEMPOTENCY_KEY_REQUIRED');
});

test('GET needs no key', () async {
  expect((await get(handler)).statusCode, 200);
});

// A failed write must not be cached, or a transient 500 becomes permanent for
// that key and the client can never retry it.
test('a failed response is not stored', () async {
  var calls = 0;
  final handler = wrapWithAuth((_) {
    calls++;
    return Response(500, body: '{"error":{"code":"INTERNAL"}}');
  });
  await post(handler, key: 'k1', body: {'name': 'A'});
  await post(handler, key: 'k1', body: {'name': 'A'});
  expect(calls, 2, reason: 'only 2xx responses are replayable');
});
```

- [ ] **Step 5: Implement idempotency**

`server/lib/src/infra/idempotency.dart`. Rules, all tested above:

- Applies to `POST` only, and the router mounts it on domain routes — **never on `/auth/*`** (spec §5): replaying a token response would hand back a rotated refresh token.
- Missing/empty header → `ApiException(ApiErrorCode.idempotencyKeyRequired)`.
- `request_hash` = `sha256` of the raw body bytes. Read the body once and re-attach it with `request.change(body: bytes)`, or the downstream handler receives an empty stream — a shelf body is single-subscription.
- Existing row with a matching hash → replay `response_status` and `response_body`.
- Existing row with a different hash → `ApiException(ApiErrorCode.idempotencyKeyReused)`.
- Store only `2xx` responses, with `expires_at = now() + 24h`.

- [ ] **Step 6: Run idempotency tests — must pass**

```bash
cd server && dart test test/infra/idempotency_test.dart
```

Expected: all pass. Fill in the two stubbed test bodies (per-user isolation, GET) before running — a stubbed test that passes is worse than no test.

- [ ] **Step 7: Implement and test the audit writer**

`server/lib/src/infra/audit.dart` — one insert into `audit_events`, stamping `correlation_id` from `correlationOf(request)`. `server/test/infra/audit_test.dart` asserts that a written event is readable back with its correlation id, and that a null `actorId` is allowed (login failures have no actor yet).

- [ ] **Step 8: Format, analyze, test, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
cd .. && git add server && git commit -m "feat(server): error envelope, correlation, idempotency and audit

Envelope status codes are pinned to the client's own mapDioError table
(dio_client.dart:67-86) and tested against it, so a typed Failure never reaches
the UI as the wrong kind. Unexpected errors return a fixed 500 message — a SQL
error naming a column is reconnaissance — while the trace id bridges to the log.

Idempotency stores a sha256 of the request body alongside the key: without it, a
key reused with different content would silently replay the wrong response.
Keys are scoped per user, and only 2xx responses are stored, so a transient 500
does not become permanent for that key. Not applied to /auth/*, where replaying
a rotated refresh token would be a defect.

Header names are the ones the client actually sends: X-Correlation-Id and
Idempotency-Key, verified in correlation_interceptor.dart:16-17."
```

---

# Phase 2 — The campaign vertical slice (D-G … D-I)

Tasks 7–11. This phase is what makes Phase 1 falsifiable: it puts a real client in front of the foundation.

---

### Task 7: The status machine and submit validation — pure, no IO

**Files:**
- Create: `server/lib/src/campaign/status_machine.dart`
- Create: `server/lib/src/campaign/validation.dart`
- Create: `server/test/campaign/status_machine_test.dart`
- Create: `server/test/campaign/validation_test.dart`

**Interfaces:**
- Consumes: `CampaignStatus`, `CampaignDecisionInput`, `ApiErrorCode` (Task 1).
- Produces:
  - `CampaignStatus? nextStatusForSubmit(CampaignStatus current)` — `null` when illegal.
  - `CampaignStatus? nextStatusForDecision(CampaignStatus current, CampaignDecisionInput decision)` — `null` when illegal.
  - `class FieldError { const FieldError(this.field, this.message); final String field; final String message; }`
  - `List<FieldError> validateForSubmit(CampaignDraftInput input)`
  - `class CampaignDraftInput { … }` — plain data, mirroring the client's submitted draft.
  - `class SessionInput { final String? venue; final int? capacity; final DateTime? startAt; final DateTime? endAt; }`

**Why these two files hold no IO.** They encode the two rules most likely to be wrong and most expensive to get wrong, and a database would make them slow to test exhaustively. Every transition — legal and illegal — is asserted here in milliseconds.

- [ ] **Step 1: Write the exhaustive status-machine test**

`server/test/campaign/status_machine_test.dart`:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/campaign/status_machine.dart';
import 'package:test/test.dart';

void main() {
  group('submit', () {
    // The authoring PRD: "transition only from Draft/Returned to Pending
    // approval". The mock's setStatus was unconditional, so a DRAFT could be
    // approved without ever being submitted.
    test('is legal only from DRAFT and RETURNED', () {
      expect(nextStatusForSubmit(CampaignStatus.draft),
          CampaignStatus.pendingApproval);
      expect(nextStatusForSubmit(CampaignStatus.returned),
          CampaignStatus.pendingApproval);

      for (final s in CampaignStatus.values.where((s) =>
          s != CampaignStatus.draft && s != CampaignStatus.returned)) {
        expect(nextStatusForSubmit(s), isNull, reason: 'submit from ${s.name}');
      }
    });
  });

  group('decision', () {
    test('is legal only from PENDING_APPROVAL', () {
      for (final d in CampaignDecisionInput.values) {
        for (final s in CampaignStatus.values
            .where((s) => s != CampaignStatus.pendingApproval)) {
          expect(nextStatusForDecision(s, d), isNull,
              reason: '${d.name} from ${s.name}');
        }
      }
    });

    test('maps each decision to its state', () {
      const pending = CampaignStatus.pendingApproval;
      expect(nextStatusForDecision(pending, CampaignDecisionInput.approve),
          CampaignStatus.approved);
      expect(
          nextStatusForDecision(
              pending, CampaignDecisionInput.returnForCorrection),
          CampaignStatus.returned);
      expect(nextStatusForDecision(pending, CampaignDecisionInput.reject),
          CampaignStatus.cancelled);
    });

    test('CANCELLED is terminal from every action', () {
      for (final d in CampaignDecisionInput.values) {
        expect(nextStatusForDecision(CampaignStatus.cancelled, d), isNull);
      }
      expect(nextStatusForSubmit(CampaignStatus.cancelled), isNull);
    });

    // A returned campaign must remain correctable and resubmittable — the PRD
    // requires return "without deleting draft data".
    test('RETURNED can be resubmitted, closing the correction loop', () {
      final resubmitted = nextStatusForSubmit(CampaignStatus.returned);
      expect(resubmitted, CampaignStatus.pendingApproval);
      expect(
          nextStatusForDecision(resubmitted!, CampaignDecisionInput.approve),
          CampaignStatus.approved);
    });
  });
}
```

- [ ] **Step 2: Run, confirm failure, implement the machine**

```bash
cd server && dart test test/campaign/status_machine_test.dart
```

Expected: FAIL. Then:

```dart
import 'package:campaign_contracts/campaign_contracts.dart';

/// The campaign lifecycle. The server is the only authority for it: the mock
/// set status unconditionally, which allowed approving a campaign that was
/// never submitted.
///
/// ACTIVE, PAUSED and COMPLETED are reachable in the lifecycle but are driven
/// by session operations (sub-project 3), not by the endpoints in this slice.
CampaignStatus? nextStatusForSubmit(CampaignStatus current) => switch (current) {
  CampaignStatus.draft || CampaignStatus.returned =>
    CampaignStatus.pendingApproval,
  _ => null,
};

CampaignStatus? nextStatusForDecision(
  CampaignStatus current,
  CampaignDecisionInput decision,
) {
  if (current != CampaignStatus.pendingApproval) return null;
  return switch (decision) {
    CampaignDecisionInput.approve => CampaignStatus.approved,
    CampaignDecisionInput.returnForCorrection => CampaignStatus.returned,
    CampaignDecisionInput.reject => CampaignStatus.cancelled,
  };
}
```

- [ ] **Step 3: Write the failing validation test**

The authoring PRD requires **server revalidation on submit** with per-field errors, because the wizard renders errors inline (**D6**). `server/test/campaign/validation_test.dart`:

```dart
import 'package:campaign_service/src/campaign/validation.dart';
import 'package:test/test.dart';

void main() {
  CampaignDraftInput valid({List<SessionInput>? sessions}) => CampaignDraftInput(
        name: 'Q3 Carpenter Drive',
        type: 'ATTENDANCE',
        objective: 'Verify attendance',
        territoryIds: const ['terr-1'],
        target: 100,
        budgetReference: 'BUD-1',
        approverId: 'user-2',
        ownerId: 'user-1',
        geofenceEnabled: true,
        sessions: sessions ??
            [
              SessionInput(
                venue: 'Hall A',
                capacity: 50,
                startAt: DateTime.utc(2026, 9, 1, 9),
                endAt: DateTime.utc(2026, 9, 1, 12),
              ),
            ],
      );

  test('a complete draft has no errors', () {
    expect(validateForSubmit(valid()), isEmpty);
  });

  test('errors are keyed by field so the wizard can render them inline', () {
    final errors = validateForSubmit(
      CampaignDraftInput(
        name: '',
        type: '',
        objective: null,
        territoryIds: const [],
        target: 0,
        budgetReference: null,
        approverId: null,
        ownerId: 'user-1',
        geofenceEnabled: false,
        sessions: const [],
      ),
    );

    final fields = errors.map((e) => e.field).toSet();
    expect(fields, containsAll(<String>[
      'name', 'type', 'territoryIds', 'approverId', 'sessions',
    ]));
    // Every error must name a field: a single opaque message satisfies the
    // endpoint and fails the screen.
    expect(errors.every((e) => e.field.isNotEmpty), isTrue);
    expect(errors.every((e) => e.message.isNotEmpty), isTrue);
  });

  // Explicitly required by the PRD, and the acceptance criterion names the
  // affected windows.
  test('overlapping sessions are rejected and identify both windows', () {
    final errors = validateForSubmit(valid(sessions: [
      SessionInput(
        venue: 'Hall A',
        capacity: 10,
        startAt: DateTime.utc(2026, 9, 1, 9),
        endAt: DateTime.utc(2026, 9, 1, 12),
      ),
      SessionInput(
        venue: 'Hall A',
        capacity: 10,
        startAt: DateTime.utc(2026, 9, 1, 11),
        endAt: DateTime.utc(2026, 9, 1, 14),
      ),
    ]));

    final overlap = errors.where((e) => e.field.startsWith('sessions'));
    expect(overlap, isNotEmpty);
    expect(overlap.first.message, contains('overlap'));
  });

  test('adjacent sessions that merely touch do not overlap', () {
    expect(
      validateForSubmit(valid(sessions: [
        SessionInput(
          venue: 'Hall A',
          capacity: 10,
          startAt: DateTime.utc(2026, 9, 1, 9),
          endAt: DateTime.utc(2026, 9, 1, 12),
        ),
        SessionInput(
          venue: 'Hall A',
          capacity: 10,
          startAt: DateTime.utc(2026, 9, 1, 12),
          endAt: DateTime.utc(2026, 9, 1, 15),
        ),
      ])),
      isEmpty,
      reason: 'end == start is back-to-back scheduling, not a conflict',
    );
  });

  test('a session ending before it starts is rejected', () {
    final errors = validateForSubmit(valid(sessions: [
      SessionInput(
        venue: 'Hall A',
        capacity: 10,
        startAt: DateTime.utc(2026, 9, 1, 12),
        endAt: DateTime.utc(2026, 9, 1, 9),
      ),
    ]));
    expect(errors.map((e) => e.field), contains('sessions[0].endAt'));
  });

  test('capacity must be positive when present', () {
    final errors = validateForSubmit(valid(sessions: [
      SessionInput(
        venue: 'Hall A',
        capacity: 0,
        startAt: DateTime.utc(2026, 9, 1, 9),
        endAt: DateTime.utc(2026, 9, 1, 12),
      ),
    ]));
    expect(errors.map((e) => e.field), contains('sessions[0].capacity'));
  });

  // SoD is checked here as data, not policy: whether it is ENFORCED is a config
  // lookup in Task 9. This only reports that owner == approver.
  test('an approver equal to the owner is reported', () {
    final errors = validateForSubmit(CampaignDraftInput(
      name: 'X',
      type: 'ATTENDANCE',
      objective: 'o',
      territoryIds: const ['terr-1'],
      target: 1,
      budgetReference: 'B',
      approverId: 'user-1',
      ownerId: 'user-1',
      geofenceEnabled: false,
      sessions: [
        SessionInput(
          venue: 'Hall',
          capacity: 1,
          startAt: DateTime.utc(2026, 9, 1, 9),
          endAt: DateTime.utc(2026, 9, 1, 10),
        ),
      ],
    ));
    expect(errors.map((e) => e.field), contains('approverId'));
  });
}
```

- [ ] **Step 4: Implement validation, then run both suites**

Implement `CampaignDraftInput`, `SessionInput`, `FieldError` and `validateForSubmit` covering: non-empty `name` and `type`; at least one territory; `target` greater than zero; `approverId` present and different from `ownerId`; at least one session; per session, `startAt`/`endAt` present, `endAt` after `startAt`, `capacity` positive when present; and pairwise overlap detection keyed `sessions[i]`. Overlap is strict — `endA > startB && endB > startA` — so touching windows pass.

```bash
cd server && dart test test/campaign/
```

Expected: all pass (5 machine + 8 validation).

- [ ] **Step 5: Commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server && git commit -m "feat(server): campaign status machine and submit validation, both IO-free

Every transition is asserted, legal and illegal, by iterating CampaignStatus
rather than listing cases — adding a status makes the test cover it
automatically. The mock's setStatus was unconditional, so a DRAFT could be
approved without ever being submitted.

Validation returns field-keyed errors because the wizard renders them inline
(D6); a single opaque message satisfies the endpoint and fails the screen.
Overlap is strict, so back-to-back sessions where end == start are scheduling,
not a conflict."
```

---

### Task 8: Campaign read endpoints — list with real paging and filtering, and get

**Files:**
- Create: `server/lib/src/campaign/campaign_model.dart`
- Create: `server/lib/src/campaign/campaign_repo.dart`
- Create: `server/lib/src/campaign/campaign_routes.dart`
- Create: `server/test/campaign/campaign_read_test.dart`
- Modify: `server/bin/server.dart` (mount the router with middleware)

**Interfaces:**
- Consumes: `Db`, `row`; `AuthContext`, `authOf`, `authenticate`, `requirePermission`; `ApiException`; `CampaignStatus`.
- Produces:
  - `class CampaignRow { final String id, name, type, organizationId, ownerId; final CampaignStatus status; final String? objective, venue, budgetReference, approverId; final DateTime? startAt, endAt; final int targetAudience, version; final List<String> territoryIds; Map<String, Object?> toWireJson(); }`
  - `class CampaignRepo { CampaignRepo(Db db); Future<({List<CampaignRow> items, int total})> list({required String organizationId, String? search, List<CampaignStatus> statuses, required int page, required int pageSize}); Future<CampaignRow?> findById(String id, {required String organizationId}); }`
  - `Router campaignRouter({required Db db, required CampaignRepo repo})`

**The wire shape is fixed by the client's DTO** (`lib/data/campaign/campaign_dto.dart`): `id`, `name`, `type`, `organizationId`, `status`, `ownerId`, `startAt`, `endAt`, `venue`, `objective`, `territoryIds`, `targetAudience`, `verifiedAttendance`. List responses are `{"items": [...], "total": <int>}`. `verifiedAttendance` is **always `0`** in this slice and documented as derived, never stored — the records it counts do not exist until sub-project 4.

- [ ] **Step 1: Write the failing read tests**

`server/test/campaign/campaign_read_test.dart` — the four behaviours the mock only pretended to have:

```dart
test('list paginates for real, and total counts all matches not the page', () async {
  await seedCampaigns(db, count: 25);
  final res = await get(handler, '/campaigns?page=2&pageSize=10', token);

  final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
  expect((body['items']! as List).length, 10);
  expect(body['total'], 25,
      reason: 'the mock returned items.length, which made paging invisible');
});

test('pageSize is capped server-side', () async {
  await seedCampaigns(db, count: 120);
  final res = await get(handler, '/campaigns?pageSize=10000', token);
  final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
  expect((body['items']! as List).length, lessThanOrEqualTo(100));
});

test('q filters by name, case-insensitively', () async {
  await seedCampaign(db, id: 'c1', name: 'Carpenter Drive');
  await seedCampaign(db, id: 'c2', name: 'Mason Workshop');
  final res = await get(handler, '/campaigns?q=carpenter', token);
  final items = (jsonDecode(await res.readAsString())
      as Map<String, Object?>)['items']! as List;
  expect(items.map((e) => (e as Map)['id']), ['c1']);
});

test('repeated status params filter to that set', () async {
  await seedCampaign(db, id: 'c1', status: CampaignStatus.draft);
  await seedCampaign(db, id: 'c2', status: CampaignStatus.approved);
  await seedCampaign(db, id: 'c3', status: CampaignStatus.cancelled);

  final res = await get(
      handler, '/campaigns?status=DRAFT&status=APPROVED', token);
  final items = (jsonDecode(await res.readAsString())
      as Map<String, Object?>)['items']! as List;
  expect(items.map((e) => (e as Map)['id']).toSet(), {'c1', 'c2'});
});

test('an unknown status value is a 400, not silently ignored', () async {
  final res = await get(handler, '/campaigns?status=NOPE', token);
  expect(res.statusCode, 400);
});

test('the wire shape matches the client DTO exactly', () async {
  await seedCampaign(db, id: 'c1');
  final res = await get(handler, '/campaigns/c1', token);
  final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;

  expect(body.keys, containsAll(<String>[
    'id', 'name', 'type', 'organizationId', 'status', 'ownerId',
    'startAt', 'endAt', 'venue', 'objective', 'territoryIds',
    'targetAudience', 'verifiedAttendance', 'version',
  ]));
  expect(body['status'], 'DRAFT');
  expect(body['verifiedAttendance'], 0,
      reason: 'derived, never stored, until sub-project 4');
});

// D7. The scope filter lives in the WHERE clause, so this is the ordinary
// not-found path rather than a separate check that could be forgotten.
test('a campaign in another organization is 404, never 403', () async {
  await seedOrganizationWithUser(db,
      orgId: 'org-2', territoryId: 'terr-2', userId: 'user-9',
      username: 'other');
  await seedCampaign(db, id: 'foreign', organizationId: 'org-2',
      ownerId: 'user-9');

  final res = await get(handler, '/campaigns/foreign', token);
  expect(res.statusCode, 404, reason: '403 would confirm the id exists');
});

test('a missing campaign is 404 with the NOT_FOUND code', () async {
  final res = await get(handler, '/campaigns/nope', token);
  expect(res.statusCode, 404);
  expect(jsonDecode(await res.readAsString())['error']['code'], 'NOT_FOUND');
});

test('timestamps are UTC ISO-8601 on the wire', () async {
  await seedCampaign(db, id: 'c1', startAt: DateTime.utc(2026, 9, 1, 9));
  final res = await get(handler, '/campaigns/c1', token);
  final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
  expect(body['startAt'], '2026-09-01T09:00:00.000Z');
});
```

- [ ] **Step 2: Run, confirm failure, implement**

```bash
cd server && dart test test/campaign/campaign_read_test.dart
```

Expected: FAIL. Then implement the model, repo and routes. Repo rules:

- **Every query carries `AND organization_id = @org`.** Not a post-fetch check — see Task 5.
- `total` comes from a `COUNT(*)` over the same predicate, not from the page length.
- `pageSize` clamped to `1..100`; `page` clamped to `>= 1`.
- `q` matches `lower(name) LIKE lower('%' || @q || '%')`, which uses the `campaigns_name_idx` on `lower(name)` for prefix matches.
- Unknown `status` value → `ApiException(ApiErrorCode.badRequest)` naming the offending value. Silently dropping it would return a superset of what was asked for.
- `territoryIds` aggregated from `campaign_territories`.

- [ ] **Step 3: Run read tests — must pass, then mount the router**

```bash
cd server && dart test test/campaign/campaign_read_test.dart
```

In `bin/server.dart`, compose the pipeline in this order and mount `/campaigns` behind it:

```dart
final handler = const Pipeline()
    .addMiddleware(correlation())
    .addMiddleware(errorEnvelope())
    .addMiddleware(authenticate(db: db, tokens: tokens))
    .addHandler(router.call);
```

`/auth/*` mounts **outside** `authenticate` (nobody has a token yet) and outside `idempotency`. Per-route `requirePermission` and `idempotency` are applied inside `campaignRouter`.

- [ ] **Step 4: Commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
cd .. && git add server && git commit -m "feat(server): campaign list and get with real paging, filtering and scope

The mock ignored q, status, page and pageSize while the client sent all four,
and returned total = items.length so paging was invisible. All four now work,
pageSize is capped at 100, and an unknown status value is a 400 rather than
silently widening the result set.

Scope is a WHERE clause, so a campaign in another organization is simply not
found and returns 404 — 403 would confirm the id exists (D7).

verifiedAttendance is 0 and documented as derived-never-stored; the records it
counts do not exist until sub-project 4."
```

---

### Task 9: Campaign writes — create, update, submit, decide

**Files:**
- Modify: `server/lib/src/campaign/campaign_repo.dart` (writes)
- Modify: `server/lib/src/campaign/campaign_routes.dart` (write routes)
- Create: `server/lib/src/campaign/config_gate.dart` (SoD lookup)
- Create: `server/test/campaign/campaign_write_test.dart`
- Create: `server/test/campaign/sod_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces:
  - `Future<CampaignRow> create(CampaignDraftInput input, {required String organizationId, required String ownerId})`
  - `Future<CampaignRow> updateDraft(String id, CampaignDraftInput input, {required String organizationId, required int expectedVersion})`
  - `Future<CampaignRow> submit(String id, {required String organizationId, required String submittedBy, required int expectedVersion})`
  - `Future<CampaignRow> decide(String id, {required String organizationId, required String reviewerId, required CampaignDecisionInput decision, String? reason, required List<String> acknowledgedWarnings, required int expectedVersion, String? correlationId})`
  - `Future<bool> sodEnforced(Db db)`

- [ ] **Step 1: Write the failing write tests**

`server/test/campaign/campaign_write_test.dart` — each test maps to a PRD acceptance criterion:

```dart
test('create returns a DRAFT with version 1', () async {
  final res = await post(handler, '/campaigns', draftBody(), token, key: 'k1');
  expect(res.statusCode, 200);
  final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
  expect(body['status'], 'DRAFT');
  expect(body['version'], 1);
});

// "when submit is double-tapped or retried, then ONE Pending approval
// transition and audit event result"
test('a double-tapped submit produces one transition and one audit event',
    () async {
  final id = await createDraft(handler, token);
  final first = await post(handler, '/campaigns/$id/submit',
      {'version': 1}, token, key: 'submit-1');
  final second = await post(handler, '/campaigns/$id/submit',
      {'version': 1}, token, key: 'submit-1');

  expect(first.statusCode, 200);
  expect(await second.readAsString(), await first.readAsString(),
      reason: 'the replay must be byte-identical, not a fresh 409');

  final audits = await db.execute(
    "SELECT id FROM audit_events WHERE action = 'campaign.submitted' "
    'AND resource_id = @id',
    params: {'id': id},
  );
  expect(audits.length, 1);
});

test('submitting with a stale version is 409 CONFLICT_STALE_VERSION', () async {
  final id = await createDraft(handler, token);
  await post(handler, '/campaigns/$id/submit', {'version': 1}, token,
      key: 'k-a');
  final res = await post(handler, '/campaigns/$id/submit', {'version': 1},
      token, key: 'k-b');

  expect(res.statusCode, 409);
  expect(jsonDecode(await res.readAsString())['error']['code'],
      'CONFLICT_STALE_VERSION');
});

test('submitting an already-approved campaign is 409 INVALID_TRANSITION',
    () async {
  final id = await approvedCampaign(db, handler);
  final res = await post(handler, '/campaigns/$id/submit',
      {'version': currentVersion}, approverToken, key: 'k-c');
  expect(jsonDecode(await res.readAsString())['error']['code'],
      'CAMPAIGN_INVALID_TRANSITION');
});

// "when submitted without reason, then no transition occurs and a specific
// error is shown"
test('return without a reason leaves the status untouched', () async {
  final id = await pendingCampaign(db, handler);
  final res = await post(handler, '/campaigns/$id/decision',
      {'decision': 'RETURN_FOR_CORRECTION', 'version': 2},
      approverToken, key: 'k-d');

  expect(res.statusCode, 422);
  expect(jsonDecode(await res.readAsString())['error']['code'],
      'DECISION_REASON_REQUIRED');

  final after = await get(handler, '/campaigns/$id', approverToken);
  expect(jsonDecode(await after.readAsString())['status'], 'PENDING_APPROVAL',
      reason: 'a rejected decision must not half-apply');
});

test('approve with unacknowledged critical warnings is 422', () async {
  final id = await pendingCampaignWithWarnings(db, handler);
  final res = await post(handler, '/campaigns/$id/decision',
      {'decision': 'APPROVE', 'version': 2, 'acknowledgedWarnings': <String>[]},
      approverToken, key: 'k-e');

  expect(jsonDecode(await res.readAsString())['error']['code'],
      'WARNINGS_UNACKNOWLEDGED');
});

test('a decision records reviewer, reason, acknowledgements, version and trace',
    () async {
  final id = await pendingCampaign(db, handler);
  await post(handler, '/campaigns/$id/decision',
      {'decision': 'APPROVE', 'version': 2, 'acknowledgedWarnings': ['w1']},
      approverToken, key: 'k-f',
      correlationId: 'trace-abc');

  final res = await db.execute(
    'SELECT * FROM campaign_decisions WHERE campaign_id = @id',
    params: {'id': id},
  );
  final d = row(res.single);
  expect(d['reviewer_id'], 'user-2');
  expect(d['decision'], 'APPROVE');
  expect(d['version_at_decision'], 2);
  expect(d['correlation_id'], 'trace-abc');
  expect(jsonDecode(d['acknowledged_warnings']! as String), ['w1']);
});

test('submit stores an immutable snapshot for the changed-field diff', () async {
  final id = await createDraft(handler, token, name: 'Original');
  await post(handler, '/campaigns/$id/submit', {'version': 1}, token,
      key: 'k-g');

  final res = await db.execute(
    'SELECT snapshot, version FROM campaign_submissions '
    'WHERE campaign_id = @id',
    params: {'id': id},
  );
  final snap = jsonDecode(row(res.single)['snapshot']! as String)
      as Map<String, Object?>;
  expect(snap['name'], 'Original');
});

test('submit revalidates server-side and returns field-keyed errors', () async {
  // A draft created directly in the database, bypassing the wizard, with
  // overlapping sessions — exactly what a malicious or stale client sends.
  final id = await seedInvalidDraft(db);
  final res = await post(handler, '/campaigns/$id/submit', {'version': 1},
      token, key: 'k-h');

  expect(res.statusCode, 422);
  final error = jsonDecode(await res.readAsString())['error']
      as Map<String, Object?>;
  expect(error['code'], 'CAMPAIGN_VALIDATION_FAILED');
  final fields = (error['details']! as Map)['fields']! as List;
  expect(fields, isNotEmpty);
  expect((fields.first as Map)['field'], isA<String>());
});
```

- [ ] **Step 2: Write the SoD test**

`server/test/campaign/sod_test.dart`:

```dart
// "Given the campaign creator is also the current user under SoD policy, when
// approval opens, then decision controls are unavailable and the reason is
// shown." The server enforces it regardless of what the UI does.
test('the owner cannot decide their own campaign when SoD is enforced',
    () async {
  final id = await pendingCampaign(db, handler, ownerId: 'user-1');
  final res = await post(handler, '/campaigns/$id/decision',
      {'decision': 'APPROVE', 'version': 2}, ownerTokenWithApprovePermission,
      key: 'k-i');

  expect(res.statusCode, 403);
  expect(jsonDecode(await res.readAsString())['error']['code'],
      'SEGREGATION_OF_DUTIES_VIOLATION');
});

test('SoD defaults to enforced when the config row is missing', () async {
  await db.execute("DELETE FROM app_config WHERE key = 'sod.enforced'");
  expect(await sodEnforced(db), isTrue,
      reason: 'a missing row must not silently disable a governance control');
});

test('SoD can be disabled by configuration', () async {
  await db.execute(
      "UPDATE app_config SET value = 'false' WHERE key = 'sod.enforced'");
  final id = await pendingCampaign(db, handler, ownerId: 'user-1');
  final res = await post(handler, '/campaigns/$id/decision',
      {'decision': 'APPROVE', 'version': 2}, ownerTokenWithApprovePermission,
      key: 'k-j');
  expect(res.statusCode, 200);
});
```

- [ ] **Step 3: Implement the writes**

Rules, in the order the handler must apply them:

1. Resolve `AuthContext`; `requirePermission('campaign_create')` on create/update/submit, `'campaign_approve'` on decide.
2. Idempotency middleware has already replayed or admitted the request.
3. Load the campaign **with the scope predicate**; absent → `notFound`.
4. Check the status machine; illegal → `campaignInvalidTransition` with `details: {'currentStatus': …}`.
5. On submit: `validateForSubmit`; non-empty → `campaignValidationFailed` with `details: {'fields': [{field, message}, …]}`.
6. On decide: SoD when `sodEnforced(db)` and `owner_id == reviewerId` → `segregationOfDutiesViolation`; reason required for return/reject → `decisionReasonRequired`; unacknowledged critical warnings on approve → `warningsUnacknowledged`.
7. Inside one `db.tx`: `UPDATE campaigns SET status = …, version = version + 1 WHERE id = @id AND organization_id = @org AND version = @expected`. **Zero affected rows → `conflictStaleVersion`.** Then insert the submission snapshot or decision row, then the audit event — all through the `TxSession`.

Every check that can fail must fail *before* the transaction opens, except the version check, which is the transaction.

- [ ] **Step 4: Run all campaign tests, then probe the version check**

```bash
cd server && dart test test/campaign/
```

Then temporarily drop `AND version = @expected` from the update and re-run:

```bash
cd server && dart test test/campaign/campaign_write_test.dart -n 'stale version'
```

Expected: **FAIL**. Revert and confirm green. The whole concurrency guarantee is that clause; a test that passes without it is testing nothing.

- [ ] **Step 5: Commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
cd .. && git add server && git commit -m "feat(server): campaign create, update, submit and decide

Concurrency is the UPDATE's own WHERE clause: zero affected rows is the stale-
version detection, so a code path that forgets to compare cannot overwrite.
Verified by removing the clause and watching the test fail.

Submit revalidates server-side with field-keyed errors (D6) — a draft written
directly to the database with overlapping sessions is rejected, because the
wizard is not a trust boundary. It also stores an immutable snapshot, without
which a resubmission has nothing to diff against.

Decisions record reviewer, decision, reason, warning acknowledgements, version
and correlation id, which is exactly what the approval PRD requires. Return
without a reason is 422 and leaves the status untouched: a rejected decision
must not half-apply.

SoD reads app_config and defaults to enforced when the row is missing, because
an unreadable config must not silently disable a governance control."
```

---

### Task 10: Client migration — wire naming, version, acknowledgements, idempotency keys

**Files:**
- Delete: `lib/data/campaign/campaign_dto.dart`, `lib/data/campaign/campaign_dto.g.dart`
- Create: `lib/data/campaign/campaign_mapper.dart`
- Modify: `lib/data/campaign/campaign_repository_impl.dart`
- Modify: `lib/domain/campaign/campaign_repository.dart` (signatures gain `version`)
- Modify: `lib/features/campaign_approval/presentation/campaign_approval_screen.dart` (pass version + acknowledgements)
- Modify: `lib/features/campaign_detail/presentation/campaign_detail_screen.dart` (pass version on submit)
- Modify: `tool/mock_server/bin/server.dart` (decision wire values, version, paging)
- Modify/Create: `test/data/campaign_mapper_test.dart`

**Interfaces:**
- Consumes: `CampaignStatus`, `CampaignDecisionInput` from `campaign_contracts` (Task 1).
- Produces: `Campaign campaignFromWire(Map<String, Object?> json)`, `Map<String, Object?> draftToWire(CampaignDraft draft)`, and `String draftDecisionWire(CampaignDecision decision)` — which maps the domain decision onto `CampaignDecisionInput.wireValue` so the `SCREAMING_SNAKE` value has exactly one definition. Repository methods gain a required `int version` on `submitForApproval` and `decide`, and `decide` gains `required List<String> acknowledgedWarnings`.

**This is the breaking-change task.** The wire naming change (`returnForCorrection` → `RETURN_FOR_CORRECTION`) invalidates client *and* mock simultaneously, which is precisely why they live in one repository (**D4**) and land in one commit.

- [ ] **Step 1: Write the failing mapper test**

`test/data/campaign_mapper_test.dart`:

```dart
import 'package:acsl_campaign/data/campaign/campaign_mapper.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> wire({String status = 'DRAFT'}) => {
        'id': 'c1',
        'name': 'Q3 Drive',
        'type': 'ATTENDANCE',
        'organizationId': 'org-1',
        'status': status,
        'ownerId': 'user-1',
        'startAt': '2026-09-01T09:00:00.000Z',
        'endAt': null,
        'venue': 'Hall A',
        'objective': 'Verify',
        'territoryIds': ['terr-1'],
        'targetAudience': 100,
        'verifiedAttendance': 0,
        'version': 3,
      };

  test('maps a well-formed payload', () {
    final c = campaignFromWire(wire());
    expect(c.id, 'c1');
    expect(c.status, CampaignStatus.draft);
    expect(c.startAt, DateTime.utc(2026, 9, 1, 9));
  });

  // The defect this task exists to close. campaign_dto.dart used
  // `orElse: () => CampaignStatus.draft`, so a CANCELLED campaign arriving with
  // an unexpected status rendered as an EDITABLE DRAFT — a silent
  // misclassification in the direction that grants more permission.
  test('an unrecognised status throws instead of becoming a draft', () {
    expect(
      () => campaignFromWire(wire(status: 'SOMETHING_NEW')),
      throwsA(isA<FormatException>()),
    );
  });

  test('a missing status throws rather than defaulting', () {
    final json = wire()..remove('status');
    expect(() => campaignFromWire(json), throwsA(isA<FormatException>()));
  });

  test('decision wire values are SCREAMING_SNAKE', () {
    expect(
      draftDecisionWire(CampaignDecision.returnForCorrection),
      'RETURN_FOR_CORRECTION',
    );
  });
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
flutter test test/data/campaign_mapper_test.dart
```

Expected: FAIL — `campaign_mapper.dart` does not exist.

- [ ] **Step 3: Implement the mapper and delete the DTO**

`lib/data/campaign/campaign_mapper.dart` replaces the generated DTO. Hand-written because the wire enums now come from the shared package and `json_serializable` cannot express "throw on unknown enum" — which is the entire point of this task.

```dart
import 'package:campaign_contracts/campaign_contracts.dart';

import '../../domain/campaign/campaign.dart';
import '../../domain/common/status.dart';

/// Wire → domain. Throws [FormatException] on anything it cannot map.
///
/// Deliberately strict about status. The previous generated DTO used
/// `orElse: () => CampaignStatus.draft`, so an unrecognised value rendered a
/// cancelled or completed campaign as an EDITABLE DRAFT. Failing loudly turns a
/// client/server version mismatch into a visible error instead of a permission
/// escalation on the most consequential field of the record.
Campaign campaignFromWire(Map<String, Object?> json) {
  final rawStatus = json['status'];
  if (rawStatus is! String) {
    throw FormatException('Campaign is missing a status.', json.toString());
  }
  final status = CampaignStatus.tryParseWire(rawStatus);
  if (status == null) {
    throw FormatException(
      'Unrecognised campaign status "$rawStatus". This app version cannot '
      'safely display this campaign.',
      rawStatus,
    );
  }
  return Campaign(
    id: json['id']! as String,
    name: json['name']! as String,
    type: json['type']! as String,
    organizationId: json['organizationId']! as String,
    status: status,
    ownerId: json['ownerId']! as String,
    startAt: _utcOrNull(json['startAt']),
    endAt: _utcOrNull(json['endAt']),
    venue: json['venue'] as String?,
    objective: json['objective'] as String?,
    territoryIds: (json['territoryIds'] as List?)?.cast<String>() ?? const [],
    targetAudience: (json['targetAudience'] as num?)?.toInt() ?? 0,
    verifiedAttendance: (json['verifiedAttendance'] as num?)?.toInt() ?? 0,
    version: (json['version'] as num?)?.toInt() ?? 0,
  );
}

DateTime? _utcOrNull(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;
```

`Campaign` gains a `version` field so screens can send it back. `CampaignDecision` maps to `CampaignDecisionInput.wireValue`.

- [ ] **Step 4: Pass idempotency keys and versions from the repository**

In `campaign_repository_impl.dart`, mutations mint a key per user action. The transport already supports it — `traceOptions(trace, {idempotencyKey})` sets the `Idempotency-Key` header via `CorrelationIdInterceptor`, and `retry_interceptor.dart` refuses to retry an unsafe method without one, so this also makes campaign mutations retryable for the first time.

```dart
  @override
  Future<Result<Campaign>> submitForApproval(
    String id, {
    required int version,
    TraceId? trace,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns/$id/submit',
        data: {'version': version},
        // A key derived from the action, so a double-tap or a transport retry
        // replays the first response instead of transitioning twice.
        options: traceOptions(
          trace ?? TraceId.generate(),
          idempotencyKey: 'submit:$id:$version',
        ),
      );
      return Ok(campaignFromWire(res.data!));
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
```

`decide` sends `{'decision': decision.wireValue, 'reason': reason, 'version': version, 'acknowledgedWarnings': acknowledgedWarnings}` with key `'decide:$id:$version'`.

**Why the key includes `version`:** it makes the key unique per *state*, so a genuine second submit after a legitimate change is not mistaken for a replay of the first.

- [ ] **Step 5: Update the mock server to the same contract**

In `tool/mock_server/bin/server.dart`: accept `APPROVE`/`RETURN_FOR_CORRECTION`/`REJECT`, return `version` on every campaign, honour `page`/`pageSize`/`q`/`status` on `GET /campaigns` with a real `total`, and return `409` when a submitted `version` does not match. The mock does not need to be complete — it needs to stop *contradicting* the contract, or the parity tests in Task 11 cannot pass.

- [ ] **Step 6: Run the whole app suite**

```bash
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
dart format --set-exit-if-changed lib test packages
flutter analyze --fatal-infos
flutter test
```

Expected: green. The count will differ from 392 because `campaign_dto` tests are replaced by mapper tests — record the new number in the commit message so the next task has a baseline.

- [ ] **Step 7: Commit**

```bash
git add lib test tool/mock_server
git commit -m "feat(client): strict status mapping, versions, acknowledgements, idempotency keys

Deletes the generated CampaignDto. It resolved an unrecognised status with
orElse: draft, so a CANCELLED or COMPLETED campaign rendered as an editable
draft — a silent misclassification in the direction that grants more permission.
The hand-written mapper throws instead; json_serializable cannot express that,
which is why it is hand-written.

Mutations now send a version and an idempotency key. The transport already
supported the header (traceOptions/CorrelationIdInterceptor); only the call
sites were missing it. The key embeds the version so a legitimate second submit
after a real change is not mistaken for a replay. retry_interceptor refuses to
retry unsafe methods without a key, so campaign mutations become retryable too.

Decision values become SCREAMING_SNAKE, which breaks the client and the mock at
the same instant — hence one commit across both, which is what the sibling
layout (D4) exists to allow."
```

---

### Task 11: Test seeding, CI, and the e2e cut-over

**Files:**
- Create: `server/lib/src/seed/seed_routes.dart`
- Create: `server/test/seed/seed_gate_test.dart`
- Create: `server/test/contract/parity_test.dart`
- Modify: `.github/workflows/ci.yml`
- Modify: `tool/scripts/run_maestro_flows.sh` (start the service instead of the mock)
- Modify: `.maestro/` login flow (one flow authenticates for real)

**Interfaces:**
- Consumes: everything above.
- Produces: `Router seedRouter({required Db db, required ServerConfig config, required PasswordHasher hasher})` mounted at `/__test__/`.

**This task is the acceptance criterion.** Everything before it is unproven.

- [ ] **Step 1: Write the seeding gate test first**

The gate matters more than the seeding. `server/test/seed/seed_gate_test.dart`:

```dart
test('seed routes are absent when seeding is disabled', () async {
  final handler = buildApp(config: configWithSeeding(false));
  final res = await handler(
      Request('POST', Uri.parse('http://localhost/__test__/reset')));
  expect(res.statusCode, 404,
      reason: 'a data-wiping route must not exist in production');
});

test('seed routes work when explicitly enabled', () async {
  final handler = buildApp(config: configWithSeeding(true));
  final res = await handler(
      Request('POST', Uri.parse('http://localhost/__test__/reset')));
  expect(res.statusCode, 204);
});

// Fails closed: ENABLE_TEST_SEEDING must be exactly 'true'.
test('any value other than "true" leaves seeding off', () async {
  for (final value in ['1', 'yes', 'TRUE', 'True', '']) {
    final config = ServerConfig.fromEnvironment({
      'DATABASE_URL': testDatabaseUrl,
      'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
      'ENABLE_TEST_SEEDING': value,
    });
    expect(config.seedingEnabled, isFalse, reason: 'value: "$value"');
  }
});
```

- [ ] **Step 2: Implement the seed routes**

`POST /__test__/reset` truncates every table and re-seeds one organization, two territories and one user per role using the exact wire role names. `POST /__test__/campaigns` accepts a fixture name matching the mock's environment fixtures — `rows`, `empty`, `error` — so the flows that depend on empty and error states keep working. The router is only mounted when `config.seedingEnabled`; it is not registered-and-guarded, it is **absent**, so there is no route to probe.

- [ ] **Step 3: Write the parity test**

`server/test/contract/parity_test.dart` runs the same assertions against the real service and the mock, so the mock cannot drift while both exist:

```dart
// The mock stays until the real service has been green for a while (spec §9).
// While both exist, they must agree on the contract the client depends on:
// status vocabulary, list envelope shape, decision values and version presence.
for (final target in [realService, mockServer]) {
  test('${target.name}: list returns {items,total} with wire statuses', () async {
    final body = await target.getJson('/campaigns?page=1&pageSize=5');
    expect(body.keys, containsAll(<String>['items', 'total']));
    for (final item in body['items']! as List) {
      final status = (item as Map)['status']! as String;
      expect(CampaignStatus.tryParseWire(status), isNotNull,
          reason: '$status is not in the shared vocabulary');
      expect(item['version'], isA<int>());
    }
  });
}
```

- [ ] **Step 4: Add the server job to CI**

In `.github/workflows/ci.yml`, a `server` job with a Postgres 16 service container:

```yaml
  server:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: campaign
          POSTGRES_PASSWORD: campaign
          POSTGRES_DB: campaign
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready --health-interval 5s
          --health-timeout 5s --health-retries 10
    env:
      DATABASE_URL: postgres://campaign:campaign@localhost:5432/campaign
      JWT_SECRET: ci-secret-at-least-32-characters-long!!
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
        with: { sdk: '3.12.2' }
      - run: dart pub get
        working-directory: packages/campaign_contracts
      - run: dart test
        working-directory: packages/campaign_contracts
      - run: dart pub get
        working-directory: server
      - run: dart format --output=none --set-exit-if-changed .
        working-directory: server
      - run: dart analyze --fatal-infos
        working-directory: server
      - run: dart test
        working-directory: server
```

- [ ] **Step 5: Cut the e2e job over to the real service**

In `tool/scripts/run_maestro_flows.sh`, replace the mock-server launch with: start Postgres, run the service with `ENABLE_TEST_SEEDING=true`, wait for `/health`, then `POST /__test__/reset` before each flow. The loop stays in the script — the emulator action runs `script:` **line by line**, each in its own `sh -c`, which is why this file exists at all.

Keep the mock available behind a flag so a red e2e can be bisected against it. That is the cut-over rule from spec §9: **do not delete the harness optimistically.**

- [ ] **Step 6: Make one flow authenticate for real**

E2E currently swaps in `FakeAuthService` whenever `config.e2e` is true, which means no end-to-end test has ever logged into the identity provider we now own (**D3**). Add a dart-define — `E2E_REAL_AUTH=true` — that leaves `DioAuthService` in place, and a matrix config using it whose flow signs in with a seeded username and password before exercising a campaign journey.

Wire it in `lib/app/di/providers.dart` where `authServiceProvider` branches on `config.e2e`:

```dart
final Provider<AuthService> authServiceProvider = Provider<AuthService>((ref) {
  final config = ref.watch(appConfigProvider);
  // E2E normally signs in through a fake transport. E2E_REAL_AUTH keeps the real
  // one so at least one flow proves the service we now own can actually issue a
  // token — shipping an identity provider no end-to-end test has logged into
  // would repeat P0.6's central mistake.
  if (config.e2e && !config.e2eRealAuth) return FakeAuthService(config.e2eRole);
  return DioAuthService(ref.watch(dioProvider));
});
```

- [ ] **Step 7: Run the acceptance criterion locally, then in CI**

```bash
cd server && docker compose up -d db
DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' \
  JWT_SECRET='a-secret-at-least-32-characters-long!!' \
  ENABLE_TEST_SEEDING=true dart run bin/server.dart &
cd .. && flutter run -d chrome --dart-define=E2E=true \
  --dart-define=API_BASE_URL=http://localhost:8080
```

Walk the campaign list, detail, wizard and approval screens against the real service. Then push and confirm CI: the `gate` job, the new `server` job, and **all five `e2e` configs plus the real-auth config green**.

**If e2e is red and cannot be reproduced locally, CI is the authority** — its emulator viewport is shorter than a local api-37 AVD, and that difference has already produced a failure that could not be reproduced on this machine.

- [ ] **Step 8: Commit**

```bash
git add server .github/workflows/ci.yml tool/scripts/run_maestro_flows.sh .maestro lib/app
git commit -m "feat: run the e2e matrix against the real service

This is the acceptance criterion for the whole slice (spec §9): the existing
client, unchanged in behaviour, drives the real service through five journeys.
A foundation whose only evidence is unit tests of its own plumbing is the shape
of defect P0.6 kept finding.

Seed routes are ABSENT unless ENABLE_TEST_SEEDING is exactly 'true' — not
registered-and-guarded, so there is no route to probe. Any other value leaves
them off.

One matrix config authenticates for real. E2E has always swapped in
FakeAuthService, so nothing had ever logged into the identity provider we now
own (D3).

The mock server stays, behind a flag, so a red e2e can be bisected against it.
It is the harness two epics depended on and is not deleted optimistically."
```

---

## Self-Review

Run against the spec after the plan is written; findings fixed inline.

**Spec coverage.** D-A → Task 1. D-B → Task 2. D-C → Task 3. D-D → Task 4. D-E → Task 5. D-F → Task 6. D-G → Tasks 7–9. D-H → Task 11 (steps 1–2). D-I → Task 11 (steps 4–5). D1 (local carpenter master) is correctly absent — it governs sub-projects 2 and 8, not this slice. D2 → Global Constraints. D3 → Tasks 4–5. D4 → Tasks 1–2. D5 → Task 1. D6 → Task 7 validation + Task 9 step 3. D7 → Tasks 5 and 8. §5 conventions → Tasks 6 and 8. §6 lifecycle → Tasks 7 and 9. §8 transactional migrations → Task 3. §9 acceptance → Task 11.

**Corrections this plan makes to the spec.** Two, both from verification rather than reasoning:

1. **D5 overstated the refactor.** Only `CampaignStatus` carries a `wireValue`; the other four enums have none, and `status.dart`'s own doc comment claiming otherwise is false for four of five. Moving all five would mean inventing four wire vocabularies for blocked contracts. Task 1 moves one enum and leaves a re-export shim, so 28 importers change to 1.
2. **The client never decodes the JWT.** `auth_service.dart:70-94` reads a top-level `claims` object from the login response, so the access token can be opaque. The claim *names* are still fixed, and `scope_claims.dart` rejects sign-in on any it does not recognise.

**Type consistency.** `CampaignStatus.tryParseWire` / `CampaignDecisionInput.tryParseWire` / `ApiErrorCode.tryParseWire` are named identically and used consistently in Tasks 1, 6, 8, 10, 11. `authOf` is defined in Task 5 and used in Tasks 6, 8, 9. `row()` is defined in Task 3 and used in Tasks 4, 5, 8, 9. `seedOrganizationWithUser` is defined in Task 4 and used in Tasks 5, 8, 9. `Db.tx` is used in Tasks 3, 6, 9 and always through the `TxSession`. `validateForSubmit` returns `List<FieldError>` in Task 7 and is consumed as such in Task 9.

**Known gaps, stated rather than hidden.** Task 9's test bodies reference helpers (`pendingCampaign`, `approvedCampaign`, `seedInvalidDraft`, `draftBody`, `post`, `get`) whose implementations are not spelled out; they are mechanical extensions of `seed_fixtures.dart` from Task 4 and the request helpers from Task 5's tests. Task 6 step 4 leaves two test bodies as comments — **fill them in before running**, because a stubbed test that passes is worse than no test. Task 11 step 2 describes the seed fixtures at the level of their names rather than their rows, because they must mirror whatever the five Maestro flows currently rely on, which the implementer should read from `.maestro/` rather than take from this plan.
