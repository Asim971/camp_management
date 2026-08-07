# Epic P0.4 Auth, RBAC & Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a real sign-in / refresh / sign-out lifecycle, enforce RBAC at both the route and the widget level, and make the app shell actually navigable — closing T-0.4.1 through T-0.4.4.

**Architecture:** `AuthService` is a thin 🔒 transport seam. `SessionManager` sits above it and solely owns the session: a sealed `AuthState` tri-state, single-flight refresh, and a platform-split token store (mobile persists, web does not). A single typed `routeTable` is read by both the router and the guard, keyed on the route *template* so matching is exact. `AppShell` composes the existing responsive layout with permission-filtered destinations.

**Tech Stack:** Flutter (web + Android), Dart 3 with `strict-casts`/`strict-raw-types`, `go_router` 14.8.1, Riverpod, Dio 5.11, `flutter_secure_storage` 10.3.1, `mocktail`, `shelf`/`shelf_router` for the mock server.

**Spec:** [`docs/superpowers/specs/2026-08-07-epic-p0-4-auth-rbac-routing-design.md`](../specs/2026-08-07-epic-p0-4-auth-rbac-routing-design.md)

## Global Constraints

- **Repo:** `D:\Camp_man`, branch `feat/campaign-management-flutter-scaffold`. `main` now holds the merged codebase. Commit after every task.
- **Lints are strict and CI-enforced.** `analysis_options.yaml` sets `strict-casts: true`, `strict-raw-types: true`, and enables `always_declare_return_types`, `avoid_dynamic_calls`, `avoid_print`, `directives_ordering`, `prefer_const_constructors`, `prefer_final_locals`, `require_trailing_commas`, `sort_child_properties_last`, `unawaited_futures`, `use_super_parameters`. `prefer_initializing_formals` is inherited from `flutter_lints` and **does** fire — prefer `this._field` constructor params over `: _field = field` bodies. Use `debugPrint`, never `print` (in `lib/` and `test/`; `tool/**` is excluded from analysis).
- **`directives_ordering`:** `dart:` then `package:` then relative, each group alphabetical.
- **Verification gates (every task):** `dart format --set-exit-if-changed .`, `flutter analyze --fatal-infos` (exit 0), `flutter test`. The final task adds `flutter build web`.
- **Do NOT run `flutter build apk`.** It fails in this sandbox with SSL/PKIX errors reaching Flutter's Android artifacts, proven independent of any code change. CI's `gate` job runs it with a working trust store.
- **Test baseline:** **147 passing / 29 skipped** locally. The 29 skips are Linux-gated goldens (`test/golden/`) and must stay at 29 — they run and pass in CI, where the total is 176.
- **Never rename `SecureStoreKeys` values.** `evidenceAesKeyV1` is frozen; the new `refreshTokenV1` becomes equally frozen — a rename silently signs out every installed device.
- **🔒 contract-pending:** `/auth/login`, `/auth/refresh`, `/auth/logout` payload shapes are placeholders, flagged in-file exactly as `DioAuditTransport`'s are.
- **The access token is never persisted** on either platform (spec D3).
- **No new `AuditAction` values.** Sign-in/sign-out emit no client audit event (spec D8).

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `lib/core/auth/auth_service.dart` | `AuthTokens`, `AuthService` seam, `DioAuthService` (🔒), `FakeAuthService` |
| `lib/core/auth/token_store.dart` | `TokenStore` + `MobileTokenStore` / `WebTokenStore` platform split |
| `lib/core/auth/scope_claims.dart` | Server claim strings → `AppRole`/`Permission`; fails loudly on unknowns |
| `lib/core/auth/session_manager.dart` | `AuthState` tri-state, `SessionManager` lifecycle, single-flight refresh |
| `lib/core/auth/permission_gate.dart` | `PermissionGate.hidden` / `.disabled` |
| `lib/app/router/route_table.dart` | `Access` markers + the one `routeTable` registry |
| `lib/features/auth/presentation/login_screen.dart` | Replaces the `/login` placeholder |
| `lib/app/shell/nav_destinations.dart` | `NavDestinationSpec` + permission filtering |
| `lib/app/shell/app_shell.dart` | Session-aware shell: breadcrumb, notifications slot, account menu |
| `test/support/fake_auth.dart` | `ScriptedAuthService`, `FakeTokenStore`, session/scope fixtures |

**Modified:**

| Path | Change |
|---|---|
| `lib/core/auth/session.dart` | Add `refreshToken`; correct the false "tokens live in secure storage" comment |
| `lib/core/storage/secure_store.dart` | Add `SecureStoreKeys.refreshTokenV1` |
| `lib/core/network/auth_interceptor.dart` | Nothing structural — `refreshToken` callback now delegates |
| `lib/app/di/providers.dart` | Replace `AuthController`'s body; wire the five new providers |
| `lib/app/router/app_router.dart` | Build routes from `routeTable`; key redirect on `state.fullPath` |
| `lib/app/router/route_guards.dart` | Take `AuthState`; add restore/deep-link handling |
| `lib/core/responsive/adaptive_scaffold.dart` | Take `destinations` + `onSelect`; drop `selectedIndex` and the hardcoded list |
| `lib/main.dart` | `await SessionManager.restore()` before `runApp` |
| `tool/mock_server/bin/server.dart` | Add the three `/auth/*` endpoints |
| 8 `AdaptiveScaffold` callers | Migrate to `AppShell` (7 also drop `selectedIndex`) |
| `test/widget/crm_case_screen_test.dart`, `bulk_import_screen_test.dart` | Adapt to `AppShell` + auth override |
| `TASK_BREAKDOWN.md` | Close the epic |

**The 8 `AdaptiveScaffold` callers** (verified by grep — `adaptive_scaffold.dart` itself is a 9th grep hit and is not a caller):

1. `lib/core/design_system/placeholder_screen.dart` — **no** `selectedIndex`
2. `lib/features/bulk_import/presentation/bulk_import_screen.dart` — `selectedIndex: 1`
3. `lib/features/campaign_approval/presentation/campaign_approval_screen.dart` — `1`
4. `lib/features/campaign_detail/presentation/campaign_detail_screen.dart` — `1`
5. `lib/features/campaign_list/presentation/campaign_list_screen.dart` — `1`
6. `lib/features/campaign_wizard/presentation/campaign_wizard_screen.dart` — `1`
7. `lib/features/crm_case/presentation/crm_case_screen.dart` — `2`
8. `lib/features/registration/presentation/registration_workspace_screen.dart` — `1`

---

## Task 1: `AuthService` seam and `AuthTokens`

**Files:**
- Create: `lib/core/auth/auth_service.dart`
- Create: `test/support/fake_auth.dart`
- Test: `test/core/auth/auth_service_test.dart`

**Interfaces:**
- Consumes: `Result`/`Ok`/`Err`/`Failure`/`FailureKind` from `lib/core/result/result.dart` (`Failure` is const-constructible: `Failure(FailureKind kind, {String? message, String? code, String? correlationId})`); `mapDioError(Object) → Failure` from `lib/core/network/dio_client.dart`; `ScriptedAdapter`/`ScriptedReply` from `test/support/scripted_adapter.dart`.
- Produces:
  - `class AuthTokens` — `AuthTokens({required String accessToken, required String refreshToken, required DateTime expiresAt, required Map<String, Object?> claims})`.
  - `abstract interface class AuthService` — `Future<Result<AuthTokens>> login(String username, String password)`, `Future<Result<AuthTokens>> refresh(String refreshToken)`, `Future<Result<void>> logout(String refreshToken)`.
  - `class DioAuthService implements AuthService` — `DioAuthService(Dio dio)`.
  - `class ScriptedAuthService implements AuthService` in `test/support/fake_auth.dart` — `ScriptedAuthService({List<Result<AuthTokens>>? loginResults, List<Result<AuthTokens>>? refreshResults, Result<void> logoutResult})`, with `int loginCalls`, `int refreshCalls`, `int logoutCalls`, `List<String> refreshTokensSeen`.
  - `AuthTokens testTokens({String access, String refresh, Duration validFor, Map<String, Object?> claims})` helper in the same support file.

- [ ] **Step 1: Write the failing tests**

Create `test/support/fake_auth.dart`:

```dart
import 'package:acsl_campaign/core/auth/auth_service.dart';
import 'package:acsl_campaign/core/result/result.dart';

/// Fixed instant so token-expiry assertions never depend on wall-clock timing.
final DateTime kTestNow = DateTime.utc(2026, 8, 7, 12);

/// Builds tokens whose expiry is [validFor] after [kTestNow], so a test can say
/// "valid for 10 minutes" or "expires in 30 seconds" without arithmetic.
AuthTokens testTokens({
  String access = 'access-1',
  String refresh = 'refresh-1',
  Duration validFor = const Duration(minutes: 30),
  Map<String, Object?>? claims,
}) => AuthTokens(
  accessToken: access,
  refreshToken: refresh,
  expiresAt: kTestNow.add(validFor),
  claims:
      claims ??
      {
        'userId': 'u-1',
        'displayName': 'Test User',
        'organizationId': 'ORG_1',
        'roles': ['campaign_creator'],
        'permissions': ['campaign_create', 'bulk_import'],
        'territoryIds': <String>[],
      },
);

/// [AuthService] whose every result is scripted, recording what it was asked.
///
/// Each list is consumed in order and its last entry repeats once exhausted, so
/// a test that drives many refreshes need not pad the script.
class ScriptedAuthService implements AuthService {
  ScriptedAuthService({
    List<Result<AuthTokens>>? loginResults,
    List<Result<AuthTokens>>? refreshResults,
    this.logoutResult = const Ok(null),
  }) : _loginResults = loginResults ?? [Ok(testTokens())],
       _refreshResults = refreshResults ?? [Ok(testTokens())];

  final List<Result<AuthTokens>> _loginResults;
  final List<Result<AuthTokens>> _refreshResults;
  final Result<void> logoutResult;

  int loginCalls = 0;
  int refreshCalls = 0;
  int logoutCalls = 0;
  final List<String> refreshTokensSeen = [];

  /// Gate a test can hold closed to keep a refresh in flight while it starts a
  /// second one — this is how the single-flight guard is proven.
  Completer<void>? refreshGate;

  @override
  Future<Result<AuthTokens>> login(String username, String password) async {
    final i = loginCalls.clamp(0, _loginResults.length - 1);
    loginCalls++;
    return _loginResults[i];
  }

  @override
  Future<Result<AuthTokens>> refresh(String refreshToken) async {
    refreshTokensSeen.add(refreshToken);
    final i = refreshCalls.clamp(0, _refreshResults.length - 1);
    refreshCalls++;
    if (refreshGate != null) await refreshGate!.future;
    return _refreshResults[i];
  }

  @override
  Future<Result<void>> logout(String refreshToken) async {
    logoutCalls++;
    return logoutResult;
  }
}
```

Add `import 'dart:async';` as the first import of that file (needed for `Completer`).

Create `test/core/auth/auth_service_test.dart`:

```dart
import 'package:acsl_campaign/core/auth/auth_service.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  Dio buildDio(ScriptedAdapter adapter) =>
      Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter;

  group('DioAuthService.login', () {
    test('posts to /auth/login and returns tokens on success', () async {
      final adapter = ScriptedAdapter([
        ScriptedReply.json(200, {
          'accessToken': 'a-1',
          'refreshToken': 'r-1',
          'expiresInSeconds': 900,
          'claims': {'userId': 'u-1'},
        }),
      ]);

      final result = await DioAuthService(buildDio(adapter)).login('bob', 'pw');

      expect(result.isOk, isTrue);
      final tokens = result.fold((t) => t, (_) => null)!;
      expect(tokens.accessToken, 'a-1');
      expect(tokens.refreshToken, 'r-1');
      expect(tokens.claims['userId'], 'u-1');
      expect(adapter.requests.single.path, '/auth/login');
      // The password must never appear in a query string, only the body.
      expect(adapter.requests.single.uri.query, isEmpty);
    });

    test('maps a 401 to FailureKind.unauthorized', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(401)]);

      final result = await DioAuthService(buildDio(adapter)).login('bob', 'no');

      expect(result.fold((_) => null, (f) => f.kind), FailureKind.unauthorized);
    });

    test('maps a connection error to FailureKind.network', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
      ]);

      final result = await DioAuthService(buildDio(adapter)).login('bob', 'pw');

      expect(result.fold((_) => null, (f) => f.kind), FailureKind.network);
    });
  });

  group('DioAuthService.refresh', () {
    test('sends the refresh token and returns the rotated pair', () async {
      final adapter = ScriptedAdapter([
        ScriptedReply.json(200, {
          'accessToken': 'a-2',
          'refreshToken': 'r-2',
          'expiresInSeconds': 900,
          'claims': <String, Object?>{},
        }),
      ]);

      final result = await DioAuthService(buildDio(adapter)).refresh('r-1');

      expect(result.fold((t) => t.refreshToken, (_) => null), 'r-2');
      expect(adapter.requests.single.path, '/auth/refresh');
    });
  });

  group('DioAuthService.logout', () {
    test('returns Ok on 204', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(204)]);

      final result = await DioAuthService(buildDio(adapter)).logout('r-1');

      expect(result.isOk, isTrue);
      expect(adapter.requests.single.path, '/auth/logout');
    });

    test('returns Err when the server rejects, without throwing', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(500)]);

      final result = await DioAuthService(buildDio(adapter)).logout('r-1');

      expect(result.isOk, isFalse);
      expect(result.fold((_) => null, (f) => f.kind), FailureKind.server);
    });
  });
}
```

- [ ] **Step 2: Extend `ScriptedAdapter` with a JSON-body reply**

`test/support/scripted_adapter.dart` currently only returns `{"ok": true}`. Add a named constructor so a test can script a real payload. Add to `ScriptedReply`:

```dart
  /// An HTTP response with [code] and an explicit JSON [body].
  const ScriptedReply.json(this.code, this.body, {this.headers = const {}})
    : failureType = null;
```

Add `final Map<String, Object?>? body;` to the class, set `body = null` in the two existing constructors' initializer lists, and in `ScriptedAdapter.fetch` replace the success return's encoded body with `jsonEncode(reply.body ?? {'ok': true})`.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/core/auth/auth_service_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/auth/auth_service.dart'`.

- [ ] **Step 4: Write the implementation**

Create `lib/core/auth/auth_service.dart`:

