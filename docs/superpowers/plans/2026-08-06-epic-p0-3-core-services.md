# Epic P0.3 Core Services Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four remaining gaps in Epic P0.3 — correlation-ID and retry interceptors, a Drift v1→v2 migration, a `SecureStore` wrapper, and a durable client audit emitter — leaving the two 🔒 server-contract touchpoints behind narrow, testable seams.

**Architecture:** A pure `TraceId` leaf that both the network and audit layers depend on carries one ID per user action end-to-end. Audit events buffer in a new Drift table (schema v2) and are drained by a dedicated `AuditFlusher` that reuses the existing pure `BackoffPolicy` but not `SyncEngine`, because audit must never discard a record while evidence sync must give up and tell the user. Sensitive reveals go through an ack-gated API that takes the reveal as a callback, so it cannot fail open.

**Tech Stack:** Flutter (web + Android), Dart 3 with `strict-casts`/`strict-raw-types`, Dio 5.11, Drift 2.28.2 + drift_dev 2.28.0, Riverpod, `flutter_secure_storage` 10.3.1, `uuid` 4.6, `mocktail`, `shelf`/`shelf_router` for the mock server.

**Spec:** [`docs/superpowers/specs/2026-08-06-epic-p0-3-core-services-design.md`](../specs/2026-08-06-epic-p0-3-core-services-design.md)

## Global Constraints

- **Repo:** `D:\Camp_man`, branch `feat/campaign-management-flutter-scaffold`. Commit after every task.
- **Lints are strict and CI-enforced.** `analysis_options.yaml` enables `strict-casts: true`, `strict-raw-types: true`, and requires `always_declare_return_types`, `avoid_dynamic_calls`, `avoid_print`, `directives_ordering`, `prefer_const_constructors`, `prefer_final_locals`, `require_trailing_commas`, `sort_child_properties_last`, `unawaited_futures`, `use_super_parameters`. Use `debugPrint`, never `print`. Every `Future` is awaited or explicitly `unawaited(...)`.
- **Verification gates (every task):** `dart format --set-exit-if-changed .` clean, `flutter analyze --fatal-infos` exits 0, `flutter test` green. The final task additionally runs `flutter build web` and `flutter build apk --flavor dev`.
- **Baseline:** 33 tests pass before this epic starts. No existing test may regress — in particular `test/core/sync_engine_test.dart` and `test/core/backoff_test.dart`, since `BackoffPolicy` is reused unchanged.
- **HARD ORDERING CONSTRAINT:** Task 1 (dump the v1 Drift schema) MUST complete and be committed before Task 6 touches `app_database.dart`. After the `schemaVersion` bump the v1 baseline can only be recovered by a git checkout.
- **Never rename `SecureStoreKeys.evidenceAesKeyV1`** (value `'evidence_aes_key_v1'`). Renaming abandons any key already on a device, and with it the ability to decrypt evidence encrypted under it.
- **🔒 contract-pending endpoints** stay placeholders, flagged in-file exactly as the campaign endpoints already are: audit posts to `POST /audit/events` with body `{"events": [...]}`.
- **Do not consolidate** `sync_uploader.dart:81-98` `_map` with `mapDioError`. It diverges deliberately: `409` means *already confirmed, treat as success upstream*.

### Refinements to the spec, applied deliberately

Three places where this plan improves on the spec's letter while keeping its intent. Each is a strict improvement to a dependency direction the spec explicitly cared about:

1. **`traceOptions()` moves out of the trace leaf.** The spec put `TraceId` and `traceOptions()` in one file, but `traceOptions()` returns a Dio `Options`. Splitting it into `lib/core/network/trace_options.dart` keeps `lib/core/trace/trace_id.dart` free of any Dio import, so `core/audit` depends only on a pure type.
2. **`AuditTransport.send` returns `Future<Result<void>>`, not `Future<void>`.** This moves `mapDioError` into `DioAuditTransport`, so `audit_emitter.dart` needs no network import at all — which is the dependency direction §4.4 of the spec asked for.
3. **`AuditEvent.correlationId` becomes a `TraceId` instead of a `String`.** Type safety is the entire point of introducing the leaf, and `AuditEvent` has no call sites yet, so this costs nothing.

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `lib/core/trace/trace_id.dart` | `TraceId` value type. Pure — imports only `uuid`. |
| `lib/core/network/trace_options.dart` | `traceOptions()` + the two `extra` key constants. Bridges trace → Dio. |
| `lib/core/network/correlation_interceptor.dart` | Stamps `X-Correlation-Id` and `Idempotency-Key`; mints a `TraceId` when none supplied. |
| `lib/core/network/retry_interceptor.dart` | Transient-failure retry over `BackoffPolicy`, gated on idempotency for unsafe methods. |
| `lib/core/storage/secure_store.dart` | `SecureStore` interface, `FlutterSecureStore`, `SecureStoreKeys`. |
| `lib/core/storage/evidence_key_store.dart` | `EvidenceKeyStore` — evidence AES key lifecycle + rotation audit. |
| `lib/core/storage/schema_versions.dart` | **Generated** by `drift_dev schema steps`. Do not hand-edit. |
| `lib/core/audit/audit_transport.dart` | `AuditTransport` seam + `DioAuditTransport` (🔒). |
| `lib/core/audit/audit_emitter.dart` | `DurableAuditSink` + `AuditFlusher`. |
| `test/support/scripted_adapter.dart` | `ScriptedAdapter` — a scriptable `HttpClientAdapter` for interceptor tests. |
| `test/support/in_memory_secure_store.dart` | `InMemorySecureStore` + `ThrowingSecureStore`. |
| `test/support/recording_audit_sink.dart` | `RecordingAuditSink` for tests that only assert emission. |
| `drift_schemas/drift_schema_v1.json`, `_v2.json` | **Generated** schema baselines. Committed. |
| `test/generated/schema.dart`, `schema_v1.dart`, `schema_v2.dart` | **Generated** migration-test helpers. Committed. |

**Modified:**

| Path | Change |
|---|---|
| `lib/core/network/dio_client.dart` | Add both interceptors in order; `mapDioError` gains the `extra` correlation fallback. |
| `lib/core/network/auth_interceptor.dart` | Replay the 401 retry through the configured client, not a bare `Dio()`. |
| `lib/core/storage/app_database.dart` | `AuditEvents` table, `schemaVersion => 2`, `MigrationStrategy`. |
| `lib/core/audit/audit.dart` | `AuditEvent` gains `id`/`actorId`/`occurredAt`, `correlationId` becomes `TraceId`; `AuditSink` gains `revealAudited`; `AuditAction` gains `evidenceKeyRotated`. |
| `lib/app/di/providers.dart` | Wire new services; remove `loadOrCreateEvidenceKey` and `_evidenceKeyName`. |
| `lib/main.dart` | Eagerly start the flusher. |
| `pubspec.yaml` | Remove the unused `retry` dependency. |
| `tool/mock_server/bin/server.dart` | Add `POST /audit/events`. |
| 5 domain repository interfaces + 5 impls | Optional `{TraceId? trace}` on six methods. |
| 5 controllers | Mint a `TraceId` per action. |
| `test/app/evidence_key_test.dart` | Rewritten against `EvidenceKeyStore`. |

---

## Task 1: Capture the v1 Drift schema baseline

**This task must land before any other task touches `app_database.dart`.** It produces no production code — only the committed JSON snapshot that Task 6's migration test validates against. After Task 6 bumps `schemaVersion`, regenerating a v1 snapshot requires checking out an older commit.

**Files:**
- Create: `drift_schemas/drift_schema_v1.json` (generated)

**Interfaces:**
- Consumes: nothing.
- Produces: `drift_schemas/drift_schema_v1.json` — consumed by `drift_dev schema steps` and `drift_dev schema generate` in Task 6.

- [ ] **Step 1: Confirm the database is still at v1 before dumping**

Run: `grep -n "schemaVersion" lib/core/storage/app_database.dart`

Expected: `int get schemaVersion => 1;`. If this already says `2`, STOP — the ordering constraint has been violated and the v1 baseline must be recovered from git history before continuing.

- [ ] **Step 2: Dump the v1 schema**

```bash
dart run drift_dev schema dump lib/core/storage/app_database.dart drift_schemas/
```

- [ ] **Step 3: Verify the dump captured exactly the three v1 tables**

```bash
ls drift_schemas/
grep -o '"name":"[a-z_]*"' drift_schemas/drift_schema_v1.json | sort -u
```

Expected: the file `drift_schemas/drift_schema_v1.json` exists, and the table names include `sync_tasks`, `attendance_drafts` and `cached_references`. There must be **no** `audit_events` — if there is, the schema was dumped after a v2 edit.

- [ ] **Step 4: Commit**

```bash
git add drift_schemas/
git commit -m "chore: dump the v1 Drift schema baseline before the v2 migration

The v1 snapshot is unrecoverable once schemaVersion is bumped, so it is
captured and committed on its own before any schema edit."
```

---

## Task 2: `TraceId` and the correlation-ID interceptor

Closes half of T-0.3.2. Also fixes the defect where `mapDioError` returns a null correlation ID on transport errors — precisely the case a user needs to quote to support.

**Files:**
- Create: `lib/core/trace/trace_id.dart`
- Create: `lib/core/network/trace_options.dart`
- Create: `lib/core/network/correlation_interceptor.dart`
- Create: `test/support/scripted_adapter.dart`
- Create: `test/core/network/correlation_interceptor_test.dart`
- Modify: `lib/core/network/dio_client.dart` (add the interceptor; extend `mapDioError`)

**Interfaces:**
- Consumes: `mapDioError(Object) → Failure` and `buildDio({required String baseUrl, required AuthInterceptor authInterceptor}) → Dio` from `lib/core/network/dio_client.dart`; `Failure`/`FailureKind` from `lib/core/result/result.dart`.
- Produces:
  - `final class TraceId` with `TraceId.of(String value)`, `factory TraceId.generate()`, field `String value`, plus `==`/`hashCode`/`toString`.
  - `const String traceIdExtraKey = 'traceId'`, `const String idempotencyKeyExtraKey = 'idempotencyKey'`.
  - `Options traceOptions(TraceId trace, {String? idempotencyKey})`.
  - `class CorrelationIdInterceptor extends Interceptor` with `const CorrelationIdInterceptor()` and `static const String headerName = 'X-Correlation-Id'`.
  - `class ScriptedAdapter implements HttpClientAdapter` with `ScriptedAdapter(List<ScriptedReply> replies)`, `List<RequestOptions> requests`, and `class ScriptedReply` (`ScriptedReply.status(int code, {Map<String, String> headers})`, `ScriptedReply.failure(DioExceptionType type)`).

- [ ] **Step 1: Write the failing tests**

