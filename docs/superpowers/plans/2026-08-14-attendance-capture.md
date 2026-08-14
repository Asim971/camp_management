# Attendance Capture Round-Trip (sub-project 4a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the four endpoints the field capture flow already drains — `GET /consent/notices`, `POST /media/presign`, `PUT /media/upload/<id>`, `POST /attendance/<key>/confirm` — on the real `campaign_service`, so the **unchanged** client runs its `presign → upload → confirm` against the real service instead of `tool/mock_server`.

**Architecture:** A pure HMAC signed-URL helper (`signed_url.dart`) turns the upload URL into a short-lived capability the bearer-less `PUT` can present; evidence bytes land in a Postgres `BYTEA` `media_objects` row; the idempotent `confirm` derives campaign+org from the session, requires the uploaded evidence, and persists an `attendance` row + `consent_records` row + audit in one transaction with status `MATCH_PROCESSING`. New shelf routers (`media`, `consent`, `attendance`) mount as Cascade legs; the media leg authenticates only `media/presign` so `media/upload` stays bearer-less and signature-gated. No client changes.

**Tech Stack:** Dart 3.12, `shelf`/`shelf_router`, `postgres` 3.5.12 (hand-written SQL, no ORM), `cryptography` 2.9.0 (HMAC-SHA256), `campaign_contracts`; the existing `Idempotency-Key` middleware; Flutter/Riverpod client (unchanged); Maestro e2e.

**Spec:** `docs/superpowers/specs/2026-08-14-attendance-capture-design.md`. Decisions cited **4a.D1**–**4a.D6**.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **SDK floor is exactly `sdk: ">=3.12.0 <4.0.0"`** in every `pubspec.yaml`.
- **`shelf`/`shelf_router` only. No ORM. No code generation** in `server/` or `packages/campaign_contracts`.
- **Wire naming is `SCREAMING_SNAKE` for enum-ish values.** The stored attendance status literal is `'MATCH_PROCESSING'`; the new error code is `ATTENDANCE_EVIDENCE_MISSING`. Field names stay camelCase.
- **Out-of-scope resources return `404`, never `403`** (**D7**). A session or carpenter outside the caller's organization is indistinguishable from missing.
- **`postgres` trap:** inside `Db.tx`, every statement goes through the `TxSession` passed to the callback, never `_db.execute`. Read every column through the `row(r)` helper (strict-casts).
- **Timestamps:** UTC ISO-8601 on the wire, `timestamptz` in Postgres.
- **The claim vocabulary is fixed.** `attendance_capture` (held by `field_user`) gates presign + confirm. Do not invent a permission.
- **Idempotency is the EXISTING middleware** `idempotency({required Db db})` keyed on the `Idempotency-Key` header — the same one the campaign decision and import commit use. Do not build a new one.
- **The upload URL is a signed capability, never an unauthenticated PUT** (4a.D3): `PUT /media/upload/<id>` authenticates by HMAC query signature, not a bearer.
- **No new required env var.** The upload-signing key derives from the existing `ServerConfig.jwtSecret`.
- **Server tests run against** `DATABASE_URL=postgres://campaign:campaign@localhost:5432/campaign` (native PG 16+; `cd server && docker compose up -d db` is one way). CI uses `postgres:16`.
- **Client is unchanged (4a.D1).** No app code edits; the Flutter suite count moves only by any (server-side) infra. Do not move `AttendanceStatus` to contracts.

---

## File Structure

```
packages/campaign_contracts/
  lib/src/error_codes.dart             MOD  + attendanceEvidenceMissing
  test/error_codes_test.dart           (existing generic round-trip covers it)

server/
  lib/src/infra/error_envelope.dart    MOD  map attendanceEvidenceMissing -> 422
  lib/src/db/migrations/embedded.dart  MOD  + '007_attendance'
  lib/src/media/signed_url.dart        NEW  sign/verify HMAC upload URLs (pure)
  lib/src/media/media_repo.dart        NEW  media_objects store/fetch
  lib/src/media/media_routes.dart      NEW  POST /media/presign, PUT /media/upload/<id>
  lib/src/consent/consent_routes.dart  NEW  GET /consent/notices
  lib/src/attendance/attendance_repo.dart   NEW  the confirm transaction
  lib/src/attendance/attendance_routes.dart NEW  POST /attendance/<key>/confirm
  lib/src/app.dart                     MOD  mount media/consent/attendance legs
  lib/src/seed/seed_routes.dart        MOD  seed a consent notice
  test/media/signed_url_test.dart      NEW
  test/media/media_routes_test.dart    NEW
  test/consent/consent_routes_test.dart NEW
  test/attendance/attendance_routes_test.dart NEW
  test/db/migrator_test.dart           MOD  007 table inventory
  test/contract/parity_test.dart       MOD  pin the four shapes

tool/mock_server/bin/server.dart       MOD  MATCH_PROCESSING + /consent/notices

.maestro/flows/attendance_capture.yaml NEW
.maestro/config.yaml                   MOD  add the flow
.github/workflows/ci.yml               MOD  add the `capture` matrix config
```

---

### Task 1: Contract error code + envelope mapping

**Files:**
- Modify: `packages/campaign_contracts/lib/src/error_codes.dart`
- Modify: `server/lib/src/infra/error_envelope.dart`

**Interfaces:**
- Produces: `ApiErrorCode.attendanceEvidenceMissing` (`ATTENDANCE_EVIDENCE_MISSING`), mapped to HTTP 422 in `ApiException.status`.
- Consumes: nothing.

**Why both files in one task:** `error_envelope.dart`'s `int get status => switch (code)` is exhaustive with no default. Adding an enum member without the arm breaks the server build immediately. Ship both together.

- [ ] **Step 1: Add the error code**

In `packages/campaign_contracts/lib/src/error_codes.dart`, add the member (after `sessionNotReady`, renaming the trailing `;`) and its wire arm:

```dart
  // session operations (sub-project 3a)
  sessionInvalidTransition,
  sessionNotReady,
  // attendance & evidence (sub-project 4a)
  attendanceEvidenceMissing;
```

```dart
    sessionNotReady => 'SESSION_NOT_READY',
    attendanceEvidenceMissing => 'ATTENDANCE_EVIDENCE_MISSING',
```

- [ ] **Step 2: Run the contracts round-trip test — must still pass**

