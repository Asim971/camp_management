import 'package:dio/dio.dart';

/// Attaches the bearer token and transparently refreshes on 401.
///
/// Contract dependency 🔒: refresh endpoint + token rotation semantics
/// (Task T-0.4.1). Until the auth service contract is confirmed, [refreshToken]
/// is a seam that throws so it is not silently a no-op.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.readAccessToken,
    required this.refreshToken,
    required this.onAuthLost,
  });

  final String? Function() readAccessToken;
  final Future<String?> Function() refreshToken;
  final void Function() onAuthLost;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
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
      // Retry the original request once with the new token.
      final req = err.requestOptions
        ..headers['Authorization'] = 'Bearer $refreshed';
      try {
        final clone = await Dio().fetch<dynamic>(req);
        return handler.resolve(clone);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}