```dart
import 'package:dio/dio.dart';

import '../network/dio_client.dart';
import '../result/result.dart';

/// A token pair plus the raw scope claims the server issued alongside it.
///
/// [claims] is deliberately untyped here: mapping it to [AppRole]/[Permission]
/// is a trust decision that belongs in `scope_claims.dart`, not in transport.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.claims,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final Map<String, Object?> claims;
}

/// Transport seam for the auth service.
///
/// 🔒 The auth contract (endpoints, payload shapes, claim names, rotation
/// semantics) is an unresolved external dependency. Keeping it behind one
/// interface means `SessionManager`, the router, the guard and every permission
/// check are transport-agnostic when it lands.
///
/// Returns [Result] rather than throwing so `session_manager.dart` needs no
/// network import: error mapping belongs here.
abstract interface class AuthService {
  Future<Result<AuthTokens>> login(String username, String password);
  Future<Result<AuthTokens>> refresh(String refreshToken);

  /// Best-effort server-side revocation. A failure must not prevent local
  /// sign-out, so the caller treats an [Err] as non-fatal.
  Future<Result<void>> logout(String refreshToken);
}

/// Dio-backed auth transport. Endpoints and payload shapes are placeholders
/// pending the 🔒 auth contract, exactly as the campaign endpoints are.
class DioAuthService implements AuthService {
  DioAuthService(this._dio);

  final Dio _dio;

  @override
  Future<Result<AuthTokens>> login(String username, String password) =>
      _tokenCall('/auth/login', {
        'username': username,
        'password': password,
      });

  @override
  Future<Result<AuthTokens>> refresh(String refreshToken) =>
      _tokenCall('/auth/refresh', {'refreshToken': refreshToken});

  @override
  Future<Result<void>> logout(String refreshToken) async {
    try {
      await _dio.post<void>(
        '/auth/logout',
        data: {'refreshToken': refreshToken},
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  Future<Result<AuthTokens>> _tokenCall(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: body);
      final data = res.data!;
      final seconds = data['expiresInSeconds'];
      return Ok(
        AuthTokens(
          accessToken: data['accessToken'] as String,
          refreshToken: data['refreshToken'] as String,
          // Relative lifetime, not an absolute server timestamp: the client
          // cannot trust its own clock to agree with the server's, but it can
          // trust "valid for N more seconds from when this arrived".
          expiresAt: DateTime.now().toUtc().add(
            Duration(seconds: seconds is int ? seconds : 0),
          ),
          claims: (data['claims'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
      );
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/core/auth/auth_service_test.dart`

Expected: PASS, 6 tests.

- [ ] **Step 6: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: format clean, analyze exits 0, **153 passing / 29 skipped** (147 + 6).

- [ ] **Step 7: Commit**

```bash
git add lib/core/auth/auth_service.dart test/support/ test/core/auth/
git commit -m "feat: add the AuthService transport seam

Returns Result rather than throwing so the session lifecycle needs no Dio
import. Token lifetime is derived from a relative expiresInSeconds rather
than an absolute server timestamp, because the client cannot trust its own
clock to agree with the server's."
```

---

## Task 2: `TokenStore` — the platform split

**Files:**
- Create: `lib/core/auth/token_store.dart`
- Modify: `lib/core/storage/secure_store.dart` (add one key)
- Test: `test/core/auth/token_store_test.dart`

**Interfaces:**
- Consumes: `SecureStore` (`Future<String?> read(String key)`, `Future<void> write(String key, String value)`, `Future<void> delete(String key)`) and `SecureStoreKeys` from `lib/core/storage/secure_store.dart`; `InMemorySecureStore` / `ThrowingSecureStore` from `test/support/in_memory_secure_store.dart`.
- Produces:
  - `abstract interface class TokenStore` — `Future<void> persist(String refreshToken)`, `Future<String?> read()`, `Future<void> clear()`.
  - `class MobileTokenStore implements TokenStore` — `MobileTokenStore(SecureStore store)`.
  - `class WebTokenStore implements TokenStore` — `const WebTokenStore()`.
  - `SecureStoreKeys.refreshTokenV1` = `'auth_refresh_token_v1'`.

- [ ] **Step 1: Write the failing test**

Create `test/core/auth/token_store_test.dart`:

```dart
import 'package:acsl_campaign/core/auth/token_store.dart';
import 'package:acsl_campaign/core/storage/secure_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_secure_store.dart';

void main() {
  group('SecureStoreKeys', () {
    test('the refresh-token key is frozen', () {
      // Renaming this silently signs out every installed device, because the
      // old key is abandoned with no way to find it again.
      expect(SecureStoreKeys.refreshTokenV1, 'auth_refresh_token_v1');
    });
  });

  group('MobileTokenStore', () {
    test('persists and reads back the refresh token', () async {
      final secure = InMemorySecureStore();
      final store = MobileTokenStore(secure);

      expect(await store.read(), isNull);
      await store.persist('r-1');

      expect(await store.read(), 'r-1');
      expect(secure.values[SecureStoreKeys.refreshTokenV1], 'r-1');
    });

    test('clear removes the token', () async {
      final secure = InMemorySecureStore({
        SecureStoreKeys.refreshTokenV1: 'r-1',
      });

      await MobileTokenStore(secure).clear();

      expect(secure.values.containsKey(SecureStoreKeys.refreshTokenV1), isFalse);
    });

    test('an unreadable store yields null instead of throwing', () async {
      // A keystore fault must not crash sign-in: the user can still enter
      // credentials. Throwing here would take down app startup.
      final store = MobileTokenStore(
        ThrowingSecureStore(PlatformException(code: 'decrypt_failed')),
      );

      expect(await store.read(), isNull);
    });
  });

  group('WebTokenStore', () {
    test('persist is a no-op and read always returns null', () async {
      // Web SecureStore is localStorage with a wrapped key, not hardware
      // backed. A refresh token there is stealable by any injected script, so
      // this platform deliberately holds nothing.
      const store = WebTokenStore();

      await store.persist('r-1');

      expect(await store.read(), isNull);
    });

    test('clear is safe to call', () async {
      const store = WebTokenStore();
      await expectLater(store.clear(), completes);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/auth/token_store_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/auth/token_store.dart'`.

- [ ] **Step 3: Add the storage key**

In `lib/core/storage/secure_store.dart`, add inside `SecureStoreKeys`:

```dart
  /// NEVER rename. Same rule as [evidenceAesKeyV1]: a rename abandons the key
  /// already on every installed device, silently signing all of them out.
  static const String refreshTokenV1 = 'auth_refresh_token_v1';
```

- [ ] **Step 4: Write the implementation**

Create `lib/core/auth/token_store.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../storage/secure_store.dart';

/// Persistence for the refresh token.
///
/// Only the *refresh* token is ever stored. The access token is short-lived and
/// re-derivable from it, so persisting it would widen the attack surface for no
/// gain.
abstract interface class TokenStore {
  Future<void> persist(String refreshToken);
  Future<String?> read();
  Future<void> clear();
}

/// Keystore/Keychain-backed store for mobile.
///
/// Field devices persist deliberately: a field user reopening the app mid
/// session may be offline and unable to re-authenticate at all, so losing the
/// session on restart would lose their working state.
class MobileTokenStore implements TokenStore {
  MobileTokenStore(this._store);

  final SecureStore _store;

  @override
  Future<void> persist(String refreshToken) =>
      _store.write(SecureStoreKeys.refreshTokenV1, refreshToken);

  @override
  Future<String?> read() async {
    try {
      return await _store.read(SecureStoreKeys.refreshTokenV1);
    } catch (error) {
      // A keystore fault (cipher change, OS reset, restore onto another
      // device) must not crash startup. The user simply signs in again.
      debugPrint('Refresh token could not be read ($error). Signing out.');
      return null;
    }
  }

  @override
  Future<void> clear() => _store.delete(SecureStoreKeys.refreshTokenV1);
}

/// Deliberate no-op store for web.
///
/// `flutter_secure_storage_web` is `localStorage` with a wrapped key, NOT
/// hardware-backed, so anything written there is readable by any script
/// injected into the page. A refresh token is the single credential least
/// worth exposing that way, so web holds tokens in memory only and a reload
/// signs the user out.
///
/// Changing this needs a server-side httpOnly refresh cookie, not a different
/// client store.
class WebTokenStore implements TokenStore {
  const WebTokenStore();

  @override
  Future<void> persist(String refreshToken) async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> clear() async {}
}

/// Selects the store for the current platform.
TokenStore createTokenStore(SecureStore store) =>
    kIsWeb ? const WebTokenStore() : MobileTokenStore(store);
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/auth/token_store_test.dart`

Expected: PASS, 6 tests.

- [ ] **Step 6: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **159 passing / 29 skipped**.

- [ ] **Step 7: Commit**

```bash
git add lib/core/auth/token_store.dart lib/core/storage/secure_store.dart test/core/auth/token_store_test.dart
git commit -m "feat: persist the refresh token on mobile only

Web SecureStore is localStorage with a wrapped key rather than hardware
backed, so a refresh token there is readable by any injected script. Web
holds tokens in memory only and a reload signs the user out; changing that
needs a server-side httpOnly cookie, not a different client store. The
access token is never persisted on either platform."
```

---

## Task 3: `scope_claims.dart` — the trust boundary

**Files:**
- Create: `lib/core/auth/scope_claims.dart`
- Test: `test/core/auth/scope_claims_test.dart`

**Interfaces:**
- Consumes: `AppRole`, `Permission`, `AccessScope` from `lib/core/auth/rbac.dart` (`AccessScope({required Set<AppRole> roles, required Set<Permission> permissions, required String organizationId, Set<String> territoryIds = const {}})`); `Result`/`Failure`/`FailureKind`.
- Produces: `Result<ScopeClaims> parseScopeClaims(Map<String, Object?> claims)` and `class ScopeClaims { final String userId; final String displayName; final AccessScope scope; }`.

**Wire vocabulary** — the exact strings this maps. All seven roles and eleven permissions, snake_case:

| `AppRole` | wire | `Permission` | wire |
|---|---|---|---|
| `campaignCreator` | `campaign_creator` | `campaignCreate` | `campaign_create` |
| `marketingApprover` | `marketing_approver` | `campaignApprove` | `campaign_approve` |
| `crmVerifier` | `crm_verifier` | `campaignCancel` | `campaign_cancel` |
| `crmSupervisor` | `crm_supervisor` | `bulkImport` | `bulk_import` |
| `fieldUser` | `field_user` | `attendanceCapture` | `attendance_capture` |
| `admin` | `admin` | `verificationDecide` | `verification_decide` |
| `reportingViewer` | `reporting_viewer` | `verificationOverride` | `verification_override` |
| | | `sensitiveMediaView` | `sensitive_media_view` |
| | | `nidReveal` | `nid_reveal` |
| | | `configManage` | `config_manage` |
| | | `export` | `export` |

- [ ] **Step 1: Write the failing test**

Create `test/core/auth/scope_claims_test.dart`:

```dart
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/scope_claims.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> claims({
    List<String> roles = const ['campaign_creator'],
    List<String> permissions = const ['campaign_create'],
    String organizationId = 'ORG_1',
    List<String> territoryIds = const [],
    String userId = 'u-1',
    String displayName = 'Test User',
  }) => {
    'userId': userId,
    'displayName': displayName,
    'organizationId': organizationId,
    'roles': roles,
    'permissions': permissions,
    'territoryIds': territoryIds,
  };

  test('maps a well-formed claim set', () {
    final result = parseScopeClaims(
      claims(
        roles: ['crm_verifier', 'crm_supervisor'],
        permissions: ['verification_decide', 'sensitive_media_view'],
        territoryIds: ['T-1', 'T-2'],
      ),
    );

    final parsed = result.fold((c) => c, (_) => null)!;
    expect(parsed.userId, 'u-1');
    expect(parsed.displayName, 'Test User');
    expect(parsed.scope.roles, {AppRole.crmVerifier, AppRole.crmSupervisor});
    expect(parsed.scope.permissions, {
      Permission.verificationDecide,
      Permission.sensitiveMediaView,
    });
    expect(parsed.scope.organizationId, 'ORG_1');
    expect(parsed.scope.territoryIds, {'T-1', 'T-2'});
  });

  test('every AppRole has a wire mapping', () {
    // A role added to the enum without a wire string would silently become
    // unmappable, and every user holding it would fail to sign in.
    for (final role in AppRole.values) {
      expect(
        wireNameForRole(role),
        isNotEmpty,
        reason: 'AppRole.${role.name} has no wire name',
      );
    }
  });

  test('every Permission has a wire mapping', () {
    for (final p in Permission.values) {
      expect(
        wireNameForPermission(p),
        isNotEmpty,
        reason: 'Permission.${p.name} has no wire name',
      );
    }
  });

  group('unknown claims fail loudly', () {
    test('an unknown role is rejected, not dropped', () {
      // Dropping it would leave a user with a narrower scope than the server
      // granted, which presents as mysterious /forbidden redirects rather than
      // as the version mismatch it actually is.
      final result = parseScopeClaims(
        claims(roles: ['campaign_creator', 'galactic_overlord']),
      );

      expect(result.isOk, isFalse);
      final failure = result.fold((_) => null, (f) => f)!;
      expect(failure.kind, FailureKind.validation);
      expect(failure.message, contains('galactic_overlord'));
    });

    test('an unknown permission is rejected', () {
      final result = parseScopeClaims(
        claims(permissions: ['campaign_create', 'launch_missiles']),
      );

      expect(result.isOk, isFalse);
      expect(result.fold((_) => null, (f) => f.message), contains('launch_missiles'));
    });

    test('all unknown names are reported together', () {
      // One sign-in attempt should reveal the whole mismatch, not the first
      // item of it.
      final result = parseScopeClaims(
        claims(roles: ['bad_role'], permissions: ['bad_perm']),
      );

      final message = result.fold((_) => null, (f) => f.message)!;
      expect(message, contains('bad_role'));
      expect(message, contains('bad_perm'));
    });

    test('an empty role set is rejected', () {
      // A user the server granted no role at all cannot use the app, and
      // silently admitting them produces an empty shell with no explanation.
      final result = parseScopeClaims(claims(roles: []));

      expect(result.isOk, isFalse);
    });

    test('a missing organizationId is rejected', () {
      // Scope narrows every query by org; an empty one would widen them.
      final result = parseScopeClaims(claims(organizationId: ''));

      expect(result.isOk, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/auth/scope_claims_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/auth/scope_claims.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/auth/scope_claims.dart`:

```dart
import '../result/result.dart';
import 'rbac.dart';

/// The identity and scope carried by a token's claims.
class ScopeClaims {
  const ScopeClaims({
    required this.userId,
    required this.displayName,
    required this.scope,
  });

  final String userId;
  final String displayName;
  final AccessScope scope;
}

/// Wire vocabulary. Exhaustive switches (no `default`) so adding a value to
/// either enum is a compile error here rather than a silent unmappable role.
String wireNameForRole(AppRole role) => switch (role) {
  AppRole.campaignCreator => 'campaign_creator',
  AppRole.marketingApprover => 'marketing_approver',
  AppRole.crmVerifier => 'crm_verifier',
  AppRole.crmSupervisor => 'crm_supervisor',
  AppRole.fieldUser => 'field_user',
  AppRole.admin => 'admin',
  AppRole.reportingViewer => 'reporting_viewer',
};

String wireNameForPermission(Permission p) => switch (p) {
  Permission.campaignCreate => 'campaign_create',
  Permission.campaignApprove => 'campaign_approve',
  Permission.campaignCancel => 'campaign_cancel',
  Permission.bulkImport => 'bulk_import',
  Permission.attendanceCapture => 'attendance_capture',
  Permission.verificationDecide => 'verification_decide',
  Permission.verificationOverride => 'verification_override',
  Permission.sensitiveMediaView => 'sensitive_media_view',
  Permission.nidReveal => 'nid_reveal',
  Permission.configManage => 'config_manage',
  Permission.export => 'export',
};

final Map<String, AppRole> _rolesByWire = {
  for (final r in AppRole.values) wireNameForRole(r): r,
};
final Map<String, Permission> _permissionsByWire = {
  for (final p in Permission.values) wireNameForPermission(p): p,
};

/// Maps server claims to an [AccessScope].
///
/// This is a TRUST BOUNDARY. An unrecognised role or permission is rejected,
/// never dropped: a user with a silently narrowed scope is indistinguishable
/// from a legitimately restricted one, so the failure would surface as
/// mysterious `/forbidden` redirects instead of the client/server version
/// mismatch it actually is. All unknown names are reported together so one
/// sign-in reveals the whole mismatch.
Result<ScopeClaims> parseScopeClaims(Map<String, Object?> claims) {
  final unknown = <String>[];

  final roleNames = _stringList(claims['roles']);
  final roles = <AppRole>{};
  for (final name in roleNames) {
    final role = _rolesByWire[name];
    if (role == null) {
      unknown.add('role "$name"');
    } else {
      roles.add(role);
    }
  }

  final permissionNames = _stringList(claims['permissions']);
  final permissions = <Permission>{};
  for (final name in permissionNames) {
    final p = _permissionsByWire[name];
    if (p == null) {
      unknown.add('permission "$name"');
    } else {
      permissions.add(p);
    }
  }

  if (unknown.isNotEmpty) {
    return Err(
      Failure(
        FailureKind.validation,
        message:
            'This account has claims this app version does not recognise: '
            '${unknown.join(', ')}.',
      ),
    );
  }

  if (roles.isEmpty) {
    return const Err(
      Failure(
        FailureKind.validation,
        message: 'This account has no role assigned for this app.',
      ),
    );
  }

  final organizationId = claims['organizationId'];
  if (organizationId is! String || organizationId.isEmpty) {
    return const Err(
      Failure(
        FailureKind.validation,
        message: 'This account is not associated with an organization.',
      ),
    );
  }

  final userId = claims['userId'];
  if (userId is! String || userId.isEmpty) {
    return const Err(
      Failure(FailureKind.validation, message: 'This account has no user id.'),
    );
  }

  return Ok(
    ScopeClaims(
      userId: userId,
      displayName: claims['displayName'] is String
          ? claims['displayName']! as String
          : userId,
      scope: AccessScope(
        roles: roles,
        permissions: permissions,
        organizationId: organizationId,
        territoryIds: _stringList(claims['territoryIds']).toSet(),
      ),
    ),
  );
}

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList()
    : const <String>[];
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/auth/scope_claims_test.dart`

Expected: PASS, 8 tests.

- [ ] **Step 5: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **167 passing / 29 skipped**.

- [ ] **Step 6: Commit**

```bash
git add lib/core/auth/scope_claims.dart test/core/auth/scope_claims_test.dart
git commit -m "feat: reject unknown auth claims instead of narrowing scope

An unrecognised role or permission is a client/server version mismatch,
but dropping it produces a user whose scope is silently narrower than the
server granted - indistinguishable from a legitimately restricted user,
and surfacing as mysterious /forbidden redirects. All unknown names are
reported together so one sign-in reveals the whole mismatch. The wire
mappings are exhaustive switches, so adding an enum value without a wire
string is a compile error."
```

---

## Task 4: `SessionManager` and `AuthState`

Needs Tasks 1–3.

**Files:**
- Create: `lib/core/auth/session_manager.dart`
- Modify: `lib/core/auth/session.dart`
- Modify: `test/support/fake_auth.dart` (add `FakeTokenStore`)
- Test: `test/core/auth/session_manager_test.dart`

**Interfaces:**
- Consumes: `AuthService`, `AuthTokens` (Task 1); `TokenStore` (Task 2); `parseScopeClaims`, `ScopeClaims` (Task 3); `Session` from `lib/core/auth/session.dart`.
- Produces:
  - `sealed class AuthState`; `final class AuthRestoring extends AuthState` (`const AuthRestoring()`); `final class AuthSignedOut extends AuthState` (`const AuthSignedOut()`); `final class AuthSignedIn extends AuthState` (`const AuthSignedIn(this.session)`, field `Session session`).
  - `class SessionManager` — `SessionManager({required AuthService service, required TokenStore tokens, DateTime Function() now = ..., Duration refreshSkew = const Duration(seconds: 60)})`, with `AuthState get state`, `Stream<AuthState> get changes`, `Future<Result<void>> signIn(String username, String password)`, `Future<void> restore()`, `Future<String?> refresh()`, `Future<void> signOut()`, `Future<String?> accessTokenForRequest()`, `void dispose()`.
  - `Session` gains `final String refreshToken`.
  - `class FakeTokenStore implements TokenStore` in `test/support/fake_auth.dart` — `FakeTokenStore([String? initial])`, with `String? value`, `int persistCalls`, `int clearCalls`.

- [ ] **Step 1: Add `FakeTokenStore` to the support file**

Append to `test/support/fake_auth.dart`:

```dart
/// In-memory [TokenStore] standing in for either platform, so a test can model
/// "mobile with a stored token" and "web that stores nothing" without kIsWeb.
class FakeTokenStore implements TokenStore {
  FakeTokenStore([this.value]);

  String? value;
  int persistCalls = 0;
  int clearCalls = 0;

  @override
  Future<void> persist(String refreshToken) async {
    persistCalls++;
    value = refreshToken;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> clear() async {
    clearCalls++;
    value = null;
  }
}
```

Add `import 'package:acsl_campaign/core/auth/token_store.dart';` to that file's imports.

- [ ] **Step 2: Write the failing test**

Create `test/core/auth/session_manager_test.dart`:

```dart
import 'dart:async';

import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth.dart';

void main() {
  SessionManager build({
    ScriptedAuthService? service,
    FakeTokenStore? tokens,
    DateTime? now,
  }) => SessionManager(
    service: service ?? ScriptedAuthService(),
    tokens: tokens ?? FakeTokenStore(),
    now: () => now ?? kTestNow,
  );

  group('signIn', () {
    test('moves to AuthSignedIn and persists the refresh token', () async {
      final tokens = FakeTokenStore();
      final manager = build(tokens: tokens);

      final result = await manager.signIn('bob', 'pw');

      expect(result.isOk, isTrue);
      expect(manager.state, isA<AuthSignedIn>());
      final session = (manager.state as AuthSignedIn).session;
      expect(session.userId, 'u-1');
      expect(session.accessToken, 'access-1');
      expect(tokens.value, 'refresh-1');
      manager.dispose();
    });

    test('stays signed out and surfaces the failure on bad credentials', () async {
      final manager = build(
        service: ScriptedAuthService(
          loginResults: [const Err(Failure(FailureKind.unauthorized))],
        ),
      );

      final result = await manager.signIn('bob', 'wrong');

      expect(result.isOk, isFalse);
      expect(result.fold((_) => null, (f) => f.kind), FailureKind.unauthorized);
      expect(manager.state, isA<AuthSignedOut>());
      manager.dispose();
    });

    test('rejects a token whose claims do not parse, without signing in', () async {
      // An unmappable role must not produce a signed-in user with an empty
      // scope - that is the silent-narrowing failure scope_claims prevents.
      final manager = build(
        service: ScriptedAuthService(
          loginResults: [
            Ok(testTokens(claims: {
              'userId': 'u-1',
              'organizationId': 'ORG_1',
              'roles': ['galactic_overlord'],
              'permissions': <String>[],
            })),
          ],
        ),
      );

      final result = await manager.signIn('bob', 'pw');

      expect(result.isOk, isFalse);
      expect(manager.state, isA<AuthSignedOut>());
      manager.dispose();
    });
  });

  group('restore', () {
    test('with a stored token: passes through AuthRestoring to signed in', () async {
      final manager = build(tokens: FakeTokenStore('stored-r'));
      final seen = <AuthState>[];
      final sub = manager.changes.listen(seen.add);

      await manager.restore();
      await pumpEventQueue();

      expect(seen.map((s) => s.runtimeType), [AuthRestoring, AuthSignedIn]);
      expect(manager.state, isA<AuthSignedIn>());
      await sub.cancel();
      manager.dispose();
    });

    test('sends the STORED token to refresh, not a fresh one', () async {
      final service = ScriptedAuthService();
      final manager = build(service: service, tokens: FakeTokenStore('stored-r'));

      await manager.restore();

      expect(service.refreshTokensSeen, ['stored-r']);
      manager.dispose();
    });

    test('with no stored token: goes straight to signed out, never restoring', () async {
      // This is the web path. Emitting AuthRestoring there would make the
      // router hold on a splash for a state web can never leave.
      final manager = build(tokens: FakeTokenStore());
      final seen = <AuthState>[];
      final sub = manager.changes.listen(seen.add);

      await manager.restore();
      await pumpEventQueue();

      expect(seen.map((s) => s.runtimeType), [AuthSignedOut]);
      await sub.cancel();
      manager.dispose();
    });

    test('a rejected stored token clears storage and signs out', () async {
      final tokens = FakeTokenStore('stale-r');
      final manager = build(
        service: ScriptedAuthService(
          refreshResults: [const Err(Failure(FailureKind.unauthorized))],
        ),
        tokens: tokens,
      );

      await manager.restore();

      expect(manager.state, isA<AuthSignedOut>());
      expect(tokens.value, isNull);
      expect(tokens.clearCalls, greaterThan(0));
      manager.dispose();
    });
  });

  group('refresh is single-flight', () {
    test('two concurrent refreshes make exactly ONE transport call', () async {
      // The race this closes is a 401-triggered refresh colliding with a
      // proactive one. Under server-side token rotation the loser presents a
      // token the winner already consumed, signing the user out mid-task.
      final service = ScriptedAuthService()..refreshGate = Completer<void>();
      final manager = build(service: service, tokens: FakeTokenStore('r-1'));
      await manager.signIn('bob', 'pw');
      service.refreshCalls = 0;

      final first = manager.refresh();
      final second = manager.refresh();
      service.refreshGate!.complete();
      final results = await Future.wait([first, second]);

      expect(service.refreshCalls, 1);
      expect(results[0], results[1]);
      manager.dispose();
    });

    test('a later refresh after the first completes does call again', () async {
      // The guard must clear, or the session could never be renewed twice.
      final service = ScriptedAuthService();
      final manager = build(service: service, tokens: FakeTokenStore('r-1'));
      await manager.signIn('bob', 'pw');
      service.refreshCalls = 0;

      await manager.refresh();
      await manager.refresh();

      expect(service.refreshCalls, 2);
      manager.dispose();
    });

    test('a failed refresh signs out and clears the token', () async {
      final tokens = FakeTokenStore('r-1');
      final service = ScriptedAuthService(
        refreshResults: [const Err(Failure(FailureKind.unauthorized))],
      );
      final manager = build(service: service, tokens: tokens);
      await manager.signIn('bob', 'pw');

      final token = await manager.refresh();

      expect(token, isNull);
      expect(manager.state, isA<AuthSignedOut>());
      expect(tokens.value, isNull);
      manager.dispose();
    });
  });

  group('accessTokenForRequest — proactive renewal', () {
    test('refreshes when the token expires inside the skew window', () async {
      final service = ScriptedAuthService(
        loginResults: [Ok(testTokens(validFor: const Duration(seconds: 30)))],
        refreshResults: [Ok(testTokens(access: 'access-2'))],
      );
      final manager = build(service: service);
      await manager.signIn('bob', 'pw');
      service.refreshCalls = 0;

      final token = await manager.accessTokenForRequest();

      expect(service.refreshCalls, 1);
      expect(token, 'access-2');
      manager.dispose();
    });

    test('does NOT refresh a token with plenty of life left', () async {
      // Refreshing eagerly on every request would multiply auth traffic and,
      // under rotation, invalidate tokens other in-flight requests hold.
      final service = ScriptedAuthService(
        loginResults: [Ok(testTokens(validFor: const Duration(minutes: 20)))],
      );
      final manager = build(service: service);
      await manager.signIn('bob', 'pw');
      service.refreshCalls = 0;

      final token = await manager.accessTokenForRequest();

      expect(service.refreshCalls, 0);
      expect(token, 'access-1');
      manager.dispose();
    });

    test('returns null when signed out', () async {
      final manager = build();

      expect(await manager.accessTokenForRequest(), isNull);
      manager.dispose();
    });
  });

  group('signOut', () {
    test('clears state and storage, then calls the service', () async {
      final tokens = FakeTokenStore();
      final service = ScriptedAuthService();
      final manager = build(service: service, tokens: tokens);
      await manager.signIn('bob', 'pw');

      await manager.signOut();

      expect(manager.state, isA<AuthSignedOut>());
      expect(tokens.value, isNull);
      expect(service.logoutCalls, 1);
      manager.dispose();
    });

    test('signs out locally even when the server call fails', () async {
      // Staying signed in because the server was unreachable is the wrong
      // failure direction on a shared field device.
      final tokens = FakeTokenStore();
      final manager = build(
        service: ScriptedAuthService(
          logoutResult: const Err(Failure(FailureKind.network)),
        ),
        tokens: tokens,
      );
      await manager.signIn('bob', 'pw');

      await manager.signOut();

      expect(manager.state, isA<AuthSignedOut>());
      expect(tokens.value, isNull);
      manager.dispose();
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/auth/session_manager_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/auth/session_manager.dart'`.