Create `test/support/scripted_adapter.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One scripted outcome for [ScriptedAdapter].
class ScriptedReply {
  /// An HTTP response with [code] and an empty JSON body.
  const ScriptedReply.status(this.code, {this.headers = const {}})
    : failureType = null;

  /// A transport-level failure (no response), e.g. a connection error.
  const ScriptedReply.failure(DioExceptionType type)
    : code = null,
      headers = const {},
      failureType = type;

  final int? code;
  final Map<String, String> headers;
  final DioExceptionType? failureType;
}

/// A scriptable [HttpClientAdapter] so interceptor tests run without a network.
///
/// Replies are consumed in order; the last reply repeats once exhausted, which
/// keeps retry tests from needing to pad the script. Every [RequestOptions] the
/// adapter sees is recorded in [requests], so a test can assert on the *second*
/// attempt's headers and resolved URI, not just the first.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this._replies);

  final List<ScriptedReply> _replies;
  final List<RequestOptions> requests = [];

  int get callCount => requests.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = _replies[(requests.length - 1).clamp(0, _replies.length - 1)];

    if (reply.failureType != null) {
      throw DioException(requestOptions: options, type: reply.failureType!);
    }

    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      reply.code!,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final entry in reply.headers.entries) entry.key: [entry.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

Create `test/core/network/correlation_interceptor_test.dart`:

```dart
import 'package:acsl_campaign/core/network/correlation_interceptor.dart';
import 'package:acsl_campaign/core/network/dio_client.dart';
import 'package:acsl_campaign/core/network/trace_options.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  Dio buildTestDio(ScriptedAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(const CorrelationIdInterceptor());
    return dio;
  }

  group('CorrelationIdInterceptor', () {
    test('mints a trace id when the caller supplied none', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);
      await buildTestDio(adapter).get<void>('/campaigns');

      final sent = adapter.requests.single;
      final header = sent.headers[CorrelationIdInterceptor.headerName];
      expect(header, isA<String>());
      expect(header as String, isNotEmpty);
      // The resolved id is written back so mapDioError can recover it.
      expect(sent.extra[traceIdExtraKey], isA<TraceId>());
      expect((sent.extra[traceIdExtraKey] as TraceId).value, header);
    });

    test('preserves a caller-supplied trace id verbatim', () async {
      // A per-action id must survive untouched, or the audit row and the API
      // call it describes end up with different ids and the trace is useless.
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);
      const trace = TraceId.of('action-abc');

      await buildTestDio(adapter).post<void>(
        '/campaigns',
        options: traceOptions(trace),
      );

      expect(
        adapter.requests.single.headers[CorrelationIdInterceptor.headerName],
        'action-abc',
      );
    });

    test('forwards an idempotency key as a header when supplied', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);

      await buildTestDio(adapter).post<void>(
        '/campaigns',
        options: traceOptions(
          const TraceId.of('t1'),
          idempotencyKey: 'key-1',
        ),
      );

      expect(adapter.requests.single.headers['Idempotency-Key'], 'key-1');
    });

    test('omits the idempotency header when none was supplied', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);

      await buildTestDio(adapter).post<void>(
        '/campaigns',
        options: traceOptions(const TraceId.of('t1')),
      );

      expect(
        adapter.requests.single.headers.containsKey('Idempotency-Key'),
        isFalse,
      );
    });
  });

  group('mapDioError correlation id', () {
    test('prefers the response header when the server sent one', () {
      final failure = mapDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response<void>(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 500,
            headers: Headers.fromMap({
              'x-correlation-id': ['server-side-id'],
            }),
          ),
        ),
      );

      expect(failure.correlationId, 'server-side-id');
    });

    test('falls back to the request trace id on a transport error', () async {
      // A connection error has no response and therefore no header. Before the
      // fallback this produced a Failure with a null correlation id - the exact
      // case a user most needs to quote to support.
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
      ]);
      final dio = buildTestDio(adapter);

      Failure? captured;
      try {
        await dio.get<void>('/campaigns', options: traceOptions(const TraceId.of('trace-9')));
      } on DioException catch (e) {
        captured = mapDioError(e);
      }

      expect(captured, isNotNull);
      expect(captured!.kind, FailureKind.network);
      expect(captured.correlationId, 'trace-9');
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/network/correlation_interceptor_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/trace/trace_id.dart'` and the same for `trace_options.dart` and `correlation_interceptor.dart`.

- [ ] **Step 3: Write the `TraceId` leaf**

Create `lib/core/trace/trace_id.dart`:

```dart
import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Identifies one user action end-to-end (Architecture §12, PRD FR-015).
///
/// A single id is minted per user action and shared by the audit row and every
/// HTTP request that action causes, so a support query can be traced from the
/// client through the server logs. Requests made outside an action scope get a
/// fresh per-request id from [CorrelationIdInterceptor], so nothing is
/// untraceable.
///
/// Deliberately a pure type: this library imports no Dio and no app code, so
/// both `core/network` and `core/audit` can depend on it without depending on
/// each other.
final class TraceId {
  const TraceId.of(this.value);

  factory TraceId.generate() => TraceId.of(_uuid.v4());

  final String value;

  @override
  bool operator ==(Object other) => other is TraceId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
```

- [ ] **Step 4: Write the Dio bridge**

Create `lib/core/network/trace_options.dart`:

```dart
import 'package:dio/dio.dart';

import '../trace/trace_id.dart';

/// Key under which a [TraceId] travels in `RequestOptions.extra`.
const String traceIdExtraKey = 'traceId';

/// Key under which a client idempotency key travels in `RequestOptions.extra`.
///
/// Presence of this key is what makes a non-idempotent request retryable
/// (see `RetryInterceptor`). Never set it for a request the server cannot
/// deduplicate.
const String idempotencyKeyExtraKey = 'idempotencyKey';

/// Builds request [Options] carrying a per-action [trace], and optionally the
/// [idempotencyKey] that permits retrying an unsafe method.
Options traceOptions(TraceId trace, {String? idempotencyKey}) => Options(
  extra: <String, Object?>{
    traceIdExtraKey: trace,
    if (idempotencyKey != null) idempotencyKeyExtraKey: idempotencyKey,
  },
);
```

- [ ] **Step 5: Write the interceptor**

Create `lib/core/network/correlation_interceptor.dart`:

```dart
import 'package:dio/dio.dart';

import '../trace/trace_id.dart';
import 'trace_options.dart';

/// Stamps every outbound request with a correlation id, and forwards a client
/// idempotency key when one was supplied.
///
/// This is the single place request decoration happens: `RetryInterceptor` only
/// *reads* `extra` to decide whether a retry is safe, it never stamps headers.
///
/// Must be registered FIRST so auth and retry both observe the resolved id.
class CorrelationIdInterceptor extends Interceptor {
  const CorrelationIdInterceptor();

  static const String headerName = 'X-Correlation-Id';
  static const String idempotencyHeaderName = 'Idempotency-Key';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final supplied = options.extra[traceIdExtraKey];
    final trace = supplied is TraceId ? supplied : TraceId.generate();

    // Write the resolved id back so mapDioError can recover it even when the
    // failure carries no response (connection error, timeout).
    options.extra[traceIdExtraKey] = trace;
    options.headers[headerName] = trace.value;

    final key = options.extra[idempotencyKeyExtraKey];
    if (key is String && key.isNotEmpty) {
      options.headers[idempotencyHeaderName] = key;
    }

    handler.next(options);
  }
}
```

- [ ] **Step 6: Wire the interceptor and extend `mapDioError`**

In `lib/core/network/dio_client.dart`, add the imports (respecting `directives_ordering` — package imports first, then relative, each alphabetical):

```dart
import 'package:dio/dio.dart';

import '../result/result.dart';
import '../trace/trace_id.dart';
import 'auth_interceptor.dart';
import 'correlation_interceptor.dart';
import 'trace_options.dart';
```

Replace the `dio.interceptors.addAll([...])` block (currently lines 21-24, carrying the `TODO(P0.3.2)`) with:

```dart
  // Order carries meaning in both directions. Correlation runs first on the
  // request so auth and retry both observe the resolved id. RetryInterceptor is
  // appended last, in Task 3, so AuthInterceptor gets first refusal on a 401 -
  // reversed, retry would spend its budget re-sending a stale token.
  dio.interceptors.addAll([const CorrelationIdInterceptor(), authInterceptor]);
```

Then in `mapDioError`, replace the single `correlationId` line with:

```dart
    final fromExtra = error.requestOptions.extra[traceIdExtraKey];
    // Prefer the server's id; fall back to the id we sent. A transport failure
    // has no response at all, so without this fallback the Failure carries no
    // correlation id - the exact case a user needs to quote to support.
    final correlationId =
        error.response?.headers.value('x-correlation-id') ??
        (fromExtra is TraceId ? fromExtra.value : null);
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/core/network/correlation_interceptor_test.dart`

Expected: PASS, 6 tests.

- [ ] **Step 8: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: format clean, analyze exits 0, all tests pass (33 existing + 6 new).

- [ ] **Step 9: Commit**

```bash
git add lib/core/trace/ lib/core/network/ test/support/scripted_adapter.dart test/core/network/
git commit -m "feat: add per-action correlation ids to every request

TraceId is a pure leaf so core/network and core/audit can both depend on
it without depending on each other. CorrelationIdInterceptor mints an id
when the caller supplied none, and writes the resolved id back into extra
so mapDioError can recover it on a transport failure - previously a
connection error produced a Failure with a null correlation id."
```

---

## Task 3: Retry interceptor

Closes T-0.3.2. The correctness rule that matters: HTTP method semantics alone are **not** sufficient. A retried bare `POST /campaigns` after a timeout creates two campaigns, and a timeout is exactly when you cannot tell whether the first one landed.

**Files:**
- Create: `lib/core/network/retry_interceptor.dart`
- Create: `test/core/network/retry_interceptor_test.dart`
- Modify: `lib/core/network/dio_client.dart` (append the interceptor)
- Modify: `pubspec.yaml` (remove the unused `retry` dependency)

**Interfaces:**
- Consumes: `BackoffPolicy` (`const BackoffPolicy({Duration base, Duration maxDelay, int maxRetries, double jitterFraction})`, `bool shouldGiveUp(int retryCount)`, `Duration delayFor(int retryCount, {double jitterSeed})`) and `double jitterSeedFor(String taskId)` from `lib/core/sync/backoff.dart`. `traceIdExtraKey`/`idempotencyKeyExtraKey` from Task 2. `ScriptedAdapter`/`ScriptedReply` from Task 2.
- Produces: `class RetryInterceptor extends Interceptor` with `RetryInterceptor({required Dio dio, BackoffPolicy policy = foregroundRetryPolicy, Future<void> Function(Duration) delay = _wait})` and `const BackoffPolicy foregroundRetryPolicy`.

- [ ] **Step 1: Write the failing test**

Create `test/core/network/retry_interceptor_test.dart`:

```dart
import 'package:acsl_campaign/core/network/correlation_interceptor.dart';
import 'package:acsl_campaign/core/network/retry_interceptor.dart';
import 'package:acsl_campaign/core/network/trace_options.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  /// Records every delay the interceptor asked for instead of sleeping, so the
  /// suite stays fast and the backoff schedule itself is assertable.
  late List<Duration> waits;

  Dio buildTestDio(ScriptedAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;
    dio.interceptors.addAll([
      const CorrelationIdInterceptor(),
      RetryInterceptor(
        dio: dio,
        delay: (d) async => waits.add(d),
      ),
    ]);
    return dio;
  }

  setUp(() => waits = []);

  group('safe methods', () {
    test('retries a GET on a connection error and succeeds', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
        const ScriptedReply.status(200),
      ]);

      final res = await buildTestDio(adapter).get<void>('/campaigns');

      expect(res.statusCode, 200);
      expect(adapter.callCount, 2);
      expect(waits, hasLength(1));
    });

    test('retries a GET on 503', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(503),
        const ScriptedReply.status(200),
      ]);

      final res = await buildTestDio(adapter).get<void>('/campaigns');

      expect(res.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('gives up after maxRetries and surfaces the last error', () async {
      // Default policy allows 2 retries, so 3 attempts total.
      final adapter = ScriptedAdapter([const ScriptedReply.status(503)]);

      await expectLater(
        buildTestDio(adapter).get<void>('/campaigns'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            503,
          ),
        ),
      );
      expect(adapter.callCount, 3);
      expect(waits, hasLength(2));
    });

    test('does not retry a 500 - the write may already have committed', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(500)]);

      await expectLater(
        buildTestDio(adapter).get<void>('/campaigns'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCount, 1);
      expect(waits, isEmpty);
    });

    test('does not retry a 404', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(404)]);

      await expectLater(
        buildTestDio(adapter).get<void>('/campaigns/missing'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCount, 1);
    });
  });

  group('unsafe methods', () {
    test('does NOT retry a bare POST', () async {
      // Retrying a POST with no idempotency key can create two campaigns, and a
      // timeout is exactly when the client cannot tell whether the first landed.
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
        const ScriptedReply.status(200),
      ]);

      await expectLater(
        buildTestDio(adapter).post<void>('/campaigns'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCount, 1);
      expect(waits, isEmpty);
    });

    test('retries a POST that carries an idempotency key', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
        const ScriptedReply.status(200),
      ]);

      final res = await buildTestDio(adapter).post<void>(
        '/campaigns',
        options: traceOptions(
          const TraceId.of('t1'),
          idempotencyKey: 'idem-1',
        ),
      );

      expect(res.statusCode, 200);
      expect(adapter.callCount, 2);
      // The replay must still carry the key, or the server cannot dedupe it.
      expect(
        adapter.requests.last.headers[
          CorrelationIdInterceptor.idempotencyHeaderName
        ],
        'idem-1',
      );
    });

    test('does not retry a DELETE without a key despite HTTP idempotency', () async {
      // DELETE is nominally idempotent per spec, but this server's semantics are
      // unconfirmed, so the explicit key is the only gate we trust.
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(503),
        const ScriptedReply.status(200),
      ]);

      await expectLater(
        buildTestDio(adapter).delete<void>('/campaigns/1'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCount, 1);
    });
  });

  group('delay selection', () {
    test('honours Retry-After over computed backoff', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(429, headers: {'retry-after': '7'}),
        const ScriptedReply.status(200),
      ]);

      await buildTestDio(adapter).get<void>('/campaigns');

      expect(waits.single, const Duration(seconds: 7));
    });

    test('falls back to jittered backoff when Retry-After is absent', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(503),
        const ScriptedReply.status(200),
      ]);

      await buildTestDio(adapter).get<void>('/campaigns');

      // base 300ms with +/-20% jitter on the first attempt.
      expect(waits.single.inMilliseconds, inInclusiveRange(240, 360));
    });

    test('ignores an unparseable Retry-After', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(503, headers: {'retry-after': 'Wed, 21 Oct'}),
        const ScriptedReply.status(200),
      ]);

      await buildTestDio(adapter).get<void>('/campaigns');

      expect(waits.single.inMilliseconds, inInclusiveRange(240, 360));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/network/retry_interceptor_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/network/retry_interceptor.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/network/retry_interceptor.dart`:

