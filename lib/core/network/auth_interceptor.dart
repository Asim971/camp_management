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

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.headers.containsKey('Authorization')) {
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
    handler.next(err);
  }
}
