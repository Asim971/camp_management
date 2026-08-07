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
///
/// A second, orthogonal race: any in-flight sign-in or refresh (its network
/// call already sent, awaiting a response) can complete *after* a sign-out and
/// resurrect the session it just ended - re-emitting [AuthSignedIn] and
/// re-persisting a token [signOut] had already cleared. On a shared field
/// device that means a departing user's session is silently restored under
/// the next person's fingers. [_generation] closes this: [signIn] and
/// [signOut] each start a new epoch, and any exchange or adoption that began
/// under an older epoch is discarded on completion rather than allowed to
/// mutate state or storage. One counter guards both directions - sign-out
/// invalidating a stale refresh, and a new sign-in invalidating a stale
/// refresh or a stale, overtaken sign-in - because both are the same shape:
/// work that finishes after the epoch it started in has ended must never win.
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

  /// Bumped by [signIn] and [signOut]. Work captured under an older value is
  /// stale by the time it completes and must not touch state or storage.
  int _generation = 0;

  AuthState get state => _state;
  Stream<AuthState> get changes => _changes.stream;

  bool _isCurrent(int generation) => generation == _generation;

  void _emit(AuthState next) {
    _state = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  Future<Result<void>> signIn(String username, String password) async {
    // A new epoch: any refresh or sign-in already in flight from an older
    // epoch must not be allowed to land after this one starts.
    final generation = ++_generation;
    final result = await _service.login(username, password);
    if (!_isCurrent(generation)) {
      // Overtaken by a newer sign-in or a sign-out while login was in
      // flight. Discard silently - neither branch below may run, or a
      // superseded attempt could still flip state out from under whatever
      // (or whoever) came after it.
      return const Err(Failure(FailureKind.conflict));
    }
    if (result case Err(:final failure)) {
      _emit(const AuthSignedOut());
      return Err(failure);
    }
    return _adopt(result.fold((t) => t, (_) => null)!, generation);
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
    // Bypasses the refresh() single-flight guard, but only restore() runs
    // during AuthRestoring and refresh() no-ops while signed out/restoring,
    // so no second concurrent exchange can start here today. It still shares
    // the generation guard, so a sign-out or sign-in racing boot cannot be
    // undone by a stale restore landing late.
    await _exchange(stored, _generation);
  }

  /// Renews the session. Concurrent callers share one transport call.
  /// Returns the new access token, or null if the session ended or this call
  /// was superseded by a sign-out/sign-in before it completed.
  Future<String?> refresh() {
    final current = _state;
    final token = switch (current) {
      AuthSignedIn(:final session) => session.refreshToken,
      _ => null,
    };
    if (token == null) return Future<String?>.value();
    final generation = _generation;
    return _inFlightRefresh ??= _exchange(
      token,
      generation,
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
    // A new epoch, struck before anything async: any refresh (or sign-in)
    // already in flight belongs to an ended epoch and must not be able to
    // resurrect this session when it completes. Abandon the in-flight future
    // too, so a later refresh() starts fresh rather than awaiting one that
    // can never help it.
    _generation++;
    _inFlightRefresh = null;
    _emit(const AuthSignedOut());
    await _tokens.clear();
    if (token != null) await _service.logout(token);
  }

  Future<String?> _exchange(String refreshToken, int generation) async {
    final result = await _service.refresh(refreshToken);
    if (!_isCurrent(generation)) {
      // Superseded while the transport call was in flight. Discard: do not
      // emit, do not touch storage, do not fall through to the error path
      // below (which would emit AuthSignedOut over whatever a newer sign-in
      // already established).
      return null;
    }
    if (result case Err()) {
      await _tokens.clear();
      _emit(const AuthSignedOut());
      return null;
    }
    final adopted = await _adopt(
      result.fold((t) => t, (_) => null)!,
      generation,
    );
    return adopted.isOk ? (_state as AuthSignedIn).session.accessToken : null;
  }

  /// Turns tokens into a session, rejecting claims that do not parse. A token
  /// whose roles are unmappable must NOT become a signed-in user with an empty
  /// scope - that is exactly the silent narrowing scope_claims prevents.
  ///
  /// Also rejects if [generation] is no longer current: this call may be
  /// resuming after a sign-out or a newer sign-in already moved the session
  /// on, and adopting now would resurrect an abandoned session or re-persist
  /// a token a newer flow already replaced or cleared.
  Future<Result<void>> _adopt(AuthTokens tokens, int generation) async {
    if (!_isCurrent(generation)) {
      return const Err(Failure(FailureKind.conflict));
    }
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