Run: `cd packages/campaign_contracts && dart pub get && dart test`
Expected: green (the generic `ApiErrorCode.values` round-trip covers the new code — confirm `test/error_codes_test.dart` iterates `values`; if it hard-codes a list, add the new code).

- [ ] **Step 3: Map it to 422 in the envelope**

In `server/lib/src/infra/error_envelope.dart`, add to the `int get status => switch (code)` block (with the other 422s, before `ApiErrorCode.internal => 500`):

```dart
    ApiErrorCode.attendanceEvidenceMissing => 422,
```

- [ ] **Step 4: Server analyzes clean**

Run: `cd server && dart analyze --fatal-infos`
Expected: `No issues found!` (the switch is exhaustive again).

- [ ] **Step 5: Format, commit**

```bash
cd packages/campaign_contracts && dart format --set-exit-if-changed . && dart analyze
cd ../../server && dart format --set-exit-if-changed lib/src/infra/error_envelope.dart
cd .. && git add packages/campaign_contracts server/lib/src/infra/error_envelope.dart
git commit -m "feat(contracts): ATTENDANCE_EVIDENCE_MISSING (422) for the confirm endpoint

The attendance confirm returns 422 ATTENDANCE_EVIDENCE_MISSING when it
references a media object that was never uploaded. Added to ApiErrorCode and
mapped in the server envelope together so the exhaustive status switch keeps
compiling."
```

---

### Task 2: Migration `007_attendance`

**Files:**
- Modify: `server/lib/src/db/migrations/embedded.dart`
- Modify: `server/test/db/migrator_test.dart`

**Interfaces:**
- Consumes: `Migrator`, `embeddedMigrations`.
- Produces: tables `consent_notices`, `media_objects`, `attendance`, `consent_records`.

- [ ] **Step 1: Write the failing table-inventory test**

Add to `server/test/db/migrator_test.dart` inside `main`:

```dart
  test('007 creates the attendance and evidence tables', () async {
    await Migrator(db).applyPending();
    final res = await db.execute(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
    );
    final names = res.map((r) => row(r)['tablename']! as String).toSet();
    expect(names, containsAll(<String>[
      'consent_notices', 'media_objects', 'attendance', 'consent_records',
    ]));
  });
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/db/migrator_test.dart -n '007 creates'`
Expected: FAIL — tables absent.

- [ ] **Step 3: Add the migration**

In `server/lib/src/db/migrations/embedded.dart`, add the map entry (after `006_session_status`, so it applies last):

```dart
  '007_attendance': _attendance,
```

and the constant at the bottom:

```dart
const String _attendance = r'''
CREATE TABLE consent_notices (
  version       INTEGER     NOT NULL,
  language      TEXT        NOT NULL,
  title         TEXT        NOT NULL,
  body          TEXT        NOT NULL,
  content_hash  TEXT        NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (version, language)
);

-- No organization_id: written by the bearer-less (signed) upload PUT, which
-- has no auth context. Org scope is enforced by the attendance row that links
-- it at confirm time (sub-project 4a.D2/D3). Real object storage, encryption
-- at rest and retention are sub-project 4b.
CREATE TABLE media_objects (
  id            TEXT PRIMARY KEY,
  content_type  TEXT        NOT NULL,
  bytes         BYTEA       NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE attendance (
  id              TEXT PRIMARY KEY,            -- == idempotency key == media id
  organization_id TEXT        NOT NULL REFERENCES organizations(id),
  campaign_id     TEXT        NOT NULL REFERENCES campaigns(id),
  session_id      TEXT        NOT NULL REFERENCES campaign_sessions(id),
  carpenter_id    TEXT        NOT NULL REFERENCES carpenters(id),
  media_ref       TEXT        NOT NULL,
  status          TEXT        NOT NULL,        -- 'MATCH_PROCESSING' in 4a
  captured_by     TEXT        NOT NULL REFERENCES staff_users(id),
  captured_at     TIMESTAMPTZ NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX attendance_org_session_idx
  ON attendance(organization_id, session_id);

CREATE TABLE consent_records (
  id             TEXT PRIMARY KEY,
  attendance_id  TEXT        NOT NULL REFERENCES attendance(id) ON DELETE CASCADE,
  notice_version INTEGER     NOT NULL,
  language       TEXT        NOT NULL,
  content_hash   TEXT        NOT NULL,
  shown_at       TIMESTAMPTZ NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
''';
```

- [ ] **Step 4: Run the migrator tests — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/db/migrator_test.dart`
Expected: all pass (the new inventory test + all existing).

- [ ] **Step 5: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/db/migrations/embedded.dart server/test/db/migrator_test.dart
git commit -m "feat(server): migration 007 — attendance, media_objects, consent tables

consent_notices, media_objects (BYTEA evidence blob, no org column — written by
the bearer-less signed upload), attendance (id == idempotency key), and
consent_records. The evidence blob is tied to an org via the attendance row
that references it at confirm time."
```

---

### Task 3: Signed upload-URL helper (pure)

**Files:**
- Create: `server/lib/src/media/signed_url.dart`
- Create: `server/test/media/signed_url_test.dart`

**Interfaces:**
- Consumes: nothing (a signing key `String` is passed in).
- Produces:
  - `Future<String> signUploadUrl({required String baseUrl, required String id, required String signingKey, required DateTime now, Duration ttl = const Duration(minutes: 15)})` — returns `"<baseUrl>/media/upload/<id>?exp=<unixSeconds>&sig=<urlSafeBase64 hmac>"`.
  - `Future<bool> verifyUploadSignature({required String id, required int exp, required String sig, required String signingKey, required DateTime now})` — recomputes the HMAC, constant-time-compares, and checks `exp` is in the future.

**Why its own file:** the security-load-bearing crypto is unit-testable with no DB and no HTTP, exactly like `session_machine.dart`.

- [ ] **Step 1: Write the failing tests**

`server/test/media/signed_url_test.dart`:

```dart
import 'package:campaign_service/src/media/signed_url.dart';
import 'package:test/test.dart';

void main() {
  const key = 'a-signing-key-at-least-32-characters!!';
  final now = DateTime.utc(2026, 8, 14, 12);

  ({String id, int exp, String sig}) parse(String url) {
    final u = Uri.parse(url);
    return (
      id: u.pathSegments.last,
      exp: int.parse(u.queryParameters['exp']!),
      sig: u.queryParameters['sig']!,
    );
  }

  test('a freshly signed URL verifies', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://10.0.2.2:8080', id: 'att-1', signingKey: key, now: now);
    expect(url, contains('/media/upload/att-1?'));
    final p = parse(url);
    expect(
      await verifyUploadSignature(
        id: p.id, exp: p.exp, sig: p.sig, signingKey: key, now: now),
      isTrue,
    );
  });

  test('a tampered id fails', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://h', id: 'att-1', signingKey: key, now: now);
    final p = parse(url);
    expect(
      await verifyUploadSignature(
        id: 'att-2', exp: p.exp, sig: p.sig, signingKey: key, now: now),
      isFalse,
    );
  });

  test('a tampered exp fails', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://h', id: 'att-1', signingKey: key, now: now);
    final p = parse(url);
    expect(
      await verifyUploadSignature(
        id: p.id, exp: p.exp + 3600, sig: p.sig, signingKey: key, now: now),
      isFalse,
    );
  });

  test('a wrong signing key fails', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://h', id: 'att-1', signingKey: key, now: now);
    final p = parse(url);
    expect(
      await verifyUploadSignature(
        id: p.id, exp: p.exp, sig: p.sig, signingKey: 'different-key-32-characters-long!!', now: now),
      isFalse,
    );
  });

  test('an expired URL fails even with a valid signature', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://h', id: 'att-1', signingKey: key, now: now,
      ttl: const Duration(minutes: 15));
    final p = parse(url);
    // 16 minutes later: past the 15-minute TTL.
    final later = now.add(const Duration(minutes: 16));
    expect(
      await verifyUploadSignature(
        id: p.id, exp: p.exp, sig: p.sig, signingKey: key, now: later),
      isFalse,
    );
  });

  // Falsification: a garbage signature must never verify.
  test('a forged signature is rejected', () async {
    expect(
      await verifyUploadSignature(
        id: 'att-1', exp: now.millisecondsSinceEpoch ~/ 1000 + 900,
        sig: 'not-a-real-signature', signingKey: key, now: now),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd server && dart test test/media/signed_url_test.dart`
Expected: FAIL — `signed_url.dart` does not exist.

- [ ] **Step 3: Implement the helper**

`server/lib/src/media/signed_url.dart` — use the `cryptography` package's HMAC (already a server dependency; no `package:crypto`). Constant-time compare via `SecretKeyData`/`Mac` equality or a manual constant-time byte compare.

```dart
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Signs and verifies short-lived upload capability URLs (sub-project 4a.D3).
///
/// The upload PUT is bearer-less (the client uses a fresh Dio), so the URL
/// itself is the authorization: an HMAC-SHA256 over "<id>.<exp>" keyed by a
/// server-held secret, with a short expiry. This is minted only by the
/// authenticated presign endpoint and expires; an unauthenticated upload
/// guarded only by an unguessable id would be a storage-exhaustion / pollution
/// vector (spec §6a).
const _hmac = Hmac.sha256();

Future<String> _sign(String id, int exp, String signingKey) async {
  final mac = await _hmac.calculateMac(
    utf8.encode('$id.$exp'),
    secretKey: SecretKey(utf8.encode(signingKey)),
  );
  return base64Url.encode(mac.bytes);
}

Future<String> signUploadUrl({
  required String baseUrl,
  required String id,
  required String signingKey,
  required DateTime now,
  Duration ttl = const Duration(minutes: 15),
}) async {
  final exp = now.add(ttl).millisecondsSinceEpoch ~/ 1000;
  final sig = await _sign(id, exp, signingKey);
  return '$baseUrl/media/upload/$id?exp=$exp&sig=${Uri.encodeQueryComponent(sig)}';
}

Future<bool> verifyUploadSignature({
  required String id,
  required int exp,
  required String sig,
  required String signingKey,
  required DateTime now,
}) async {
  if (now.millisecondsSinceEpoch ~/ 1000 > exp) return false;
  final expected = await _sign(id, exp, signingKey);
  return _constantTimeEquals(expected, sig);
}

/// Length-independent-leaking but value-constant-time comparison — never a
/// plain `==`, which short-circuits on the first differing byte.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
```

- [ ] **Step 4: Run the tests — must pass**

Run: `cd server && dart test test/media/signed_url_test.dart`
Expected: all pass, including the expiry and forged-signature cases.

- [ ] **Step 5: Prove the falsification is real**

Temporarily change `verifyUploadSignature` to `return now... <= exp;` (ignore the signature) and re-run — the tampered/forged tests must FAIL. Revert. Record it.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/media/signed_url.dart server/test/media/signed_url_test.dart
git commit -m "feat(server): HMAC-signed upload capability URLs (pure)

