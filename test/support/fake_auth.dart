import 'dart:async';

import 'package:acsl_campaign/core/auth/auth_service.dart';
import 'package:acsl_campaign/core/auth/token_store.dart';
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

/// [TokenStore] whose read fails, standing in for storage that is present but
/// unusable — a Keystore whose cipher changed under an OS update, a backup
/// restored onto different hardware. Writes are no-ops rather than throws,
/// because it is the boot-path *read* this models; [WriteThrowingTokenStore]
/// covers the other half.
///
/// Neither shape is reachable through the shipped stores — [MobileTokenStore]
/// catches inside every method and [WebTokenStore] is all no-ops — so these
/// model a future [TokenStore] implementation, which is the point: the store is
/// an injected interface and `SessionManager` must survive a careless one.
class ThrowingTokenStore implements TokenStore {
  @override
  Future<void> persist(String refreshToken) async {}

  @override
  Future<String?> read() async => throw StateError('storage unavailable');

  @override
  Future<void> clear() async {}
}

/// [TokenStore] that reads fine and fails on every *write*.
///
/// This is the asymmetric shape, and the interesting one: the read succeeding
/// is what carries `restore()` past `_emit(AuthRestoring())` before the failure
/// lands, so the exception alone is not enough to leave a usable app — state
/// has to be repaired too, or the router holds on a splash forever.
class WriteThrowingTokenStore implements TokenStore {
  WriteThrowingTokenStore([this.value = 'stored-r']);

  final String? value;

  @override
  Future<void> persist(String refreshToken) async =>
      throw StateError('storage is read-only');

  @override
  Future<String?> read() async => value;

  @override
  Future<void> clear() async => throw StateError('storage is read-only');
}