- [ ] **Step 4: Add `refreshToken` to `Session` and fix its false comment**

Replace the doc comment and add the field in `lib/core/auth/session.dart`:

```dart
import 'rbac.dart';

/// Authenticated session state.
///
/// Both tokens are held in memory here. The REFRESH token is additionally
/// persisted on mobile (see `TokenStore`); on web nothing is persisted, so a
/// reload signs the user out. The ACCESS token is never persisted anywhere -
/// it is short-lived and re-derivable from refresh.
///
/// Signed-out is represented by `AuthSignedOut`, not by a null Session (see
/// `AuthState` in session_manager.dart).
class Session {
  const Session({
    required this.userId,
    required this.displayName,
    required this.scope,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String userId;
  final String displayName;
  final AccessScope scope;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
```

- [ ] **Step 5: Write `SessionManager`**

Create `lib/core/auth/session_manager.dart`:

```dart
import 'dart:async';

import '../result/result.dart';
import 'auth_service.dart';
import 'scope_claims.dart';
import 'session.dart';
import 'token_store.dart';

/// Authentication state.
///
/// A sealed tri-state rather than `Session?`, because a nullable session
/// conflates "signed out" with "not yet known". On mobile, cold start holds a
/// persisted refresh token that has not been exchanged yet; treating that as
/// signed-out flashes the login screen on every launch and then redirects away
/// from it. The router holds on a splash during [AuthRestoring] instead.
sealed class AuthState {
  const AuthState();
}

/// Boot only, and only on a platform that persists tokens. Web never enters it.
final class AuthRestoring extends AuthState {
  const AuthRestoring();
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.session);
  final Session session;
}

DateTime _systemNow() => DateTime.now().toUtc();

/// Owns the session lifecycle: sign-in, restore, refresh, sign-out.
///
/// Refresh has two independent triggers - a 401 from `AuthInterceptor` and
/// proactive renewal near expiry. Both route through [refresh], which holds a
/// single in-flight future, because under server-side token rotation two
/// concurrent refreshes mean the loser presents a token the winner already
/// consumed and the user is signed out mid-task. That failure only appears
/// under concurrency, so it is structural here rather than something tests are
/// expected to catch downstream.
class SessionManager {
  SessionManager({
    required AuthService service,
    required TokenStore tokens,
    DateTime Function() now = _systemNow,
    this.refreshSkew = const Duration(seconds: 60),
  }) : _service = service,
       _tokens = tokens,
       _now = now;

  final AuthService _service;
  final TokenStore _tokens;
  final DateTime Function() _now;

  /// Renew when this much life or less remains. A request sent with two
  /// seconds of validity is a guaranteed 401 and a wasted round-trip, so the
  /// 401 path becomes the exception rather than the norm.
  final Duration refreshSkew;

  final StreamController<AuthState> _changes =
      StreamController<AuthState>.broadcast();

  AuthState _state = const AuthSignedOut();
  Future<String?>? _inFlightRefresh;

  AuthState get state => _state;
  Stream<AuthState> get changes => _changes.stream;

  void _emit(AuthState next) {
    _state = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  Future<Result<void>> signIn(String username, String password) async {
    final result = await _service.login(username, password);
    if (result case Err(:final failure)) {
      _emit(const AuthSignedOut());
      return Err(failure);
    }
    return _adopt(result.fold((t) => t, (_) => null)!);
  }

  /// Exchanges any persisted refresh token for a session. Call once at boot.
  Future<void> restore() async {
    final stored = await _tokens.read();
    if (stored == null) {
      // Web, or a first run. Never emit AuthRestoring: the router would hold
      // on a splash for a state this platform can never leave.
      _emit(const AuthSignedOut());
      return;
    }
    _emit(const AuthRestoring());
    await _exchange(stored);
  }

  /// Renews the session. Concurrent callers share one transport call.
  /// Returns the new access token, or null if the session ended.
  Future<String?> refresh() {
    final current = _state;
    final token = switch (current) {
      AuthSignedIn(:final session) => session.refreshToken,
      _ => null,
    };
    if (token == null) return Future<String?>.value();
    return _inFlightRefresh ??= _exchange(
      token,
    ).whenComplete(() => _inFlightRefresh = null);
  }

  /// The token to attach to an outbound request, renewing first if it is
  /// within [refreshSkew] of expiry.
  Future<String?> accessTokenForRequest() async {
    final current = _state;
    if (current is! AuthSignedIn) return null;
    final remaining = current.session.expiresAt.difference(_now());
    if (remaining <= refreshSkew) return refresh();
    return current.session.accessToken;
  }

  /// Local first, then best effort on the server. A failed network call must
  /// not leave the user signed in: on a shared field device, staying
  /// authenticated because the server was unreachable is the wrong direction.
  Future<void> signOut() async {
    final current = _state;
    final token = switch (current) {
      AuthSignedIn(:final session) => session.refreshToken,
      _ => null,
    };
    _emit(const AuthSignedOut());
    await _tokens.clear();
    if (token != null) await _service.logout(token);
  }

  Future<String?> _exchange(String refreshToken) async {
    final result = await _service.refresh(refreshToken);
    if (result case Err()) {
      await _tokens.clear();
      _emit(const AuthSignedOut());
      return null;
    }
    final adopted = await _adopt(result.fold((t) => t, (_) => null)!);
    return adopted.isOk ? (_state as AuthSignedIn).session.accessToken : null;
  }

  /// Turns tokens into a session, rejecting claims that do not parse. A token
  /// whose roles are unmappable must NOT become a signed-in user with an empty
  /// scope - that is exactly the silent narrowing scope_claims prevents.
  Future<Result<void>> _adopt(AuthTokens tokens) async {
    final parsed = parseScopeClaims(tokens.claims);
    if (parsed case Err(:final failure)) {
      await _tokens.clear();
      _emit(const AuthSignedOut());
      return Err(failure);
    }
    final claims = parsed.fold((c) => c, (_) => null)!;
    await _tokens.persist(tokens.refreshToken);
    _emit(
      AuthSignedIn(
        Session(
          userId: claims.userId,
          displayName: claims.displayName,
          scope: claims.scope,
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiresAt: tokens.expiresAt,
        ),
      ),
    );
    return const Ok(null);
  }

  void dispose() => _changes.close();
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/core/auth/session_manager_test.dart`

Expected: PASS, 14 tests. If `buildE2ESession` in `lib/core/auth/e2e_session.dart` now fails to compile (it constructs `Session` without `refreshToken`), add `refreshToken: 'e2e-refresh'` to it — the E2E fixture is replaced properly in Task 6, and this keeps the tree compiling meanwhile.

- [ ] **Step 7: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **181 passing / 29 skipped**.

- [ ] **Step 8: Commit**

```bash
git add lib/core/auth/ test/core/auth/session_manager_test.dart test/support/fake_auth.dart
git commit -m "feat: add SessionManager with single-flight refresh

AuthState is a sealed tri-state because a nullable Session conflates
signed-out with not-yet-known: on mobile, cold start holds a persisted
token that has not been exchanged, and treating that as signed-out flashes
the login screen on every launch. Refresh holds a single in-flight future,
because under server-side rotation two concurrent refreshes mean the loser
presents a consumed token and the user is signed out mid-task. Sign-out
clears locally before calling the server, so an unreachable server cannot
leave a shared device signed in."
```

---

## Task 5: `routeTable`, guards, and the exhaustiveness gate

**Files:**
- Create: `lib/app/router/route_table.dart`
- Modify: `lib/app/router/route_guards.dart` (rewrite)
- Modify: `lib/app/router/app_router.dart`
- Test: `test/app/router/route_table_test.dart`, `test/app/router/route_guards_test.dart`

**Interfaces:**
- Consumes: `Permission` from `lib/core/auth/rbac.dart`; `AuthState`/`AuthSignedIn`/`AuthSignedOut`/`AuthRestoring` (Task 4); `AppConfig` from `lib/app/flavors.dart` (fields `flavor`, `apiBaseUrl`, `mediaHost`, `e2e`, `e2eRole`, `e2eQuality`, `e2eSeed`, and getter `devRoutesEnabled`).
- Produces:
  - `sealed class Access`; `final class Public extends Access` (`const Public()`); `final class Authenticated extends Access` (`const Authenticated()`); `final class Requires extends Access` (`const Requires(this.permission)`).
  - `class RouteEntry` — `const RouteEntry(this.path, this.access)`, fields `String path`, `Access access`.
  - `const List<RouteEntry> routeTable`, `const Set<String> devOnlyPaths`, and `Access? accessFor(String? fullPath)`.
  - `class RouteGuards` — `const RouteGuards()`, with `String? evaluate({required AuthState auth, required String? fullPath, required String location, String? intended})` and `static const String homePath = '/'`.
  - `String? redirectTargetAfterSignIn(AuthState auth, String? intended)`.

- [ ] **Step 1: Write the failing tests**

Create `test/app/router/route_table_test.dart`:

```dart
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/app/router/app_router.dart';
import 'package:acsl_campaign/app/router/route_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('routeTable integrity', () {
    test('no path is declared twice', () {
      final paths = routeTable.map((e) => e.path).toList();
      expect(paths.length, paths.toSet().length);
    });

    test('every dev-only path is present in the table', () {
      final paths = routeTable.map((e) => e.path).toSet();
      for (final p in devOnlyPaths) {
        expect(paths, contains(p), reason: '$p is registered but ungoverned');
      }
    });
  });

  group('exhaustiveness: registered routes == table', () {
    // This is the guarantee the epic exists to create. Adding a route without
    // an access decision must fail here rather than silently shipping ungated.
    test('with dev routes enabled, the sets are identical', () {
      final registered = registeredRoutePaths(devRoutesEnabled: true);

      expect(registered, routeTable.map((e) => e.path).toSet());
    });

    test('with dev routes disabled, the set is the table minus dev paths', () {
      final registered = registeredRoutePaths(devRoutesEnabled: false);
      final expected = routeTable
          .map((e) => e.path)
          .toSet()
          .difference(devOnlyPaths);

      expect(registered, expected);
      expect(registered, isNot(contains('/dev')));
      expect(registered, isNot(contains('/gallery')));
    });
  });

  group('accessFor', () {
    test('resolves a parameterised template', () {
      expect(accessFor('/campaigns/:id/approve'), isA<Requires>());
    });

    test('returns null for an unknown path', () {
      expect(accessFor('/nope'), isNull);
    });

    test('returns null for a null fullPath', () {
      expect(accessFor(null), isNull);
    });
  });
}
```

Create `test/app/router/route_guards_test.dart`:

```dart
import 'package:acsl_campaign/app/router/route_guards.dart';
import 'package:acsl_campaign/app/router/route_table.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const guards = RouteGuards();

  AuthState signedIn({Set<Permission> permissions = const {}}) => AuthSignedIn(
    Session(
      userId: 'u-1',
      displayName: 'Test User',
      scope: AccessScope(
        roles: const {AppRole.campaignCreator},
        permissions: permissions,
        organizationId: 'ORG_1',
      ),
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  group('unauthenticated', () {
    test('a protected route redirects to /login', () {
      expect(
        guards.evaluate(
          auth: const AuthSignedOut(),
          fullPath: '/campaigns',
          location: '/campaigns',
        ),
        '/login',
      );
    });

    test('/login itself is allowed', () {
      expect(
        guards.evaluate(
          auth: const AuthSignedOut(),
          fullPath: '/login',
          location: '/login',
        ),
        isNull,
      );
    });
  });

  group('AuthRestoring', () {
    test('does NOT redirect', () {
      // Redirecting here is what would flash the login screen on every mobile
      // cold start and then bounce away from it.
      expect(
        guards.evaluate(
          auth: const AuthRestoring(),
          fullPath: '/campaigns',
          location: '/campaigns',
        ),
        isNull,
      );
    });
  });

  group('authenticated', () {
    test('an Authenticated route is allowed with no permissions', () {
      expect(
        guards.evaluate(
          auth: signedIn(),
          fullPath: '/campaigns',
          location: '/campaigns',
        ),
        isNull,
      );
    });

    test('signed-in user on /login goes home', () {
      expect(
        guards.evaluate(
          auth: signedIn(),
          fullPath: '/login',
          location: '/login',
        ),
        RouteGuards.homePath,
      );
    });

    test('a held permission allows the route', () {
      expect(
        guards.evaluate(
          auth: signedIn(permissions: {Permission.campaignCreate}),
          fullPath: '/campaigns/new',
          location: '/campaigns/new',
        ),
        isNull,
      );
    });

    test('a missing permission redirects to /forbidden', () {
      expect(
        guards.evaluate(
          auth: signedIn(),
          fullPath: '/campaigns/new',
          location: '/campaigns/new',
        ),
        '/forbidden',
      );
    });
  });

  group('parameterised routes resolve by template, not by location', () {
    test('two different ids both resolve to the same requirement', () {
      // Keying on the concrete location is why the old guard needed prefix
      // matching. Keying on the template makes matching exact.
      for (final id in ['CMP-1', 'CMP-2']) {
        expect(
          guards.evaluate(
            auth: signedIn(),
            fullPath: '/campaigns/:id/approve',
            location: '/campaigns/$id/approve',
          ),
          '/forbidden',
        );
        expect(
          guards.evaluate(
            auth: signedIn(permissions: {Permission.campaignApprove}),
            fullPath: '/campaigns/:id/approve',
            location: '/campaigns/$id/approve',
          ),
          isNull,
        );
      }
    });
  });

  group('unknown routes fail closed', () {
    test('a path absent from the table is forbidden, not allowed', () {
      // Failing open here would undo the whole exhaustiveness guarantee: an
      // unregistered path would be reachable by anyone signed in.
      expect(
        guards.evaluate(
          auth: signedIn(),
          fullPath: '/secret-admin',
          location: '/secret-admin',
        ),
        '/forbidden',
      );
    });
  });

  group('deep-link restoration', () {
    test('returns the intended destination when it is permitted', () {
      expect(
        redirectTargetAfterSignIn(
          signedIn(permissions: {Permission.verificationDecide}),
          '/verification',
        ),
        '/verification',
      );
    });

    test('falls back home when the intended destination is NOT permitted', () {
      // Restoring blindly would send the user from login straight to
      // /forbidden, which reads as a broken sign-in rather than an answer
      // about permissions.
      expect(
        redirectTargetAfterSignIn(signedIn(), '/verification'),
        RouteGuards.homePath,
      );
    });

    test('rejects an intended path that is not in the table', () {
      // On web this value is user-influenceable via the URL, so only paths
      // this app actually declares may be honoured.
      expect(
        redirectTargetAfterSignIn(signedIn(), 'https://evil.test/phish'),
        RouteGuards.homePath,
      );
      expect(
        redirectTargetAfterSignIn(signedIn(), '/not-a-route'),
        RouteGuards.homePath,
      );
    });

    test('falls back home when there is no intended destination', () {
      expect(redirectTargetAfterSignIn(signedIn(), null), RouteGuards.homePath);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/app/router/`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/app/router/route_table.dart'`.

