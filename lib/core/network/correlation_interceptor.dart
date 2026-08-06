import 'package:dio/dio.dart';

import '../trace/trace_id.dart';
import 'trace_options.dart';

/// Stamps every outbound request with a correlation id, and forwards a client
/// idempotency key when one was supplied.
///
/// This is the single place request decoration happens: `RetryInterceptor` only
/// *reads* `extra` to decide whether a retry is safe, it never stamps headers.
///
/// Must be registered FIRST so auth and retry both observe the resolved id.
class CorrelationIdInterceptor extends Interceptor {
  const CorrelationIdInterceptor();

  static const String headerName = 'X-Correlation-Id';
  static const String idempotencyHeaderName = 'Idempotency-Key';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final supplied = options.extra[traceIdExtraKey];
    final trace = supplied is TraceId ? supplied : TraceId.generate();

    // Write the resolved id back so mapDioError can recover it even when the
    // failure carries no response (connection error, timeout).
    options.extra[traceIdExtraKey] = trace;
    options.headers[headerName] = trace.value;

    final key = options.extra[idempotencyKeyExtraKey];
    if (key is String && key.isNotEmpty) {
      options.headers[idempotencyHeaderName] = key;
    }

    handler.next(options);
  }
}