presign mints .../media/upload/<id>?exp&sig where sig = HMAC-SHA256(id.exp)
keyed by a server secret; the bearer-less upload PUT is authorized by verifying
that signature and its expiry, not a token. Constant-time compare. Closes the
unauthenticated-upload DoS/pollution hole (spec 4a.D3 / research)."
```

---

### Task 4: Media repo + routes (presign + upload) + wiring

**Files:**
- Create: `server/lib/src/media/media_repo.dart`
- Create: `server/lib/src/media/media_routes.dart`
- Modify: `server/lib/src/app.dart`
- Create: `server/test/media/media_routes_test.dart`

**Interfaces:**
- Consumes: `signUploadUrl`/`verifyUploadSignature` (Task 3); `Db`/`row`; `authOf`/`requirePermission`/`_authenticateUnder` (`auth/middleware.dart`, `app.dart`); `ApiException`/`ApiErrorCode`; `ServerConfig.jwtSecret`.
- Produces:
  - `class MediaRepo { MediaRepo(Db db); Future<void> put(String id, {required String contentType, required List<int> bytes}); Future<({String contentType, List<int> bytes})?> get(String id); }`
  - `Router mediaRouter({required Db db, required String signingKey})`.

**Signing key:** `app.dart` passes `signingKey: config.jwtSecret` to `mediaRouter` (4a.D3 — no new env var).

**Upload size cap:** reject a body over a sane evidence ceiling (use `const _maxUploadBytes = 8 * 1024 * 1024;`) with `413`.

- [ ] **Step 1: Write the failing routes tests**

`server/test/media/media_routes_test.dart` (harness modelled on `server/test/import_/import_routes_test.dart`: `buildApp` + `Request` objects + `TokenService`):

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
  late String fieldToken; // attendance_capture
  late String viewerToken; // no attendance_capture

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db,
        userId: 'user-f', username: 'field', roles: const ['field_user']);
    await seedOrganizationWithUser(db,
        userId: 'user-v', username: 'viewer', roles: const ['reporting_viewer']);
    final tokens = TokenService(db: db, config: config);
    fieldToken = (await tokens.issueFor('user-f')).accessToken;
    viewerToken = (await tokens.issueFor('user-v')).accessToken;
    handler = buildApp(db: db, config: config);
  });
  tearDown(() async => db.close());

  Future<Response> presign(String attendanceId, {String? bearer}) => handler(Request(
        'POST', Uri.parse('http://10.0.2.2:8080/media/presign'),
        headers: {
          if (bearer != null) 'authorization': 'Bearer $bearer',
          'content-type': 'application/json',
        },
        body: jsonEncode({'attendanceId': attendanceId}),
      ));

  Future<Map<String, Object?>> body(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  test('presign requires attendance_capture', () async {
    expect((await presign('att-1', bearer: viewerToken)).statusCode, 403);
    expect((await presign('att-1')).statusCode, 401);
  });

  test('presign returns a signed upload URL for this host', () async {
    final res = await presign('att-1', bearer: fieldToken);
    expect(res.statusCode, 200);
    final url = (await body(res))['url']! as String;
    expect(url, contains('/media/upload/att-1?exp='));
    expect(url, contains('sig='));
  });

  test('upload with a valid signature stores the bytes; a bad signature is 403',
      () async {
    final url = ((await body(await presign('att-1', bearer: fieldToken)))['url']!) as String;
    final signed = Uri.parse(url);

    // A bearer-less PUT with the signed query succeeds.
    final ok = await handler(Request('PUT', signed,
        body: const [1, 2, 3, 4], headers: {'content-type': 'application/octet-stream'}));
    expect(ok.statusCode, 200);

    // Tampering with the signature is 403.
    final bad = signed.replace(queryParameters: {
      ...signed.queryParameters, 'sig': 'forged',
    });
    final rejected = await handler(Request('PUT', bad,
        body: const [1, 2, 3], headers: {'content-type': 'application/octet-stream'}));
    expect(rejected.statusCode, 403);
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/media/media_routes_test.dart`
Expected: FAIL — `mediaRouter` / the media leg do not exist.

- [ ] **Step 3: Implement the repo**

`server/lib/src/media/media_repo.dart`:

```dart
import 'dart:typed_data';

import 'package:postgres/postgres.dart';

import '../db/pool.dart';

/// Stores evidence blobs as Postgres BYTEA (sub-project 4a.D2). Already-encrypted
/// by the client, so opaque here. Object storage + encryption-at-rest + retention
/// are sub-project 4b.
class MediaRepo {
  MediaRepo(this._db);
  final Db _db;

  /// Idempotent: a re-uploaded id overwrites (the id is the attendance key, so a
  /// sync retry that re-PUTs is harmless).
  Future<void> put(
    String id, {
    required String contentType,
    required List<int> bytes,
  }) async {
    await _db.execute(
      'INSERT INTO media_objects (id, content_type, bytes) '
      'VALUES (@id, @ct, @b) '
      'ON CONFLICT (id) DO UPDATE SET content_type = @ct, bytes = @b',
      params: {'id': id, 'ct': contentType, 'b': Uint8List.fromList(bytes)},
    );
  }

  Future<({String contentType, List<int> bytes})?> get(String id) async {
    final res = await _db.execute(
      'SELECT content_type, bytes FROM media_objects WHERE id = @id',
      params: {'id': id},
    );
    if (res.isEmpty) return null;
    final r = row(res.single);
    return (
      contentType: r['content_type']! as String,
      bytes: r['bytes']! as List<int>,
    );
  }
}
```

> Verify the driver's BYTEA binding: `postgres` 3.x accepts a `Uint8List`/`List<int>` param for a `bytea` column and returns a `Uint8List` on read. If a read comes back as something else, cast accordingly — the media-routes test's round-trip surfaces it.

- [ ] **Step 4: Implement the routes**

`server/lib/src/media/media_routes.dart`:

```dart
import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/error_envelope.dart';
import 'media_repo.dart';
import 'signed_url.dart';

const int _maxUploadBytes = 8 * 1024 * 1024;

/// `POST /media/presign` (attendance_capture) mints a signed upload URL;
/// `PUT /media/upload/<id>` is bearer-less and authorized by that signature
/// (4a.D3). The upload leg must NOT be wrapped in `authenticate` — see app.dart.
Router mediaRouter({required Db db, required String signingKey}) {
  final router = Router();
  final repo = MediaRepo(db);

  router.post(
    '/media/presign',
    const Pipeline().addMiddleware(requirePermission('attendance_capture')).addHandler(
      (Request request) async {
        final decoded = jsonDecode(await request.readAsString());
        final attendanceId = (decoded is Map ? decoded['attendanceId'] : null);
        if (attendanceId is! String || attendanceId.isEmpty) {
          throw ApiException(ApiErrorCode.badRequest,
              message: 'attendanceId is required.');
        }
        // Build the URL from the request host so the emulator (10.0.2.2:8080)
        // and the Cloud tunnel both reach the upload endpoint.
        final u = request.requestedUri;
        final baseUrl = '${u.scheme}://${u.authority}';
        final url = await signUploadUrl(
          baseUrl: baseUrl,
          id: attendanceId,
          signingKey: signingKey,
          now: DateTime.now(),
        );
        return Response.ok(jsonEncode({'url': url}),
            headers: {'content-type': 'application/json'});
      },
    ),
  );

  router.put('/media/upload/<id>', (Request request, String id) async {
    final exp = int.tryParse(request.url.queryParameters['exp'] ?? '');
    final sig = request.url.queryParameters['sig'];
    if (exp == null || sig == null ||
        !await verifyUploadSignature(
          id: id, exp: exp, sig: sig, signingKey: signingKey, now: DateTime.now())) {
      throw ApiException(ApiErrorCode.forbidden,
          message: 'Invalid or expired upload URL.');
    }
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > _maxUploadBytes) {
        return Response(413, body: 'Evidence exceeds the size limit.');
      }
    }
    await repo.put(id,
        contentType: request.headers['content-type'] ?? 'application/octet-stream',
        bytes: bytes);
    return Response.ok('');
  });

  return router;
}
```

