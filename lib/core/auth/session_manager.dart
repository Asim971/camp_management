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
  // `this._field` initializing formals still expose a PUBLIC call-site name
  // (Dart strips the leading underscore for the named-parameter label), so
  // `SessionManager(service: ..., tokens: ..., now: ...)` at every call site
  // is unaffected by this.
  SessionManager({
    required this._service,
    required this._tokens,
    this._now = _systemNow,
    this.refreshSkew = const Duration(seconds: 60),
  });

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