```dart
import 'package:dio/dio.dart';

import '../sync/backoff.dart';
import '../trace/trace_id.dart';
import 'trace_options.dart';

/// Retry budget for foreground API calls.
///
/// Deliberately NOT the sync engine's policy. Sync tolerates `maxRetries: 8`
/// over up to five minutes because a field upload can wait; a foreground call
/// blocking the UI that long is a bug. Worst case here is under ~7s added.
const BackoffPolicy foregroundRetryPolicy = BackoffPolicy(
  base: Duration(milliseconds: 300),
  maxDelay: Duration(seconds: 3),
  maxRetries: 2,
);

const String _attemptExtraKey = 'retryAttempt';

Future<void> _wait(Duration d) => Future<void>.delayed(d);

/// Retries transient transport and overload failures.
///
/// Registered LAST so [AuthInterceptor] gets first refusal on a 401 - reversed,
/// this would spend its budget re-sending a request with a stale token.
///
/// Retries are re-dispatched through the same [Dio], so the full interceptor
/// chain (including auth) runs again. Recursion is bounded by an attempt
/// counter carried in `RequestOptions.extra`.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required Dio dio,
    BackoffPolicy policy = foregroundRetryPolicy,
    Future<void> Function(Duration) delay = _wait,
  }) : _dio = dio,
       _policy = policy,
       _delay = delay;

  final Dio _dio;
  final BackoffPolicy _policy;
  final Future<void> Function(Duration) _delay;

  /// Transient by nature: worth another attempt.
  ///
  /// 500 and 501 are excluded on purpose - a 500 may have committed a write and
  /// no server contract says otherwise, so a blind retry risks a duplicate.
  static const Set<int> _retryableStatus = {429, 502, 503, 504};

  static const Set<DioExceptionType> _retryableTypes = {
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.sendTimeout,
  };

  static const Set<String> _safeMethods = {'GET', 'HEAD'};

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attemptValue = options.extra[_attemptExtraKey];
    final attempt = attemptValue is int ? attemptValue : 0;

    if (!_isRetryable(err) ||
        !_isSafeToRetry(options) ||
        _policy.shouldGiveUp(attempt)) {
      return handler.next(err);
    }

    await _delay(_retryAfter(err) ?? _backoff(options, attempt));

    options.extra[_attemptExtraKey] = attempt + 1;
    try {
      final response = await _dio.fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  bool _isRetryable(DioException err) {
    final status = err.response?.statusCode;
    if (status != null) return _retryableStatus.contains(status);
    return _retryableTypes.contains(err.type);
  }

  /// Safe methods retry freely. Everything else retries ONLY with an explicit
  /// idempotency key: HTTP method semantics alone are not a guarantee this
  /// server honours, and a duplicate write is worse than a surfaced error.
  bool _isSafeToRetry(RequestOptions options) {
    if (_safeMethods.contains(options.method.toUpperCase())) return true;
    final key = options.extra[idempotencyKeyExtraKey];
    return key is String && key.isNotEmpty;
  }

  /// `Retry-After` in delta-seconds form. The HTTP-date form is not honoured:
  /// it requires trusting the client clock, which on field devices is exactly
  /// what we avoid elsewhere. An unparseable value falls back to backoff.
  Duration? _retryAfter(DioException err) {
    final raw = err.response?.headers.value('retry-after');
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    return seconds == null ? null : Duration(seconds: seconds);
  }

  /// Seeds jitter from the trace id so a given call jitters reproducibly in
  /// tests while different calls still de-synchronise across devices.
  Duration _backoff(RequestOptions options, int attempt) {
    final trace = options.extra[traceIdExtraKey];
    final seed = jitterSeedFor(
      trace is TraceId ? trace.value : options.path,
    );
    return _policy.delayFor(attempt, jitterSeed: seed);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/network/retry_interceptor_test.dart`

Expected: PASS, 11 tests.

- [ ] **Step 5: Wire the interceptor into `buildDio`**

In `lib/core/network/dio_client.dart`, add `import 'retry_interceptor.dart';` (after `correlation_interceptor.dart`, before `trace_options.dart` — `directives_ordering` sorts alphabetically) and replace the `addAll` block with:

```dart
  dio.interceptors.addAll([
    const CorrelationIdInterceptor(),
    authInterceptor,
    // Last on purpose: AuthInterceptor must get first refusal on a 401.
    RetryInterceptor(dio: dio),
  ]);
```

- [ ] **Step 6: Remove the unused `retry` dependency**

In `pubspec.yaml`, delete the line `  retry: ^3.1.2` from the `# Network` block. It has never been imported anywhere in `lib/` or `test/` — `BackoffPolicy` covers the need and is already unit-tested.

Run: `flutter pub get`

- [ ] **Step 7: Confirm `retry` is genuinely unreferenced**

Run: `grep -rn "package:retry" lib test tool || echo "clean"`

Expected: `clean`.

- [ ] **Step 8: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: format clean, analyze exits 0, all tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/core/network/ test/core/network/ pubspec.yaml pubspec.lock
git commit -m "feat: retry transient API failures, gated on idempotency

Unsafe methods retry only when the request carries an explicit
idempotency key: HTTP method semantics are not a guarantee this server
honours, and a retried bare POST after a timeout can create two
campaigns. 500 and 501 are excluded because the write may have
committed. Reuses the tested BackoffPolicy at a foreground-appropriate
tuning and drops the never-imported retry dependency."
```

---

## Task 4: Fix the 401 replay path

`auth_interceptor.dart:43` builds a fresh `Dio()` with no `baseUrl` and no interceptors to replay the original request. Every repository in `lib/data/` uses relative paths (`/campaigns`, `/verification/queue`), so a successful refresh would be followed by a request to an unresolvable URL. It is latent only because `refreshToken` currently throws first.

**Files:**
- Modify: `lib/core/network/auth_interceptor.dart`
- Modify: `lib/core/network/dio_client.dart` (pass the replay callback through)
- Create: `test/core/network/auth_interceptor_test.dart`

**Interfaces:**
- Consumes: `ScriptedAdapter`/`ScriptedReply` from Task 2.
- Produces: `AuthInterceptor({required String? Function() readAccessToken, required Future<String?> Function() refreshToken, required void Function() onAuthLost, required Future<Response<dynamic>> Function(RequestOptions) replay})`.
- **`buildDio`'s signature is unchanged.** The replay callback is supplied to `AuthInterceptor`'s constructor at the composition root (Step 5), not plumbed through `buildDio` — `buildDio` already receives the fully-built interceptor.

- [ ] **Step 1: Write the failing test**

Create `test/core/network/auth_interceptor_test.dart`:

```dart
import 'package:acsl_campaign/core/network/auth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  group('AuthInterceptor 401 refresh', () {
    test('replays the request against the configured baseUrl', () async {
      // The bug this pins: replaying through a bare Dio() drops baseUrl, and
      // every repository calls relative paths, so the replay would go nowhere.
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(401),
        const ScriptedReply.status(200),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter;

      var refreshCalls = 0;
      var authLost = false;
      dio.interceptors.add(
        AuthInterceptor(
          readAccessToken: () => 'stale',
          refreshToken: () async {
            refreshCalls++;
            return 'fresh';
          },
          onAuthLost: () => authLost = true,
          replay: (options) => dio.fetch<dynamic>(options),
        ),
      );

      final res = await dio.get<void>('/campaigns');

      expect(res.statusCode, 200);
      expect(refreshCalls, 1);
      expect(authLost, isFalse);
      expect(adapter.callCount, 2);
      expect(adapter.requests.last.uri.toString(), 'https://api.test/campaigns');
      expect(adapter.requests.last.headers['Authorization'], 'Bearer fresh');
    });

    test('signals auth lost when refresh yields no token', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(401)]);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter;

      var authLost = false;
      dio.interceptors.add(
        AuthInterceptor(
          readAccessToken: () => 'stale',
          refreshToken: () async => null,
          onAuthLost: () => authLost = true,
          replay: (options) => dio.fetch<dynamic>(options),
        ),
      );

      await expectLater(dio.get<void>('/campaigns'), throwsA(isA<DioException>()));
      expect(authLost, isTrue);
      expect(adapter.callCount, 1);
    });

    test('attaches the bearer token when one is available', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(
        AuthInterceptor(
          readAccessToken: () => 'token-1',
          refreshToken: () async => null,
          onAuthLost: () {},
          replay: (options) => dio.fetch<dynamic>(options),
        ),
      );

      await dio.get<void>('/campaigns');

      expect(adapter.requests.single.headers['Authorization'], 'Bearer token-1');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/network/auth_interceptor_test.dart`

Expected: FAIL to compile — `No named parameter with the name 'replay'`.

- [ ] **Step 3: Add the replay seam**

In `lib/core/network/auth_interceptor.dart`, update the doc comment and constructor, and replace the bare-`Dio()` call:

```dart
import 'package:dio/dio.dart';

/// Attaches the bearer token and transparently refreshes on 401.
///
/// Contract dependency 🔒: refresh endpoint + token rotation semantics
/// (Task T-0.4.1). Until the auth service contract is confirmed, [refreshToken]
/// is a seam that throws so it is not silently a no-op.
///
/// [replay] re-issues the original request after a successful refresh. It is
/// injected rather than constructed here because a fresh `Dio()` carries no
/// `baseUrl`, and every repository in `lib/data/` uses relative paths - so a
/// self-built client would send the replay to an unresolvable URL.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.readAccessToken,
    required this.refreshToken,
    required this.onAuthLost,
    required this.replay,
  });

  final String? Function() readAccessToken;
  final Future<String?> Function() refreshToken;
  final void Function() onAuthLost;
  final Future<Response<dynamic>> Function(RequestOptions options) replay;
```

Then replace the body of the 401 branch in `onError`:

```dart
    if (err.response?.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed == null) {
        onAuthLost();
        return handler.next(err);
      }
      // Retry the original request once with the new token, through the
      // configured client so baseUrl and the interceptor chain still apply.
      final req = err.requestOptions
        ..headers['Authorization'] = 'Bearer $refreshed';
      try {
        return handler.resolve(await replay(req));
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/network/auth_interceptor_test.dart`

Expected: PASS, 3 tests.

- [ ] **Step 5: Supply the replay at the composition root**

In `lib/app/di/providers.dart`, rewrite `dioProvider` (currently lines 63-74). The `late final` capture is what breaks the constructor cycle: the interceptor needs the client, and the client needs the interceptor.

```dart
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  // The interceptor needs the client it lives in, so bind lazily: `dio` is
  // assigned before any request can run, so the closure never sees it unset.
  late final Dio dio;
  final interceptor = AuthInterceptor(
    readAccessToken: () => ref.read(authControllerProvider)?.accessToken,
    refreshToken: () async {
      // TODO(T-0.4.1): call refresh endpoint; return new token or null.
      throw UnimplementedError('Auth refresh pending service contract');
    },
    onAuthLost: () => ref.read(authControllerProvider.notifier).clear(),
    replay: (options) => dio.fetch<dynamic>(options),
  );
  dio = buildDio(baseUrl: config.apiBaseUrl, authInterceptor: interceptor);
  return dio;
});
```

- [ ] **Step 6: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: format clean, analyze exits 0, all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/core/network/auth_interceptor.dart lib/app/di/providers.dart test/core/network/auth_interceptor_test.dart
git commit -m "fix: replay the 401 retry through the configured Dio client

The retry built a fresh Dio() with no baseUrl, and every repository uses
relative paths, so a successful refresh would have been followed by a
request to an unresolvable URL. Latent only because refreshToken still
throws pending the T-0.4.1 contract."
```

---

## Task 5: `SecureStore` wrapper

Closes T-0.3.4's wrapper half. `EvidenceKeyStore` follows in Task 8, once `AuditSink` exists to record a key rotation.

**Files:**
- Create: `lib/core/storage/secure_store.dart`
- Create: `test/support/in_memory_secure_store.dart`
- Create: `test/core/storage/secure_store_test.dart`

