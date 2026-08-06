import 'package:dio/dio.dart';

import '../result/result.dart';
import '../trace/trace_id.dart';
import 'auth_interceptor.dart';
import 'correlation_interceptor.dart';
import 'retry_interceptor.dart';
import 'trace_options.dart';

/// Base request options shared by the app's main [Dio] client and its
/// interceptor-free replay client (see [buildReplayDio]) - both must resolve
/// relative paths (`/campaigns`) against the same `baseUrl` and timeouts.
BaseOptions _baseOptions(String baseUrl) => BaseOptions(
  baseUrl: baseUrl,
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 30),
  headers: {'Accept': 'application/json'},
);

/// Builds the app-wide [Dio] instance. All API traffic goes through here so
/// auth/refresh, correlation-ID, retry and error mapping are centralized.
Dio buildDio({
  required String baseUrl,
  required AuthInterceptor authInterceptor,
}) {
  final dio = Dio(_baseOptions(baseUrl));

  // Order carries meaning in both directions. Correlation runs first on the
  // request so auth and retry both observe the resolved id. RetryInterceptor is
  // appended last, in Task 3, so AuthInterceptor gets first refusal on a 401 -
  // reversed, retry would spend its budget re-sending a stale token.
  dio.interceptors.addAll([
    const CorrelationIdInterceptor(),
    authInterceptor,
    // Last on purpose: AuthInterceptor must get first refusal on a 401.
    RetryInterceptor(dio: dio),
  ]);

  return dio;
}

/// Builds a [Dio] with the same `baseUrl`/timeouts as [buildDio] but no
/// interceptors - in particular, no [AuthInterceptor].
///
/// This is the client [AuthInterceptor.replay] must dispatch through. Because
/// `AuthInterceptor extends QueuedInterceptor`, whose error queue is
/// exclusive, replaying a request through a client that carries the *same*
/// `AuthInterceptor` would mean a second 401 on the replay needs a second
/// `onError` run - which queues behind the first `onError`, still awaiting
/// `replay()`. Neither can proceed: deadlock. A client with no interceptors
/// can never re-enter `AuthInterceptor.onError`, so that failure mode is
/// structurally impossible; a second 401 simply surfaces as a thrown
/// `DioException` from `replay()`.
Dio buildReplayDio({required String baseUrl}) => Dio(_baseOptions(baseUrl));

/// Maps transport/HTTP errors to the domain [Failure] taxonomy so features
/// never inspect raw [DioException]s.
Failure mapDioError(Object error) {
  if (error is DioException) {
    final fromExtra = error.requestOptions.extra[traceIdExtraKey];
    // Prefer the server's id; fall back to the id we sent. A transport failure
    // has no response at all, so without this fallback the Failure carries no
    // correlation id - the exact case a user needs to quote to support.
    final correlationId =
        error.response?.headers.value('x-correlation-id') ??
        (fromExtra is TraceId ? fromExtra.value : null);
    final code = error.response?.statusCode;
    final kind = switch (code) {
      401 => FailureKind.unauthorized,
      403 => FailureKind.forbidden,
      404 => FailureKind.notFound,
      409 => FailureKind.conflict,
      422 => FailureKind.validation,
      _ when error.type == DioExceptionType.connectionError =>
        FailureKind.network,
      _
          when error.type == DioExceptionType.connectionTimeout ||
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
