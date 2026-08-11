import 'session_manager.dart';

/// Late-bound bridge between the Dio `AuthInterceptor` and the
/// [SessionManager].
///
/// Exists to break a provider cycle that broke every real-auth sign-in
/// (PR #6 e2e, 2026-08-11): `dioProvider`'s interceptor callbacks used to
/// `ref.read(authStateProvider)` / `ref.read(sessionManagerProvider)`, whose
/// dependency chains lead back to `dioProvider` itself
/// (`authState -> sessionManager -> authService -> dio`). Riverpod checks
/// for cycles AT READ TIME — not only while providers build — so the first
/// request through the real `DioAuthService` (the login itself) threw
/// `CircularDependencyError` from inside `onRequest`. The comment that used
/// to live on those reads ("lazy closures that run per request, long after
/// all four providers are built") was reasoning about build order, which was
/// never the rule being enforced.
///
/// This object is a dependency LEAF: `authBindingProvider` watches nothing,
/// `dioProvider` reads only it, and `sessionManagerProvider` calls [attach]
/// at the end of its own build — before any caller can hold the manager and
/// start a request — so the graph is acyclic while the interceptor still
/// reaches live session state.
///
/// Unattached behaviour (only reachable if a request fires before
/// `sessionManagerProvider` has ever been built — which the attach-in-build
/// ordering makes impossible for any authenticated flow, since a session
/// requires the manager): no token attached, refresh yields null, sign-out
/// is a no-op. All three fail in the signed-out direction.
class AuthBinding {
  SessionManager? _manager;

  void attach(SessionManager manager) => _manager = manager;

  /// The access token to attach to an outbound request, or null when signed
  /// out (or not yet attached).
  String? get accessToken => switch (_manager?.state) {
    AuthSignedIn(:final session) => session.accessToken,
    _ => null,
  };

  /// See [SessionManager.refresh]; null when unattached.
  Future<String?> refresh() async => _manager?.refresh();

  /// See [SessionManager.signOut]; no-op when unattached.
  Future<void> signOut() async => _manager?.signOut();
}