**Interfaces:**
- Consumes: `flutter_secure_storage` 10.3.1.
- Produces:
  - `abstract interface class SecureStore` with `Future<String?> read(String key)`, `Future<void> write(String key, String value)`, `Future<void> delete(String key)`.
  - `class FlutterSecureStore implements SecureStore` — `FlutterSecureStore([FlutterSecureStorage? storage])`.
  - `abstract final class SecureStoreKeys` with `static const String evidenceAesKeyV1 = 'evidence_aes_key_v1'`.
  - `class InMemorySecureStore implements SecureStore` — `Map<String, String> values`, `int writeCount`.
  - `class ThrowingSecureStore implements SecureStore` — `ThrowingSecureStore(Object error)`, throws on `read`, records writes in `values`.

- [ ] **Step 1: Write the failing test**

Create `test/support/in_memory_secure_store.dart`:

```dart
import 'package:acsl_campaign/core/storage/secure_store.dart';

/// In-memory [SecureStore] for tests. Replaces mocking FlutterSecureStorage,
/// which required a `mocktail` stub per call and could not express "a value
/// exists but cannot be decrypted".
class InMemorySecureStore implements SecureStore {
  InMemorySecureStore([Map<String, String>? initial])
    : values = {...?initial};

  final Map<String, String> values;
  int writeCount = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A store whose reads always fail - models the platform case where a value is
/// present but undecryptable (v10 cipher change, keystore reset, restore onto a
/// different device). Writes still succeed so recovery paths are testable.
class ThrowingSecureStore implements SecureStore {
  ThrowingSecureStore(this.error);

  final Object error;
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => throw error;

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
```

Create `test/core/storage/secure_store_test.dart`:

```dart
import 'package:acsl_campaign/core/storage/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_secure_store.dart';

void main() {
  group('SecureStoreKeys', () {
    test('the evidence key name is frozen', () {
      // Renaming this abandons any key already on a device, and with it the
      // ability to decrypt evidence encrypted under it. Never change it.
      expect(SecureStoreKeys.evidenceAesKeyV1, 'evidence_aes_key_v1');
    });
  });

  group('InMemorySecureStore', () {
    test('round-trips a value', () async {
      final store = InMemorySecureStore();

      expect(await store.read('k'), isNull);
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
    });

    test('delete removes the value', () async {
      final store = InMemorySecureStore({'k': 'v'});

      await store.delete('k');

      expect(await store.read('k'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/storage/secure_store_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/storage/secure_store.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/storage/secure_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys used with [SecureStore]. Centralised so a rename is a deliberate,
/// reviewable act rather than an inline edit.
abstract final class SecureStoreKeys {
  /// NEVER rename. Renaming abandons any key already present on a device, and
  /// with it the ability to decrypt evidence encrypted under that key.
  static const String evidenceAesKeyV1 = 'evidence_aes_key_v1';
}

/// Platform-backed secret storage (Keystore on Android, Keychain on iOS).
///
/// **Web is not hardware-backed.** `flutter_secure_storage_web` is
/// `localStorage` with a wrapped key, so on web this is obfuscation, not
/// protection. Consequences: the evidence AES key stays mobile-only (capture
/// already is), and the CRM web surface must persist nothing whose compromise
/// matters beyond the session.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          // v10 defaults resetOnError to true, which silently deletes a value
          // it cannot decrypt. For the evidence key that would orphan every
          // queued capture with no signal, so opt out and let the caller
          // (EvidenceKeyStore) handle the failure explicitly and audibly.
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/storage/secure_store_test.dart`

Expected: PASS, 3 tests.

- [ ] **Step 5: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: format clean, analyze exits 0, all tests pass. `providers.dart` still uses the raw `FlutterSecureStorage` at this point — Task 8 builds `EvidenceKeyStore` on top of `SecureStore`, and Task 9 rewires the composition root onto both. The temporary coexistence is intentional, not duplication to clean up here.

- [ ] **Step 6: Commit**

```bash
git add lib/core/storage/secure_store.dart test/support/in_memory_secure_store.dart test/core/storage/secure_store_test.dart
git commit -m "feat: add a SecureStore wrapper with a frozen key registry

Moves the resetOnError:false reasoning out of a provider comment and into
the implementation, and documents that web is localStorage rather than
hardware-backed so no caller assumes Keystore-grade guarantees there."
```

---

## Task 6: `AuditEvents` table and the v1→v2 migration

Closes T-0.3.3. **Requires Task 1 to be committed.**

**Files:**
- Modify: `lib/core/storage/app_database.dart`
- Create: `lib/core/storage/schema_versions.dart` (generated)
- Create: `drift_schemas/drift_schema_v2.json` (generated)
- Create: `test/generated/schema.dart`, `schema_v1.dart`, `schema_v2.dart` (generated)
- Create: `test/core/storage/migration_test.dart`

**Interfaces:**
- Consumes: `AppDatabase(QueryExecutor)` and `AppDatabase.open()` from `lib/core/storage/app_database.dart`; `drift_dev/api/migrations.dart`.
- Produces: `AuditEvents` table with generated `AuditEvent` row class (**named `AuditEventRow` via `@DataClassName` to avoid colliding with the domain `AuditEvent` in `lib/core/audit/audit.dart`**), `AppDatabase.schemaVersion == 2`, and `AppDatabase.migration`.

- [ ] **Step 1: Confirm Task 1 landed**

Run: `git log --oneline -- drift_schemas/ | tail -1 && ls drift_schemas/drift_schema_v1.json`

Expected: a commit touching `drift_schemas/` exists and `drift_schema_v1.json` is present. If not, STOP and complete Task 1 first.

- [ ] **Step 2: Write the failing test**

Create `test/core/storage/migration_test.dart`:

```dart
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v1.dart' as v1;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('migrates v1 to v2', () async {
    final connection = await verifier.schemaAt(1);
    final db = AppDatabase(connection.executor);

    await verifier.migrateAndValidate(db, 2);

    await db.close();
  });

  test('preserves queued field data across the upgrade', () async {
    // This is the assertion that protects users. A migration that silently
    // drops a queued attendance capture loses field evidence which cannot be
    // recaptured - the carpenter has left the venue.
    final connection = await verifier.schemaAt(1);

    final oldDb = v1.DatabaseAtV1.connect(connection);
    await oldDb.into(oldDb.syncTasks).insert(
      v1.SyncTasksData(
        id: 'task-1',
        type: 'attendance',
        payloadJson: '{"sessionId":"s1"}',
        status: 'pendingSync',
        retryCount: 3,
        createdAt: DateTime.utc(2026, 8, 1, 9, 30),
        lastError: 'connection refused',
      ),
    );
    await oldDb.into(oldDb.attendanceDrafts).insert(
      v1.AttendanceDraftsData(
        id: 'task-1',
        sessionId: 's1',
        carpenterId: 'c1',
        encryptedMediaPath: '/enc/task-1.bin',
        capturedAt: DateTime.utc(2026, 8, 1, 9, 29),
        capturedBy: 'field-user-1',
      ),
    );
    await oldDb.close();

    final db = AppDatabase(connection.executor);
    await verifier.migrateAndValidate(db, 2);

    final tasks = await db.select(db.syncTasks).get();
    expect(tasks, hasLength(1));
    expect(tasks.single.id, 'task-1');
    expect(tasks.single.retryCount, 3);
    expect(tasks.single.lastError, 'connection refused');

    final drafts = await db.select(db.attendanceDrafts).get();
    expect(drafts, hasLength(1));
    expect(drafts.single.encryptedMediaPath, '/enc/task-1.bin');
    expect(drafts.single.capturedBy, 'field-user-1');

    // The new table exists and starts empty.
    expect(await db.select(db.auditEvents).get(), isEmpty);

    await db.close();
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/storage/migration_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: '../../generated/schema.dart'`. The generated helpers do not exist yet.

- [ ] **Step 4: Add the table and the migration**

In `lib/core/storage/app_database.dart`, add the table after `CachedReferences` (before the `@DriftDatabase` annotation):

```dart
/// Durable buffer for client audit events (Guideline §12, PRD FR-015). The
/// server is the authoritative store; this table exists so an event survives
/// process death on its way there.
///
/// The row class is named `AuditEventRow` because the domain-level `AuditEvent`
/// in `lib/core/audit/audit.dart` is what callers construct; this is only its
/// persisted shape.
@DataClassName('AuditEventRow')
class AuditEvents extends Table {
  /// Autoincrement so flush order is genuinely FIFO. [id] is a UUID and
  /// [occurredAt] can tie at millisecond resolution, so neither gives a stable
  /// ordering on its own.
  IntColumn get seq => integer().autoIncrement()();

  /// Client-generated UUID, so the server can dedupe a replayed batch.
  TextColumn get id => text().unique()();

  TextColumn get action => text()(); // AuditAction.name
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get correlationId => text()();

  /// Captured at emit time, never inferred at flush time. Field devices are
  /// shared: an event captured offline by one user can flush after a different
  /// user has logged in, and attributing it to whoever happens to be holding
  /// the phone would corrupt the audit trail.
  TextColumn get actorId => text()();

  TextColumn get remarks => text().nullable()();

  /// Client clock. The server should treat this as untrusted and pair it with
  /// its own receipt time.
  DateTimeColumn get occurredAt => dateTime()();

  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}
```

Update the annotation and class body:

```dart
@DriftDatabase(
  tables: [SyncTasks, AttendanceDrafts, CachedReferences, AuditEvents],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the on-device database across native and web (wasm). Tests use the
  /// primary constructor with an in-memory `NativeDatabase.memory()` executor.
  AppDatabase.open() : super(driftDatabase(name: 'acsl_campaign'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      // v2 adds the audit buffer. The three v1 tables are untouched, which is
      // what makes the data-survival assertion in migration_test.dart hold.
      from1To2: (m, schema) async => m.createTable(schema.auditEvents),
    ),
  );
}
```

Add the import for the generated step helper at the top, after the existing imports:

```dart
import 'schema_versions.dart';
```

- [ ] **Step 5: Generate the row classes**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: `lib/core/storage/app_database.g.dart` regenerates with `AuditEvents`/`AuditEventRow`. This will still fail to compile because `schema_versions.dart` does not exist yet — that is expected; continue to Step 6.

- [ ] **Step 6: Generate the migration step helper**

```bash
dart run drift_dev schema steps drift_schemas/ lib/core/storage/schema_versions.dart
```

Expected: `lib/core/storage/schema_versions.dart` is created, exposing `stepByStep(from1To2: ...)`.

- [ ] **Step 7: Dump the v2 schema and generate the test helpers**

```bash
dart run drift_dev schema dump lib/core/storage/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/
```

Expected: `drift_schemas/drift_schema_v2.json` plus `test/generated/schema.dart`, `schema_v1.dart`, `schema_v2.dart`.

- [ ] **Step 8: Reconcile the test with the generated names**

Open `test/generated/schema_v1.dart` and confirm the class and row names the test imports actually exist: `DatabaseAtV1`, `SyncTasksData`, `AttendanceDraftsData`, and the `connect` constructor. drift's generator has used both `DatabaseAtV1(connection)` and `DatabaseAtV1.connect(connection)` across versions.

If the generated names differ, update `test/core/storage/migration_test.dart` to match the generated file — the generated code is the source of truth, not this plan. Do not hand-edit anything under `test/generated/` or `drift_schemas/`.

- [ ] **Step 9: Run the test to verify it passes**

Run: `flutter test test/core/storage/migration_test.dart`

Expected: PASS, 2 tests.

- [ ] **Step 10: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: format clean, analyze exits 0, all tests pass. `test/core/sync_engine_test.dart` must still be green — it opens `AppDatabase(NativeDatabase.memory())`, which now runs `onCreate` at v2.

- [ ] **Step 11: Commit**

```bash
git add lib/core/storage/ drift_schemas/ test/generated/ test/core/storage/migration_test.dart
git commit -m "feat: add the audit_events table as Drift schema v2

seq autoincrements so flush order is FIFO; actorId is captured at emit
time rather than inferred at flush, because shared field devices would
otherwise attribute an offline event to whoever next logged in. The
migration test asserts both the schema shape and that queued attendance
rows survive the upgrade intact."
```

---

## Task 7: `DurableAuditSink` — durable emit and the ack-gated reveal

First half of T-0.3.6. The flusher follows in Task 8.