- [ ] **Step 5: Wire the media leg in `app.dart`**

Add `import 'media/media_routes.dart';`. Build the leg so **only `media/presign` is authenticated** (the upload PUT must stay bearer-less):

```dart
  final mediaHandler = const Pipeline()
      .addMiddleware(
        _authenticateUnder(
          const {'media/presign'}, // NOT 'media' — /media/upload is signature-gated
          db: db,
          tokens: tokens,
        ),
      )
      .addHandler(mediaRouter(db: db, signingKey: config.jwtSecret).call);
```

and add `.add(mediaHandler)` to the `Cascade` (after the session leg).

> Why `'media/presign'` and not `'media'`: `_authenticateUnder` runs `authenticate` for any path that equals a root or starts with `root/`. `media/upload/<id>` does not start with `media/presign`, so it passes through unauthenticated and the router verifies its signature. Using `'media'` would 401 the bearer-less upload before it reached the handler.

- [ ] **Step 6: Run the media tests — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/media/media_routes_test.dart`
Expected: all pass (403/401 on presign, signed URL shape, upload-stores + bad-signature-403).

- [ ] **Step 7: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/media server/lib/src/app.dart server/test/media/media_routes_test.dart
git commit -m "feat(server): media presign + signed bearer-less upload

POST /media/presign (attendance_capture) mints a host-derived signed upload URL;
PUT /media/upload/<id> verifies the HMAC signature (no bearer) and stores the
evidence bytes as a media_objects BYTEA row, capped at 8MB. The media leg
authenticates only media/presign so the upload PUT stays signature-gated."
```

---

### Task 5: Consent notices endpoint + seed

**Files:**
- Create: `server/lib/src/consent/consent_routes.dart`
- Modify: `server/lib/src/app.dart`
- Modify: `server/lib/src/seed/seed_routes.dart`
- Create: `server/test/consent/consent_routes_test.dart`