- [ ] **Step 3: Write the route table**

Create `lib/app/router/route_table.dart`:

```dart
import '../../core/auth/rbac.dart';

/// What a route demands of the caller.
sealed class Access {
  const Access();
}

/// Reachable without a session (`/login`, `/forbidden`).
final class Public extends Access {
  const Public();
}

/// Any signed-in user.
final class Authenticated extends Access {
  const Authenticated();
}

/// A signed-in user holding [permission].
final class Requires extends Access {
  const Requires(this.permission);
  final Permission permission;
}

class RouteEntry {
  const RouteEntry(this.path, this.access);

  /// The route TEMPLATE as registered with GoRouter (e.g.
  /// `/campaigns/:id/approve`), matched against `GoRouterState.fullPath`.
  final String path;
  final Access access;
}

/// Paths registered only when `AppConfig.devRoutesEnabled`. They still carry an
/// [Access] so the exhaustiveness test can account for them in both builds.
const Set<String> devOnlyPaths = {'/dev', '/gallery'};

/// THE single source of truth for route access.
///
/// Both the router and [RouteGuards] read this list, so a route cannot exist
/// without an access decision - `route_table_test` asserts the registered set
/// and this table are identical. The previous design kept a separate
/// prefix-matching function, so a new route matched no prefix and shipped
/// ungated with nothing to notice.
const List<RouteEntry> routeTable = [
  RouteEntry('/login', Public()),
  RouteEntry('/forbidden', Public()),

  RouteEntry('/dev', Authenticated()),
  RouteEntry('/gallery', Authenticated()),

  RouteEntry('/', Authenticated()),

  RouteEntry('/campaigns', Authenticated()),
  RouteEntry('/campaigns/new', Requires(Permission.campaignCreate)),
  RouteEntry('/campaigns/:id', Authenticated()),
  RouteEntry('/campaigns/:id/approve', Requires(Permission.campaignApprove)),
  RouteEntry('/campaigns/:id/register', Requires(Permission.campaignCreate)),
  RouteEntry('/campaigns/:id/import', Requires(Permission.bulkImport)),

  RouteEntry('/verification', Requires(Permission.verificationDecide)),
  RouteEntry(
    '/verification/cases/:id',
    Requires(Permission.verificationDecide),
  ),

  RouteEntry('/search/:sessionId', Requires(Permission.attendanceCapture)),
  RouteEntry(
    '/capture/:sessionId/:carpenterId',
    Requires(Permission.attendanceCapture),
  ),
  RouteEntry('/queue', Requires(Permission.attendanceCapture)),

  RouteEntry('/analytics', Requires(Permission.export)),
];

final Map<String, Access> _byPath = {
  for (final e in routeTable) e.path: e.access,
};

/// Resolves the access rule for a route template. Null means the path is not
/// declared, which the guard treats as forbidden rather than allowed.
Access? accessFor(String? fullPath) =>
    fullPath == null ? null : _byPath[fullPath];
```

- [ ] **Step 4: Rewrite the guards**

Replace `lib/app/router/route_guards.dart` entirely:

```dart
import '../../core/auth/session_manager.dart';
import 'route_table.dart';

/// Pure guard logic (unit-testable, no Flutter imports). GoRouter's `redirect`
/// calls into these so role/scope is enforced BEFORE a route builds (§7).
class RouteGuards {
  const RouteGuards();

  static const String homePath = '/';
  static const String loginPath = '/login';
  static const String forbiddenPath = '/forbidden';

  /// Returns a redirect path, or null to allow.
  ///
  /// [fullPath] is the matched route TEMPLATE (`GoRouterState.fullPath`), not
  /// the concrete location: `/campaigns/:id/approve` cannot be compared to
  /// `/campaigns/CMP-1/approve` by equality, and matching on the template is
  /// what removes the need for prefix matching. [location] is carried only so
  /// an unauthenticated caller's intended destination can be preserved.
  String? evaluate({
    required AuthState auth,
    required String? fullPath,
    required String location,
    String? intended,
  }) {
    // Boot on a platform that persists tokens: the exchange is in flight and
    // we do not yet know whether there is a session. Redirecting now would
    // flash the login screen on every cold start.
    if (auth is AuthRestoring) return null;

    final access = accessFor(fullPath);

    if (access is Public) {
      // Already signed in and sitting on /login: go where they were headed.
      if (fullPath == loginPath && auth is AuthSignedIn) {
        return redirectTargetAfterSignIn(auth, intended);
      }
      return null;
    }

    if (auth is! AuthSignedIn) {
      if (fullPath == loginPath) return null;
      return loginPath;
    }

    // Undeclared route: fail CLOSED. Allowing it would undo the whole point of
    // the table, since an unregistered path would be reachable by anyone.
    if (access == null) return forbiddenPath;

    if (access is Requires && !auth.session.scope.can(access.permission)) {
      return forbiddenPath;
    }

    return null;
  }
}

/// Where to land after a successful sign-in.
///
/// The intended destination is re-checked rather than restored blindly:
/// sending a user who lacks the permission from login straight to /forbidden
/// reads as a broken sign-in rather than an answer about permissions. The value
/// is also validated against [routeTable] instead of being trusted as text,
/// because on web it is user-influenceable through the URL.
String? redirectTargetAfterSignIn(AuthState auth, String? intended) {
  if (auth is! AuthSignedIn || intended == null) return RouteGuards.homePath;

  final access = accessFor(intended);
  if (access == null) return RouteGuards.homePath;
  if (access is Requires && !auth.session.scope.can(access.permission)) {
    return RouteGuards.homePath;
  }
  return intended;
}
```

- [ ] **Step 5: Rewire the router**

In `lib/app/router/app_router.dart`: delete `_requiredPermission` entirely, add `import 'route_table.dart';`, change the redirect to pass `state.fullPath`, and expose the path set for the exhaustiveness test.

Replace the `redirect` callback with:

```dart
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      return guards.evaluate(
        auth: auth,
        fullPath: state.fullPath,
        location: state.matchedLocation,
        intended: state.uri.queryParameters['from'],
      );
    },
```

Append at the bottom of the file:

```dart
/// The route templates the router registers, for the exhaustiveness test in
/// `route_table_test.dart`. Kept beside the route definitions so the two
/// cannot drift: if a GoRoute is added here it must be listed here too, and
/// the test then demands a matching `routeTable` entry.
Set<String> registeredRoutePaths({required bool devRoutesEnabled}) => {
  '/login',
  '/forbidden',
  if (devRoutesEnabled) ...devOnlyPaths,
  '/',
  '/campaigns',
  '/campaigns/new',
  '/campaigns/:id',
  '/campaigns/:id/approve',
  '/campaigns/:id/register',
  '/campaigns/:id/import',
  '/verification',
  '/verification/cases/:id',
  '/search/:sessionId',
  '/capture/:sessionId/:carpenterId',
  '/queue',
  '/analytics',
};
```

`authStateProvider` does not exist yet — Task 9 creates it. For now add this temporary provider near the top of `app_router.dart` so the tree compiles, and delete it in Task 9:

```dart
// TEMPORARY (removed in the providers-wiring task): bridges the old
// authControllerProvider to the new AuthState shape.
final authStateProvider = Provider<AuthState>((ref) {
  final session = ref.watch(authControllerProvider);
  return session == null ? const AuthSignedOut() : AuthSignedIn(session);
});
```

Also replace `_AuthListenable`'s `ref.listen(authControllerProvider, …)` target with `authStateProvider`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/app/router/`

Expected: PASS, 8 route-table tests + 14 guard tests.

If the exhaustiveness test fails, the mismatch is real: reconcile `registeredRoutePaths` and `routeTable` against the actual `GoRoute` definitions rather than editing the test to agree.

- [ ] **Step 7: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **203 passing / 29 skipped**.

- [ ] **Step 8: Commit**

```bash
git add lib/app/router/ test/app/router/
git commit -m "feat: govern routes from one table, keyed on the route template

The guard previously prefix-matched the concrete location against a
function maintained separately from the route definitions, so a new route
matched no prefix and shipped ungated with nothing to notice. Access now
comes from one table that both the router and the guard read, keyed on
GoRouterState.fullPath so a parameterised template matches exactly. An
undeclared path fails closed. The exhaustiveness test asserts the
registered set equals the table, twice - with dev routes on and off."
```

---

## Task 6: Login screen and the mock-server auth endpoints

