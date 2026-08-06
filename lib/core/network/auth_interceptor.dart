import 'package:dio/dio.dart';

const String _authReplayExtraKey = 'authReplayed';

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
///
/// One refresh attempt per request: if the replayed request also returns 401,
/// [onAuthLost] is signaled and the error passes through without retry. This
/// prevents deadlock in QueuedInterceptor (whose error queue is exclusive) and
/// stops token refresh loops.
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
    // Skip token attachment if this request is already replaying after a refresh.
    // Other interceptors (e.g. RetryInterceptor) reuse RequestOptions, so we
    // must not block re-reading the live token on mere header presence.
    if (options.extra[_authReplayExtraKey] != true) {
      final token = readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      // Prevent multiple refresh attempts on the same request. If a replay
      // after refresh also returns 401, signal auth lost without retrying.
      if (err.requestOptions.extra[_authReplayExtraKey] == true) {
        onAuthLost();
        return handler.next(err);
      }

      final refreshed = await refreshToken();
      if (refreshed == null) {
        onAuthLost();
        return handler.next(err);
      }
      // Retry the original request once with the new token, through the
      // configured client so baseUrl and the interceptor chain still apply.
      final req = err.requestOptions
        ..extra[_authReplayExtraKey] = true
        ..headers['Authorization'] = 'Bearer $refreshed';
      try {
        final response = await replay(req);
        // If replay also returns 401, signal auth lost (do not retry again,
        // which would deadlock in QueuedInterceptor's exclusive error queue).
        if (response.statusCode == 401) {
          onAuthLost();
          return handler.next(
            DioException(
              requestOptions: req,
              response: response,
              type: DioExceptionType.badResponse,
            ),
          );
        }
        return handler.resolve(response);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}