**Interfaces:**
- Consumes: `Db`/`row`; `authOf`; `_authenticateUnder`.
- Produces: `Router consentRouter({required Db db})` serving `GET /consent/notices` → `{'notices': [ {version, language, title, body, contentHash} ]}` (the client's `NoticeRepository.fetchLatest` reads the `notices` array).

- [ ] **Step 1: Write the failing test**

`server/test/consent/consent_routes_test.dart`:

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
  late String token;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db);
    token = (await TokenService(db: db, config: config).issueFor('user-1')).accessToken;
    handler = buildApp(db: db, config: config);
    await db.execute(
      "INSERT INTO consent_notices (version, language, title, body, content_hash) "
      "VALUES (1, 'en', 'Consent', 'We record your attendance.', 'hash-en')",
    );
  });
  tearDown(() async => db.close());

  test('GET /consent/notices returns the notices; requires auth', () async {
    final unauth = await handler(Request('GET', Uri.parse('http://h/consent/notices')));
    expect(unauth.statusCode, 401);

    final res = await handler(Request('GET', Uri.parse('http://h/consent/notices'),
        headers: {'authorization': 'Bearer $token'}));
    expect(res.statusCode, 200);
    final notices = (jsonDecode(await res.readAsString()) as Map)['notices']! as List;
    expect(notices, hasLength(1));
    final n = notices.single as Map;
    expect(n['version'], 1);
    expect(n['language'], 'en');
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/consent/consent_routes_test.dart`
Expected: FAIL — no consent leg.

- [ ] **Step 3: Implement the router**

`server/lib/src/consent/consent_routes.dart`:

```dart
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/pool.dart';

/// `GET /consent/notices` — authenticate-only (any org member). A background
/// refresh off the capture path; capture uses the client's bundled notice.
Router consentRouter({required Db db}) {
  final router = Router();

  router.get('/consent/notices', (Request request) async {
    final res = await db.execute(
      'SELECT version, language, title, body, content_hash '
      'FROM consent_notices ORDER BY version DESC, language',
    );
    final notices = [
      for (final raw in res)
        () {
          final r = row(raw);
          return {
            'version': r['version'],
            'language': r['language'],
            'title': r['title'],
            'body': r['body'],
            'contentHash': r['content_hash'],
          };
        }(),
    ];
    return Response.ok(jsonEncode({'notices': notices}),
        headers: {'content-type': 'application/json'});
  });

  return router;
}
```

- [ ] **Step 4: Wire the consent leg + seed a notice**

In `app.dart`: `import 'consent/consent_routes.dart';`, build `consentHandler` with `_authenticateUnder(const {'consent'}, db: db, tokens: tokens)` wrapping `consentRouter(db: db).call`, and `.add(consentHandler)`.

In `server/lib/src/seed/seed_routes.dart`, seed a notice inside the reset/seed path (find where the fixtures are inserted; add a `consent_notices` insert mirroring the client's bundled `assets/consent/notice_v1.json` — version 1, `en` and `bn`):

```dart
await db.execute(
  "INSERT INTO consent_notices (version, language, title, body, content_hash) VALUES "
  "(1, 'en', 'Attendance consent', "
  " 'Your photo and attendance are recorded for verification.', 'seed-en-v1'), "
  "(1, 'bn', 'উপস্থিতি সম্মতি', "
  " 'যাচাইয়ের জন্য আপনার ছবি ও উপস্থিতি সংরক্ষণ করা হয়।', 'seed-bn-v1') "
  "ON CONFLICT (version, language) DO NOTHING",
);
```

(If the seed truncates tables on reset, add `consent_notices` to the truncate list so a reset reseeds it cleanly.)

- [ ] **Step 5: Run the consent tests — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/consent/consent_routes_test.dart`
Expected: pass.

- [ ] **Step 6: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/consent server/lib/src/app.dart server/lib/src/seed/seed_routes.dart server/test/consent
git commit -m "feat(server): GET /consent/notices + seeded consent notice

Closes the latent /consent/notices 404 (NoticeRepository.fetchLatest). Returns
the seeded notices as {notices:[...]} for the client's background refresh;
capture itself stays on the bundled notice. Seeds v1 en+bn on reset."
```

---

### Task 6: Attendance confirm (the transaction) + wiring

**Files:**
- Create: `server/lib/src/attendance/attendance_repo.dart`
- Create: `server/lib/src/attendance/attendance_routes.dart`
- Modify: `server/lib/src/app.dart`
- Create: `server/test/attendance/attendance_routes_test.dart`

**Interfaces:**
- Consumes: `Db`/`row`; `AuditWriter.writeTx`; `authOf`/`requirePermission`; `idempotency({required Db db})`; `correlationOf`; `ApiException`/`ApiErrorCode`; migration 007; the media_objects table (Task 2/4).
- Produces:
  - `class AttendanceRepo { AttendanceRepo(Db db); Future<AttendanceConfirmResult> confirm({required String attendanceId, required String organizationId, required String capturedBy, required Map<String,Object?> payload, String? correlationId}); }`
  - `enum AttendanceConfirmOutcome { confirmed, sessionNotFound, carpenterNotFound, evidenceMissing }`
  - `class AttendanceConfirmResult { final AttendanceConfirmOutcome outcome; final String? status; }`
  - `Router attendanceRouter({required Db db})`.

- [ ] **Step 1: Write the failing routes tests**

`server/test/attendance/attendance_routes_test.dart` — model the harness on `import_routes_test.dart`. The confirm requires an uploaded media object; seed one directly (`INSERT INTO media_objects …`) or drive it through presign+upload. Use `seedCampaign(..., status: CampaignStatus.approved)` + `seedCampaignSession(...)` + `seedCarpenter(...)` (all exist; note `seedCampaign` defaults to draft — pass approved), and a `field_user` token.

```dart
// Cover, at minimum:
// - happy path: presign+upload evidence for key K, then POST /attendance/K/confirm
//   with {sessionId, carpenterId, capturedAt, capturedBy, consent*} + Idempotency-Key:K
//   -> 200 {status: 'MATCH_PROCESSING', id: K}; a row exists in attendance and consent_records;
//   an audit_events 'attendance.captured' row exists.
// - idempotent replay: the same POST again -> 200 (stored response), still exactly ONE
//   attendance row.
// - cross-org session -> 404 (seed a session under org-2; a field_user of org-1 confirms).
// - unknown carpenter -> 404.
// - confirm with no prior upload (no media_objects row for K) -> 422 ATTENDANCE_EVIDENCE_MISSING.
// - 403 without attendance_capture; 401 unauthenticated.
// Seed media directly: INSERT INTO media_objects (id, content_type, bytes) VALUES (K,'application/octet-stream', E'\\x01');
```

Write the concrete tests (real assertions, the `Idempotency-Key` header on every confirm, and the exact `ATTENDANCE_EVIDENCE_MISSING` code check).

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/attendance/attendance_routes_test.dart`
Expected: FAIL — the attendance leg does not exist.

- [ ] **Step 3: Implement the repo**

`server/lib/src/attendance/attendance_repo.dart`:

```dart
import 'package:postgres/postgres.dart';

import '../db/pool.dart';
import '../infra/audit.dart';

enum AttendanceConfirmOutcome { confirmed, sessionNotFound, carpenterNotFound, evidenceMissing }

class AttendanceConfirmResult {
  const AttendanceConfirmResult(this.outcome, {this.status});
  final AttendanceConfirmOutcome outcome;
  final String? status; // set for confirmed
}

const _uuid = Uuid();

/// The confirm transaction (4a.D4). Derives campaign+org from the session,
/// requires the carpenter and the uploaded evidence, and persists the
/// attendance + consent record + audit atomically. No matching/PAD/geofence
/// here — the record lands in MATCH_PROCESSING (verification is sub-project 5).
class AttendanceRepo {
  AttendanceRepo(this._db) : _audit = AuditWriter(_db);
  final Db _db;
  final AuditWriter _audit;

  Future<AttendanceConfirmResult> confirm({
    required String attendanceId,
    required String organizationId,
    required String capturedBy,
    required Map<String, Object?> payload,
    String? correlationId,
  }) async {
    final sessionId = payload['sessionId'] as String?;
    final carpenterId = payload['carpenterId'] as String?;
    if (sessionId == null || carpenterId == null) {
      return const AttendanceConfirmResult(AttendanceConfirmOutcome.sessionNotFound);
    }

    // Session must be in the actor's org; campaign_id comes from it (D7).
    final sessionRows = await _db.execute(
      'SELECT s.campaign_id FROM campaign_sessions s '
      'JOIN campaigns c ON c.id = s.campaign_id '
      'WHERE s.id = @s AND c.organization_id = @org',
      params: {'s': sessionId, 'org': organizationId},
    );
    if (sessionRows.isEmpty) {
      return const AttendanceConfirmResult(AttendanceConfirmOutcome.sessionNotFound);
    }
    final campaignId = row(sessionRows.single)['campaign_id']! as String;

    final carpenterRows = await _db.execute(
      'SELECT 1 FROM carpenters WHERE id = @c AND organization_id = @org',
      params: {'c': carpenterId, 'org': organizationId},
    );
    if (carpenterRows.isEmpty) {
      return const AttendanceConfirmResult(AttendanceConfirmOutcome.carpenterNotFound);
    }

    final media = await _db.execute(
      'SELECT 1 FROM media_objects WHERE id = @id',
      params: {'id': attendanceId},
    );
    if (media.isEmpty) {
      return const AttendanceConfirmResult(AttendanceConfirmOutcome.evidenceMissing);
    }

    final capturedAt = DateTime.parse(payload['capturedAt']! as String);
    await _db.tx((tx) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO attendance '
          '(id, organization_id, campaign_id, session_id, carpenter_id, '
          ' media_ref, status, captured_by, captured_at) '
          "VALUES (@id, @org, @camp, @s, @c, @id, 'MATCH_PROCESSING', @by, @at)",
        ),
        parameters: {
          'id': attendanceId, 'org': organizationId, 'camp': campaignId,
          's': sessionId, 'c': carpenterId, 'by': capturedBy, 'at': capturedAt,
        },
      );
      await tx.execute(
        Sql.named(
          'INSERT INTO consent_records '
          '(id, attendance_id, notice_version, language, content_hash, shown_at) '
          'VALUES (@id, @att, @v, @lang, @hash, @shown)',
        ),
        parameters: {
          'id': _uuid.v4(),
          'att': attendanceId,
          'v': (payload['consentVersion']! as num).toInt(),
          'lang': payload['consentLanguage']! as String,
          'hash': payload['consentContentHash']! as String,
          'shown': DateTime.parse(payload['consentShownAt']! as String),
        },
      );
      await _audit.writeTx(tx,
          action: 'attendance.captured', resourceType: 'attendance',
          resourceId: attendanceId, actorId: capturedBy, correlationId: correlationId,
          payload: {'sessionId': sessionId, 'carpenterId': carpenterId});
    });
    return const AttendanceConfirmResult(
        AttendanceConfirmOutcome.confirmed, status: 'MATCH_PROCESSING');
  }
}
```

> Add `import 'package:uuid/uuid.dart';` for `Uuid`. Confirm `AuditWriter.writeTx` exists (it does — used by 3a). The confirm reads `payload` values with explicit casts; a missing required field should surface as a clean error, not a raw cast crash — if the plan's happy-path tests pass but you want defensiveness, wrap the payload reads to throw `ApiException(badRequest)` on a missing field (the client always sends them, so this is belt-and-suspenders).

- [ ] **Step 4: Implement the routes**

`server/lib/src/attendance/attendance_routes.dart`:

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
import 'attendance_repo.dart';

/// `POST /attendance/<key>/confirm` — attendance_capture + the existing
/// Idempotency-Key middleware. Idempotent replay returns the stored response,
/// which the client treats as success.
Router attendanceRouter({required Db db}) {
  final router = Router();
  final repo = AttendanceRepo(db);

  router.post(
    '/attendance/<key>/confirm',
    const Pipeline()
        .addMiddleware(requirePermission('attendance_capture'))
        .addMiddleware(idempotency(db: db))
        .addHandler((Request request) async {
          final auth = authOf(request);
          final key = request.params['key']!;
          final decoded = jsonDecode(await request.readAsString());
          final payload = (decoded as Map).cast<String, Object?>();
          final result = await repo.confirm(
            attendanceId: key,
            organizationId: auth.organizationId,
            capturedBy: auth.userId,
            payload: payload,
            correlationId: correlationOf(request),
          );
          switch (result.outcome) {
            case AttendanceConfirmOutcome.confirmed:
              return Response.ok(
                jsonEncode({'status': result.status, 'id': key}),
                headers: {'content-type': 'application/json'});
            case AttendanceConfirmOutcome.sessionNotFound:
            case AttendanceConfirmOutcome.carpenterNotFound:
              throw ApiException(ApiErrorCode.notFound);
            case AttendanceConfirmOutcome.evidenceMissing:
              throw ApiException(ApiErrorCode.attendanceEvidenceMissing,
                  message: 'No uploaded evidence for this attendance.');
          }
        }),
  );

  return router;
}
```

- [ ] **Step 5: Wire the attendance leg in `app.dart`**

`import 'attendance/attendance_routes.dart';`, build `attendanceHandler` with `_authenticateUnder(const {'attendance'}, db: db, tokens: tokens)` wrapping `attendanceRouter(db: db).call`, and `.add(attendanceHandler)`.

- [ ] **Step 6: Run the attendance tests + the full server suite — must pass**

Run: `cd server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test`
Expected: the attendance tests pass (happy path, idempotent replay = one row, cross-org 404, evidence-missing 422, 403/401) and the whole suite is green.

- [ ] **Step 7: Format, analyze, commit**

```bash
cd server && dart format --set-exit-if-changed . && dart analyze --fatal-infos
cd .. && git add server/lib/src/attendance server/lib/src/app.dart server/test/attendance
git commit -m "feat(server): idempotent attendance confirm

POST /attendance/<key>/confirm (attendance_capture + Idempotency-Key) derives
campaign+org from the session (404 out-of-org), requires the carpenter and the
uploaded evidence (422 ATTENDANCE_EVIDENCE_MISSING), and persists the attendance
+ consent record + audit atomically as MATCH_PROCESSING. Verification is 5."
```

---

### Task 7: Mock parity

**Files:**
- Modify: `tool/mock_server/bin/server.dart`
- Modify: `server/test/contract/parity_test.dart`

**Interfaces:**
- Consumes: the ratified 4a wire.
- Produces: a mock whose consent/presign/upload/confirm shapes match the real service, pinned by parity.

- [ ] **Step 1: Align the mock**

In `tool/mock_server/bin/server.dart`: the `/attendance/<id>/confirm` handler returns `{'status': 'MATCH_PROCESSING'}` (SCREAMING_SNAKE; currently `matchProcessing`). Add `GET /consent/notices` returning `{'notices': [{'version': 1, 'language': 'en', 'title': 'Consent', 'body': '…', 'contentHash': 'mock-en'}]}` if it is not already present. Leave `/media/presign` returning `{'url': …}` (the client is agnostic to whether the mock's URL is signed).

- [ ] **Step 2: Pin parity**

In `server/test/contract/parity_test.dart`, add a case (following the existing structure) asserting mock and real agree:
- `GET /consent/notices` — both return `{'notices': [...]}` with each item carrying `version` (int) + `language` (string).
- `POST /attendance/<id>/confirm` — both return a `status` whose value is `'MATCH_PROCESSING'` (assert the exact literal on both sides). For the real side, seed an approved campaign + session + carpenter + a media_objects row for the key and send the confirm with an `Idempotency-Key` and a valid consent payload; for the mock, POST the same shape.

- [ ] **Step 3: Run parity, format, analyze, commit**

```bash
cd tool/mock_server && dart pub get && dart analyze && dart format --set-exit-if-changed .
cd ../../server && DATABASE_URL='postgres://campaign:campaign@localhost:5432/campaign' dart test test/contract/parity_test.dart
cd .. && git add tool/mock_server/bin/server.dart server/test/contract/parity_test.dart
git commit -m "chore(mock): attendance/consent wire matches the real service

Mock confirm returns MATCH_PROCESSING (SCREAMING_SNAKE) and GET /consent/notices
returns {notices:[...]}; parity pins that the mock and real service agree on the
consent and confirm shapes."
```

---

### Task 8: E2E — real-service capture flow + CI gate

**Files:**
- Create: `.maestro/flows/attendance_capture.yaml`
- Modify: `.maestro/config.yaml`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the real endpoints (Tasks 4–6), the seeded consent notice + session + carpenter, the E2E `FakeCaptureSource`.
- Produces: a green blocking `capture` emulator gate proving the presign→upload→confirm round-trip against the real service.

- [ ] **Step 1: Author the flow**

`.maestro/flows/attendance_capture.yaml` — model the real-auth login prelude on `.maestro/flows/session_ops.yaml`, then reuse the capture steps from `.maestro/flows/field_online_capture.yaml`. Sign in for real as **`field_user`** (`Test1234!`), navigate to the seeded session's capture entry point, capture (the E2E `FakeCaptureSource` supplies a deterministic image — no camera), acknowledge consent, submit, and assert the offline queue reaches **"Match processing"** (the label from `offline_queue_screen.dart`, which only appears after a real presign→upload→confirm succeeds). Tag `capture`. Read `field_online_capture.yaml` for the exact capture/consent/submit step ids; add the real-auth login prelude and drop any FakeAuth-specific launcher steps.

> If the capture entry point cannot be reached under real auth with the current seed (e.g. it needs a specific navigation the mock provided differently), record the gap precisely and stop for guidance rather than guessing — the controller holds the cross-flow context.

- [ ] **Step 2: Add to the workspace inventory**

In `.maestro/config.yaml`, add `- flows/attendance_capture.yaml` to the `flows:` list.

- [ ] **Step 3: Add the CI matrix config**

In `.github/workflows/ci.yml`, add to the `e2e` job's `matrix.config` list (mirroring the `sessionOps`/`bulkImport` entries — real service, real auth, blocking):

```yaml
          # 4a: real-auth field_user capture round-trip (presign -> upload ->
          # confirm) against the real campaign_service. Acceptance proof for
          # sub-project 4a. The `field` config keeps the mock until 4c migrates
          # field_capture_recapture.
          - key: capture
            defines: '--dart-define=E2E_REAL_AUTH=true --dart-define=ROLE=field_user'
            useMock: '0'
            flows: .maestro/flows/attendance_capture.yaml
```

- [ ] **Step 4: Local validation (no emulator) — the server contract the flow depends on**

Bring up the real server and curl the round-trip; record the transcript:

```bash
cd server && ENABLE_TEST_SEEDING=true JWT_SECRET='local-compose-secret-at-least-32-chars!' docker compose up -d --build
# wait for /health, then:
curl -fsS -X POST localhost:8080/__test__/reset
TOKEN=$(curl -fsS -X POST localhost:8080/auth/login -H 'content-type: application/json' -d '{"username":"field_user","password":"Test1234!"}' | ... extract accessToken)
# consent:
curl -fsS -H "Authorization: Bearer $TOKEN" localhost:8080/consent/notices        # {notices:[...]}
# presign -> upload -> confirm for a key K, using the seeded session + carpenter:
URL=$(curl -fsS -X POST -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{"attendanceId":"K"}' localhost:8080/media/presign | ... extract url)
curl -fsS -X PUT --data-binary 'ciphertext' "$URL"                                 # 200
curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H 'Idempotency-Key: K' -H 'content-type: application/json' \
  -d '{"sessionId":"seed-camp-1-session-1","carpenterId":"<seeded carpenter id>","capturedAt":"2026-08-14T09:00:00.000Z","capturedBy":"seed-field_user","consentVersion":1,"consentLanguage":"en","consentShownAt":"2026-08-14T08:59:00.000Z","consentContentHash":"h"}' \
  localhost:8080/attendance/K/confirm                                              # {status:MATCH_PROCESSING,id:K}
cd server && docker compose down
```

Record the exact outputs (the seeded carpenter id is what `seedCarpenter`/`/carpenters` exposes). If the emulator is available, also run the flow via `run_maestro_flows.sh`.

- [ ] **Step 5: Commit**

```bash
git add .maestro/flows/attendance_capture.yaml .maestro/config.yaml .github/workflows/ci.yml
git commit -m "feat(e2e): attendance capture round-trip against the real service

A real-auth field_user flow captures, consents, and submits; the offline queue
reaches 'Match processing' only after a real presign -> upload -> confirm. Added
as a blocking `capture` emulator config (useMock 0). The `field` config keeps
the mock until 4c."
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task:
- §2 4a.D1 (server-only, no client change, no AttendanceStatus move) → the plan touches no `lib/` app code; error code + status literal only.
- 4a.D2 (BYTEA media, presign→own URL) → Tasks 2, 4. 4a.D3 (HMAC-signed capability upload) → Tasks 3, 4 (+ the `media/presign`-only auth root). 4a.D4 (confirm transaction, derive-from-session, evidence-required, idempotent) → Task 6. 4a.D5 (RBAC) → Tasks 4, 6 (`attendance_capture`), 5 (consent authenticate-only). 4a.D6 (no matching) → Task 6 (status literal `MATCH_PROCESSING`).
- §3 error code → Task 1; endpoints → Tasks 4–6. §4 migration → Task 2. §5 files → Tasks 3–6. §6 mock/seed → Tasks 5, 7. §6a validated patterns → folded into Tasks 3 (HMAC), 4 (BYTEA + size cap), 6 (idempotency reuse). §7 e2e → Task 8. §8 testing → the tests in every task incl. the signed-URL falsification and the idempotent-replay assertion. §9 out-of-scope items are not implemented.

**Placeholder scan:** the two prose-guided steps (Task 6 Step 1's test outline, Task 8 Step 1's flow authoring) name concrete assertions/ids and reference the exact template files; no "handle edge cases"/"similar to Task N"/bare "write tests". Task 8 Step 4's curl uses `...` only for shell value-extraction plumbing, with the concrete request bodies spelled out.

**Type consistency:** `signUploadUrl`/`verifyUploadSignature` (Task 3) are used with the same signatures in Task 4; `MediaRepo.{put,get}` (Task 4); `AttendanceRepo.confirm` + `AttendanceConfirmOutcome`/`AttendanceConfirmResult` (Task 6) used by `attendanceRouter`; `ApiErrorCode.attendanceEvidenceMissing`→422 (Task 1) thrown in Task 6; the `media/presign`-only auth root (Task 4) is what keeps `media/upload` bearer-less for Task 3's signature check. The status literal `'MATCH_PROCESSING'` is identical in the repo, the routes response, the mock, and the parity assertion.
