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
/// self-built client would send the replay to an unresolvable URL. Callers
/// MUST point [replay] at a client that does **not** carry this interceptor.
/// This class extends `QueuedInterceptor`, whose error queue is exclusive -
/// only one `onError` runs at a time. Replaying through a `Dio` that has this
/// same interceptor installed means a second 401 on the replay would need a
/// second `onError` run, which queues behind the first `onError` that is
/// still awaiting `replay()`. Neither can proceed: deadlock. Replaying
/// through a plain client with no interceptors sidesteps this entirely - a
/// second 401 just makes `replay()` throw a `DioException`, which the `catch`
/// below turns into a normal propagated error. There is therefore no need for
/// a "have we already replayed this request" flag: the re-entrancy that flag
/// would have guarded against cannot happen.
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

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Always re-read the live token. Other interceptors (e.g.
    // RetryInterceptor) reuse RequestOptions, so a retry must not ship a
    // stale cached header - it needs whatever token is current now. The 401
    // replay's own fresh header (set in onError, below) is safe from being
    // clobbered here because replay() dispatches through a client that does
    // not have this interceptor installed, so onRequest never runs for it.
    final token = readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed == null) {
        onAuthLost();
        return handler.next(err);
      }
      // Retry the original request once with the new token. replay() must
      // dispatch through a client with baseUrl set but this interceptor
      // absent - see the class doc for why that structurally rules out a
      // second 401 re-entering this interceptor's onError.
      final req = err.requestOptions
        ..headers['Authorization'] = 'Bearer $refreshed';
      try {
        return handler.resolve(await replay(req));
      } on DioException catch (e) {
        // The replay itself failed - most notably, it can also come back
        // 401 if the "fresh" token was rejected too. Because replay() has no
        // AuthInterceptor of its own, that surfaces here as a thrown
        // DioException rather than a second onError run, so this one
        // refresh attempt is all that ever happens for a given request.
        if (e.response?.statusCode == 401) {
          onAuthLost();
        }
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}