**Files:**
- Modify: `lib/core/audit/audit.dart`
- Create: `lib/core/audit/audit_transport.dart`
- Create: `lib/core/audit/audit_emitter.dart`
- Create: `test/core/audit/audit_emitter_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `AuditEvents`/`AuditEventRow` from Task 6; `TraceId` from Task 2; `Result`/`Ok`/`Err`/`Failure`/`FailureKind` from `lib/core/result/result.dart`; `mapDioError` from `lib/core/network/dio_client.dart`.
- Produces:
  - `AuditEvent({required AuditAction action, required String entity, required String entityId, required TraceId correlationId, required String actorId, String? remarks})`.
  - `AuditSink` with `Future<void> emit(AuditEvent event)` and `Future<Result<T>> revealAudited<T>(AuditEvent event, Future<T> Function() reveal)`.
  - `AuditAction.evidenceKeyRotated` (new enum value).
  - `class AuditEventPayload` — wire shape with `String action` (deliberately not the enum), `entity`, `entityId`, `correlationId`, `actorId`, `remarks`, `factory AuditEventPayload.fromEvent(AuditEvent)`, and `Map<String, Object?> toJson()`.
  - `abstract interface class AuditTransport` with `Future<Result<void>> send(List<AuditEventPayload> events)`; `class DioAuditTransport implements AuditTransport` — `DioAuditTransport(Dio dio)`.
  - `class DurableAuditSink implements AuditSink` — `DurableAuditSink({required AppDatabase db, required AuditTransport transport, DateTime Function() now = ..., String Function() newId = ..., void Function()? onBuffered})`.

- [ ] **Step 1: Write the failing test**

Create `test/core/audit/audit_emitter_test.dart`:

```dart
import 'package:acsl_campaign/core/audit/audit.dart';
import 'package:acsl_campaign/core/audit/audit_emitter.dart';
import 'package:acsl_campaign/core/audit/audit_transport.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Transport whose result is scripted per call, recording what it was asked to
/// send and how many rows existed at that moment.
class _ScriptedTransport implements AuditTransport {
  _ScriptedTransport(this._results, {this.onSend});

  final List<Result<void>> _results;

  /// Async on purpose: the ordering test inspects the DB from here, and a
  /// `void Function()` would let that inspection fire-and-forget, so the
  /// assertion could run before the read completed.
  final Future<void> Function()? onSend;

  final List<List<AuditEventPayload>> batches = [];

  @override
  Future<Result<void>> send(List<AuditEventPayload> events) async {
    batches.add(events);
    await onSend?.call();
    return _results[(batches.length - 1).clamp(0, _results.length - 1)];
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  var counter = 0;
  DurableAuditSink buildSink(
    AuditTransport transport, {
    void Function()? onBuffered,
  }) {
    counter = 0;
    return DurableAuditSink(
      db: db,
      transport: transport,
      now: () => DateTime.utc(2026, 8, 6, 12),
      newId: () => 'id-${++counter}',
      onBuffered: onBuffered,
    );
  }

  AuditEvent event({
    AuditAction action = AuditAction.campaignApproved,
    String entityId = 'CMP-1',
  }) => AuditEvent(
    action: action,
    entity: 'campaign',
    entityId: entityId,
    correlationId: const TraceId.of('trace-1'),
    actorId: 'user-1',
  );

  group('emit', () {
    test('persists the event and returns without contacting the transport',
        () async {
      // emit() must be durable-and-async: it returns on local commit so an
      // audit outage never blocks a campaign approval.
      final transport = _ScriptedTransport([const Ok(null)]);
      final sink = buildSink(transport);

      await sink.emit(event());

      final rows = await db.select(db.auditEvents).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'id-1');
      expect(rows.single.action, 'campaignApproved');
      expect(rows.single.actorId, 'user-1');
      expect(rows.single.correlationId, 'trace-1');
      expect(rows.single.occurredAt, DateTime.utc(2026, 8, 6, 12));
      expect(rows.single.attempts, 0);
      expect(transport.batches, isEmpty);
    });

    test('notifies the buffer callback so a full batch can flush early',
        () async {
      var notifications = 0;
      final sink = buildSink(
        _ScriptedTransport([const Ok(null)]),
        onBuffered: () => notifications++,
      );

      await sink.emit(event());
      await sink.emit(event(entityId: 'CMP-2'));

      expect(notifications, 2);
    });

    test('assigns increasing seq values so flush order is FIFO', () async {
      final sink = buildSink(_ScriptedTransport([const Ok(null)]));

      await sink.emit(event(entityId: 'first'));
      await sink.emit(event(entityId: 'second'));

      final rows = await (db.select(db.auditEvents)
            ..orderBy([(t) => OrderingTerm(expression: t.seq)]))
          .get();
      expect(rows.map((r) => r.entityId), ['first', 'second']);
      expect(rows.first.seq, lessThan(rows.last.seq));
    });
  });