**Files:**
- Create: `lib/features/auth/presentation/login_screen.dart`
- Modify: `lib/core/design_system/bmd_field.dart` (add `obscureText`)
- Modify: `lib/core/auth/e2e_session.dart` (becomes the fake's fixture)
- Modify: `lib/app/router/app_router.dart` (route `/login` to the real screen)
- Modify: `tool/mock_server/bin/server.dart`
- Test: `test/widget/login_screen_test.dart`, plus one case appended to `test/design_system/design_system_test.dart`

**Interfaces:**
- Consumes: `SessionManager` (Task 4); `BmdButton({required String label, required VoidCallback? onPressed, BmdButtonVariant variant, IconData? icon, bool loading, String? identifier})`; `FailureKind`.
- `BmdField`'s **verified** default constructor is `BmdField({required String label, TextEditingController? controller, String? initialValue, String? helper, String? errorText, String? Function(String?)? validator, String? hint, TextInputType? keyboardType, bool enabled = true, bool required = false, int maxLines = 1, int minLines = 1, String? identifier, ValueChanged<String>? onChanged, Key? key})`. It has **no `obscureText` and no `onSubmitted`** — this task adds the former and does not use the latter.
- Produces: `class LoginScreen extends ConsumerStatefulWidget`; `String loginErrorMessage(Failure)` exported from the same file; `class FakeAuthService implements AuthService` in `lib/core/auth/e2e_session.dart` — `FakeAuthService(String role)`; `BmdField` gains `bool obscureText`.

- [ ] **Step 1: Write the failing test**

Create `test/widget/login_screen_test.dart`:

```dart
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/features/auth/presentation/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('loginErrorMessage', () {
    test('401 does not reveal WHICH field was wrong', () {
      // Distinguishing "no such user" from "wrong password" is a username
      // enumeration oracle.
      final message = loginErrorMessage(
        const Failure(FailureKind.unauthorized),
      );

      expect(message, 'That username or password is not correct.');
      expect(message.toLowerCase(), isNot(contains('user does not')));
      expect(message.toLowerCase(), isNot(contains('no such')));
    });

    test('403 explains the account is not enabled', () {
      expect(
        loginErrorMessage(const Failure(FailureKind.forbidden)),
        'This account is not enabled for this app.',
      );
    });

    test('network and timeout both point at connectivity', () {
      for (final kind in [FailureKind.network, FailureKind.timeout]) {
        expect(
          loginErrorMessage(Failure(kind)),
          'Cannot reach the sign-in service. Check your connection and try again.',
        );
      }
    });

    test('server failure is distinct from a connectivity failure', () {
      expect(
        loginErrorMessage(const Failure(FailureKind.server)),
        'The sign-in service is having trouble. Try again shortly.',
      );
    });

    test('a validation failure surfaces the claim mismatch verbatim', () {
      // scope_claims names the unrecognised claims; that detail is what makes
      // a version mismatch diagnosable, so it must not be swallowed.
      final message = loginErrorMessage(
        const Failure(
          FailureKind.validation,
          message: 'This account has claims this app version does not '
              'recognise: role "galactic_overlord".',
        ),
      );

      expect(message, contains('galactic_overlord'));
    });

    test('every FailureKind maps to a non-empty, non-generic message', () {
      // Guideline 2.1 forbids a generic "something went wrong" anywhere.
      for (final kind in FailureKind.values) {
        final message = loginErrorMessage(Failure(kind));
        expect(message, isNotEmpty, reason: '$kind has no message');
        expect(
          message.toLowerCase(),
          isNot(contains('something went wrong')),
          reason: '$kind falls back to a generic message',
        );
      }
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widget/login_screen_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/features/auth/presentation/login_screen.dart'`.

- [ ] **Step 3: Add `obscureText` to `BmdField`**

A password field needs masked entry, and `BmdField` has no such parameter — its existing `BmdField.masked` is for *revealing* a stored value like an NID suffix, not for typing a secret. The alternative is a raw `TextField` on the login screen, which reintroduces exactly the pattern P0.2 eliminated across 11 call sites when it made `BmdField` the single renderer. So add the parameter rather than bypass the component.

In `lib/core/design_system/bmd_field.dart`, add `this.obscureText = false,` to the **default** constructor's parameter list only, and set `obscureText = false` in the initializer list of the other three constructors (`.multiline`, `.masked`, and the search variant if it shares the field). Declare it beside `enabled`:

```dart
  /// Masks typed input (passwords). Distinct from [BmdField.masked], which
  /// reveals a stored value on demand rather than hiding what is being typed.
  final bool obscureText;
```

and pass it into the `TextFormField` at line ~136:

```dart
      obscureText: obscureText,
```

Append this case to `test/design_system/design_system_test.dart`:

```dart
  testWidgets('BmdField.obscureText masks typed input', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BmdField(label: 'Password', obscureText: true),
        ),
      ),
    );

    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.obscureText, isTrue);
  });
```

Add whatever imports that file needs for `BmdField` and `TextFormField` if they are not already present.

- [ ] **Step 4: Write the login screen**

Create `lib/features/auth/presentation/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_field.dart';
import '../../../core/result/result.dart';

/// Maps a sign-in [Failure] to a correction-first message (Guideline §2.1).
///
/// Never returns a generic message: every kind is named explicitly, and the
/// exhaustive switch means a new [FailureKind] is a compile error here rather
/// than a silent fallback to "something went wrong".
String loginErrorMessage(Failure failure) => switch (failure.kind) {
  // Deliberately does NOT say which of the two was wrong: doing so is a
  // username-enumeration oracle.
  FailureKind.unauthorized => 'That username or password is not correct.',
  FailureKind.forbidden => 'This account is not enabled for this app.',
  FailureKind.network ||
  FailureKind.timeout ||
  FailureKind.offlineQueued =>
    'Cannot reach the sign-in service. Check your connection and try again.',
  FailureKind.server => 'The sign-in service is having trouble. Try again shortly.',
  // scope_claims names the unrecognised claims, and that detail is what makes
  // a client/server version mismatch diagnosable.
  FailureKind.validation =>
    failure.message ?? 'This account has details this app cannot read.',
  FailureKind.notFound => 'The sign-in service could not be found. Check the app configuration.',
  FailureKind.conflict => 'Another sign-in is already in progress. Try again.',
  FailureKind.unknown => 'Sign-in could not be completed. Try again.',
};

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter both your username and password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(sessionManagerProvider)
        .signIn(username, password);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.fold((_) => null, loginErrorMessage);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sign in',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                BmdField(
                  label: 'Username',
                  controller: _username,
                  identifier: 'login_username',
                ),
                const SizedBox(height: 16),
                BmdField(
                  label: 'Password',
                  controller: _password,
                  obscureText: true,
                  identifier: 'login_password',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                BmdButton(
                  label: 'Sign in',
                  loading: _busy,
                  identifier: 'login_submit',
                  onPressed: _busy ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

There is deliberately **no submit-on-enter**: `BmdField` exposes no `onSubmitted`, and adding a second parameter to a shared design-system component for one screen's convenience is not worth it. The user presses the button.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/widget/login_screen_test.dart test/design_system/design_system_test.dart`

Expected: PASS — 6 login tests, and the existing design-system suite plus the new `obscureText` case.

- [ ] **Step 6: Convert the E2E session into a fake `AuthService`**

Rewrite `lib/core/auth/e2e_session.dart` so E2E exercises the real lifecycle against a scripted transport rather than bypassing it:

```dart
import '../result/result.dart';
import 'auth_service.dart';
import 'rbac.dart';
import 'scope_claims.dart';

/// [AuthService] that mints a valid token pair for a named role, for E2E runs
/// and the dev launcher. Test-only: reachable only when `AppConfig.e2e` is true
/// (see TESTING_MAESTRO.md §3.2).
///
/// Deliberately an AuthService rather than a pre-built Session: E2E then drives
/// the same SessionManager path production does, instead of skipping it.
class FakeAuthService implements AuthService {
  FakeAuthService(this.role);

  final String role;

  @override
  Future<Result<AuthTokens>> login(String username, String password) async =>
      Ok(_tokens());

  @override
  Future<Result<AuthTokens>> refresh(String refreshToken) async =>
      Ok(_tokens());

  @override
  Future<Result<void>> logout(String refreshToken) async => const Ok(null);

  AuthTokens _tokens() {
    final appRole = switch (role) {
      'crm_verifier' => AppRole.crmVerifier,
      'campaign_creator' => AppRole.campaignCreator,
      'admin' => AppRole.admin,
      _ => AppRole.fieldUser,
    };

    final permissions = switch (appRole) {
      AppRole.fieldUser => {Permission.attendanceCapture},
      AppRole.crmVerifier => {
        Permission.verificationDecide,
        Permission.sensitiveMediaView,
      },
      AppRole.campaignCreator => {
        Permission.campaignCreate,
        Permission.bulkImport,
        Permission.export,
      },
      AppRole.admin => Permission.values.toSet(),
      _ => <Permission>{},
    };

    return AuthTokens(
      accessToken: 'e2e-token',
      refreshToken: 'e2e-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 12)),
      claims: {
        'userId': 'e2e-$role',
        'displayName': 'E2E $role',
        'organizationId': 'ORG_E2E',
        'roles': [wireNameForRole(appRole)],
        'permissions': [
          for (final p in permissions) wireNameForPermission(p),
        ],
        'territoryIds': <String>[],
      },
    );
  }
}
```

- [ ] **Step 7: Route `/login` to the real screen**

In `lib/app/router/app_router.dart`, replace the `/login` route's builder with `(_, __) => const LoginScreen()` and add the import. Leave `/forbidden` as its placeholder — a designed permission-denied screen is T-4.2's work.

- [ ] **Step 8: Add the mock-server auth endpoints**

In `tool/mock_server/bin/server.dart`, add before the closing of `_buildRouter`:

```dart
  // ---- Auth (🔒 contract-pending shapes) ----------------------------------
  // Role is taken from the username so E2E can sign in as each role:
  // "crm_verifier", "campaign_creator", "admin", anything else -> field user.
  r.post('/auth/login', (Request req) async {
    final body = await _body(req);
    final username = (body['username'] as String?) ?? 'field_user';
    final password = (body['password'] as String?) ?? '';
    if (password.isEmpty) {
      return _json({'error': 'invalid credentials'}, status: 401);
    }
    return _json(_authPayload(username));
  });

  r.post('/auth/refresh', (Request req) async {
    final body = await _body(req);
    final token = (body['refreshToken'] as String?) ?? '';
    if (token.isEmpty || token == 'expired') {
      return _json({'error': 'invalid refresh token'}, status: 401);
    }
    // Rotate: a new refresh token each time, so the client's single-flight
    // guard is exercised against realistic rotation.
    return _json(_authPayload(token.replaceFirst('refresh-for-', '')));
  });

  r.post('/auth/logout', (Request req) async {
    await _body(req);
    return Response(204);
  });
```

And add this helper beside `_json`:

```dart
Map<String, dynamic> _authPayload(String username) {
  final roles = <String, List<String>>{
    'crm_verifier': ['verification_decide', 'sensitive_media_view'],
    'campaign_creator': ['campaign_create', 'bulk_import', 'export'],
    'admin': [
      'campaign_create',
      'campaign_approve',
      'campaign_cancel',
      'bulk_import',
      'attendance_capture',
      'verification_decide',
      'verification_override',
      'sensitive_media_view',
      'nid_reveal',
      'config_manage',
      'export',
    ],
  };
  final role = roles.containsKey(username) ? username : 'field_user';
  return {
    'accessToken': 'mock-access-$role',
    'refreshToken': 'refresh-for-$role',
    'expiresInSeconds': 900,
    'claims': {
      'userId': 'mock-$role',
      'displayName': 'Mock $role',
      'organizationId': 'ORG_MOCK',
      'roles': [role],
      'permissions': roles[role] ?? ['attendance_capture'],
      'territoryIds': <String>[],
    },
  };
}
```

- [ ] **Step 9: Check the mock server compiles**

Run: `cd tool/mock_server && dart pub get && dart analyze && cd ../..`

Expected: no issues. (`tool/**` is excluded from the app's `analysis_options.yaml`, so it must be checked separately.)

- [ ] **Step 10: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **210 passing / 29 skipped** (209 from this task's 6 login tests plus the 1 new `obscureText` case). `providers.dart` still references the old `AuthController`; `sessionManagerProvider` arrives in Task 9. If the login screen cannot compile because that provider does not exist yet, add it to `providers.dart` now as part of this task:

```dart
final authServiceProvider = Provider<AuthService>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.e2e) return FakeAuthService(config.e2eRole);
  return DioAuthService(ref.watch(dioProvider));
});

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => createTokenStore(ref.watch(secureStoreProvider)),
);

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(
    service: ref.watch(authServiceProvider),
    tokens: ref.watch(tokenStoreProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});
```

- [ ] **Step 11: Commit**

```bash
git add lib/features/auth/ lib/core/auth/e2e_session.dart lib/core/design_system/bmd_field.dart lib/app/ test/widget/login_screen_test.dart test/design_system/design_system_test.dart tool/mock_server/bin/server.dart
git commit -m "feat: add a real sign-in screen and mock auth endpoints

A 401 message deliberately does not say which of username or password was
wrong, since distinguishing them is an enumeration oracle. Every
FailureKind maps to a specific correction-first message through an
exhaustive switch, so a new kind is a compile error rather than a silent
fall back to a generic error.

E2E now signs in through a FakeAuthService instead of a pre-built Session,
so it drives the same SessionManager path production does. The mock server
rotates refresh tokens, which exercises the single-flight guard against
realistic rotation."
```

---

## Task 7: `PermissionGate`

**Files:**
- Create: `lib/core/auth/permission_gate.dart`
- Test: `test/core/auth/permission_gate_test.dart`

**Interfaces:**
- Consumes: `Permission`, `AccessScope`; `AuthState`/`AuthSignedIn` (Task 4); `authStateProvider` (Task 5's temporary provider, promoted in Task 9).
- Produces: `class PermissionGate extends ConsumerWidget` with `const PermissionGate.hidden(this.permission, {required this.child, super.key}) : reason = null, _mode = _GateMode.hidden` and `const PermissionGate.disabled(this.permission, {required this.reason, required this.child, super.key}) : _mode = _GateMode.disabled`.

- [ ] **Step 1: Write the failing test**

Create `test/core/auth/permission_gate_test.dart`:

```dart
import 'package:acsl_campaign/app/router/app_router.dart';
import 'package:acsl_campaign/core/auth/permission_gate.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AuthState signedIn(Set<Permission> permissions) => AuthSignedIn(
    Session(
      userId: 'u-1',
      displayName: 'Test User',
      scope: AccessScope(
        roles: const {AppRole.fieldUser},
        permissions: permissions,
        organizationId: 'ORG_1',
      ),
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  Future<void> pump(
    WidgetTester tester, {
    required AuthState auth,
    required Widget child,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => auth)],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );

  group('PermissionGate.hidden', () {
    testWidgets('renders the child when the permission is held', (tester) async {
      await pump(
        tester,
        auth: signedIn({Permission.export}),
        child: const PermissionGate.hidden(
          Permission.export,
          child: Text('Analytics'),
        ),
      );

      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('renders NOTHING when the permission is missing', (tester) async {
      await pump(
        tester,
        auth: signedIn(const {}),
        child: const PermissionGate.hidden(
          Permission.export,
          child: Text('Analytics'),
        ),
      );

      expect(find.text('Analytics'), findsNothing);
    });

    testWidgets('renders nothing when signed out', (tester) async {
      await pump(
        tester,
        auth: const AuthSignedOut(),
        child: const PermissionGate.hidden(
          Permission.export,
          child: Text('Analytics'),
        ),
      );

      expect(find.text('Analytics'), findsNothing);
    });
  });

  group('PermissionGate.disabled', () {
    testWidgets('renders the child untouched when the permission is held', (
      tester,
    ) async {
      var tapped = false;
      await pump(
        tester,
        auth: signedIn({Permission.campaignApprove}),
        child: PermissionGate.disabled(
          Permission.campaignApprove,
          reason: 'Only a Campaign Approver can approve this campaign.',
          child: ElevatedButton(
            onPressed: () => tapped = true,
            child: const Text('Approve'),
          ),
        ),
      );

      await tester.tap(find.text('Approve'));
      expect(tapped, isTrue);
    });

    testWidgets('keeps the child VISIBLE but blocks interaction', (tester) async {
      // Visible-but-disabled is the whole point: a missing button leaves the
      // user unable to tell permission from lifecycle state from bug.
      var tapped = false;
      await pump(
        tester,
        auth: signedIn(const {}),
        child: PermissionGate.disabled(
          Permission.campaignApprove,
          reason: 'Only a Campaign Approver can approve this campaign.',
          child: ElevatedButton(
            onPressed: () => tapped = true,
            child: const Text('Approve'),
          ),
        ),
      );

      expect(find.text('Approve'), findsOneWidget);
      await tester.tap(find.text('Approve'), warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('exposes the reason to a screen reader, not just a tooltip', (
      tester,
    ) async {
      // T-3.4.1's accessibility gate checks this: a mouse-only explanation is
      // no explanation for a keyboard or screen-reader user.
      const reason = 'Only a Campaign Approver can approve this campaign.';
      await pump(
        tester,
        auth: signedIn(const {}),
        child: const PermissionGate.disabled(
          Permission.campaignApprove,
          reason: reason,
          child: Text('Approve'),
        ),
      );

      final semantics = tester.getSemantics(find.text('Approve'));
      expect(semantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((s) => s.properties.label?.contains(reason) ?? false),
        isTrue,
        reason: 'the denial reason must reach the semantics tree',
      );
    });
  });
}
```

Add `import 'package:flutter/semantics.dart';` to that test's imports for `SemanticsFlag`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/auth/permission_gate_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/core/auth/permission_gate.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/auth/permission_gate.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_router.dart';
import 'rbac.dart';
import 'session_manager.dart';

enum _GateMode { hidden, disabled }

/// Gates a widget on a [Permission].
///
/// Two modes, chosen per call site because the right answer differs by
/// context:
///
///  * [PermissionGate.hidden] for whole surfaces the user has no business
///    knowing about. A disabled "Analytics" nav item is noise and leaks how
///    the organization is structured.
///  * [PermissionGate.disabled] for an action on a record the user is already
///    looking at. A missing Approve button leaves them unable to tell a
///    permission problem from a lifecycle-state problem from a bug - and
///    leaves support unable to either.
///
/// Client-side gating drives UX only; the server re-checks every call.
class PermissionGate extends ConsumerWidget {
  const PermissionGate.hidden(this.permission, {required this.child, super.key})
    : reason = null,
      _mode = _GateMode.hidden;

  const PermissionGate.disabled(
    this.permission, {
    required this.reason,
    required this.child,
    super.key,
  }) : _mode = _GateMode.disabled;

  final Permission permission;
  final Widget child;

  /// Why the action is unavailable. Reaches the semantics tree, not only a
  /// hover tooltip.
  final String? reason;

  final _GateMode _mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final allowed = switch (auth) {
      AuthSignedIn(:final session) => session.scope.can(permission),
      _ => false,
    };

    if (allowed) return child;

    return switch (_mode) {
      _GateMode.hidden => const SizedBox.shrink(),
      _GateMode.disabled => Tooltip(
        message: reason!,
        child: Semantics(
          label: reason,
          enabled: false,
          container: true,
          child: ExcludeFocus(
            // IgnorePointer blocks interaction without changing layout, so the
            // affordance stays exactly where the user expects to find it.
            child: IgnorePointer(
              child: Opacity(opacity: 0.38, child: child),
            ),
          ),
        ),
      ),
    };
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/auth/permission_gate_test.dart`

Expected: PASS, 6 tests. If the semantics assertion fails on how `Semantics(enabled: false)` merges, inspect the tree with `tester.getSemantics` and adjust the *widget* so the flag and label are genuinely present — do not weaken the assertion, since it is what T-3.4.1 will check.

- [ ] **Step 5: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **216 passing / 29 skipped**.

- [ ] **Step 6: Commit**

```bash
git add lib/core/auth/permission_gate.dart test/core/auth/permission_gate_test.dart
git commit -m "feat: gate widgets on permissions, hidden or disabled per site

Hidden for whole surfaces the user has no business knowing about, since a
disabled nav item is noise and leaks org structure. Disabled with a reason
for an action on a record they are already looking at, because a missing
button leaves them unable to tell permission from lifecycle state from
bug. The reason reaches the semantics tree rather than only a hover
tooltip, which is what the T-3.4.1 accessibility gate checks."
```

---

## Task 8: `AppShell` and the 8 screen migrations

**Files:**
- Create: `lib/app/shell/nav_destinations.dart`
- Create: `lib/app/shell/app_shell.dart`
- Modify: `lib/core/responsive/adaptive_scaffold.dart`
- Modify: all 8 `AdaptiveScaffold` callers (listed in File Structure)
- Modify: `test/widget/crm_case_screen_test.dart`, `test/widget/bulk_import_screen_test.dart`
- Test: `test/app/shell/app_shell_test.dart`

**Interfaces:**
- Consumes: `Breakpoint.of(BuildContext)` / `isMobile` / `isDesktopUp` and `ContentConstraints.maxWorkingWidth` / `gutter(Breakpoint)` from `lib/core/responsive/breakpoints.dart`; `Permission`; `authStateProvider`.
- Produces:
  - `class NavDestinationSpec` — `const NavDestinationSpec({required String path, required String label, required IconData icon, Permission? permission})`.
  - `const List<NavDestinationSpec> allNavDestinations`.
  - `List<NavDestinationSpec> visibleDestinations(AuthState)`.
  - `int? selectedIndexFor(List<NavDestinationSpec>, String location)`.
  - `class AppShell extends ConsumerWidget` — `const AppShell({required String title, required Widget body, List<Widget> actions = const [], List<String> breadcrumb = const [], super.key})`.
  - `AdaptiveScaffold` signature becomes `const AdaptiveScaffold({required String title, required Widget body, List<Widget> actions = const [], List<NavDestinationSpec> destinations = const [], int? selectedIndex, ValueChanged<int>? onDestinationSelected, Widget? leadingAction, super.key})` — **`selectedIndex` becomes nullable and is no longer passed by screens.**

- [ ] **Step 1: Write the failing test**

Create `test/app/shell/app_shell_test.dart`:

```dart
import 'package:acsl_campaign/app/router/app_router.dart';
import 'package:acsl_campaign/app/shell/app_shell.dart';
import 'package:acsl_campaign/app/shell/nav_destinations.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AuthState signedIn(Set<Permission> permissions) => AuthSignedIn(
    Session(
      userId: 'u-1',
      displayName: 'Rina Akter',
      scope: AccessScope(
        roles: const {AppRole.fieldUser},
        permissions: permissions,
        organizationId: 'ORG_1',
      ),
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  group('visibleDestinations', () {
    test('a field user sees only what they hold', () {
      // The old shell showed all four web surfaces to everyone, every one of
      // which the route guard then bounced to /forbidden.
      final visible = visibleDestinations(
        signedIn({Permission.attendanceCapture}),
      );

      expect(visible.map((d) => d.label), isNot(contains('Analytics')));
      expect(visible.map((d) => d.label), isNot(contains('Verification')));
    });

    test('an admin sees every destination', () {
      final visible = visibleDestinations(
        signedIn(Permission.values.toSet()),
      );

      expect(visible.length, allNavDestinations.length);
    });

    test('signed out yields no destinations', () {
      expect(visibleDestinations(const AuthSignedOut()), isEmpty);
    });

    test('a destination with no permission requirement is always visible', () {
      final visible = visibleDestinations(signedIn(const {}));

      expect(
        visible.map((d) => d.path),
        contains(allNavDestinations.first.path),
      );
    });
  });

  group('selectedIndexFor', () {
    const destinations = [
      NavDestinationSpec(path: '/', label: 'Dashboard', icon: Icons.home),
      NavDestinationSpec(
        path: '/campaigns',
        label: 'Campaigns',
        icon: Icons.campaign,
      ),
    ];

    test('matches a nested location to its section', () {
      // Selection must be derived, not passed: filtering shifts indices per
      // user, so a hardcoded 2 can point at the wrong item or off the end.
      expect(selectedIndexFor(destinations, '/campaigns/CMP-1/approve'), 1);
    });

    test('matches the root exactly, not as a prefix of everything', () {
      expect(selectedIndexFor(destinations, '/'), 0);
      expect(selectedIndexFor(destinations, '/campaigns'), 1);
    });

    test('returns null for a location outside every section', () {
      expect(selectedIndexFor(destinations, '/queue'), isNull);
    });

    test('prefers the longest matching path', () {
      const nested = [
        NavDestinationSpec(path: '/', label: 'Home', icon: Icons.home),
        NavDestinationSpec(path: '/a', label: 'A', icon: Icons.abc),
        NavDestinationSpec(path: '/a/b', label: 'AB', icon: Icons.abc),
      ];

      expect(selectedIndexFor(nested, '/a/b/c'), 2);
    });
  });

  group('AppShell', () {
    Future<void> pump(
      WidgetTester tester, {
      required AuthState auth,
      Size size = const Size(1440, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authStateProvider.overrideWith((ref) => auth)],
          child: const MaterialApp(
            home: AppShell(title: 'Campaigns', body: Text('BODY')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the body and the title', (tester) async {
      await pump(tester, auth: signedIn(Permission.values.toSet()));

      expect(find.text('BODY'), findsOneWidget);
      expect(find.text('Campaigns'), findsWidgets);
    });

    testWidgets('shows the signed-in display name in the account menu', (
      tester,
    ) async {
      await pump(tester, auth: signedIn(Permission.values.toSet()));

      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Rina Akter'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('a field user does not see the Analytics destination', (
      tester,
    ) async {
      await pump(tester, auth: signedIn({Permission.attendanceCapture}));

      expect(find.text('Analytics'), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/app/shell/app_shell_test.dart`

Expected: FAIL at compile time — `Target of URI doesn't exist: 'package:acsl_campaign/app/shell/nav_destinations.dart'`.

- [ ] **Step 3: Write the destinations**

Create `lib/app/shell/nav_destinations.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/auth/rbac.dart';
import '../../core/auth/session_manager.dart';

/// A top-level navigation target.
class NavDestinationSpec {
  const NavDestinationSpec({
    required this.path,
    required this.label,
    required this.icon,
    this.permission,
  });

  final String path;
  final String label;
  final IconData icon;

  /// Null means every signed-in user sees it.
  final Permission? permission;
}

/// Every possible destination. What a given user sees is the filtered subset -
/// see [visibleDestinations].
const List<NavDestinationSpec> allNavDestinations = [
  NavDestinationSpec(
    path: '/',
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
  ),
  NavDestinationSpec(
    path: '/campaigns',
    label: 'Campaigns',
    icon: Icons.campaign_outlined,
  ),
  NavDestinationSpec(
    path: '/verification',
    label: 'Verification',
    icon: Icons.how_to_reg_outlined,
    permission: Permission.verificationDecide,
  ),
  NavDestinationSpec(
    path: '/queue',
    label: 'Queue',
    icon: Icons.cloud_upload_outlined,
    permission: Permission.attendanceCapture,
  ),
  NavDestinationSpec(
    path: '/analytics',
    label: 'Analytics',
    icon: Icons.insights_outlined,
    permission: Permission.export,
  ),
];

/// The destinations this user may actually reach.
///
/// Filtering matters because the previous shell offered all four web surfaces
/// to everyone, and the route guard then bounced a field user out of every one
/// of them - the shell advertised what the guard forbade.
List<NavDestinationSpec> visibleDestinations(AuthState auth) =>
    switch (auth) {
      AuthSignedIn(:final session) => [
        for (final d in allNavDestinations)
          if (d.permission == null || session.scope.can(d.permission!)) d,
      ],
      _ => const [],
    };

/// Which destination owns [location].
///
/// Derived rather than passed: filtering shifts indices per user, so a
/// hardcoded index can highlight the wrong item or point past the end of the
/// list. Longest match wins so a nested section beats its parent, and `/` only
/// matches itself rather than prefixing everything.
int? selectedIndexFor(
  List<NavDestinationSpec> destinations,
  String location,
) {
  var bestIndex = -1;
  var bestLength = -1;
  for (var i = 0; i < destinations.length; i++) {
    final path = destinations[i].path;
    final matches = path == '/'
        ? location == '/'
        : location == path || location.startsWith('$path/');
    if (matches && path.length > bestLength) {
      bestIndex = i;
      bestLength = path.length;
    }
  }
  return bestIndex == -1 ? null : bestIndex;
}
```

- [ ] **Step 4: Make `AdaptiveScaffold` take its destinations**

In `lib/core/responsive/adaptive_scaffold.dart`: delete the `static const _destinations` list, add `import '../../app/shell/nav_destinations.dart';`, and change the constructor and usages so `destinations` is a parameter, `selectedIndex` is `int?`, and a `leadingAction` slot exists for the account menu.

```dart
  const AdaptiveScaffold({
    required this.title,
    required this.body,
    this.actions = const [],
    this.destinations = const [],
    this.selectedIndex,
    this.onDestinationSelected,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final List<NavDestinationSpec> destinations;

  /// Null when the current location belongs to no destination (a detail screen
  /// reached from elsewhere). Material requires a valid index when it renders
  /// a selection, so the nav is omitted entirely rather than guessing.
  final int? selectedIndex;

  final ValueChanged<int>? onDestinationSelected;
```

In `build`, render the `NavigationBar` / `NavigationRail` only when `destinations.length >= 2 && selectedIndex != null`, using `destinations` for the items. A single destination is not navigation, and a null index has nothing to highlight.

- [ ] **Step 5: Write `AppShell`**

Create `lib/app/shell/app_shell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_manager.dart';
import '../../core/responsive/adaptive_scaffold.dart';
import '../di/providers.dart';
import '../router/app_router.dart';
import 'nav_destinations.dart';

/// The session-aware app shell (§3.3).
///
/// Wraps [AdaptiveScaffold]'s pure responsive layout with everything that
/// depends on who is signed in: permission-filtered destinations, the
/// breadcrumb, a notifications slot, and the account menu with sign-out.
class AppShell extends ConsumerWidget {
  const AppShell({
    required this.title,
    required this.body,
    this.actions = const [],
    this.breadcrumb = const [],
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;

  /// Ancestor labels, outermost first. The current screen is [title] and is
  /// not repeated here.
  final List<String> breadcrumb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final destinations = visibleDestinations(auth);
    final location = GoRouterState.of(context).matchedLocation;

    return AdaptiveScaffold(
      title: title,
      destinations: destinations,
      selectedIndex: selectedIndexFor(destinations, location),
      onDestinationSelected: (i) => context.go(destinations[i].path),
      actions: [
        ...actions,
        // Notifications slot (§3.3). Wired to a real feed by a later epic; the
        // slot exists now so the shell's geometry is settled.
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none),
          onPressed: null,
        ),
        _AccountMenu(auth: auth),
      ],
      body: breadcrumb.isEmpty
          ? body
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Breadcrumb(trail: breadcrumb, current: title),
                const SizedBox(height: 8),
                Expanded(child: body),
              ],
            ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.trail, required this.current});

  final List<String> trail;
  final String current;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Semantics(
      label: 'Breadcrumb: ${[...trail, current].join(', ')}',
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final label in trail) ...[
            Text(label, style: style),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right, size: 14, color: style?.color),
            ),
          ],
          Text(current, style: style?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = switch (auth) {
      AuthSignedIn(:final session) => session.displayName,
      _ => null,
    };
    if (name == null) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (value) async {
        if (value == 'signOut') {
          await ref.read(sessionManagerProvider).signOut();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(enabled: false, child: Text(name)),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'signOut', child: Text('Sign out')),
      ],
    );
  }
}
```

- [ ] **Step 6: Run the shell test to verify it passes**

Run: `flutter test test/app/shell/app_shell_test.dart`

Expected: PASS, 11 tests.

- [ ] **Step 7: Migrate all 8 callers**

For each of the 8 files listed in File Structure: replace `AdaptiveScaffold(` with `AppShell(`, **delete the `selectedIndex:` line** (7 of the 8 have one), and add `import '../../../app/shell/app_shell.dart';` (adjust the relative depth — `placeholder_screen.dart` is at `lib/core/design_system/`, so it needs `../../app/shell/app_shell.dart`). Remove the now-unused `adaptive_scaffold.dart` import from each.

Add breadcrumbs where the hierarchy is real, e.g. in `campaign_approval_screen.dart`:

```dart
    return AppShell(
      title: 'Approve campaign',
      breadcrumb: const ['Campaigns'],
```

and in `bulk_import_screen.dart`, `registration_workspace_screen.dart` and `campaign_wizard_screen.dart` likewise (`const ['Campaigns']`). Leave `campaign_list_screen.dart`, `crm_case_screen.dart`, `campaign_detail_screen.dart` and `placeholder_screen.dart` without one.

- [ ] **Step 8: Fix the two widget tests**

Both `test/widget/crm_case_screen_test.dart` and `test/widget/bulk_import_screen_test.dart` now render an `AppShell`, which reads `authStateProvider` and `GoRouterState`. Add an `authStateProvider` override to each `ProviderScope` (a signed-in state holding the permissions that screen needs), and wrap the widget under test in a minimal `MaterialApp.router` so `GoRouterState.of` resolves.

Do **not** weaken any existing assertion — these two tests are the only widget coverage of screens this task touches. If a test fails for a reason other than the shell wiring, stop and report it.

- [ ] **Step 9: Verify nothing regressed**

Run: `dart format --set-exit-if-changed . && flutter analyze --fatal-infos && flutter test`

Expected: **227 passing / 29 skipped**. Confirm the skip count is still exactly 29 — a golden that starts failing here means the shell changed the gallery's rendering.

- [ ] **Step 10: Commit**

```bash
git add lib/app/shell/ lib/core/responsive/adaptive_scaffold.dart lib/core/design_system/placeholder_screen.dart lib/features/ test/app/shell/ test/widget/
git commit -m "feat: make the app shell navigable and permission-aware

The nav was inert: no caller passed onDestinationSelected, so clicking a
destination did nothing, while 7 of 8 callers passed selectedIndex so the
right item still highlighted. Destinations were also hardcoded and
unfiltered, offering a field user four surfaces the route guard then
bounced them out of.

AppShell now owns the session-aware parts - filtered destinations,
breadcrumb, notifications slot, account menu with sign-out - and
AdaptiveScaffold keeps only responsive layout. Selection is derived from
the location, because filtering shifts indices per user and a hardcoded
index can point past the end of the list."
```

---

## Task 9: Wire the composition root and close the epic

**Files:**
- Modify: `lib/app/di/providers.dart`
- Modify: `lib/app/router/app_router.dart` (promote `authStateProvider`, delete the temporary bridge)
- Modify: `lib/main.dart`
- Modify: `lib/core/network/auth_interceptor.dart` usage in `providers.dart`
- Modify: `TASK_BREAKDOWN.md`
- Test: `test/app/auth_wiring_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: `authServiceProvider`, `tokenStoreProvider`, `sessionManagerProvider`, `authStateProvider` (promoted to `providers.dart`); `AuthController` and `authControllerProvider` are **deleted**.

- [ ] **Step 1: Write the failing test**

Create `test/app/auth_wiring_test.dart`:

```dart
import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';

void main() {
  test('authStateProvider reflects the SessionManager', () async {
    final service = ScriptedAuthService();
    final tokens = FakeTokenStore();
    final manager = SessionManager(service: service, tokens: tokens);
    addTearDown(manager.dispose);

    final container = ProviderContainer(
      overrides: [sessionManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);

    expect(container.read(authStateProvider), isA<AuthSignedOut>());

    await manager.signIn('bob', 'pw');
    // Let the broadcast stream deliver to the provider's listener.
    await pumpEventQueue();

    expect(container.read(authStateProvider), isA<AuthSignedIn>());
  });

  test('signing out returns authStateProvider to signed out', () async {
    final manager = SessionManager(
      service: ScriptedAuthService(),
      tokens: FakeTokenStore(),
    );
    addTearDown(manager.dispose);

    final container = ProviderContainer(
      overrides: [sessionManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);

    await manager.signIn('bob', 'pw');
    await pumpEventQueue();
    await manager.signOut();
    await pumpEventQueue();

    expect(container.read(authStateProvider), isA<AuthSignedOut>());
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/app/auth_wiring_test.dart`

Expected: FAIL — `authStateProvider` is not exported from `providers.dart` (it currently lives in `app_router.dart` as a temporary bridge).

- [ ] **Step 3: Rewire `providers.dart`**

Delete `AuthController` and `authControllerProvider` entirely. Add the four providers (moving `authStateProvider` here from `app_router.dart`):

```dart
final authServiceProvider = Provider<AuthService>((ref) {
  final config = ref.watch(appConfigProvider);
  // E2E signs in through a fake transport rather than skipping the lifecycle,
  // so Maestro exercises the same SessionManager path production does.
  if (config.e2e) return FakeAuthService(config.e2eRole);
  return DioAuthService(ref.watch(dioProvider));
});

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => createTokenStore(ref.watch(secureStoreProvider)),
);

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(
    service: ref.watch(authServiceProvider),
    tokens: ref.watch(tokenStoreProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// The router, the shell and every PermissionGate watch this.
final authStateProvider = Provider<AuthState>((ref) {
  final manager = ref.watch(sessionManagerProvider);
  final sub = manager.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return manager.state;
});
```

Then update `dioProvider`'s interceptor so the throwing seam is gone:

```dart
  final interceptor = AuthInterceptor(
    readAccessToken: () => switch (ref.read(authStateProvider)) {
      AuthSignedIn(:final session) => session.accessToken,
      _ => null,
    },
    refreshToken: () => ref.read(sessionManagerProvider).refresh(),
    onAuthLost: () => unawaited(ref.read(sessionManagerProvider).signOut()),
    replay: (options) => replayClient.fetch<dynamic>(options),
  );
```

Note the circularity: `authServiceProvider` reads `dioProvider`, and `dioProvider`'s interceptor reads `sessionManagerProvider`. Riverpod resolves this because the interceptor callbacks are lazy — they run per request, long after both providers are built. Keep them as closures; do not hoist either read to provider-build time.

- [ ] **Step 4: Delete the temporary bridge**

In `lib/app/router/app_router.dart`, delete the temporary `authStateProvider` definition and its `TEMPORARY` comment, and import it from `../di/providers.dart` instead.

- [ ] **Step 5: Restore the session at boot**

In `lib/main.dart`, after the E2E seeding block and before `runApp`:

```dart
  // Exchange any persisted refresh token before the first frame, so the router
  // sees AuthRestoring rather than AuthSignedOut and does not flash the login
  // screen on a mobile cold start that has a valid session.
  await container.read(sessionManagerProvider).restore();
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/app/auth_wiring_test.dart`

Expected: PASS, 2 tests.

- [ ] **Step 7: Run the full gate suite**

```bash
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter build web
```

Expected: format clean; analyze exits 0; **229 passing / 29 skipped**; web build succeeds. **Do not run `flutter build apk`** — it fails in this sandbox for environmental reasons (SSL/PKIX), and CI runs it.

- [ ] **Step 8: Confirm the old auth surface is gone**

```bash
grep -rn "authControllerProvider\|AuthController\|buildE2ESession\|UnimplementedError('Auth refresh" lib test || echo "clean"
```

Expected: `clean`. Any hit is a straggler from the old shape.

- [ ] **Step 9: Commit**

```bash
git add lib/ test/app/auth_wiring_test.dart
git commit -m "feat: wire the auth lifecycle into the composition root

AuthInterceptor.refreshToken now delegates to SessionManager instead of
throwing, so a 401 actually renews the session, and onAuthLost signs out
through the same owner. main() exchanges any persisted refresh token
before the first frame, so a mobile cold start with a valid session sees
AuthRestoring rather than flashing the login screen.

AuthController is deleted: the session lives in SessionManager and
authStateProvider republishes it. Closes T-0.4.1 through T-0.4.4."
```

- [ ] **Step 10: Close the epic in `TASK_BREAKDOWN.md`**

Update the Epic P0.4 table's status column and add a closing note beneath it, in the style of the P0.2 and P0.3 notes:

```markdown
> **P0.4 complete** (2026-08-07). T-0.4.1's lifecycle lives in a dedicated
> `SessionManager` with single-flight refresh: a 401-triggered refresh racing a
> proactive one would, under server-side rotation, leave the loser presenting a
> consumed token and sign the user out mid-task. `AuthState` is a sealed
> tri-state rather than `Session?`, because a nullable session conflates
> signed-out with not-yet-known and a mobile cold start would flash the login
> screen. Tokens: the refresh token persists to Keystore/Keychain on mobile and
> **not at all on web**, where `SecureStore` is `localStorage` rather than
> hardware-backed; the access token is never persisted anywhere. Changing the
> web behaviour needs a server-side httpOnly cookie, not a different client
> store. T-0.4.3 replaces prefix matching with one `routeTable` that both the
> router and the guard read, keyed on `GoRouterState.fullPath` so a
> parameterised template matches exactly; an undeclared path fails closed, and
> a test asserts the registered set equals the table with dev routes both on
> and off. T-0.4.2 adds `PermissionGate` (hidden for whole surfaces, disabled
> with a screen-reader-reachable reason for actions on a visible record);
> `AccessScope.inTerritory` remains modelled and unconsumed until P1/P3's
> territory-filtered queries. T-0.4.4's nav was previously inert — no caller
> passed `onDestinationSelected` — and its destinations were unfiltered, so a
> field user was offered four surfaces the guard then rejected. The auth wire
> format stays 🔒 pending the contract; `DioAuthService` and `scope_claims.dart`
> are the only places it lands.
```

Also correct the stale claim at T-0.1.4: branch protection **is** enabled on `main` with `gate` as a required status check (`strict: true`), contradicting the "branch protection was never enabled" note.

- [ ] **Step 11: Commit the docs**

```bash
git add TASK_BREAKDOWN.md
git commit -m "docs: close Epic P0.4 and correct the branch-protection claim

The T-0.1.4 note said the gate check is not required and branch protection
was never enabled. Both are false: main is protected with gate as a
required status check and strict up-to-date enforcement."
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task:

| Spec section | Task |
|---|---|
| §3.1 `auth_service.dart` (seam, `DioAuthService`, `FakeAuthService`) | 1, 6 |
| §3.2 `session_manager.dart` (`AuthState`, single-flight) | 4 |
| §3.3 `token_store.dart` + `refreshTokenV1` | 2 |
| §3.4 `scope_claims.dart` | 3 |
| §3.5 `permission_gate.dart` | 7 |
| §3.6 `route_table.dart` | 5 |
| §3.7 `login_screen.dart` | 6 |
| §3.8 `app_shell.dart` + `nav_destinations.dart` | 8 |
| §3.9 mock-server `/auth/*` | 6 |
| §3.10 modified files incl. `main.dart` | 4, 5, 8, 9 |
| §4.1 `AuthService`/`AuthTokens`, E2E via fake | 1, 6 |
| §4.2 lifecycle table (signIn/restore/refresh/skew/signOut) | 4 |
| §4.3 `TokenStore` platform split, D3 | 2 |
| §4.4 trust boundary | 3 |
| §4.5 route table, `fullPath`, dev routes, deep-link re-check | 5 |
| §4.6 `PermissionGate`, `inTerritory` unconsumed | 7 |
| §4.7 shell split, derived selection | 8 |
| §4.8 mock server | 6 |
| §5 error handling (`loginErrorMessage`, refresh shows no dialog) | 6, 4 |
| §6 all nine test files | 1–9 |
| §7 sequence | 1–9 in order |
| §8 risks | mitigations embedded (Task 6 Step 3 note on `BmdField`; Task 8 Step 8 on the 2 widget tests; Task 5 Step 6 on exhaustiveness mismatch) |
| §9 out of scope | untouched |

**Type consistency verified across tasks.** `AuthTokens(accessToken/refreshToken/expiresAt/claims)` (1→4, 6); `AuthService.login/refresh/logout` returning `Result` (1→4, 6, 9); `ScriptedAuthService` fields `loginCalls`/`refreshCalls`/`logoutCalls`/`refreshTokensSeen`/`refreshGate` and `testTokens(...)`/`kTestNow` (1→4, 9); `TokenStore.persist/read/clear` + `createTokenStore(SecureStore)` (2→4, 9); `FakeTokenStore(initial)` with `value`/`persistCalls`/`clearCalls` (4→9); `parseScopeClaims → Result<ScopeClaims>` and `wireNameForRole`/`wireNameForPermission` (3→4, 6); `AuthState`/`AuthRestoring`/`AuthSignedOut`/`AuthSignedIn(session)` (4→5, 7, 8, 9); `SessionManager.signIn/restore/refresh/signOut/accessTokenForRequest/state/changes/dispose` (4→6, 8, 9); `Access`/`Public`/`Authenticated`/`Requires(permission)`/`RouteEntry(path, access)`/`routeTable`/`devOnlyPaths`/`accessFor` (5→7 via guard, 5→5 tests); `RouteGuards.evaluate({auth, fullPath, location, intended})` + `homePath` and `redirectTargetAfterSignIn` (5→5 tests); `registeredRoutePaths({devRoutesEnabled})` (5→5 tests); `authStateProvider` (5 temporary → 9 promoted, consumed by 7, 8); `sessionManagerProvider` (6 or 9 → 8, 9); `NavDestinationSpec(path/label/icon/permission)`, `allNavDestinations`, `visibleDestinations`, `selectedIndexFor` (8→8 tests); `AppShell({title, body, actions, breadcrumb})` (8→8 screen migrations).

**Two places where the existing code, not this plan, is authoritative** — each has an explicit reconciliation step rather than an assumption: the semantics-tree shape for `Semantics(enabled: false)` (Task 7 Step 4), and the `registeredRoutePaths`/`routeTable` reconciliation if the exhaustiveness test fails (Task 5 Step 6).

**One defect this self-review caught and fixed.** The login screen was written against a `BmdField` that has neither `obscureText` nor `onSubmitted` — I verified the real constructor rather than assuming it. Task 6 now adds `obscureText` to `BmdField` with its own test, because the alternative is a raw `TextField` on the login screen, which reintroduces exactly the pattern P0.2 eliminated when it migrated 11 raw field sites to make `BmdField` the single renderer. Submit-on-enter was dropped rather than adding a second parameter to a shared component for one screen.

**One risk worth adding to §8's list at execution time:** Task 6 modifies `bmd_field.dart`, a P0.2 design-system component with golden coverage. Adding an unused-by-default optional parameter cannot change rendering for existing call sites, but the goldens only run on Linux, so a regression would surface in CI rather than locally.

**Running test totals** (baseline 147 passing / 29 skipped): T1 +6 → 153, T2 +6 → 159, T3 +8 → 167, T4 +14 → 181, T5 +22 → 203, T6 +7 → 210, T7 +6 → 216, T8 +11 → 227, T9 +2 → **229 passing / 29 skipped**. The 29 skips are Linux-gated goldens throughout; CI's total will be **258**. Task 6's seventh test is the `BmdField.obscureText` case appended to the existing design-system suite.

**One deliberate ordering note:** `sessionManagerProvider` is introduced in Task 6 rather than Task 9, because `login_screen.dart` cannot compile without it. Task 9 then moves `authStateProvider` out of its temporary home in `app_router.dart` and deletes `AuthController`. Task 6's Step 9 flags this explicitly so an implementer does not treat it as scope creep.
