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
/// A second, orthogonal race: any in-flight sign-in, refresh or restore (its
/// network/storage call already sent, awaiting a response) can complete
/// *after* a sign-out and resurrect the session it just ended - re-emitting
/// [AuthSignedIn] and re-persisting a token [signOut] had already cleared. On
/// a shared field device that means a departing user's session is silently
/// restored under the next person's fingers. [_generation] closes this:
/// [signIn] and [signOut] each start a new epoch, captured *before* either
/// does any `await`, and [restore] captures the epoch in effect before its
/// own first `await` too. Checking once at the top of an async method is not
/// enough - an await between the check and a mutation reopens the hole, and
/// on mobile `TokenStore.persist`/`.clear` are real Keystore I/O, not a
/// microtask sliver - so every mutation re-checks immediately before (and,
/// for persist, immediately after) it runs, via [_emitIfCurrent] and
/// [_persistIfCurrent]. One counter guards every direction - sign-out
/// invalidating a stale refresh or restore, and a new sign-in invalidating a
/// stale refresh or a stale, overtaken sign-in - because all of these are the
/// same shape: work that finishes after the epoch it started in has ended
/// must never win.
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

  /// The generation [_inFlightRefresh] was started under. A future captured
  /// under an older generation must never be handed to a caller in a newer
  /// one - see [refresh].
  int? _inFlightRefreshGeneration;

  /// Bumped by [signIn] and [signOut]. Work captured under an older value is
  /// stale by the time it completes and must not touch state or storage.
  int _generation = 0;

  /// FIFO queue forcing every adopt-path token-store mutation to *complete*
  /// in the order it was *enqueued*, not the order its underlying I/O happens
  /// to finish in. Two independent async writes to the same key otherwise
  /// race on completion order alone: a slow, stale `persist()` can land after
  /// a perfectly current one and silently overwrite it, even though both
  /// passed their generation check when they started. Chaining every
  /// mutation through this one future makes that inversion structurally
  /// impossible rather than merely checked-for.
  ///
  /// [signOut]'s own `clear()` deliberately does NOT go through this queue -
  /// see the comment there.
  Future<void> _storeQueue = Future<void>.value();

  /// The generation of the most recently *enqueued* persist, regardless of
  /// whether it has completed yet. Lets a stale persist's post-write check
  /// tell "nothing newer has been queued behind me, so nobody else will fix
  /// storage" apart from "a newer one is already queued and will win by
  /// ordering" - see [_persistIfCurrent].
  int _lastPersistGeneration = 0;

  Future<void> _enqueue(Future<void> Function() op) {
    final result = _storeQueue.then((_) => op());
    // The queue itself must never end up permanently rejected - that would
    // wedge every later mutation behind a dead future - so swallow the error
    // here. The caller of this specific op still sees it via [result].
    _storeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  AuthState get state => _state;
  Stream<AuthState> get changes => _changes.stream;

  bool _isCurrent(int generation) => generation == _generation;

  void _emit(AuthState next) {
    _state = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  /// Emits [next] only if [generation] is still current. Every state
  /// mutation that could resurrect or clobber a session goes through this -
  /// never a bare [_emit] - so a stale caller structurally cannot flip state.
  void _emitIfCurrent(int generation, AuthState next) {
    if (_isCurrent(generation)) _emit(next);
  }

  /// Persists [refreshToken] for [generation], undoing the write if the
  /// generation moved while the write itself was in flight and nothing newer
  /// has since been queued to fix it.
  ///
  /// A pre-write check alone is not enough: `persist` can be a real Keystore
  /// write wide enough for a `signOut()` to start *and finish* entirely
  /// during it, in which case our write lands in storage *after* `signOut`'s
  /// (deliberately un-queued) `clear()` already did, silently resurrecting
  /// the cleared token - so this also re-checks after the write.
  ///
  /// The undo is conditional on [generation] still being the *latest queued*
  /// persist ([_lastPersistGeneration]), not on `_state is AuthSignedIn`: an
  /// earlier version checked state instead, but state and storage do not
  /// update atomically - a newer sign-in's persist can finish and be
  /// reflected in storage microtasks *before* its own `_emit` runs, so
  /// checking state let an older write's "helpful" cleanup wipe a newer,
  /// already-written token that state hadn't caught up to yet. Checking
  /// against the queue position instead is exact: if a newer persist has
  /// already been enqueued, the queue's own ordering - not this cleanup -
  /// guarantees it has (or will have) the final word, so clearing here would
  /// only reintroduce the inversion this queue exists to close.
  Future<bool> _persistIfCurrent(int generation, String refreshToken) async {
    if (!_isCurrent(generation)) return false;
    _lastPersistGeneration = generation;
    await _enqueue(() => _tokens.persist(refreshToken));
    if (!_isCurrent(generation)) {
      if (generation == _lastPersistGeneration) {
        await _enqueue(_tokens.clear);
      }
      return false;
    }
    return true;
  }

  Future<Result<void>> signIn(String username, String password) async {
    // A new epoch, struck before any await: any refresh, restore or sign-in
    // already in flight from an older epoch must not be allowed to land
    // after this one starts.
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
      _emitIfCurrent(generation, const AuthSignedOut());
      return Err(failure);
    }
    return _adopt(result.fold((t) => t, (_) => null)!, generation);
  }

  /// Exchanges any persisted refresh token for a session. Call once at boot.
  ///
  /// Deliberately does NOT swallow a failing [TokenStore]: `bootstrap` is what
  /// turns a pre-frame failure into a *recorded* degradation on
  /// `BootDiagnostics`, and a guard here that returned normally made the
  /// failure invisible to that recorder - "guarded but silent", the exact
  /// failure mode P0.6 exists to remove. So the error is rethrown.
  ///
  /// What is NOT delegated upwards is *state repair*. `bootstrap`'s `step()`
  /// can only catch an exception; it structurally cannot undo an
  /// [AuthRestoring] this method already emitted. So the `catch` below repairs
  /// state at the layer that owns state and then rethrows - both, not either.
  ///
  /// Two failing-store shapes matter, and only the second needs the repair:
  ///
  /// - Throws on **read**: the read is the first `await`, ahead of every
  ///   [_emit], and the guard at the top means state is already
  ///   [AuthSignedOut] - so the caller is left with a usable app with nothing
  ///   to fix. Keep the read there; moving it below the
  ///   `_emit(AuthRestoring())` would drag this shape into the second case.
  /// - Reads, then throws on **write**: `_exchange` -> `_adopt` ->
  ///   [_persistIfCurrent], or `_exchange`'s own `_enqueue(_tokens.clear)`,
  ///   throws *after* `_emit(const AuthRestoring())` below. Left unrepaired
  ///   that is a permanent splash - recorded, but still unusable, and a hang
  ///   reads worse to a user than a crash.
  ///
  /// Neither shape is reachable through today's implementations
  /// ([MobileTokenStore] catches inside `persist`/`read`/`clear`,
  /// [WebTokenStore] is all no-ops), so the write shape is a latent hazard held
  /// closed rather than a live bug - but [TokenStore] is an injected interface
  /// and the next implementation of it need not be as careful.
  /// `session_manager_test.dart` pins both shapes.
  Future<void> restore() async {
    // A live session (signed in, or already restoring) must not be torn down
    // by a stray extra call - restore() is meant to run once at boot, and
    // without this guard a second call could race the first, or clobber an
    // already-established sign-in.
    if (_state is! AuthSignedOut) return;
    try {
      // Captured before the storage read, like signIn/signOut capture theirs
      // before their first await: a sign-out that completes entirely during a
      // slow read must be able to invalidate this restore when it resumes.
      final generation = _generation;
      final stored = await _tokens.read();
      if (!_isCurrent(generation)) {
        // Superseded while the stored token was being read. Whatever ended
        // this epoch already decided state and storage; do not touch either.
        return;
      }
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
      // the generation guard below, so a sign-out or sign-in racing boot cannot
      // be undone by a stale restore landing late.
      await _exchange(stored, generation);
    } catch (_) {
      // Conditioned on [AuthRestoring] rather than on the generation, because
      // that is precisely "this call left state mid-flight": AuthRestoring is
      // emitted nowhere else, and every other emitter (signIn, signOut,
      // _adopt, _exchange) moves to a terminal state. So a sign-out or a
      // completed sign-in that raced us has already published a terminal state
      // that must NOT be clobbered with AuthSignedOut - and nor must an
      // AuthSignedIn this restore itself just adopted before throwing on the
      // way out. Repair only, never overwrite.
      if (_state is AuthRestoring) _emit(const AuthSignedOut());
      // Rethrow: repairing state is this layer's job, but REPORTING the
      // degradation is bootstrap's, and it can only see a thrown error.
      rethrow;
    }
  }

  /// Renews the session. Concurrent callers SHARE one transport call, but
  /// only within the same generation.
  ///
  /// [_inFlightRefresh] alone is not enough of a key: pairing it with
  /// [_inFlightRefreshGeneration] closes two failures a bare nullable future
  /// cannot distinguish. First, a refresh started under an old epoch and
  /// still in flight when a new [signIn] lands must not be handed to a
  /// caller in the new epoch merely because the field is non-null - that
  /// caller would receive a future that resolves against the PREVIOUS user's
  /// session, and a null result from it would sign the new user out of a
  /// perfectly valid one. Second, cleanup on completion must not deregister a
  /// newer refresh that has since taken the field's place - `identical`
  /// below, not a bare null-assignment, is what makes that structurally
  /// impossible: a completing future only ever clears the slot if it is
  /// still the one occupying it.
  Future<String?> refresh() {
    final current = _state;
    final token = switch (current) {
      AuthSignedIn(:final session) => session.refreshToken,
      _ => null,
    };
    if (token == null) return Future<String?>.value();
    final generation = _generation;
    final existing = _inFlightRefresh;
    if (existing != null && _inFlightRefreshGeneration == generation) {
      return existing;
    }
    late Future<String?> started;
    started = _exchange(token, generation).whenComplete(() {
      if (identical(_inFlightRefresh, started)) {
        _inFlightRefresh = null;
        _inFlightRefreshGeneration = null;
      }
    });
    _inFlightRefresh = started;
    _inFlightRefreshGeneration = generation;
    return started;
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
    // A new epoch, struck before anything async: any refresh, restore or
    // sign-in already in flight belongs to an ended epoch and must not be
    // able to resurrect this session when it completes. Abandon the
    // in-flight refresh future too, so a later refresh() starts fresh rather
    // than awaiting one that can never help it.
    _generation++;
    _inFlightRefresh = null;
    _inFlightRefreshGeneration = null;
    _emit(const AuthSignedOut());
    // Deliberately NOT routed through _enqueue: sign-out is local-first and
    // must clear storage immediately, even if an older, already-dispatched
    // adopt-path write is still parked mid-flight in the queue (that write's
    // own post-completion check in _persistIfCurrent is what undoes it - the
    // queue only orders writes that have not been dispatched yet, and this
    // one already has been by the time signOut runs).
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
      await _enqueue(_tokens.clear);
      _emitIfCurrent(generation, const AuthSignedOut());
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
  /// Also rejects if [generation] is no longer current at any point during
  /// this call: it may be resuming after a sign-out or a newer sign-in
  /// already moved the session on, and adopting now would resurrect an
  /// abandoned session or re-persist a token a newer flow already replaced or
  /// cleared. The persist step re-checks *after* its own await via
  /// [_persistIfCurrent], because staleness can appear while that write is in
  /// flight, not only before it starts.
  Future<Result<void>> _adopt(AuthTokens tokens, int generation) async {
    if (!_isCurrent(generation)) {
      return const Err(Failure(FailureKind.conflict));
    }
    final parsed = parseScopeClaims(tokens.claims);
    if (parsed case Err(:final failure)) {
      if (_isCurrent(generation)) {
        await _enqueue(_tokens.clear);
        _emitIfCurrent(generation, const AuthSignedOut());
      }
      return Err(failure);
    }
    final claims = parsed.fold((c) => c, (_) => null)!;
    final persisted = await _persistIfCurrent(generation, tokens.refreshToken);
    if (!persisted) {
      return const Err(Failure(FailureKind.conflict));
    }
    _emitIfCurrent(
      generation,
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