  group('revealAudited', () {
    test('writes the row BEFORE calling the transport', () async {
      // Ordering is the whole control: if the transport were called first, a
      // crash mid-post would leave no record that access was attempted.
      var rowsWhenSent = -1;
      final transport = _ScriptedTransport(
        [const Ok(null)],
        onSend: () async {
          rowsWhenSent = (await db.select(db.auditEvents).get()).length;
        },
      );
      final sink = buildSink(transport);

      await sink.revealAudited(event(action: AuditAction.sensitiveMediaViewed),
          () async => 'photo-bytes');

      expect(rowsWhenSent, 1);
    });

    test('invokes the reveal and clears the row once the server acks', () async {
      final sink = buildSink(_ScriptedTransport([const Ok(null)]));
      var revealed = false;

      final result = await sink.revealAudited(
        event(action: AuditAction.nidRevealed),
        () async {
          revealed = true;
          return 'NID-1234';
        },
      );

      expect(revealed, isTrue);
      expect(result.isOk, isTrue);
      expect(result.fold((v) => v, (_) => null), 'NID-1234');
      // Confirmed sent, so nothing is left for the flusher.
      expect(await db.select(db.auditEvents).get(), isEmpty);
    });

    test('does NOT invoke the reveal when the ack fails', () async {
      // Fails closed. This is the assertion that makes audit-on-view a real
      // control rather than a best-effort log line.
      final sink = buildSink(
        _ScriptedTransport([const Err(Failure(FailureKind.network))]),
      );
      var revealed = false;

      final result = await sink.revealAudited(
        event(action: AuditAction.sensitiveMediaViewed),
        () async {
          revealed = true;
          return 'photo-bytes';
        },
      );

      expect(revealed, isFalse);
      expect(result.isOk, isFalse);
      expect(
        result.fold((_) => null, (f) => f.kind),
        FailureKind.network,
      );
    });

    test('leaves the row buffered when the ack fails', () async {
      // The reveal was blocked, but the attempt must still reach the server
      // eventually - the flusher picks this up.
      final sink = buildSink(
        _ScriptedTransport([const Err(Failure(FailureKind.timeout))]),
      );

      await sink.revealAudited(
        event(action: AuditAction.sensitiveMediaViewed),
        () async => 'photo-bytes',
      );

      final rows = await db.select(db.auditEvents).get();
      expect(rows, hasLength(1));
      expect(rows.single.action, 'sensitiveMediaViewed');
    });

    test('carries the correlation id on the failure', () async {
      final sink = buildSink(
        _ScriptedTransport([
          const Err(Failure(FailureKind.forbidden, correlationId: 'srv-1')),
        ]),
      );

      final result = await sink.revealAudited(
        event(action: AuditAction.nidRevealed),
        () async => 'NID-1234',
      );

      // A 403 on the audit endpoint is a permissions problem and must not read
      // the same as a dropped connection.
      expect(result.fold((_) => null, (f) => f.kind), FailureKind.forbidden);
      expect(result.fold((_) => null, (f) => f.correlationId), 'srv-1');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/audit/audit_emitter_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/audit/audit_emitter.dart'`.

- [ ] **Step 3: Extend the audit model and interface**

Replace `lib/core/audit/audit.dart` entirely:

```dart
import '../result/result.dart';
import '../trace/trace_id.dart';

/// Client-side audit event emission (Guideline §12, PRD FR-015). The server is
/// the authoritative audit store; the client emits structured events with a
/// correlation ID so a user action can be traced end-to-end. Sensitive views
/// (photo open, NID reveal) MUST emit an event before the value is shown - see
/// [AuditSink.revealAudited], which enforces that structurally.
enum AuditAction {
  campaignCreated,
  campaignSubmitted,
  campaignApproved,
  campaignReturned,
  campaignRejected,
  participantRegistered,
  bulkImportCommitted,
  attendanceCaptured,
  verificationDecided,
  sensitiveMediaViewed,
  nidRevealed,
  configChanged,
  exportPerformed,

  /// The evidence-encryption key could not be read and a new one was generated.
  /// Every piece of evidence encrypted under the previous key is now
  /// undecryptable, so this must never look like a normal first run.
  evidenceKeyRotated,
}

class AuditEvent {
  const AuditEvent({
    required this.action,
    required this.entity,
    required this.entityId,
    required this.correlationId,
    required this.actorId,
    this.remarks,
  });

  final AuditAction action;
  final String entity;
  final String entityId;
  final TraceId correlationId;

  /// Who performed the action, captured at emit time. Never inferred at flush
  /// time: field devices are shared, so an event captured offline by one user
  /// can flush after a different user has logged in.
  final String actorId;

  final String? remarks;
}

/// Emits [AuditEvent]s. The concrete implementation buffers durably and posts
/// to the audit endpoint; failures are retried and never block the user
/// workflow - with one deliberate exception, [revealAudited].
abstract interface class AuditSink {
  /// Records [event] durably and returns. Transport happens later, so an audit
  /// outage never blocks a user action.
  Future<void> emit(AuditEvent event);

  /// Records [event], waits for the server to acknowledge it, and only then
  /// invokes [reveal].
  ///
  /// The reveal is passed in rather than performed by the caller after checking
  /// a returned `Result`, because a `Result` the caller must remember to check
  /// fails OPEN the first time someone forgets - and "someone forgot" is the
  /// normal failure mode for a compliance control. Structuring it this way makes
  /// showing the value without a recorded access impossible.
  ///
  /// Returns `Err` without invoking [reveal] if the event cannot be recorded.
  Future<Result<T>> revealAudited<T>(
    AuditEvent event,
    Future<T> Function() reveal,
  );
}
```

- [ ] **Step 4: Write the transport seam**

Create `lib/core/audit/audit_transport.dart`:

```dart
import 'package:dio/dio.dart';

import '../network/dio_client.dart';
import '../result/result.dart';
import 'audit.dart';

/// One audit event in wire shape.
///
/// [action] is a plain String, not an [AuditAction], on purpose. The flusher
/// reads rows written by whatever build was installed at the time, and Android
/// permits downgrades - so a row can legitimately carry an action this build
/// has no enum value for. Mapping it back through the enum would force a
/// choice between throwing mid-flush and substituting some *other* real
/// action, and silently relabelling a compliance record is falsification, not
/// degradation. The persisted string ships verbatim instead.
class AuditEventPayload {
  const AuditEventPayload({
    required this.action,
    required this.entity,
    required this.entityId,
    required this.correlationId,
    required this.actorId,
    this.remarks,
  });

  /// From an in-memory event, where the action is known and typed.
  factory AuditEventPayload.fromEvent(AuditEvent event) => AuditEventPayload(
    action: event.action.name,
    entity: event.entity,
    entityId: event.entityId,
    correlationId: event.correlationId.value,
    actorId: event.actorId,
    remarks: event.remarks,
  );

  final String action;
  final String entity;
  final String entityId;
  final String correlationId;
  final String actorId;
  final String? remarks;

  Map<String, Object?> toJson() => {
    'action': action,
    'entity': entity,
    'entityId': entityId,
    'correlationId': correlationId,
    'actorId': actorId,
    if (remarks != null) 'remarks': remarks,
  };
}

/// Transport seam for shipping audit events to the server.
///
/// 🔒 The audit contract (endpoint, payload shape, batch semantics) is an
/// unresolved external dependency. Keeping it behind one method means the
/// table, the flusher, the poison-pill rule and the [AuditSink.revealAudited]
/// contract are all transport-agnostic when it lands.
///
/// Returns a [Result] rather than throwing so `audit_emitter.dart` needs no
/// network import: error mapping belongs here.
abstract interface class AuditTransport {
  Future<Result<void>> send(List<AuditEventPayload> events);
}

/// Dio-backed transport. The endpoint and payload shape are placeholders
/// pending the 🔒 audit contract, exactly as the campaign endpoints are.
class DioAuditTransport implements AuditTransport {
  DioAuditTransport(this._dio);

  final Dio _dio;

  @override
  Future<Result<void>> send(List<AuditEventPayload> events) async {
    try {
      await _dio.post<void>(
        '/audit/events',
        data: {'events': [for (final e in events) e.toJson()]},
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
}
```

- [ ] **Step 5: Write the sink**

Create `lib/core/audit/audit_emitter.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../result/result.dart';
import '../storage/app_database.dart';
import '../trace/trace_id.dart';
import 'audit.dart';
import 'audit_transport.dart';

const Uuid _uuid = Uuid();

DateTime _systemNow() => DateTime.now().toUtc();
String _uuidV4() => _uuid.v4();

/// Drift-backed [AuditSink]. Events are committed locally first and shipped by
/// `AuditFlusher`, so they survive process death on the way to the server.
class DurableAuditSink implements AuditSink {
  DurableAuditSink({
    required AppDatabase db,
    required AuditTransport transport,
    DateTime Function() now = _systemNow,
    String Function() newId = _uuidV4,
    this.onBuffered,
  }) : _db = db,
       _transport = transport,
       _now = now,
       _newId = newId;

  final AppDatabase _db;
  final AuditTransport _transport;
  final DateTime Function() _now;
  final String Function() _newId;

  /// Called after each durable write so a full batch can flush early rather
  /// than waiting for the periodic timer.
  final void Function()? onBuffered;

  @override
  Future<void> emit(AuditEvent event) async {
    try {
      await _insert(event, _newId());
    } catch (error) {
      // An audit outage must not block a campaign approval or a capture. This
      // is the one place a lost event is tolerated, and only because the
      // alternative is blocking the user's work on a local DB fault.
      debugPrint('Audit event could not be buffered ($error): ${event.action}');
      return;
    }
    onBuffered?.call();
  }

  @override
  Future<Result<T>> revealAudited<T>(
    AuditEvent event,
    Future<T> Function() reveal,
  ) async {
    final id = _newId();

    // Write first: a crash mid-post must still leave evidence that access was
    // attempted.
    try {
      await _insert(event, id);
    } catch (error) {
      return Err(
        Failure(
          FailureKind.unknown,
          message: 'Audit event could not be recorded locally: $error',
          correlationId: event.correlationId.value,
        ),
      );
    }

    final sent = await _transport.send([AuditEventPayload.fromEvent(event)]);
    if (sent case Err(:final failure)) {
      // Fail closed. The row stays pending so the flusher still delivers the
      // attempt, but the value is not shown.
      return Err(failure);
    }

    await (_db.delete(_db.auditEvents)..where((t) => t.id.equals(id))).go();
    return Ok(await reveal());
  }

  Future<void> _insert(AuditEvent event, String id) =>
      _db.into(_db.auditEvents).insert(
        AuditEventsCompanion.insert(
          id: id,
          action: event.action.name,
          entity: event.entity,
          entityId: event.entityId,
          correlationId: event.correlationId.value,
          actorId: event.actorId,
          remarks: Value(event.remarks),
          occurredAt: _now(),
        ),
      );
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/core/audit/audit_emitter_test.dart`

Expected: PASS, 9 tests. If `AuditEventsCompanion.insert` rejects a named argument, open `lib/core/storage/app_database.g.dart` and match the generated companion's parameter names — generated code is the source of truth.

- [ ] **Step 7: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: format clean, analyze exits 0, all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/core/audit/ test/core/audit/
git commit -m "feat: add a durable audit sink with an ack-gated reveal

revealAudited takes the reveal as a callback rather than returning a
Result the caller must check, because a Result fails open the first time
someone forgets to check it. The row is written before the transport is
called, so a crash mid-post still leaves evidence access was attempted,
and a failed ack leaves the row buffered while blocking the reveal."
```

---

## Task 8: `AuditFlusher`, `EvidenceKeyStore`, and the mock-server endpoint

Completes T-0.3.6 and T-0.3.4.

**Files:**
- Modify: `lib/core/audit/audit_emitter.dart` (add `AuditFlusher`)
- Create: `lib/core/storage/evidence_key_store.dart`
- Create: `test/support/recording_audit_sink.dart`
- Create: `test/core/audit/audit_flusher_test.dart`
- Rewrite: `test/app/evidence_key_test.dart` → `test/core/storage/evidence_key_store_test.dart`
- Modify: `tool/mock_server/bin/server.dart`

**Interfaces:**
- Consumes: `DurableAuditSink`, `AuditTransport`, `AuditEvent`, `AuditAction` from Task 7; `AppDatabase` from Task 6; `SecureStore`, `SecureStoreKeys` from Task 5; `BackoffPolicy` from `lib/core/sync/backoff.dart`.
- Produces:
  - `class AuditFlusher` — `AuditFlusher({required AppDatabase db, required AuditTransport transport, Stream<bool>? connectivity, BackoffPolicy policy = auditFlushPolicy, Duration interval = const Duration(seconds: 30), int batchSize = 20, int maxAttempts = 10, int highWaterMark = 20000})`, with `void start()`, `Future<void> flush()`, `void notifyBuffered()`, `Future<void> dispose()`.
  - `const BackoffPolicy auditFlushPolicy`.
  - `class EvidenceKeyStore` — `EvidenceKeyStore({required SecureStore store, required AuditSink audit})`, with `Future<List<int>> loadOrCreate()`.
  - `class RecordingAuditSink implements AuditSink` — `List<AuditEvent> events`.

- [ ] **Step 1: Write the failing tests**

Create `test/support/recording_audit_sink.dart`:

```dart
import 'package:acsl_campaign/core/audit/audit.dart';
import 'package:acsl_campaign/core/result/result.dart';

/// [AuditSink] that only records, for tests asserting *that* something was
/// audited rather than how it was transported.
class RecordingAuditSink implements AuditSink {
  final List<AuditEvent> events = [];

  @override
  Future<void> emit(AuditEvent event) async => events.add(event);

  @override
  Future<Result<T>> revealAudited<T>(
    AuditEvent event,
    Future<T> Function() reveal,
  ) async {
    events.add(event);
    return Ok(await reveal());
  }
}
```

Create `test/core/audit/audit_flusher_test.dart`:

```dart
import 'package:acsl_campaign/core/audit/audit.dart';
import 'package:acsl_campaign/core/audit/audit_emitter.dart';
import 'package:acsl_campaign/core/audit/audit_transport.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedTransport implements AuditTransport {
  _ScriptedTransport(this._results);

  final List<Result<void>> _results;
  final List<List<AuditEventPayload>> batches = [];

  @override
  Future<Result<void>> send(List<AuditEventPayload> events) async {
    batches.add(events);
    return _results[(batches.length - 1).clamp(0, _results.length - 1)];
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed(String id, {int attempts = 0}) =>
      db.into(db.auditEvents).insert(
        AuditEventsCompanion.insert(
          id: id,
          action: AuditAction.campaignApproved.name,
          entity: 'campaign',
          entityId: id,
          correlationId: 'trace-$id',
          actorId: 'user-1',
          occurredAt: DateTime.utc(2026, 8, 6, 12),
          attempts: Value(attempts),
        ),
      );

  AuditFlusher buildFlusher(
    AuditTransport transport, {
    int batchSize = 20,
    int maxAttempts = 10,
  }) => AuditFlusher(
    db: db,
    transport: transport,
    batchSize: batchSize,
    maxAttempts: maxAttempts,
  );

  test('deletes rows the server confirmed', () async {
    await seed('a');
    await seed('b');
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport).flush();

    expect(transport.batches.single, hasLength(2));
    expect(await db.select(db.auditEvents).get(), isEmpty);
  });

  test('keeps rows and records the error when the send fails', () async {
    await seed('a');
    final transport = _ScriptedTransport([
      const Err(Failure(FailureKind.network, message: 'offline')),
    ]);

    await buildFlusher(transport).flush();

    final rows = await db.select(db.auditEvents).get();
    expect(rows, hasLength(1));
    expect(rows.single.attempts, 1);
    expect(rows.single.lastError, contains('offline'));
  });

  test('never discards an event, however many attempts have failed', () async {
    // The sync engine gives up after maxRetries and tells the user. Audit must
    // not: a discarded compliance record is silent data loss.
    await seed('a', attempts: 99);
    final transport = _ScriptedTransport([
      const Err(Failure(FailureKind.server)),
    ]);

    await buildFlusher(transport).flush();

    expect(await db.select(db.auditEvents).get(), hasLength(1));
  });

  test('sends in FIFO order', () async {
    await seed('first');
    await seed('second');
    await seed('third');
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport).flush();

    expect(
      transport.batches.single.map((e) => e.entityId),
      ['first', 'second', 'third'],
    );
  });

  test('respects the batch size', () async {
    await seed('a');
    await seed('b');
    await seed('c');
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport, batchSize: 2).flush();

    expect(transport.batches.single, hasLength(2));
    expect(await db.select(db.auditEvents).get(), hasLength(1));
  });

  test('skips a poison pill so it cannot block later events', () async {
    // A permanently rejected row must not stall the queue head forever. It is
    // skipped, NOT deleted - one bad event degrades one record, not the trail.
    await seed('poison', attempts: 10);
    await seed('healthy');
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport, maxAttempts: 10).flush();

    expect(transport.batches.single.map((e) => e.entityId), ['healthy']);
    final remaining = await db.select(db.auditEvents).get();
    expect(remaining, hasLength(1));
    expect(remaining.single.entityId, 'poison');
  });

  test('does nothing when there is nothing pending', () async {
    final transport = _ScriptedTransport([const Ok(null)]);

    await buildFlusher(transport).flush();

    expect(transport.batches, isEmpty);
  });

  test('flushes early once a full batch has buffered', () async {
    final transport = _ScriptedTransport([const Ok(null)]);
    final flusher = buildFlusher(transport, batchSize: 2);

    await seed('a');
    flusher.notifyBuffered();
    await seed('b');
    flusher.notifyBuffered();
    // Let the flush scheduled by the second notification settle.
    await Future<void>.delayed(Duration.zero);
    await flusher.dispose();

    expect(transport.batches, isNotEmpty);
  });

  test('a concurrent flush does not double-send the same rows', () async {
    await seed('a');
    final transport = _ScriptedTransport([const Ok(null)]);
    final flusher = buildFlusher(transport);

    await Future.wait([flusher.flush(), flusher.flush()]);

    expect(transport.batches, hasLength(1));
  });
}
```

Create `test/core/storage/evidence_key_store_test.dart` (this replaces `test/app/evidence_key_test.dart`):

```dart
import 'dart:convert';

import 'package:acsl_campaign/core/audit/audit.dart';
import 'package:acsl_campaign/core/storage/evidence_key_store.dart';
import 'package:acsl_campaign/core/storage/secure_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_secure_store.dart';
import '../../support/recording_audit_sink.dart';

void main() {
  group('EvidenceKeyStore', () {
    test('reuses an existing key instead of replacing it', () async {
      // A key already in secure storage must come back byte-identical. If this
      // ever regresses, every piece of evidence encrypted under the stored key
      // becomes undecryptable.
      final stored = List<int>.generate(32, (i) => i);
      final store = InMemorySecureStore({
        SecureStoreKeys.evidenceAesKeyV1: base64Encode(stored),
      });
      final audit = RecordingAuditSink();

      final key = await EvidenceKeyStore(store: store, audit: audit)
          .loadOrCreate();

      expect(key, stored);
      expect(store.writeCount, 0);
      expect(audit.events, isEmpty);
    });

    test('generates and persists a key on first run', () async {
      // Nothing stored yet. The generated key must be 32 bytes and must be
      // written back, or every app start would mint a different key and no
      // evidence would survive a restart.
      final store = InMemorySecureStore();
      final audit = RecordingAuditSink();

      final key = await EvidenceKeyStore(store: store, audit: audit)
          .loadOrCreate();

      expect(key, hasLength(32));
      expect(
        base64Decode(store.values[SecureStoreKeys.evidenceAesKeyV1]!),
        key,
      );
      // A first run is not a rotation - nothing was lost, so nothing to audit.
      expect(audit.events, isEmpty);
    });

    test('regenerates and audits when the stored key cannot be read', () async {
      // v10 changed the at-rest cipher, so a key written by v9 may be
      // unreadable. Capture must keep working, so a fresh key is generated -
      // but every piece of evidence under the old key is now undecryptable, so
      // this must leave a durable trace rather than only a debugPrint.
      final store = ThrowingSecureStore(
        PlatformException(code: 'decrypt_failed'),
      );
      final audit = RecordingAuditSink();

      final key = await EvidenceKeyStore(store: store, audit: audit)
          .loadOrCreate();

      expect(key, hasLength(32));
      expect(
        base64Decode(store.values[SecureStoreKeys.evidenceAesKeyV1]!),
        key,
      );
      expect(audit.events, hasLength(1));
      expect(audit.events.single.action, AuditAction.evidenceKeyRotated);
      expect(audit.events.single.entity, 'evidenceKey');
    });

    test('does not let a storage failure escape and crash capture', () async {
      final store = ThrowingSecureStore(
        PlatformException(code: 'keystore_unavailable'),
      );

      await expectLater(
        EvidenceKeyStore(store: store, audit: RecordingAuditSink())
            .loadOrCreate(),
        completes,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/core/audit/audit_flusher_test.dart test/core/storage/evidence_key_store_test.dart`

Expected: FAIL at compile time — `AuditFlusher` and `evidence_key_store.dart` do not exist.

- [ ] **Step 3: Add `AuditFlusher`**

Append to `lib/core/audit/audit_emitter.dart`, and add `import 'dart:async';` at the top plus `import '../sync/backoff.dart';` with the other relative imports:

```dart
/// Retry schedule for the audit buffer.
///
/// `maxRetries` is unused - the flusher has no give-up path - so the effective
/// behaviour is exponential growth to a five-minute plateau, retried forever.
const BackoffPolicy auditFlushPolicy = BackoffPolicy(
  base: Duration(seconds: 2),
  maxDelay: Duration(minutes: 5),
);

/// Drains the durable audit buffer to the server.
///
/// Deliberately NOT built on [SyncEngine]: that discards a task after
/// `maxRetries: 8` and surfaces a user-visible failure, which for a compliance
/// record would be silent data loss. This shares the *policy* object, not the
/// queue.
class AuditFlusher {
  AuditFlusher({
    required AppDatabase db,
    required AuditTransport transport,
    Stream<bool>? connectivity,
    BackoffPolicy policy = auditFlushPolicy,
    Duration interval = const Duration(seconds: 30),
    int batchSize = 20,
    int maxAttempts = 10,
    int highWaterMark = 20000,
  }) : _db = db,
       _transport = transport,
       _connectivity = connectivity,
       _policy = policy,
       _interval = interval,
       _batchSize = batchSize,
       _maxAttempts = maxAttempts,
       _highWaterMark = highWaterMark;

  final AppDatabase _db;
  final AuditTransport _transport;
  final Stream<bool>? _connectivity;
  final BackoffPolicy _policy;
  final Duration _interval;
  final int _batchSize;

  /// Attempts after which a row is set aside. It is skipped, never deleted: a
  /// permanently rejected event would otherwise stall every later event, since
  /// the queue is strictly FIFO by `seq`.
  final int _maxAttempts;

  final int _highWaterMark;

  Timer? _timer;
  StreamSubscription<bool>? _connectivitySub;
  Future<void>? _inFlight;
  int _buffered = 0;
  bool _warnedHighWater = false;
  bool _disposed = false;

  void start() {
    _timer ??= Timer.periodic(_interval, (_) => unawaited(flush()));
    _connectivitySub ??= _connectivity?.listen((online) {
      if (online) unawaited(flush());
    });
  }

  /// Called by [DurableAuditSink] after each durable write. Flushes early once
  /// a full batch has accumulated rather than waiting for the timer.
  void notifyBuffered() {
    _buffered++;
    if (_buffered >= _batchSize) {
      _buffered = 0;
      unawaited(flush());
    }
  }

  /// Sends one batch. Concurrent calls share the in-flight future so two
  /// triggers cannot double-send the same rows.
  Future<void> flush() {
    if (_disposed) return Future<void>.value();
    return _inFlight ??= _flushOnce().whenComplete(() => _inFlight = null);
  }

  Future<void> _flushOnce() async {
    final rows =
        await (_db.select(_db.auditEvents)
              ..where((t) => t.attempts.isSmallerThanValue(_maxAttempts))
              ..orderBy([(t) => OrderingTerm(expression: t.seq)])
              ..limit(_batchSize))
            .get();
    if (rows.isEmpty) return;

    final result = await _transport.send(rows.map(_toPayload).toList());

    if (result case Err(:final failure)) {
      await _db.batch((b) {
        for (final row in rows) {
          b.update(
            _db.auditEvents,
            AuditEventsCompanion(
              attempts: Value(row.attempts + 1),
              lastError: Value(failure.message ?? failure.kind.name),
            ),
            where: (t) => t.seq.equals(row.seq),
          );
        }
      });
      await _checkHighWaterMark();
      return;
    }

    await _db.batch((b) {
      b.deleteWhere(
        _db.auditEvents,
        (t) => t.seq.isIn(rows.map((r) => r.seq).toList()),
      );
    });
  }

  /// Nothing is ever dropped, so an indefinitely offline device grows this
  /// table. Rows are ~200 bytes, so weeks offline costs single-digit MB; past
  /// the mark that stops being negligible and is worth a signal.
  Future<void> _checkHighWaterMark() async {
    if (_warnedHighWater) return;
    // selectOnly + a count expression rather than loading rows: at the mark
    // this table holds 20k rows and `select(...).get().length` would read them
    // all into memory just to size them.
    final total = _db.auditEvents.seq.count();
    final row = await (_db.selectOnly(_db.auditEvents)
          ..addColumns([total]))
        .getSingle();
    final count = row.read(total) ?? 0;
    if (count < _highWaterMark) return;
    _warnedHighWater = true;
    debugPrint(
      'Audit buffer holds $count events (>= $_highWaterMark) and cannot reach '
      'the server. Events are retained, not dropped.',
    );
  }

  /// The action string passes through verbatim - never round-tripped through
  /// [AuditAction]. A row written by a build with actions this one lacks (an
  /// Android downgrade) must reach the server labelled with what actually
  /// happened, not with whatever enum value happened to be the fallback.
  AuditEventPayload _toPayload(AuditEventRow row) => AuditEventPayload(
    action: row.action,
    entity: row.entity,
    entityId: row.entityId,
    correlationId: row.correlationId,
    actorId: row.actorId,
    remarks: row.remarks,
  );

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _inFlight;
  }
}
```

- [ ] **Step 4: Write `EvidenceKeyStore`**

Create `lib/core/storage/evidence_key_store.dart`:

```dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audit/audit.dart';
import '../trace/trace_id.dart';
import 'secure_store.dart';

/// Owns the 32-byte AES key used to encrypt attendance evidence.
///
/// Extracted from the composition root so its failure paths are testable: what
/// happens here decides whether queued evidence stays decryptable.
class EvidenceKeyStore {
  EvidenceKeyStore({required SecureStore store, required AuditSink audit})
    : _store = store,
      _audit = audit;

  final SecureStore _store;
  final AuditSink _audit;

  /// Loads the evidence key, generating and persisting one on first run.
  ///
  /// Never throws: a failure here must not crash the capture path.
  Future<List<int>> loadOrCreate() async {
    String? existing;
    var rotated = false;

    try {
      existing = await _store.read(SecureStoreKeys.evidenceAesKeyV1);
    } catch (error) {
      // A key exists but cannot be decrypted - after the v10 cipher change, an
      // OS keystore reset, or a restore onto a different device. Regenerating
      // keeps capture working, but every piece of evidence encrypted under the
      // previous key becomes undecryptable, so this must never look like a
      // normal first run.
      rotated = true;
      debugPrint(
        'Evidence key could not be read ($error). Generating a new one; '
        'evidence encrypted under the previous key can no longer be decrypted.',
      );
    }

    if (existing != null) return base64Decode(existing);

    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    try {
      await _store.write(
        SecureStoreKeys.evidenceAesKeyV1,
        base64Encode(bytes),
      );
    } catch (error) {
      // Capture can proceed with an in-memory key, but nothing encrypted under
      // it will survive a restart.
      debugPrint('Evidence key could not be persisted ($error).');
    }

    if (rotated) {
      // Durable trace, not just a debugPrint: this is the event an
      // investigation into undecryptable evidence would look for.
      await _audit.emit(
        AuditEvent(
          action: AuditAction.evidenceKeyRotated,
          entity: 'evidenceKey',
          entityId: SecureStoreKeys.evidenceAesKeyV1,
          correlationId: TraceId.generate(),
          // No session is guaranteed at capture-setup time, and the rotation is
          // a device event rather than a user action.
          actorId: 'system',
        ),
      );
    }

    return bytes;
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/core/audit/audit_flusher_test.dart test/core/storage/evidence_key_store_test.dart`

Expected: PASS, 9 flusher tests + 4 evidence-key tests.

- [ ] **Step 6: Delete the superseded test**

```bash
git rm test/app/evidence_key_test.dart
```

Its three cases are all carried over into `test/core/storage/evidence_key_store_test.dart`, which additionally asserts the rotation audit. Nothing is lost.

- [ ] **Step 7: Add the mock-server endpoint**

In `tool/mock_server/bin/server.dart`, add after the verification routes block (following `r.post('/verification/cases/<id>/decision', ...)`):

```dart
  // ---- Audit (🔒 contract-pending shape) ----------------------------------
  // Real so dev and E2E flush successfully; a throwing stub would fail every
  // flush and grow the local buffer for no reason.
  r.post('/audit/events', (Request req) async {
    final body = await _body(req);
    final events = body['events'];
    return _json({'accepted': events is List ? events.length : 0});
  });
```

- [ ] **Step 8: Confirm the mock server still compiles**

Run: `cd tool/mock_server && dart pub get && dart analyze && cd ../..`

Expected: analyze reports no issues. (`tool/**` is excluded from the app's own analysis_options, so it must be checked separately.)

- [ ] **Step 9: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: format clean, analyze exits 0, all tests pass.

- [ ] **Step 10: Commit**

```bash
git add lib/core/audit/ lib/core/storage/evidence_key_store.dart test/ tool/mock_server/bin/server.dart
git commit -m "feat: drain the audit buffer and audit evidence-key rotation

The flusher never discards an event - unlike the sync engine, which gives
up after maxRetries and tells the user - but does set a row aside after
ten attempts so a permanently rejected event cannot stall the strictly
FIFO queue behind it. EvidenceKeyStore moves the key lifecycle out of the
composition root and finally emits on the unreadable-key path, which
previously left no durable trace despite making all prior evidence
undecryptable."
```

---

## Task 9: Wire everything and thread the trace through six actions

Completes the epic. `providers.dart` sheds the two things that moved out, the flusher starts at boot, and the six audit-bearing repository methods accept a per-action `TraceId`.

**Files:**
- Modify: `lib/app/di/providers.dart`
- Modify: `lib/main.dart`
- Modify: `lib/domain/campaign/campaign_repository.dart`, `lib/data/campaign/campaign_repository_impl.dart`
- Modify: `lib/domain/registration/registration_repository.dart`, `lib/data/registration/registration_repository_impl.dart`
- Modify: `lib/domain/import/import_repository.dart`, `lib/data/import/import_repository_impl.dart`
- Modify: `lib/domain/verification/verification_repository.dart`, `lib/data/verification/verification_repository_impl.dart`
- Modify: `lib/features/campaign_wizard/application/wizard_controller.dart`, `lib/features/campaign_approval/application/approval_controller.dart`, `lib/features/crm_case/application/crm_case_controller.dart`, `lib/features/registration/application/registration_controller.dart`, `lib/features/bulk_import/application/import_controller.dart`
- Create: `test/core/network/trace_threading_test.dart`

**Interfaces:**
- Consumes: everything produced by Tasks 2-8.
- Produces: `secureStoreProvider`, `evidenceKeyStoreProvider`, `auditTransportProvider`, `auditSinkProvider`, `auditFlusherProvider` in `lib/app/di/providers.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/core/network/trace_threading_test.dart`:

```dart
import 'package:acsl_campaign/core/network/correlation_interceptor.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:acsl_campaign/data/campaign/campaign_repository_impl.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  late ScriptedAdapter adapter;
  late CampaignRepositoryImpl repo;

  setUp(() {
    adapter = ScriptedAdapter([const ScriptedReply.status(200)]);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(const CorrelationIdInterceptor());
    repo = CampaignRepositoryImpl(dio);
  });

  String? sentCorrelationId() {
    final value =
        adapter.requests.single.headers[CorrelationIdInterceptor.headerName];
    return value is String ? value : null;
  }

  test('submitForApproval forwards the caller trace id', () async {
    await repo.submitForApproval('CMP-1', trace: const TraceId.of('action-1'));

    expect(sentCorrelationId(), 'action-1');
  });

  test('decide forwards the caller trace id', () async {
    await repo.decide(
      'CMP-1',
      decision: CampaignDecision.approve,
      trace: const TraceId.of('action-2'),
    );

    expect(sentCorrelationId(), 'action-2');
  });

  test('a call with no trace still gets a minted id', () async {
    // Unscoped traffic must never be untraceable.
    await repo.getById('CMP-1');

    expect(sentCorrelationId(), isNotNull);
    expect(sentCorrelationId(), isNotEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/network/trace_threading_test.dart`

Expected: FAIL to compile — `No named parameter with the name 'trace'`.

- [ ] **Step 3: Thread `trace` through the six methods**

Exactly six methods gain an optional trailing `{TraceId? trace}` — the ones that pair one-to-one with an existing `AuditAction`:

| Interface + impl | Method | `AuditAction` |
|---|---|---|
| `CampaignRepository` | `createDraft` | `campaignCreated` |
| `CampaignRepository` | `submitForApproval` | `campaignSubmitted` |
| `CampaignRepository` | `decide` | `campaignApproved`/`Returned`/`Rejected` |
| `RegistrationRepository` | `register` | `participantRegistered` |
| `ImportRepository` | `commit` | `bulkImportCommitted` |
| `VerificationRepository` | `decide` | `verificationDecided` |

Do **not** thread `updateDraft`, `requestNewProfile`, `uploadDryRun`, or session `start`/`close`/`pause`. No `AuditAction` exists for them, so an action-scoped id with no audit row to join to buys nothing; they keep the interceptor's per-request id.

In each **interface**, add the parameter and import `TraceId`. For example in `lib/domain/campaign/campaign_repository.dart`:

```dart
import '../../core/trace/trace_id.dart';
```

```dart
  /// Creates a new Draft campaign from wizard input. Returns the persisted
  /// campaign (with server id + Draft status).
  ///
  /// [trace] is the per-action correlation id; pass the same one to the audit
  /// event for this action so the two can be joined (Architecture §12).
  Future<Result<Campaign>> createDraft(CampaignDraft draft, {TraceId? trace});

  Future<Result<Campaign>> submitForApproval(String id, {TraceId? trace});

  /// Approve/return/reject. [reason] is mandatory for return/reject (§8.4).
  Future<Result<Campaign>> decide(
    String id, {
    required CampaignDecision decision,
    String? reason,
    TraceId? trace,
  });
```

In each **impl**, add a shared private helper and pass it as `options`. In `lib/data/campaign/campaign_repository_impl.dart` add the imports:

```dart
import '../../core/network/trace_options.dart';
import '../../core/trace/trace_id.dart';
```

and the helper plus updated calls:

```dart
  /// `null` lets CorrelationIdInterceptor mint a per-request id.
  Options? _options(TraceId? trace) =>
      trace == null ? null : traceOptions(trace);

  @override
  Future<Result<Campaign>> createDraft(
    CampaignDraft draft, {
    TraceId? trace,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/campaigns',
        data: _draftToJson(draft),
        options: _options(trace),
      );
      return Ok(CampaignDto.fromJson(res.data!).toDomain());
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
```

Apply the same shape to `submitForApproval` and `decide` in this file, and to `RegistrationRepositoryImpl.register`, `ImportRepositoryImpl.commit`, and `VerificationRepositoryImpl.decide`. Each of those four files needs the same two imports and the same `_options` helper.

No idempotency key is introduced for any of these. Without one they are not retried, which is the intended conservative default (spec D7); adding keys is the feature tasks' work alongside the server contract.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/network/trace_threading_test.dart`

Expected: PASS, 3 tests.

- [ ] **Step 5: Mint a trace at each of the seven call sites**

Each controller mints one `TraceId` per user action. Add `import '../../../core/trace/trace_id.dart';` to each file (adjust depth to the file's location) and pass it:

| File:line | Change |
|---|---|
| `lib/features/campaign_wizard/application/wizard_controller.dart:103` | `await repo.createDraft(state.draft, trace: TraceId.generate())` |
| `lib/features/campaign_wizard/application/wizard_controller.dart:121` and `:126` | Mint **one** `final trace = TraceId.generate();` before line 121 and pass it to **both** `createDraft` and `submitForApproval` — save-then-submit is a single user action and must share one id |
| `lib/features/campaign_approval/application/approval_controller.dart:42` | add `trace: TraceId.generate()` to the `.decide(...)` call |
| `lib/features/crm_case/application/crm_case_controller.dart:35` | add `trace: TraceId.generate()` to the `repo.decide(...)` call |
| `lib/features/registration/application/registration_controller.dart:73` | add `trace: TraceId.generate()` to the `.register(...)` call |
| `lib/features/bulk_import/application/import_controller.dart:40` | `.commit(job.id, trace: TraceId.generate())` |

The two presentation-layer `.decide(` calls (`campaign_approval_screen.dart:140`, `crm_case_screen.dart:252`) call their *controller*, not a repository. Leave them unchanged.

- [ ] **Step 6: Rewire the composition root**

In `lib/app/di/providers.dart`:

1. Delete `loadOrCreateEvidenceKey` (lines 111-131), the `_evidenceKeyName` constant (line 104) and its doc comment, and the `dart:convert`/`dart:math`/`flutter/services.dart` imports if nothing else uses them.
2. Replace `secureStoreProvider`'s raw `FlutterSecureStorage` with the wrapper and add the new providers:

```dart
final secureStoreProvider = Provider<SecureStore>((ref) => FlutterSecureStore());

final auditTransportProvider = Provider<AuditTransport>(
  (ref) => DioAuditTransport(ref.watch(dioProvider)),
);

/// Started eagerly from `main()` — see [AuditFlusher.start]. Lazily creating it
/// on a feature's first read (as the sync engine is) would mean audit only
/// flushed once someone opened the offline-queue screen.
final auditFlusherProvider = Provider<AuditFlusher>((ref) {
  final flusher = AuditFlusher(
    db: ref.watch(appDatabaseProvider),
    transport: ref.watch(auditTransportProvider),
    connectivity: ref.watch(connectivityStreamProvider),
  );
  ref.onDispose(() => unawaited(flusher.dispose()));
  return flusher;
});

final auditSinkProvider = Provider<AuditSink>((ref) {
  final flusher = ref.watch(auditFlusherProvider);
  return DurableAuditSink(
    db: ref.watch(appDatabaseProvider),
    transport: ref.watch(auditTransportProvider),
    onBuffered: flusher.notifyBuffered,
  );
});

final evidenceKeyStoreProvider = Provider<EvidenceKeyStore>(
  (ref) => EvidenceKeyStore(
    store: ref.watch(secureStoreProvider),
    audit: ref.watch(auditSinkProvider),
  ),
);
```

3. Point `mediaEncryptorProvider` at the new store:

```dart
/// 32-byte AES key for evidence encryption, generated once and held in secure
/// storage (Keystore/Keychain-backed on mobile). Never logged or exported.
final mediaEncryptorProvider = Provider<MediaEncryptor>((ref) {
  final keys = ref.watch(evidenceKeyStoreProvider);
  return AesGcmEncryptor(keys.loadOrCreate);
});
```

4. Add `import 'dart:async';` for `unawaited`, plus imports for `audit.dart`, `audit_emitter.dart`, `audit_transport.dart`, `evidence_key_store.dart` and `secure_store.dart`. Remove the now-unused `flutter_secure_storage` import.

- [ ] **Step 7: Start the flusher at boot**

In `lib/main.dart`, after the E2E seeding block and before `runApp`:

```dart
  // Audit must flush regardless of which screen the user visits, so the flusher
  // is started here rather than lazily on a feature's first read.
  container.read(auditFlusherProvider).start();
```

- [ ] **Step 8: Verify the whole epic**

Run each and confirm before moving on:

```bash
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter build web
flutter build apk --flavor dev
```

Expected: format clean; analyze exits 0; every test passes (33 baseline + 47 new); both builds succeed.

- [ ] **Step 9: Confirm the moved code left no stragglers**

Run: `grep -rn "loadOrCreateEvidenceKey\|_evidenceKeyName\|FlutterSecureStorage" lib test | grep -v "secure_store.dart"`

Expected: no output. `FlutterSecureStorage` must now appear only inside `lib/core/storage/secure_store.dart`.

- [ ] **Step 10: Commit**

```bash
git add lib/ test/
git commit -m "feat: wire the P0.3 core services and thread per-action traces

The six repository methods that pair with an existing AuditAction now
accept an optional TraceId, so the audit row and the API calls it caused
share one id; everything else keeps the interceptor's per-request id. The
audit flusher starts from main() rather than lazily, because audit must
flush regardless of which screen the user opens. Closes T-0.3.2, T-0.3.3,
T-0.3.4 and T-0.3.6."
```

- [ ] **Step 11: Update the epic status in `TASK_BREAKDOWN.md`**

Replace the Epic P0.3 table (lines 60-68) status column so each row reflects reality, and add a closing note beneath it in the style of the P0.2 note:

```markdown
> **P0.3 complete** (2026-08-06). T-0.3.2 ships correlation-ID and retry
> interceptors; the retry gate is an explicit idempotency key rather than HTTP
> method semantics, so no unsafe method is replayed without server-side dedupe.
> T-0.3.6's buffer is Drift schema v2 (`audit_events`) drained by a dedicated
> `AuditFlusher` — deliberately not the `SyncEngine`, whose give-up-after-8
> rule would silently discard compliance records. Sensitive views go through
> `AuditSink.revealAudited`, which takes the reveal as a callback so it cannot
> fail open. Feature-level audit emission stays with the owning tasks
> (T-1.4.2, T-1.6.3, T-3.1.4); this epic emits only `evidenceKeyRotated`.
> `AuthInterceptor.refreshToken` remains a throwing seam pending T-0.4.1.
```

- [ ] **Step 12: Commit the status update**

```bash
git add TASK_BREAKDOWN.md
git commit -m "docs: close Epic P0.3 in the task breakdown"
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task:

| Spec section | Task |
|---|---|
| §3.1 `TraceId` | 2 |
| §3.2 correlation interceptor + `mapDioError` fallback | 2 |
| §3.3 retry interceptor + drop `retry` | 3 |
| §3.4 schema v2 + migration + `drift_schemas/` | 1, 6 |
| §3.5 `SecureStore`, `SecureStoreKeys`, `EvidenceKeyStore` | 5, 8 |
| §3.6 `audit_emitter`, `audit_transport`, `revealAudited` | 7, 8 |
| §3.7 `AuthInterceptor` 401 fix | 4 |
| §3.8 mock-server `POST /audit/events` | 8 |
| §3.9 `providers.dart` wiring | 9 |
| §4.1 interceptor order, trace lifecycle, six methods | 2, 3, 9 |
| §4.2 retry rules table | 3 |
| §4.3 table shape, `seq`, `actorId`, migration sequencing | 6 |
| §4.4 web-storage constraint, key registry, acyclic deps | 5, 8 |
| §4.5 flush triggers, no-discard, poison pill, 🔒 seam, eager start | 8, 9 |
| §5 error handling (`emit` swallows, `revealAudited` fails closed) | 7 |
| §6 all seven test files | 2-9 |
| §7 sequence (v1 dump first) | 1, and Task 6 Step 1 re-checks it |
| §8 risks | mitigations embedded (Task 6 Step 8 covers generated-name drift) |
| §9 out of scope | nothing in this plan touches them |

**Type consistency verified across tasks.** `TraceId.of`/`.generate`/`.value` (2→3, 7, 8, 9); `traceIdExtraKey`/`idempotencyKeyExtraKey` (2→3); `CorrelationIdInterceptor.headerName`/`.idempotencyHeaderName` (2→3, 4, 9); `ScriptedAdapter(replies)`/`.requests`/`.callCount` and `ScriptedReply.status`/`.failure` (2→3, 4, 9); `BackoffPolicy.delayFor(int, {double jitterSeed})`/`.shouldGiveUp(int)`/`jitterSeedFor(String)` (existing→3, 8); `AuditEvent(action/entity/entityId/correlationId/actorId/remarks)` (7→8); `AuditEventPayload.fromEvent`/`.toJson` and `AuditTransport.send(List<AuditEventPayload>) → Future<Result<void>>` (7→8, 9); `AuditFlusher.notifyBuffered`/`.start`/`.flush`/`.dispose` (8→9); `SecureStore.read/write/delete` and `SecureStoreKeys.evidenceAesKeyV1` (5→8, 9); `EvidenceKeyStore.loadOrCreate` (8→9); `AuditEventRow` vs the domain `AuditEvent` disambiguated by `@DataClassName` in Task 6 and consumed under that name in Task 8's `_toPayload`.

**Pre-flight amendment (2026-08-06).** `AuditEventPayload` was introduced before execution began, replacing a `_toEvent` that mapped an unrecognised action string to `AuditAction.configChanged`. Substituting one real action for another falsifies a compliance record, and Android app downgrades make the case reachable. The action string now ships verbatim.

**Two places where generated code, not this plan, is authoritative** — each has an explicit reconciliation step rather than an assumption: drift's v1 test-helper class names (Task 6 Step 8) and `AuditEventsCompanion.insert`'s parameter names (Task 7 Step 6).
