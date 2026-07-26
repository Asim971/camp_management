import 'package:dio/dio.dart';

import '../result/result.dart';
import 'auth_interceptor.dart';

/// Builds the app-wide [Dio] instance. All API traffic goes through here so
/// auth/refresh, correlation-ID, retry and error mapping are centralized.
Dio buildDio({
  required String baseUrl,
  required AuthInterceptor authInterceptor,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.addAll([
    authInterceptor,
    // TODO(P0.3.2): add CorrelationIdInterceptor + RetryInterceptor.
  ]);

  return dio;
}

/// Maps transport/HTTP errors to the domain [Failure] taxonomy so features
/// never inspect raw [DioException]s.
Failure mapDioError(Object error) {
  if (error is DioException) {
    final correlationId =
        error.response?.headers.value('x-correlation-id');
    final code = error.response?.statusCode;
    final kind = switch (code) {
      401 => FailureKind.unauthorized,
      403 => FailureKind.forbidden,
      404 => FailureKind.notFound,
      409 => FailureKind.conflict,
      422 => FailureKind.validation,
      _ when error.type == DioExceptionType.connectionError =>
        FailureKind.network,
      _ when error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout =>
        FailureKind.timeout,
      _ when code != null && code >= 500 => FailureKind.server,
      _ => FailureKind.unknown,
    };
    return Failure(
      kind,
      message: error.message,
      code: code?.toString(),
      correlationId: correlationId,
    );
  }
  return Failure(FailureKind.unknown, message: error.toString());
}
